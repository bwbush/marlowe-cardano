{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}

module Language.Marlowe.Protocol.Query.Types
  where

import Data.Aeson (ToJSON(..), Value(..), object, (.=))
import Data.Bifunctor (bimap)
import Data.Binary (Binary(..), getWord8, putWord8)
import Data.Map (Map)
import Data.Type.Equality (testEquality, type (:~:)(Refl))
import GHC.Generics (Generic)
import GHC.Show (showCommaSpace, showSpace)
import Language.Marlowe.Runtime.ChainSync.Api (BlockHeader, PolicyId, TransactionMetadata, TxOutRef)
import Language.Marlowe.Runtime.Core.Api
  (ContractId, MarloweVersion(..), MarloweVersionTag(..), Payout, SomeMarloweVersion(..), TransactionScriptOutput)
import Language.Marlowe.Runtime.Discovery.Api (ContractHeader)
import Network.Protocol.Codec.Spec (MessageEq(..), ShowProtocol(..))
import Network.Protocol.Driver (MessageToJSON(..))
import Network.TypedProtocol
import Network.TypedProtocol.Codec (AnyMessageAndAgency(..))

data MarloweQuery where
  StReq :: MarloweQuery
  StRes :: a -> MarloweQuery
  StDone :: MarloweQuery

data Request a where
  ReqContractHeaders :: Range ContractId -> Request (Page ContractId ContractHeader)
  ReqContractState :: ContractId -> Request (Maybe SomeContractState)
  ReqBoth :: Request a -> Request b -> Request (a, b)

data SomeRequest where
  SomeRequest :: Request a -> SomeRequest

instance Binary SomeRequest where
  get = do
    tag <- getWord8
    case tag of
      0x00 -> do
        SomeRequest a <- get
        SomeRequest b <- get
        pure $ SomeRequest $ ReqBoth a b
      0x01 -> SomeRequest . ReqContractHeaders <$> get
      0x02 -> SomeRequest . ReqContractState <$> get
      _ -> fail "Invalid Request tag"

  put (SomeRequest req) = case req of
    ReqBoth a b -> do
      putWord8 0x00
      put $ SomeRequest a
      put $ SomeRequest b
    ReqContractHeaders range -> do
      putWord8 0x01
      put range
    ReqContractState contractId -> do
      putWord8 0x02
      put contractId

deriving instance Eq (Request a)
deriving instance Show (Request a)
instance ToJSON (Request a) where
  toJSON = \case
    ReqBoth a b -> object
      [ "req-both" .= (toJSON a, toJSON b)
      ]
    ReqContractHeaders range -> object
      [ "get-contract-headers-for-range" .= range
      ]
    ReqContractState contractId -> object
      [ "get-contract-state" .= contractId
      ]

data StRes a where
  TokContractHeaders :: StRes (Page ContractId ContractHeader)
  TokContractState :: StRes (Maybe SomeContractState)
  TokBoth :: StRes a -> StRes b -> StRes (a, b)

deriving instance Show (StRes a)
deriving instance Eq (StRes a)

