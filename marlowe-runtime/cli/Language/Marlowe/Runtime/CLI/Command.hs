{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}

module Language.Marlowe.Runtime.CLI.Command
  where

import Control.Concurrent.STM (STM)
import Control.Exception (SomeException, catch, throw)
import Control.Exception.Base (throwIO)
import Control.Monad.Trans.Reader (runReaderT)
import qualified Data.ByteString.Lazy as LB
import Data.Foldable (asum)
import Language.Marlowe.Protocol.Sync.Client (marloweSyncClientPeer)
import Language.Marlowe.Protocol.Sync.Codec (codecMarloweSync)
import Language.Marlowe.Runtime.CLI.Command.Apply
  ( ApplyCommand
  , advanceCommandParser
  , applyCommandParser
  , chooseCommandParser
  , depositCommandParser
  , notifyCommandParser
  , runApplyCommand
  )
import Language.Marlowe.Runtime.CLI.Command.Create (CreateCommand, createCommandParser, runCreateCommand)
import Language.Marlowe.Runtime.CLI.Command.Log (LogCommand, logCommandParser, runLogCommand)
import Language.Marlowe.Runtime.CLI.Command.Submit (SubmitCommand, runSubmitCommand, submitCommandParser)
import Language.Marlowe.Runtime.CLI.Command.Tx (TxCommand)
import Language.Marlowe.Runtime.CLI.Command.Withdraw (WithdrawCommand, runWithdrawCommand, withdrawCommandParser)
import Language.Marlowe.Runtime.CLI.Env (Env(..))
import Language.Marlowe.Runtime.CLI.Monad (CLI, runCLI)
import Language.Marlowe.Runtime.CLI.Option (optParserWithEnvDefault)
import qualified Language.Marlowe.Runtime.CLI.Option as O
import Network.Protocol.ChainSeek.Codec (DeserializeError)
import Network.Protocol.Driver (RunClient)
import Network.Protocol.Handshake.Client (runClientPeerOverSocketWithHandshake)
import Network.Protocol.Handshake.Types (HasSignature(..))
import Network.Protocol.Job.Client (jobClientPeer)
import Network.Protocol.Job.Codec (codecJob)
import Network.Socket (AddrInfo, HostName, PortNumber, SocketType(..), addrSocketType, defaultHints, getAddrInfo)
import Network.TypedProtocol (Peer, PeerRole(AsClient))
import Network.TypedProtocol.Codec (Codec)
import Options.Applicative
import System.IO (hPutStrLn, stderr)

-- | Top-level options for running a command in the Marlowe Runtime CLI.
data Options = Options
  { historyHost :: !HostName
  , historySyncPort :: !PortNumber
  , txHost :: !HostName
  , txCommandPort :: !PortNumber
  , cmd :: !Command
  }

-- | A command for the Marlowe Runtime CLI.
data Command
  = Apply (TxCommand ApplyCommand)
  | Create (TxCommand CreateCommand)
  | Log LogCommand
  | Submit SubmitCommand
  | Withdraw (TxCommand WithdrawCommand)

-- | Read options from the environment and the command line.
getOptions :: IO Options
getOptions = do
  historyHostParser <- optParserWithEnvDefault O.historyHost
  historySyncPortParser <- optParserWithEnvDefault O.historySyncPort
  txHostParser <- optParserWithEnvDefault O.txHost
  txCommandPortParser <- optParserWithEnvDefault O.txCommandPort
  let
    commandParser = asum
      [ hsubparser $ mconcat
          [ commandGroup "Contract history commands"
          , command "log" $ Log <$> logCommandParser
          ]
      , hsubparser $ mconcat
          [ commandGroup "Contract transaction commands"
          , command "apply" $ Apply <$> applyCommandParser
          , command "advance" $ Apply <$> advanceCommandParser
          , command "deposit" $ Apply <$> depositCommandParser
          , command "choose" $ Apply <$> chooseCommandParser
          , command "notify" $ Apply <$> notifyCommandParser
          , command "create" $ Create <$> createCommandParser
          , command "withdraw" $ Withdraw <$> withdrawCommandParser
          ]
      , hsubparser $ mconcat
          [ commandGroup "Low level commands"
          , command "submit" $ Submit <$> submitCommandParser
          ]
      ]
    parser = Options
      <$> historyHostParser
      <*> historySyncPortParser
      <*> txHostParser
      <*> txCommandPortParser
      <*> commandParser
    infoMod = mconcat
      [ fullDesc
      , progDesc "Command line interface for managing Marlowe smart contracts on Cardano."
      ]
  execParser $ info (helper <*> parser) infoMod

-- | Run a command.
runCommand :: Command -> CLI ()
runCommand = \case
  Apply cmd -> runApplyCommand cmd
  Create cmd -> runCreateCommand cmd
  Log cmd -> runLogCommand cmd
  Submit cmd -> runSubmitCommand cmd
  Withdraw cmd -> runWithdrawCommand cmd

-- | Interpret a CLI action in IO using the provided options.
runCLIWithOptions :: STM () -> Options -> CLI a -> IO a
runCLIWithOptions sigInt Options{..} cli = do
  historySyncAddr <- resolve historyHost historySyncPort
  txJobAddr <- resolve txHost txCommandPort
  runReaderT (runCLI cli) Env
    { envRunHistorySyncClient = runClientPeerOverSocket' "History sync client failure" historySyncAddr codecMarloweSync marloweSyncClientPeer
    , envRunTxJobClient = runClientPeerOverSocket' "Tx client client failure" txJobAddr codecJob jobClientPeer
    , sigInt
    }
  where
    resolve host port =
      head <$> getAddrInfo (Just defaultHints { addrSocketType = Stream }) (Just host) (Just $ show port)

runClientPeerOverSocket'
  :: forall protocol client (st :: protocol)
   . HasSignature protocol
  => String -- ^ Client failure stderr extra message
  -> AddrInfo -- ^ Socket address to connect to
  -> Codec protocol DeserializeError IO LB.ByteString -- ^ A codec for the protocol
  -> (forall a. client IO a -> Peer protocol 'AsClient st IO a) -- ^ Interpret the client as a protocol peer
  -> RunClient IO client
runClientPeerOverSocket' errMsg addr codec clientToPeer client = do
  let
    run = runClientPeerOverSocketWithHandshake throwIO addr codec clientToPeer client
  run `catch` \(err :: SomeException)-> do
    hPutStrLn stderr errMsg
    throw err
