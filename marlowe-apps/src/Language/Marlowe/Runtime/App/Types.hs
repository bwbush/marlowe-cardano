{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}


module Language.Marlowe.Runtime.App.Types
  ( App
  , Client(..)
  , Config(..)
  , MarloweRequest(..)
  , MarloweResponse(..)
  , RunClient
  , Services(..)
  , mkBody
  ) where


import Control.Applicative (Alternative)
import Control.Monad.Base (MonadBase)
import Control.Monad.Cleanup (MonadCleanup)
import Control.Monad.Except (ExceptT)
import Control.Monad.Fix (MonadFix)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Trans.Control (MonadBaseControl)
import Control.Monad.Trans.Reader (ReaderT(..))
import Data.Default (Default(..))
import Data.String (fromString)
import Language.Marlowe (POSIXTime(..))
import Language.Marlowe.Protocol.HeaderSync.Client (MarloweHeaderSyncClient)
import Language.Marlowe.Protocol.Query.Client (MarloweQueryClient)
import Language.Marlowe.Protocol.Sync.Client (MarloweSyncClient)
import Language.Marlowe.Runtime.Cardano.Api (fromCardanoTxId)
import Language.Marlowe.Runtime.ChainSync.Api
  ( Address
  , ChainSyncCommand
  , Lovelace(..)
  , RuntimeChainSeekClient
  , TokenName
  , TransactionMetadata
  , TxId
  , TxOutRef
  , fromBech32
  , fromJSONEncodedTransactionMetadata
  , toBech32
  )
import Language.Marlowe.Runtime.Core.Api
  ( ContractId
  , IsMarloweVersion(Contract, Inputs)
  , MarloweVersionTag(V1)
  , Payout(..)
  , Transaction(Transaction, blockHeader, contractId, inputs, output, transactionId, validityLowerBound, validityUpperBound)
  , TransactionOutput(payouts, scriptOutput)
  , TransactionScriptOutput(..)
  , renderContractId
  )
import Language.Marlowe.Runtime.Discovery.Api (ContractHeader)
import Language.Marlowe.Runtime.History.Api
  (ContractStep(..), CreateStep(..), RedeemStep(RedeemStep, datum, redeemingTx, utxo))
import Language.Marlowe.Runtime.Transaction.Api (MarloweTxCommand)
import Network.Protocol.Job.Client (JobClient)
import Network.Socket (HostName, PortNumber)

import qualified Cardano.Api as C
  ( AsType(AsBabbageEra, AsPaymentExtendedKey, AsPaymentKey, AsSigningKey, AsTx, AsTxBody)
  , BabbageEra
  , HasTextEnvelope
  , PaymentExtendedKey
  , PaymentKey
  , SigningKey
  , TextEnvelope
  , Tx
  , TxBody
  , deserialiseFromTextEnvelope
  , getTxId
  , serialiseToTextEnvelope
  )
import qualified Data.Aeson.Types as A
  (FromJSON(parseJSON), Parser, ToJSON(toJSON), Value(String), object, parseFail, withObject, (.:), (.=))
import qualified Data.Map.Strict as M (Map, map, mapKeys)
import qualified Data.Text as T (Text)
import qualified Language.Marlowe.Runtime.ChainSync.Api as CS (Transaction)


type App = ExceptT String IO


data Config =
  Config
  { chainSeekHost :: HostName
  , chainSeekCommandPort :: PortNumber
  , chainSeekSyncPort :: PortNumber
  , syncHost :: HostName
  , syncSyncPort :: PortNumber
  , syncHeaderPort :: PortNumber
  , syncQueryPort :: PortNumber
  , txHost :: HostName
  , txCommandPort :: PortNumber
  , timeoutSeconds :: Int
  , buildSeconds :: Int
  , confirmSeconds :: Int
  , retrySeconds :: Int
  , retryLimit :: Int
  }
    deriving (Read, Show)

instance Default Config where
  def =
    Config
    { chainSeekHost = "127.0.0.1"
    , chainSeekCommandPort = 3720
    , chainSeekSyncPort = 3715
    , syncHost = "127.0.0.1"
    , syncSyncPort = 3724
    , syncHeaderPort = 3725
    , syncQueryPort = 3726
    , txHost = "127.0.0.1"
    , txCommandPort = 3723
    , timeoutSeconds = 600
    , buildSeconds = 3
    , confirmSeconds = 3
    , retrySeconds = 10
    , retryLimit = 5
    }


