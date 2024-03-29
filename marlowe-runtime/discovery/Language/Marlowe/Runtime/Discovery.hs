{-# LANGUAGE Arrows #-}
{-# LANGUAGE RankNTypes #-}

module Language.Marlowe.Runtime.Discovery
  where

import Control.Concurrent.Component
import Data.Set (Set)
import qualified Language.Marlowe.Runtime.ChainSync.Api as Chain
import Language.Marlowe.Runtime.Core.Api (MarloweVersion, SomeMarloweVersion)
import Language.Marlowe.Runtime.Core.ScriptRegistry (MarloweScripts)
import Language.Marlowe.Runtime.Discovery.Chain
import Language.Marlowe.Runtime.Discovery.QueryServer
import Language.Marlowe.Runtime.Discovery.Store
import Language.Marlowe.Runtime.Discovery.SyncServer
import Network.Protocol.Driver (RunClient)
import Numeric.Natural (Natural)

data DiscoveryDependencies = DiscoveryDependencies
  { acceptRunSyncServer :: IO (RunSyncServer IO)
  , acceptRunQueryServer :: IO (RunQueryServer IO)
  , connectToChainSeek :: RunClient IO Chain.RuntimeChainSeekClient
  , pageSize :: Natural
  , getMarloweVersion :: Chain.ScriptHash -> Maybe (SomeMarloweVersion, MarloweScripts)
  , getScripts :: forall v. MarloweVersion v -> Set MarloweScripts
  }

discovery :: Component IO DiscoveryDependencies ()
discovery = proc DiscoveryDependencies{..} -> do
  changes <- discoveryChainClient -< DiscoveryChainClientDependencies{..}
  DiscoveryStore{..} <- discoveryStore -< DiscoveryStoreDependencies{..}
  discoverySyncServer -< DiscoverySyncServerDependencies{..}
  discoveryQueryServer -< DiscoveryQueryServerDependencies{..}
