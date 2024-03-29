{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

module Language.Marlowe.Runtime.Web.Client
  ( Page(..)
  , getContract
  , getContracts
  , getTransaction
  , getTransactions
  , postContract
  , postTransaction
  , putContract
  , putTransaction
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Functor (void)
import Data.Maybe (fromJust)
import Data.Proxy (Proxy(..))
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.TypeLits (KnownSymbol, symbolVal)
import Language.Marlowe.Runtime.Web.API
  (API, GetContractsResponse, GetTransactionsResponse, ListObject(..), api, retractLink)
import Language.Marlowe.Runtime.Web.Types
import Servant (ResponseHeader(..), getResponse, lookupResponseHeader, type (:<|>)((:<|>)))
import Servant.Client (Client, ClientM)
import qualified Servant.Client as Servant
import Servant.Pagination (ExtractRange(extractRange), HasPagination(..), PutRange(..), Range, Ranges)

client :: Client ClientM API
client = Servant.client api

data Page field resource = Page
  { totalCount :: Int
  , nextRange :: Range field (RangeType resource field)
  , items :: [resource]
  }

getContracts
  :: Maybe (Range "contractId" TxOutRef)
  -> ClientM (Page "contractId" ContractHeader)
getContracts range = do
  let getContracts' :<|> _ = client
  response <- getContracts' $ putRange <$> range
  totalCount <- reqHeaderValue $ lookupResponseHeader @"Total-Count" response
  nextRanges <- reqHeaderValue $ lookupResponseHeader @"Next-Range" response
  let ListObject items = getResponse response
  pure Page
    { totalCount
    , nextRange = extractRangeSingleton @GetContractsResponse nextRanges
    , items = retractLink <$> items
    }

postContract
  :: Address
  -> Maybe (Set Address)
  -> Maybe (Set TxOutRef)
  -> PostContractsRequest
  -> ClientM CreateTxBody
postContract changeAddress otherAddresses collateralUtxos request = do
  let _ :<|> postContract' :<|> _ = client
  response <- postContract'
    request
    changeAddress
    (setToCommaList <$> otherAddresses)
    (setToCommaList <$> collateralUtxos)
  pure $ retractLink response

getContract :: TxOutRef -> ClientM ContractState
getContract contractId = do
  let _ :<|> _ :<|> contractApi = client
  let getContract' :<|> _ = contractApi contractId
  retractLink <$> getContract'

putContract :: TxOutRef -> TextEnvelope -> ClientM ()
putContract contractId tx = do
  let _ :<|> _ :<|> contractApi = client
  let _ :<|> putContract' :<|> _ = contractApi contractId
  void $ putContract' tx

getTransactions
  :: TxOutRef
  -> Maybe (Range "transactionId" TxId)
  -> ClientM (Page "transactionId" TxHeader)
getTransactions contractId range = do
  let _ :<|> _ :<|> contractApi = client
  let _ :<|> _ :<|> getTransactions' :<|> _= contractApi contractId
  response <- getTransactions' $ putRange <$> range
  totalCount <- reqHeaderValue $ lookupResponseHeader @"Total-Count" response
  nextRanges <- reqHeaderValue $ lookupResponseHeader @"Next-Range" response
  let ListObject items = getResponse response
  pure Page
    { totalCount
    , nextRange = extractRangeSingleton @GetTransactionsResponse nextRanges
    , items = retractLink <$> items
    }

postTransaction
  :: Address
  -> Maybe (Set Address)
  -> Maybe (Set TxOutRef)
  -> TxOutRef
  -> PostTransactionsRequest
  -> ClientM ApplyInputsTxBody
postTransaction changeAddress otherAddresses collateralUtxos contractId request = do
  let _ :<|> _ :<|> contractApi = client
  let _ :<|> _ :<|> _ :<|> postTransactions' :<|> _ = contractApi contractId
  response <- postTransactions'
    request
    changeAddress
    (setToCommaList <$> otherAddresses)
    (setToCommaList <$> collateralUtxos)
  pure $ retractLink response

getTransaction :: TxOutRef -> TxId -> ClientM Tx
getTransaction contractId transactionId = do
  let _ :<|> _ :<|> contractApi = client
  let _ :<|> _ :<|> _ :<|> _ :<|> transactionApi = contractApi contractId
  let getTransaction' :<|> _ = transactionApi transactionId
  retractLink . retractLink <$> getTransaction'

putTransaction :: TxOutRef -> TxId -> TextEnvelope -> ClientM ()
putTransaction contractId transactionId tx = do
  let _ :<|> _ :<|> contractApi = client
  let _ :<|> _ :<|> _ :<|> _ :<|> transactionApi = contractApi contractId
  let _ :<|> putTransaction' = transactionApi transactionId
  void $ putTransaction' tx

setToCommaList :: Set a -> CommaList a
setToCommaList = CommaList . Set.toList

reqHeaderValue :: forall name a. KnownSymbol name => ResponseHeader name a -> ClientM a
reqHeaderValue = \case
  Header a -> pure a
  UndecodableHeader _ -> liftIO $ fail $ "Unable to decode header " <> symbolVal (Proxy @name)
  MissingHeader -> liftIO $ fail $ "Required header missing " <> symbolVal (Proxy @name)

extractRangeSingleton
  :: HasPagination resource field
  => Ranges '[field] resource
  -> Range field (RangeType resource field)
extractRangeSingleton = fromJust . extractRange