data Services m =
  Services
  { runChainSeekCommandClient :: RunClient m (JobClient ChainSyncCommand)
  , runChainSeekSyncClient :: RunClient m RuntimeChainSeekClient
  , runSyncSyncClient :: RunClient m MarloweSyncClient
  , runSyncHeaderClient :: RunClient m MarloweHeaderSyncClient
  , runSyncQueryClient :: RunClient m MarloweQueryClient
  , runTxCommandClient :: RunClient m (JobClient MarloweTxCommand)
  }


-- | A monad type for Marlowe Runtime.Client programs.
newtype Client a = Client { runClient :: ReaderT (Services IO) IO a }
  deriving newtype (Alternative, Applicative, Functor, Monad, MonadBase IO, MonadBaseControl IO, MonadCleanup, MonadFail, MonadFix, MonadIO)


-- | A function signature for running a client for some protocol in some monad m.
type RunClient m client = forall a. client m a -> m a


data MarloweRequest v =
    ListContracts
  | ListHeaders
  | Get
    { reqContractId :: ContractId
    }
  | Create
    { reqContract :: Contract v
    , reqRoles :: M.Map TokenName Address
    , reqMinUtxo :: Lovelace
--  , reqStakeAddress :: Maybe StakeCredential
    , reqMetadata :: TransactionMetadata
    , reqAddresses :: [Address]
    , reqChange :: Address
    , reqCollateral :: [TxOutRef]
    }
  | Apply
    { reqContractId :: ContractId
    , reqInputs :: Inputs v
    , reqValidityLowerBound :: Maybe POSIXTime
    , reqValidityUpperBound :: Maybe POSIXTime
    , reqMetadata :: TransactionMetadata
    , reqAddresses :: [Address]
    , reqChange :: Address
    , reqCollateral :: [TxOutRef]
    }
  | Withdraw
    { reqContractId :: ContractId
    , reqRole :: TokenName
    , reqAddresses :: [Address]
    , reqChange :: Address
    , reqCollateral :: [TxOutRef]
    }
  | Sign
    { reqTxBody :: C.TxBody C.BabbageEra
    , reqPaymentKeys :: [C.SigningKey C.PaymentKey]
    , reqPaymentExtendedKeys :: [C.SigningKey C.PaymentExtendedKey]
    }
  | Submit
    { reqTx :: C.Tx C.BabbageEra
    }
  | Wait
    { reqTxId :: TxId
    , reqPollingSeconds :: Int
    }


