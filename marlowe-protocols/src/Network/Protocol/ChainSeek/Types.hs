{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

-- | The type of the chain seek protocol.

module Network.Protocol.ChainSeek.Types
  where

import Data.Aeson (ToJSON(..), Value(..), object, (.=))
import Data.Binary (Binary(..), Get, Put)
import Data.Data (type (:~:)(Refl))
import Data.Functor ((<&>))
import Data.Kind (Type)
import Data.Maybe (catMaybes)
import Data.Proxy (Proxy(..))
import Data.String (IsString)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import GHC.Show (showSpace)
import Network.Protocol.Codec.Spec (ArbitraryMessage(..), MessageEq(..), ShowProtocol(..))
import Network.Protocol.Driver (MessageToJSON(..))
import Network.Protocol.Handshake.Types (HasSignature(..))
import Network.TypedProtocol (PeerHasAgency(..), Protocol(..))
import Network.TypedProtocol.Codec (AnyMessageAndAgency(..))
import Test.QuickCheck (Arbitrary, Gen, arbitrary, oneof, shrink)

data SomeTag q = forall err result. SomeTag (Tag q err result)

class Query (q :: * -> * -> *) where
  data Tag q :: * -> * -> *
  tagFromQuery :: q err result -> Tag q err result
  tagEq :: Tag q err result -> Tag q err' result' -> Maybe (err :~: err', result :~: result')
  putTag :: Tag q err result -> Put
  getTag :: Get (SomeTag q)
  putQuery :: q err result -> Put
  getQuery :: Tag q err result -> Get (q err result)
  putErr :: Tag q err result -> err -> Put
  getErr :: Tag q err result -> Get err
  putResult :: Tag q err result -> result -> Put
  getResult :: Tag q err result -> Get result

class Query q => QueryToJSON (q :: * -> * -> *) where
  queryToJSON :: q err result -> Value
  errToJSON :: Tag q err result -> err -> Value
  resultToJSON :: Tag q err result -> result -> Value

-- | The type of states in the protocol.
data ChainSeek (query :: Type -> Type -> Type) point tip where
  -- | The server is waiting for the client to initiate the handshake.
  StInit :: ChainSeek query point tip

  -- | The client is waiting for the server to accept the handshake.
  StHandshake :: ChainSeek query point tip

  -- | The client and server are idle. The client can send a request.
  StIdle :: ChainSeek query point tip

  -- | The client has sent a next update request. The client is now waiting for
  -- a response, and the server is preparing to send a response. The server can
  -- respond immediately or it can send a 'Wait' message followed by a response
  -- at some point in the future.
  StNext :: err -> result -> ChainSeek query point tip

  -- | The server has sent a ping to the client to determine if it is still
  -- connected and is waiting for a pong.
  StPoll :: err -> result -> ChainSeek query point tip

  -- | The terminal state of the protocol.
  StDone :: ChainSeek query point tip

instance
  ( HasSignature query
  , HasSignature point
  , HasSignature tip
  ) => HasSignature (ChainSeek query point tip) where
  signature _ = T.intercalate " "
    [ "ChainSeek"
    , signature $ Proxy @query
    , signature $ Proxy @point
    , signature $ Proxy @tip
    ]

-- | Schema version used for
newtype SchemaVersion = SchemaVersion Text
  deriving stock (Show, Eq, Ord)
  deriving newtype (IsString, ToJSON)

instance Arbitrary SchemaVersion where
  arbitrary = SchemaVersion . T.pack <$> arbitrary

instance Binary SchemaVersion where
  put (SchemaVersion v) = put $ T.encodeUtf8 v
  get = do
    bytes <- get
    case T.decodeUtf8' bytes of
      Left err      -> fail $ show err
      Right version -> pure $ SchemaVersion version

instance Protocol (ChainSeek query point tip) where

  -- | The type of messages in the protocol. Corresponds to the state
  -- transition in the state machine diagram.
  data Message (ChainSeek query point tip) from to where

    -- | Initiate a handshake for the given schema version.
    MsgRequestHandshake :: SchemaVersion -> Message (ChainSeek query point tip)
      'StInit
      'StHandshake

    -- | Accept the handshake.
    MsgConfirmHandshake :: Message (ChainSeek query point tip)
      'StHandshake
      'StIdle

    -- | Reject the handshake.
    MsgRejectHandshake :: [SchemaVersion] -> Message (ChainSeek query point tip)
      'StHandshake
      'StDone

    -- | Request the next matching result for the given query from the client's
    -- position.
    MsgQueryNext :: query err result -> Message (ChainSeek query point tip)
      'StIdle
      ('StNext err result)

    -- | Reject a query with an error message.
    MsgRejectQuery :: err -> tip -> Message (ChainSeek query point tip)
      ('StNext err result)
      'StIdle

    -- | Send a response to a query and roll the client forward to a new point.
    MsgRollForward :: result -> point -> tip -> Message (ChainSeek query point tip)
      ('StNext err result)
      'StIdle

    -- | Roll the client backward.
    MsgRollBackward :: point -> tip -> Message (ChainSeek query point tip)
      ('StNext err result)
      'StIdle

    -- | Inform the client they must wait indefinitely to receive a reply.
    MsgWait :: Message (ChainSeek query point tip)
      ('StNext err result)
      ('StPoll err result)

    -- | End the protocol
    MsgDone :: Message (ChainSeek query point tip)
      'StIdle
      'StDone

    -- | Ask the server if there have been any updates.
    MsgPoll :: Message (ChainSeek query point tip)
      ('StPoll err result)
      ('StNext err result)

    -- | Cancel the polling loop.
    MsgCancel :: Message (ChainSeek query point tip)
      ('StPoll err result)
      'StIdle

  data ClientHasAgency st where
    TokInit :: ClientHasAgency 'StInit
    TokIdle :: ClientHasAgency 'StIdle
    TokPoll :: ClientHasAgency ('StPoll err result)

  data ServerHasAgency st where
    TokHandshake :: ServerHasAgency 'StHandshake
    TokNext :: Tag query err result -> ServerHasAgency ('StNext err result :: ChainSeek query point tip)

  data NobodyHasAgency st where
    TokDone :: NobodyHasAgency 'StDone

  exclusionLemma_ClientAndServerHaveAgency TokInit = \case
  exclusionLemma_ClientAndServerHaveAgency TokIdle = \case
  exclusionLemma_ClientAndServerHaveAgency TokPoll = \case

  exclusionLemma_NobodyAndClientHaveAgency TokDone  = \case

  exclusionLemma_NobodyAndServerHaveAgency TokDone  = \case

instance
  ( QueryToJSON query
  , ToJSON tip
  , ToJSON point
  ) => MessageToJSON (ChainSeek query point tip) where
  messageToJSON = \case
    ClientAgency TokInit -> \case
      MsgRequestHandshake version -> object [ "requestHandshake" .= toJSON version ]
    ClientAgency TokIdle -> \case
      MsgQueryNext query -> object [ "queryNext" .= queryToJSON query ]
      MsgDone -> String "done"
    ClientAgency TokPoll -> \case
      MsgPoll -> String "poll"
      MsgCancel -> String "cancel"
    ServerAgency TokHandshake -> \case
      MsgConfirmHandshake -> String "confirmHandshake"
      MsgRejectHandshake versions -> object [ "rejectHandshake" .= toJSON versions ]
    ServerAgency (TokNext tag) -> \case
      MsgRejectQuery err tip -> object
        [ "rejectQuery" .= object
            [ "error" .= errToJSON tag err
            , "tip" .= toJSON tip
            ]
        ]
      MsgRollForward result point tip -> object
        [ "rollForward" .= object
            [ "result" .= resultToJSON tag result
            , "point" .= toJSON point
            , "tip" .= toJSON tip
            ]
        ]
      MsgRollBackward point tip -> object
        [ "rollBackward" .= object
            [ "point" .= toJSON point
            , "tip" .= toJSON tip
            ]
        ]
      MsgWait -> String "wait"

class Query query => ArbitraryQuery query where
  arbitraryTag :: Gen (SomeTag query)
  arbitraryQuery :: Tag query err result -> Gen (query err result)
  arbitraryErr :: Tag query err result -> Maybe (Gen err)
  arbitraryResult :: Tag query err result -> Gen result
  shrinkQuery :: query err result -> [query err result]
  shrinkErr :: Tag query err result-> err -> [err]
  shrinkResult :: Tag query err result-> result -> [result]

instance
  ( Arbitrary point
  , Arbitrary tip
  , ArbitraryQuery query
  ) => ArbitraryMessage (ChainSeek query point tip) where
  arbitraryMessage = do
    SomeTag tag <- arbitraryTag
    let mGenError = arbitraryErr tag
    oneof $ catMaybes
      [ Just $ AnyMessageAndAgency (ClientAgency TokInit) . MsgRequestHandshake <$> arbitrary
      , Just $ pure $ AnyMessageAndAgency (ServerAgency TokHandshake) MsgConfirmHandshake
      , Just $ AnyMessageAndAgency (ServerAgency TokHandshake) . MsgRejectHandshake <$> arbitrary
      , Just $ do
          query <- arbitraryQuery tag
          pure $ AnyMessageAndAgency (ClientAgency TokIdle) $ MsgQueryNext query
      , Just $ pure $ AnyMessageAndAgency (ClientAgency TokIdle) MsgDone
      , mGenError <&> \genErr -> do
          tip <- arbitrary
          err <- genErr
          pure $ AnyMessageAndAgency (ServerAgency $ TokNext tag) $ MsgRejectQuery err tip
      , Just $ do
          result <- arbitraryResult tag
          point <- arbitrary
          tip <- arbitrary
          pure $ AnyMessageAndAgency (ServerAgency $ TokNext tag) $ MsgRollForward result point tip
      , Just $ do
          point <- arbitrary
          tip <- arbitrary
          pure $ AnyMessageAndAgency (ServerAgency $ TokNext tag) $ MsgRollBackward point tip
      , Just $ do
          pure $ AnyMessageAndAgency (ServerAgency $ TokNext tag) MsgWait
      , Just $ pure $ AnyMessageAndAgency (ClientAgency TokPoll) MsgPoll
      , Just $ pure $ AnyMessageAndAgency (ClientAgency TokPoll) MsgCancel
      ]
  shrinkMessage agency = \case
    MsgRequestHandshake version -> MsgRequestHandshake <$> shrink version
    MsgRejectHandshake versions -> MsgRejectHandshake <$> shrink versions
    MsgQueryNext query -> MsgQueryNext <$> shrinkQuery query
    MsgRejectQuery err tip -> []
      <> [ MsgRejectQuery err' tip | err' <- case agency of ServerAgency (TokNext tag) -> shrinkErr tag err ]
      <> [ MsgRejectQuery err tip' | tip' <- shrink tip ]
    MsgRollForward result point tip -> []
      <> [ MsgRollForward result' point tip | result' <- case agency of ServerAgency (TokNext tag) -> shrinkResult tag result ]
      <> [ MsgRollForward result point' tip | point' <- shrink point ]
      <> [ MsgRollForward result point tip' | tip' <- shrink tip ]
    MsgRollBackward point tip -> []
      <> [ MsgRollBackward point' tip | point' <- shrink point ]
      <> [ MsgRollBackward point tip' | tip' <- shrink tip ]
    _ -> []

class Query query => QueryEq query where
  queryEq :: query err result -> query err result -> Bool
  errEq :: Tag query err result -> err -> err -> Bool
  resultEq :: Tag query err result -> result -> result -> Bool

instance
  ( Eq point
  , Eq tip
  , QueryEq query
  ) => MessageEq (ChainSeek query point tip) where
  messageEq (AnyMessageAndAgency agency msg) = case (agency, msg) of
    (_, MsgRequestHandshake version) -> \case
      AnyMessageAndAgency _ (MsgRequestHandshake version') -> version == version'
      _ -> False
    (_, MsgRejectHandshake versions) -> \case
      AnyMessageAndAgency _ (MsgRejectHandshake versions') -> versions == versions'
      _ -> False
    (_, MsgConfirmHandshake) -> \case
      AnyMessageAndAgency _ MsgConfirmHandshake -> True
      _ -> False
    (_, MsgQueryNext query) -> \case
      AnyMessageAndAgency _ (MsgQueryNext query') ->
        case tagEq (tagFromQuery query) (tagFromQuery query') of
          Just (Refl, Refl) -> queryEq query query'
          Nothing -> False
      _ -> False
    (ServerAgency (TokNext tag), MsgRejectQuery err tip) -> \case
      AnyMessageAndAgency (ServerAgency (TokNext tag')) (MsgRejectQuery err' tip') ->
        tip == tip' && case tagEq tag tag' of
          Just (Refl, Refl) -> errEq tag err err'
          Nothing -> False
      _ -> False
    (ServerAgency (TokNext tag), MsgRollForward result point tip) -> \case
      AnyMessageAndAgency (ServerAgency (TokNext tag')) (MsgRollForward result' point' tip') ->
        point == point' && tip == tip' && case tagEq tag tag' of
          Just (Refl, Refl) -> resultEq tag result result'
          Nothing -> False
      _ -> False
    (_, MsgRollBackward point tip) -> \case
      AnyMessageAndAgency _ (MsgRollBackward point' tip') ->
        point == point' && tip == tip'
      _ -> False
    (_, MsgWait) -> \case
      AnyMessageAndAgency _ MsgWait -> True
      _ -> False
    (_, MsgDone) -> \case
      AnyMessageAndAgency _ MsgDone -> True
      _ -> False
    (_, MsgPoll) -> \case
      AnyMessageAndAgency _ MsgPoll -> True
      _ -> False
    (_, MsgCancel) -> \case
      AnyMessageAndAgency _ MsgCancel -> True
      _ -> False

class Query query => ShowQuery query where
  showsPrecTag :: Int -> Tag query err result -> ShowS
  showsPrecQuery :: Int -> query err result -> ShowS
  showsPrecErr :: Int -> Tag query err result -> err -> ShowS
  showsPrecResult :: Int -> Tag query err result -> result -> ShowS

instance
  ( Show point
  , Show tip
  , ShowQuery query
  ) => ShowProtocol (ChainSeek query point tip) where
  showsPrecMessage p agency = \case
    MsgRequestHandshake version -> showParen (p >= 11)
      ( showString "MsgRequestHandshake"
      . showSpace
      . showsPrec 11 version
      )
    MsgRejectHandshake versions -> showParen (p >= 11)
      ( showString "MsgRejectHandshake"
      . showSpace
      . showsPrec 11 versions
      )
    MsgConfirmHandshake -> showString "MsgConfirmHandshake"
    MsgQueryNext query -> showParen (p >= 11)
      ( showString "MsgQueryNext"
      . showSpace
      . showsPrecQuery 11 query
      )
    MsgRejectQuery err tip -> showParen (p >= 11)
      ( showString "MsgRejectQuery"
      . showSpace
      . case agency of ServerAgency (TokNext tag) -> showsPrecErr 11 tag err
      . showSpace
      . showsPrec 11 tip
      )
    MsgRollForward result point tip -> showParen (p >= 11)
      ( showString "MsgRollForward"
      . showSpace
      . case agency of ServerAgency (TokNext tag) -> showsPrecResult 11 tag result
      . showSpace
      . showsPrec 11 point
      . showSpace
      . showsPrec 11 tip
      )
    MsgRollBackward point tip -> showParen (p >= 11)
      ( showString "MsgRollBackward"
      . showSpace
      . showsPrec 11 point
      . showSpace
      . showsPrec 11 tip
      )
    MsgWait -> showString "MsgWait"
    MsgDone -> showString "MsgDone"
    MsgPoll -> showString "MsgPoll"
    MsgCancel -> showString "MsgCancel"

  showsPrecServerHasAgency p = \case
    TokHandshake -> showString "TokHandshake"
    TokNext tag -> showParen (p >= 11)
      ( showString "TokNext"
      . showSpace
      . showsPrecTag p tag
      )

  showsPrecClientHasAgency _ = showString . \case
    TokInit -> "TokInit"
    TokIdle -> "TokIdle"
    TokPoll -> "TokPoll"