instance Protocol MarloweQuery where
  data Message MarloweQuery st st' where
    MsgRequest :: Request a -> Message MarloweQuery
      'StReq
      ('StRes a)

    MsgRespond :: a -> Message MarloweQuery
      ('StRes a)
      'StReq

    MsgDone :: Message MarloweQuery
      'StReq
      'StDone

  data ClientHasAgency ps where
    TokReq :: ClientHasAgency 'StReq

  data ServerHasAgency ps where
    TokRes :: StRes a -> ServerHasAgency ('StRes a)

  data NobodyHasAgency ps where
    TokDone :: NobodyHasAgency 'StDone

  exclusionLemma_ClientAndServerHaveAgency TokReq = \case
  exclusionLemma_NobodyAndClientHaveAgency TokDone = \case
  exclusionLemma_NobodyAndServerHaveAgency TokDone = \case

data Range a = Range
  { rangeStart :: Maybe a
  , rangeOffset :: Int
  , rangeLimit :: Int
  , rangeDirection :: Order
  }
  deriving stock (Eq, Show, Read, Ord, Functor, Generic, Foldable, Traversable)
  deriving anyclass (ToJSON, Binary)

data Page a b = Page
  { items :: [b]
  , nextRange :: Maybe (Range a)
  , totalCount :: Int
  }
  deriving stock (Eq, Show, Read, Ord, Functor, Generic, Foldable, Traversable)
  deriving anyclass (ToJSON, Binary)

data SomeContractState = forall v. SomeContractState (MarloweVersion v) (ContractState v)

instance Show SomeContractState where
  showsPrec p (SomeContractState MarloweV1 state) = showParen (p >= 11)
    ( showString "SomeContractState"
    . showSpace
    . showsPrec 11 MarloweV1
    . showSpace
    . showsPrec 11 state
    )

instance Eq SomeContractState where
  SomeContractState v state == SomeContractState v' state' = case testEquality v v' of
    Nothing -> False
    Just Refl -> case v of
      MarloweV1 -> state == state'

instance Binary SomeContractState where
  put (SomeContractState MarloweV1 state) = do
    put $ SomeMarloweVersion MarloweV1
    put state
  get = do
    SomeMarloweVersion MarloweV1 <- get
    SomeContractState MarloweV1 <$> get

instance ToJSON SomeContractState where
  toJSON (SomeContractState MarloweV1 state) = object
    [ "version" .= MarloweV1
    , "state" .= state
    ]

data ContractState v = ContractState
  { contractId :: ContractId
  , roleTokenMintingPolicyId :: PolicyId
  , metadata :: TransactionMetadata
  , initialBlock :: BlockHeader
  , initialOutput :: TransactionScriptOutput v
  , latestBlock :: BlockHeader
  , latestOutput :: Maybe (TransactionScriptOutput v)
  , availablePayouts :: Map TxOutRef (Payout v)
  } deriving (Generic)

deriving instance Show (ContractState 'V1)
deriving instance Eq (ContractState 'V1)
deriving instance ToJSON (ContractState 'V1)
deriving instance Binary (ContractState 'V1)

data Order = Ascending | Descending
  deriving stock (Eq, Show, Read, Ord, Enum, Bounded, Generic)
  deriving anyclass (ToJSON, Binary)

instance MessageToJSON MarloweQuery where
  messageToJSON = \case
    ClientAgency TokReq -> \case
      MsgRequest req -> object [ "request" .= req ]
      MsgDone -> String "done"
    ServerAgency (TokRes req) -> \case
      MsgRespond a -> object [ "respond" .= responseToJSON req a ]

    where
      responseToJSON :: StRes a -> a -> Value
      responseToJSON = \case
        TokContractHeaders -> toJSON
        TokContractState -> toJSON
        TokBoth a b -> toJSON . bimap (responseToJSON a) (responseToJSON b)

instance ShowProtocol MarloweQuery where
  showsPrecMessage p =  \case
    ClientAgency TokReq -> \case
      MsgRequest req -> showParen (p >= 11) (showString "MsgRequest" . showSpace . showsPrec 11 req)
      MsgDone -> showString "MsgDone"
    ServerAgency (TokRes req) -> \case
      MsgRespond a -> showParen (p >= 11) (showString "MsgRespond" . showSpace . showsPrecResult req 11 a)
    where
      showsPrecResult :: StRes a -> Int -> a -> String -> String
      showsPrecResult = \case
        TokContractHeaders -> showsPrec
        TokContractState -> showsPrec
        TokBoth ta tb -> \_ (a, b) -> showParen True (showsPrecResult ta 0 a . showCommaSpace . showsPrecResult tb 0 b)
  showsPrecServerHasAgency p (TokRes req) = showParen (p >= 11) (showString "TokRes" . showSpace . showsPrec 11 req)
  showsPrecClientHasAgency _ TokReq = showString "TokReq"

instance MessageEq MarloweQuery where
  messageEq = \case
    AnyMessageAndAgency (ClientAgency TokReq) (MsgRequest req) -> \case
      AnyMessageAndAgency (ClientAgency TokReq) (MsgRequest req') -> reqEq req req'
      _ -> False
    AnyMessageAndAgency (ClientAgency TokReq) MsgDone -> \case
      AnyMessageAndAgency (ClientAgency TokReq) MsgDone -> True
      _ -> False
    AnyMessageAndAgency (ServerAgency (TokRes req)) (MsgRespond a) -> \case
      AnyMessageAndAgency (ServerAgency (TokRes req')) (MsgRespond a') -> resultEq req req' a a'
      _ -> False
    where
      reqEq :: Request a -> Request a1 -> Bool
      reqEq (ReqBoth a b) (ReqBoth a' b') = reqEq a a' && reqEq b b'
      reqEq (ReqBoth _ _) _ = False
      reqEq (ReqContractHeaders range) (ReqContractHeaders range') = range == range'
      reqEq (ReqContractHeaders _) _ = False
      reqEq (ReqContractState contractId) (ReqContractState contractId') = contractId == contractId'
      reqEq (ReqContractState _) _ = False

      resultEq :: StRes a -> StRes b -> a -> b -> Bool
      resultEq (TokBoth ta tb) (TokBoth ta' tb') = \(a, b) (a', b') ->
        resultEq ta ta' a a' && resultEq tb tb' b b'
      resultEq (TokBoth _ _) _ = const $ const False
      resultEq TokContractHeaders TokContractHeaders = (==)
      resultEq TokContractHeaders _ = const $ const False
      resultEq TokContractState TokContractState = (==)
      resultEq TokContractState _ = const $ const False

requestToSt :: Request x -> StRes x
requestToSt = \case
  ReqContractHeaders _ -> TokContractHeaders
  ReqContractState _ -> TokContractState
  ReqBoth r1 r2 -> TokBoth (requestToSt r1) (requestToSt r2)
