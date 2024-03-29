{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StrictData #-}

module Language.Marlowe.Runtime.Indexer.ChainSeekClient
  where

import Cardano.Api (CardanoMode, EraHistory, SystemStart)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Component
import Control.Concurrent.STM (STM, atomically, newTQueue, readTQueue, writeTQueue)
import Data.Set (Set)
import Data.Set.NonEmpty (NESet)
import qualified Data.Set.NonEmpty as NESet
import Data.Time (NominalDiffTime, nominalDiffTimeToSeconds)
import Data.Void (Void, absurd)
import Language.Marlowe.Runtime.ChainSync.Api
import Language.Marlowe.Runtime.Indexer.Database (DatabaseQueries(..))
import Language.Marlowe.Runtime.Indexer.Types (MarloweBlock(..), MarloweUTxO(..), extractMarloweBlock)
import Network.Protocol.ChainSeek.Client
import Network.Protocol.Driver (RunClient)
import Network.Protocol.Query.Client (QueryClient, liftQuery)
import Observe.Event (addField, withEvent)
import Observe.Event.Backend (EventBackend)

data ChainSeekClientSelector f where
  LoadMarloweUTxO :: ChainSeekClientSelector MarloweUTxO

-- | Injectable dependencies for the chain seek client
data ChainSeekClientDependencies r = ChainSeekClientDependencies
  { databaseQueries :: DatabaseQueries IO
  -- ^ Implementations of the database queries.

  , runChainSeekClient :: RunClient IO RuntimeChainSeekClient
  -- ^ A function that runs a client of the chain seek protocol.

  , runChainSyncQueryClient :: RunClient IO (QueryClient ChainSyncQuery)
  -- ^ A function that runs a client of the chain sync query protocol.

  , pollingInterval :: NominalDiffTime
  -- ^ How frequently to poll the chain seek server when waiting.

  , marloweScriptHashes :: NESet ScriptHash
  -- ^ The set of known marlowe script hashes.

  , payoutScriptHashes :: NESet ScriptHash
  -- ^ The set of known payout script hashes.

  , eventBackend :: EventBackend IO r ChainSeekClientSelector
  }

-- | A change to the chain with respect to Marlowe contracts
data ChainEvent
  -- | A change in which a new block of Marlowe transactions is added to the chain.
  = RollForward MarloweBlock ChainPoint ChainPoint

  -- | A change in which the chain is reverted to a previous point, discarding later blocks.
  | RollBackward ChainPoint ChainPoint

-- | A component that runs a chain seek client to traverse the blockchain and
-- extract blocks of Marlowe transactions. The sequence of changes to the chain
-- can be read by repeatedly running the resulting STM action.
chainSeekClient :: forall r. Component IO (ChainSeekClientDependencies r) (STM ChainEvent)
chainSeekClient = component \ChainSeekClientDependencies{..} -> do
  -- Initialize a TQueue for emitting ChainEvents.
  eventQueue <- newTQueue

  -- Return the component's thread action and the action to pull the next chain
  -- event.
  pure
    -- In this component's thread, run the chain seek client that will pull the
    -- transactions for discovering and following Marlowe contracts
    ( runChainSeekClient $ client
        (atomically . writeTQueue eventQueue)
        databaseQueries
        pollingInterval
        marloweScriptHashes
        payoutScriptHashes
        runChainSyncQueryClient
        eventBackend
    , readTQueue eventQueue
    )
  where
  -- | A chain seek client that discovers and follows all Marlowe contracts
  client
    :: (ChainEvent -> IO ())
    -> DatabaseQueries IO
    -> NominalDiffTime
    -> NESet ScriptHash
    -> NESet ScriptHash
    -> RunClient IO (QueryClient ChainSyncQuery)
    -> EventBackend IO r ChainSeekClientSelector
    -> RuntimeChainSeekClient IO ()
  client emit DatabaseQueries{..} pollingInterval marloweScriptHashes payoutScriptHashes runChainSyncQueryClient eventBackend =
    ChainSeekClient do
      let
        queryChainSync :: ChainSyncQuery Void err a -> IO a
        queryChainSync query = do
          result <- runChainSyncQueryClient $ liftQuery query
          case result of
            Left _ -> fail "Failed to query chain sync"
            Right a -> pure a
      systemStart <- queryChainSync GetSystemStart
      eraHistory <- queryChainSync GetEraHistory
      securityParameter <- queryChainSync GetSecurityParameter
      pure $ SendMsgRequestHandshake moveSchema $ ClientStHandshake
        { recvMsgHandshakeRejected = \_ -> fail "unsupported chain seek version"
        , recvMsgHandshakeConfirmed = do
            -- Get the intersection points - the most recent block headers stored locally.
            intersectionPoints <- getIntersectionPoints
            let
              -- A client state for handling the intersect response.
              clientNextIntersect = ClientStNext
                -- Rejection of an intersection request implies no intersection was found.
                -- In this case, we have no choice but to start synchronization from Genesis.
                { recvMsgQueryRejected = \_ tip -> do
                    -- Roll everything back to Genesis.
                    emit $ RollBackward Genesis tip

                    -- Start the main synchronization loop
                    pure $ clientIdle securityParameter systemStart eraHistory $ MarloweUTxO mempty mempty

                -- An intersection point was found, resume synchronization from
                -- that point.
                , recvMsgRollForward = \_ point tip -> do
                    -- Always emit a rollback at the start.
                    emit $ RollBackward point tip

                    -- Load the MarloweUTxO
                    utxo <- withEvent eventBackend LoadMarloweUTxO \ev -> case point of
                      -- If the intersection point is at Genesis, return an empty MarloweUTxO.
                      Genesis -> pure $ MarloweUTxO mempty mempty

                      -- Otherwise load it from the database.
                      At block -> do
                        utxo <- getMarloweUTxO block
                        addField ev utxo
                        pure utxo

                    -- Start the main synchronization loop.
                    pure $ clientIdle securityParameter systemStart eraHistory utxo

                -- Since the client is at Genesis at the start of this request,
                -- it will never be rolled back. Handle the perfunctory case by
                -- looping.
                , recvMsgRollBackward = \_ _ -> pure clientIdleIntersect

                -- If the client is caught up to the tip, poll for the query results.
                , recvMsgWait = pollWithNext clientNextIntersect
                }

              -- A client state for sending the intersect request.
              clientIdleIntersect = SendMsgQueryNext (Intersect intersectionPoints) clientNextIntersect

            pure case intersectionPoints of
              -- Just start the loop right away with an empty UTxO.
              [] -> clientIdle securityParameter systemStart eraHistory $ MarloweUTxO mempty mempty
              -- Request an intersection
              _ -> clientIdleIntersect
        }
      where
      allScriptCredentials = NESet.map ScriptCredential $ NESet.union marloweScriptHashes payoutScriptHashes
      -- A helper function to poll pending query results after a set timeout and
      -- continue with the given ClientStNext.
      pollWithNext
        :: ClientStNext Move err res ChainPoint (WithGenesis BlockHeader) IO a
        -> IO (ClientStPoll Move err res ChainPoint (WithGenesis BlockHeader) IO a)
      pollWithNext next = do
        -- Wait for the polling interval to elapse (converted from seconds to
        -- milliseconds).
        threadDelay $ floor $ 1_000_000 * nominalDiffTimeToSeconds pollingInterval

        -- Poll for results and handle the response with the given ClientStNext.
        pure $ SendMsgPoll next

      -- The client's idle state handler for the main synchronization loop.
      -- Sends the next query to the chain seek server and handles the
      -- response.
      clientIdle
        :: Int
        -> SystemStart
        -> EraHistory CardanoMode
        -> MarloweUTxO
        -> ClientStIdle Move ChainPoint (WithGenesis BlockHeader) IO a
      clientIdle securityParameter systemStart eraHistory = SendMsgQueryNext (FindTxsFor allScriptCredentials) . clientNext securityParameter systemStart eraHistory

      -- Handles responses from the main synchronization loop query.
      clientNext
        :: Int
        -> SystemStart
        -> EraHistory CardanoMode
        -> MarloweUTxO
        -> ClientStNext Move Void (Set Transaction) ChainPoint (WithGenesis BlockHeader) IO a
      clientNext securityParameter systemStart eraHistory utxo = ClientStNext
        -- Fail with an error if chainseekd rejects the query. This is safe
        -- from bad user input, because our queries are derived from the ledger
        -- state, and so will only be rejected if the query derivation is
        -- incorrect, or chainseekd is corrupt. Because both are unexpected
        -- errors, it is a non-recoverable error state.
        { recvMsgQueryRejected = absurd

        -- Handle the next block by extracting Marlowe transactions into a
        -- MarloweBlock and updating the MarloweUTxO.
        , recvMsgRollForward = \txs point tip -> do
            -- Get the current block (not expected ever to be Genesis).
            block <- case point of
              Genesis -> fail "Rolled forward to Genesis"
              At block -> pure block

            -- Extract the Marlowe block and compute the next MarloweUTxO.
            nextUtxo <- case extractMarloweBlock systemStart eraHistory (NESet.toSet marloweScriptHashes) block txs utxo of
              -- If no MarloweBlock was extracted (not expected, but harmless), do nothing and return the current MarloweUTxO.
              -- This is not expected because the query would only be satisfied by a block that contains some usable Marlowe information.
              Nothing -> pure utxo

              Just (nextUtxo, marloweBlock) -> do
                -- Emit the marlowe block in a roll forward event to a downstream consumer.
                emit $ RollForward marloweBlock point tip

                -- Return the new MarloweUTxO
                pure nextUtxo

            -- Loop back into the main synchronization loop with an updated
            -- rollback state.
            pure $ clientIdle securityParameter systemStart eraHistory nextUtxo

        , recvMsgRollBackward = \point tip -> do
            emit $ RollBackward point tip
            nextUtxo <- case point of
              Genesis -> pure $ MarloweUTxO mempty mempty
              At block -> getMarloweUTxO block
            pure $ clientIdle securityParameter systemStart eraHistory nextUtxo

        , recvMsgWait = pollWithNext $ clientNext securityParameter systemStart eraHistory utxo
        }
