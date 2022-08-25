{-# LANGUAGE GADTs #-}

module Main where

import Control.Concurrent.STM (atomically)
import Control.Exception (bracket, bracketOnError, throwIO)
import Data.Either (fromRight)
import Data.Void (Void)
import Language.Marlowe.Runtime.ChainSync.Api (ChainSyncQuery (..), RuntimeChainSeekClient, WithGenesis (..),
                                               runtimeChainSeekCodec)
import qualified Language.Marlowe.Runtime.Core.Api as Core
import Language.Marlowe.Runtime.History (History (..), HistoryDependencies (..), mkHistory)
import Language.Marlowe.Runtime.History.Api (historyJobCodec, historyQueryCodec)
import Language.Marlowe.Runtime.History.JobServer (RunJobServer (RunJobServer))
import Language.Marlowe.Runtime.History.QueryServer (RunQueryServer (RunQueryServer))
import Network.Channel (socketAsChannel)
import Network.Protocol.ChainSeek.Client (chainSeekClientPeer)
import Network.Protocol.Driver (mkDriver)
import Network.Protocol.Job.Server (jobServerPeer)
import Network.Protocol.Query.Client (liftQuery, queryClientPeer)
import Network.Protocol.Query.Codec (codecQuery)
import Network.Protocol.Query.Server (queryServerPeer)
import Network.Socket (AddrInfo (..), AddrInfoFlag (..), HostName, PortNumber, SockAddr, SocketOption (..),
                       SocketType (..), accept, bind, close, connect, defaultHints, getAddrInfo, listen, openSocket,
                       setCloseOnExecIfNeeded, setSocketOption, withFdSocket, withSocketsDo)
import Network.TypedProtocol (runPeerWithDriver, startDState)
import Options.Applicative (auto, execParser, fullDesc, header, help, info, long, metavar, option, progDesc, short,
                            strOption, value)

main :: IO ()
main = run =<< getOptions

clientHints :: AddrInfo
clientHints = defaultHints { addrSocketType = Stream }

run :: Options -> IO ()
run Options{..} = withSocketsDo do
  jobAddr <- resolve commandPort
  queryAddr <- resolve queryPort
  bracket (openServer jobAddr) close \jobSocket ->
    bracket (openServer queryAddr) close \querySocket -> do
      slotConfig <- queryChainSync GetSlotConfig
      securityParameter <- queryChainSync GetSecurityParameter
      let

        connectToChainSeek :: forall a. RuntimeChainSeekClient IO a -> IO a
        connectToChainSeek client = do
          chainSeekAddr <- head <$> getAddrInfo (Just clientHints) (Just chainSeekHost) (Just $ show chainSeekPort)
          bracket (openClient chainSeekAddr) close \chainSeekSocket -> do
            let driver = mkDriver throwIO runtimeChainSeekCodec $ socketAsChannel chainSeekSocket
            let peer = chainSeekClientPeer Genesis client
            fst <$> runPeerWithDriver driver peer (startDState driver)

        acceptRunJobServer = do
          (conn, _ :: SockAddr) <- accept jobSocket
          let driver = mkDriver throwIO historyJobCodec $ socketAsChannel conn
          pure $ RunJobServer \server -> do
            let peer = jobServerPeer server
            fst <$> runPeerWithDriver driver peer (startDState driver)

        acceptRunQueryServer = do
          (conn, _ :: SockAddr) <- accept querySocket
          let driver = mkDriver throwIO historyQueryCodec $ socketAsChannel conn
          pure $ RunQueryServer \server -> do
            let peer = queryServerPeer server
            fst <$> runPeerWithDriver driver peer (startDState driver)

      let getMarloweVersion = Core.getMarloweVersion
      let followerPageSize = 1024 -- TODO move to config with a default
      History{..} <- atomically $ mkHistory HistoryDependencies{..}
      runHistory
  where
    openClient addr = bracketOnError (openSocket addr) close \sock -> do
      connect sock $ addrAddress addr
      pure sock

    openServer addr = bracketOnError (openSocket addr) close \socket -> do
      setSocketOption socket ReuseAddr 1
      withFdSocket socket setCloseOnExecIfNeeded
      bind socket $ addrAddress addr
      listen socket 2048
      return socket

    resolve p = do
      let hints = defaultHints { addrFlags = [AI_PASSIVE], addrSocketType = Stream }
      head <$> getAddrInfo (Just hints) (Just host) (Just $ show p)

    queryChainSync :: ChainSyncQuery Void e a -> IO a
    queryChainSync query = do
      addr <- head <$> getAddrInfo (Just clientHints) (Just chainSeekHost) (Just $ show chainSeekQueryPort)
      bracket (openClient addr) close \socket -> do
        let driver = mkDriver throwIO codecQuery $ socketAsChannel socket
        let client = liftQuery query
        let peer = queryClientPeer client
        result <- fst <$> runPeerWithDriver driver peer (startDState driver)
        pure $ fromRight (error "failed to query chain seek server") result

data Options = Options
  { chainSeekPort      :: PortNumber
  , chainSeekQueryPort :: PortNumber
  , commandPort        :: PortNumber
  , queryPort          :: PortNumber
  , chainSeekHost      :: HostName
  , host               :: HostName
  }

getOptions :: IO Options
getOptions = execParser $ info parser infoMod
  where
    parser = Options
      <$> chainSeekPortParser
      <*> chainSeekQueryPortParser
      <*> commandPortParser
      <*> queryPortParser
      <*> chainSeekHostParser
      <*> hostParser

    chainSeekPortParser = option auto $ mconcat
      [ long "chain-seek-port-number"
      , value 3715
      , metavar "PORT_NUMBER"
      , help "The port number of the chain seek server"
      ]

    chainSeekQueryPortParser = option auto $ mconcat
      [ long "chain-seek-query-port-number"
      , value 3716
      , metavar "PORT_NUMBER"
      , help "The port number of the chain sync query server"
      ]

    commandPortParser = option auto $ mconcat
      [ long "command-port"
      , short 'c'
      , value 3717
      , metavar "PORT_NUMBER"
      , help "The port number to run the job server on"
      ]

    queryPortParser = option auto $ mconcat
      [ long "query-port"
      , short 'c'
      , value 3718
      , metavar "PORT_NUMBER"
      , help "The port number to run the query server on"
      ]

    chainSeekHostParser = strOption $ mconcat
      [ long "chain-seek-host"
      , value "127.0.0.1"
      , metavar "HOST_NAME"
      , help "The host name of the chain seek server"
      ]

    hostParser = strOption $ mconcat
      [ long "host"
      , short 'h'
      , value "127.0.0.1"
      , metavar "HOST_NAME"
      , help "The host name to run the history server on"
      ]

    infoMod = mconcat
      [ fullDesc
      , progDesc "Contract follower for Marlowe Runtime"
      , header "marlowe-follower : a contract follower for the Marlowe Runtime."
      ]
