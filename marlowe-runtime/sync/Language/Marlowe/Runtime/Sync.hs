{-# LANGUAGE Arrows #-}

module Language.Marlowe.Runtime.Sync
  where

import Control.Concurrent.Component
import Language.Marlowe.Protocol.HeaderSync.Server (MarloweHeaderSyncServer)
import Language.Marlowe.Protocol.Query.Server (MarloweQueryServer)
import Language.Marlowe.Protocol.Sync.Server (MarloweSyncServer)
import Language.Marlowe.Runtime.Sync.Database (DatabaseQueries)
import Language.Marlowe.Runtime.Sync.MarloweHeaderSyncServer
import Language.Marlowe.Runtime.Sync.MarloweSyncServer
import Language.Marlowe.Runtime.Sync.QueryServer
import Network.Protocol.Driver (RunServer)

data SyncDependencies = SyncDependencies
  { databaseQueries :: DatabaseQueries IO
  , acceptRunMarloweSyncServer :: IO (RunServer IO MarloweSyncServer)
  , acceptRunMarloweHeaderSyncServer :: IO (RunServer IO MarloweHeaderSyncServer)
  , acceptRunMarloweQueryServer :: IO (RunServer IO MarloweQueryServer)
  }

sync :: Component IO SyncDependencies ()
sync = proc SyncDependencies{..} -> do
  marloweSyncServer -< MarloweSyncServerDependencies{..}
  marloweHeaderSyncServer -< MarloweHeaderSyncServerDependencies{..}
  queryServer -< QueryServerDependencies{..}
