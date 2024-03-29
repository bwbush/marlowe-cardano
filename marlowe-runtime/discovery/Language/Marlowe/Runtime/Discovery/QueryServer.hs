{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StrictData #-}

module Language.Marlowe.Runtime.Discovery.QueryServer
  where

import Control.Concurrent.Component
import Data.Void (Void, absurd)
import Language.Marlowe.Runtime.ChainSync.Api (PolicyId)
import Language.Marlowe.Runtime.Discovery.Api
import Network.Protocol.Driver (RunServer(..))
import Network.Protocol.Query.Server
import Network.Protocol.Query.Types
import Numeric.Natural (Natural)

type RunQueryServer m = RunServer m (QueryServer DiscoveryQuery)

data DiscoveryQueryServerDependencies = DiscoveryQueryServerDependencies
  { acceptRunQueryServer :: IO (RunQueryServer IO)
  , getHeaders :: IO [ContractHeader]
  , getHeadersByRoleTokenCurrency :: PolicyId -> IO [ContractHeader]
  , pageSize :: Natural
  }

discoveryQueryServer :: Component IO DiscoveryQueryServerDependencies ()
discoveryQueryServer = serverComponent worker \DiscoveryQueryServerDependencies{..} -> do
  runQueryServer <- acceptRunQueryServer
  pure WorkerDependencies {..}

data WorkerDependencies = WorkerDependencies
  { runQueryServer   :: RunQueryServer IO
  , getHeaders :: IO [ContractHeader]
  , getHeadersByRoleTokenCurrency :: PolicyId -> IO [ContractHeader]
  , pageSize :: Natural
  }

worker :: Component IO WorkerDependencies ()
worker = component_ \WorkerDependencies{..} -> do
  let
    RunServer run = runQueryServer

    server :: QueryServer DiscoveryQuery IO ()
    server = QueryServer $ pure $ ServerStInit \case
      GetContractHeaders ->
        getContractHeadersServer pageSize getHeaders
      GetContractHeadersByRoleTokenCurrency policyId ->
        getContractHeadersByRoleTokenCurrencyServer policyId getHeadersByRoleTokenCurrency
  run server

getContractHeadersServer
  :: Natural
  -> IO [ContractHeader]
  -> IO (ServerStNext DiscoveryQuery 'CanReject () Void [ContractHeader] IO ())
getContractHeadersServer pageSize getHeaders = next <$> getHeaders
  where
  next
    :: [ContractHeader]
    -> ServerStNext DiscoveryQuery k () Void [ContractHeader] IO ()
  next headers = case splitAt (fromIntegral pageSize) headers of
    (page, []) -> lastPage page
    (page, headers') -> SendMsgNextPage page (Just ()) ServerStPage
      { recvMsgDone = pure ()
      , recvMsgRequestNext = const $ pure $ next headers'
      }
  lastPage
    :: [ContractHeader]
    -> ServerStNext DiscoveryQuery k () Void [ContractHeader] IO ()
  lastPage page = SendMsgNextPage page Nothing ServerStPage
    { recvMsgDone = pure ()
    , recvMsgRequestNext = const $ pure $ lastPage []
    }

getContractHeadersByRoleTokenCurrencyServer
  :: PolicyId
  -> (PolicyId -> IO [ContractHeader])
  -> IO (ServerStNext DiscoveryQuery 'CanReject Void Void [ContractHeader] IO ())
getContractHeadersByRoleTokenCurrencyServer policyId getHeadersByRoleTokenCurrency = do
  headers <- getHeadersByRoleTokenCurrency policyId
  pure $ SendMsgNextPage headers Nothing ServerStPage
    { recvMsgDone = pure ()
    , recvMsgRequestNext = absurd
    }