instance A.FromJSON (MarloweRequest 'V1) where
  parseJSON =
    A.withObject "MarloweRequest"
      $ \o ->
        (o A..: "request" :: A.Parser String)
          >>= \case
            "list" -> pure ListContracts
            "headers" -> pure ListHeaders
            "get" -> do
                       reqContractId <- fromString <$> o A..: "contractId"
                       pure Get{..}
            "create" -> do
                          reqContract <- o A..: "contract"
                          reqRoles <- M.mapKeys fromString . M.map fromString <$> (o A..: "roles" :: A.Parser (M.Map String String))
                          reqMinUtxo <- Lovelace <$> o A..: "minUtxo"
                          reqMetadata <- metadataFromJSON =<< o A..: "metadata"
                          reqAddresses <- mapM addressFromJSON =<< o A..: "addresses"
                          reqChange <- addressFromJSON =<< o A..: "change"
                          reqCollateral <- fmap fromString <$> o A..: "collateral"
                          pure Create{..}
            "apply" -> do
                         reqContractId <- fromString <$> o A..: "contractId"
                         reqInputs <- o A..: "inputs"
                         reqValidityLowerBound <- Just . POSIXTime <$> o A..: "validityLowerBound"
                         reqValidityUpperBound <- Just . POSIXTime <$> o A..: "validityUpperBound"
                         reqMetadata <- metadataFromJSON =<< o A..: "metadata"
                         reqAddresses <- mapM addressFromJSON =<< o A..: "addresses"
                         reqChange <- addressFromJSON =<< o A..: "change"
                         reqCollateral <- fmap fromString <$> o A..: "collateral"
                         pure Apply{..}
            "withdraw" -> do
                            reqContractId <- fromString <$> o A..: "contractId"
                            reqRole <- fromString <$> o A..: "role"
                            reqAddresses <- mapM addressFromJSON =<< o A..: "addresses"
                            reqChange <- addressFromJSON =<< o A..: "change"
                            reqCollateral <- fmap fromString <$> o A..: "collateral"
                            pure Withdraw{..}
            "sign" -> do
                        reqTxBody <- textEnvelopeFromJSON (C.AsTxBody C.AsBabbageEra) =<< o A..: "body"
                        reqPaymentKeys <- mapM (textEnvelopeFromJSON $ C.AsSigningKey C.AsPaymentKey) =<< o A..: "paymentKeys"
                        reqPaymentExtendedKeys <- mapM (textEnvelopeFromJSON $ C.AsSigningKey C.AsPaymentExtendedKey) =<< o A..: "paymentExtendedKeys"
                        pure Sign{..}
            "submit" -> do
                        reqTx <- textEnvelopeFromJSON (C.AsTx C.AsBabbageEra) =<< o A..: "tx"
                        pure Submit{..}
            "wait" -> do
                        reqTxId <- fromString <$> o A..: "txId"
                        reqPollingSeconds <- o A..: "pollingSeconds"
                        pure Wait{..}
            request -> fail $ "Invalid request: " <> request <> "."

instance A.ToJSON (MarloweRequest 'V1) where
  toJSON ListContracts = A.object ["request" A..= ("list" :: String)]
  toJSON ListHeaders = A.object ["request" A..= ("headers" :: String)]
  toJSON Get{..} =
    A.object
      [ "request" A..= ("get" :: String)
      , "contractId" A..= renderContractId reqContractId
      ]
  toJSON Create{..} =
    A.object
      [ "request" A..= ("create" :: String)
      , "contract" A..= reqContract
      , "roles" A..= M.mapKeys show reqRoles
      , "minUtxo" A..= unLovelace reqMinUtxo
      , "metadata" A..= reqMetadata
      , "addresses" A..= fmap addressToJSON reqAddresses
      , "change" A..= addressToJSON reqChange
      , "collateral" A..= reqCollateral
      ]
  toJSON Apply{..} =
    A.object
      [ "request" A..= ("apply" :: String)
      , "inputs" A..= reqInputs
      , "validityLowerBound" A..= fmap getPOSIXTime reqValidityLowerBound
      , "validityUpperBound" A..= fmap getPOSIXTime reqValidityUpperBound
      , "metadata" A..= reqMetadata
      , "addresses" A..= fmap addressToJSON reqAddresses
      , "change" A..= addressToJSON reqChange
      , "collateral" A..= reqCollateral
      ]
  toJSON Withdraw{..} =
    A.object
      [ "request" A..= ("withdraw" :: String)
      , "role" A..= reqRole
      , "addresses" A..= fmap addressToJSON reqAddresses
      , "change" A..= addressToJSON reqChange
      , "collateral" A..= reqCollateral
      ]
  toJSON Sign{..} =
    A.object
      [ "request" A..= ("sign" :: String)
      , "body" A..= textEnvelopeToJSON reqTxBody
      , "paymentKeys" A..= fmap textEnvelopeToJSON reqPaymentKeys
      , "paymentExtendedKeys" A..= fmap textEnvelopeToJSON reqPaymentExtendedKeys
      ]
  toJSON Submit{..} =
    A.object
      [ "request" A..= ("submit" :: String)
      , "tx" A..= textEnvelopeToJSON reqTx
      ]
  toJSON Wait{..} =
    A.object
      [ "request" A..= ("wait" :: String)
      , "txId" A..= reqTxId
      , "pollingSeconds" A..= reqPollingSeconds
      ]


data MarloweResponse v =
    Contracts
    { resContractIds :: [ContractId]
    }
  | Headers
    { resContractHeaders :: [ContractHeader]
    }
  | FollowResult
    { resResult :: Bool
    }
  | Info
    { resCreation :: CreateStep v
    , resSteps :: [ContractStep v]
    }
  | Body
    { resContractId :: ContractId
    , resTxId :: TxId
    , resTxBody :: C.TxBody C.BabbageEra
    }
  | Tx
    { resTxId :: TxId
    , resTx :: C.Tx C.BabbageEra
    }
  | TxId
    { resTxId :: TxId
    }
  | TxInfo
    {
      resTransaction :: CS.Transaction
    }


instance A.ToJSON (MarloweResponse 'V1) where
  toJSON Contracts{..} =
    A.object
      [ "response" A..= ("contracts" :: String)
      , "contractIds" A..= fmap renderContractId resContractIds
      ]
  toJSON Headers{..} =
    A.object
      [ "response" A..= ("headers" :: String)
      , "contractHeaders" A..= resContractHeaders
      ]
  toJSON FollowResult{..} =
    A.object
      [ "response" A..= ("result" :: String)
      , "result" A..= resResult
      ]
  toJSON Info{..} =
    A.object
      [ "response" A..= ("info" :: String)
      , "creation" A..= contractCreationToJSON resCreation
      , "steps" A..= fmap contractStepToJSON resSteps
      ]
  toJSON Body{..} =
    A.object
      [ "response" A..= ("body" :: String)
      , "contractId" A..= renderContractId resContractId
      , "txId" A..= C.getTxId resTxBody
      , "body" A..= textEnvelopeToJSON resTxBody
      ]
  toJSON Tx{..} =
    A.object
      [ "response" A..= ("tx" :: String)
      , "txId" A..= resTxId
      , "tx" A..= textEnvelopeToJSON resTx
      ]
  toJSON TxId{..} =
    A.object
      [ "response" A..= ("txId" :: String)
      , "txId" A..= resTxId
      ]
  toJSON TxInfo{..} =
    A.object
      [ "reponse" A..= ("txInfo" :: String)
      , "transaction" A..= resTransaction
      ]


contractCreationToJSON :: CreateStep 'V1-> A.Value
contractCreationToJSON CreateStep{..} =
  A.object
    [ "output" A..= transactionScriptOutputToJSON createOutput
    , "payoutValidatorHash" A..= filter (/= '"') (show payoutValidatorHash)
    ]


contractStepToJSON :: ContractStep 'V1-> A.Value
contractStepToJSON (ApplyTransaction Transaction{..}) =
  A.object
    [ "step" A..= ("apply" :: String)
    , "txId" A..= transactionId
    , "contractId" A..= renderContractId contractId
    , "redeemer" A..= inputs
    , "scriptOutput" A..= fmap transactionScriptOutputToJSON (scriptOutput output)
    , "payouts" A..= M.map payoutToJSON (payouts output)
    ]
contractStepToJSON (RedeemPayout RedeemStep{..}) =
  A.object
    [ "step" A..= ("payout" :: String)
    , "utxo" A..= utxo
    , "redeemingTx" A..= redeemingTx
    , "datumm" A..= datum
    ]


transactionScriptOutputToJSON :: TransactionScriptOutput 'V1 -> A.Value
transactionScriptOutputToJSON TransactionScriptOutput{..} =
  A.object
    [ "address" A..= address
    , "assets" A..= assets
    , "utxo" A..= utxo
    , "datum" A..= datum
    ]


payoutToJSON :: Payout 'V1 -> A.Value
payoutToJSON Payout{..} =
  A.object
    [ "address" A..= address
    , "assets" A..= assets
    , "datum" A..= datum
    ]


textEnvelopeFromJSON :: C.HasTextEnvelope a => C.AsType a -> C.TextEnvelope -> A.Parser a
textEnvelopeFromJSON asType envelope =
  do
    case C.deserialiseFromTextEnvelope asType envelope of
      Left msg -> fail $ show msg
      Right body -> pure body


textEnvelopeToJSON :: C.HasTextEnvelope a => a -> A.Value
textEnvelopeToJSON x =
  let
    envelope = C.serialiseToTextEnvelope Nothing x
  in
    A.toJSON envelope


mkBody :: ContractId -> C.TxBody C.BabbageEra -> MarloweResponse v
mkBody resContractId resTxBody =
  let
    resTxId = fromCardanoTxId $ C.getTxId resTxBody
  in
    Body{..}


addressFromJSON :: T.Text -> A.Parser Address
addressFromJSON = maybe (A.parseFail "Failed decoding Bech32 address.") pure . fromBech32


addressToJSON :: Address -> A.Value
addressToJSON = maybe (error "Failed encoding Bech32 address.") A.String . toBech32


metadataFromJSON :: A.Value -> A.Parser TransactionMetadata
metadataFromJSON = maybe (A.parseFail "Failed decoding transaction metadata.") pure . fromJSONEncodedTransactionMetadata
