-----------------------------------------------------------------------------
--
-- Module      :  $Headers
-- License     :  Apache 2.0
--
-- Stability   :  Experimental
-- Portability :  Portable
--
-- | Testing Marlowe contracts.
--
-----------------------------------------------------------------------------


{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}


module Language.Marlowe.CLI.Test
  ( -- * Testing
    runTests
  ) where


import Cardano.Api
  ( ConsensusModeParams(CardanoModeParams)
  , EpochSlots(..)
  , IsShelleyBasedEra
  , Key(getVerificationKey, verificationKeyHash)
  , LocalNodeConnectInfo(..)
  , ScriptDataSupportedInEra
  )
import qualified Cardano.Api as C
import Cardano.Api.Shelley (protocolParamProtocolVersion)
import Control.Lens (Bifunctor(bimap))
import Control.Monad.Error.Class (throwError)
import Control.Monad.Except (MonadError, MonadIO)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT(runReaderT), runReader)
import Language.Marlowe.CLI.Cardano.Api (toPlutusProtocolVersion)
import Language.Marlowe.CLI.IO (decodeFileStrict, getDefaultCostModel, queryInEra, readSigningKey)
import Language.Marlowe.CLI.Test.Script (scriptTest)
import Language.Marlowe.CLI.Test.Types (ExecutionMode, MarloweTests(..), Wallet(Wallet), buildWallet)
import Language.Marlowe.CLI.Transaction (querySlotConfig)
import Language.Marlowe.CLI.Types (CliEnv(CliEnv), CliError(..), SigningKeyFile(SigningKeyFile))
import qualified Language.Marlowe.CLI.Types as T
import PlutusCore (defaultCostModelParams)


-- | Run tests of a Marlowe contract.
runTests :: IsShelleyBasedEra era
         => MonadError CliError m
         => MonadIO m
         => ScriptDataSupportedInEra era
         -> MarloweTests era FilePath  -- ^ The tests.
         -> m ()                   -- ^ Action for running the tests.
runTests era ScriptTests{..} =
  do
    costModel <- getDefaultCostModel
    let
      runCli action = runReaderT action (CliEnv era)
      connection =
        LocalNodeConnectInfo
        {
          localConsensusModeParams = CardanoModeParams $ EpochSlots 21600
        , localNodeNetworkId       = stNetwork
        , localNodeSocketPath      = stSocketPath
        }
    protocol <- runCli $ queryInEra connection C.QueryProtocolParameters
    faucetSigningKey <- readSigningKey (SigningKeyFile stFaucetSigningKeyFile)
    let
      protocolVersion = toPlutusProtocolVersion $ protocolParamProtocolVersion protocol
    faucet <- runCli $ buildWallet connection stFaucetAddress faucetSigningKey
    slotConfig <- runCli $ querySlotConfig connection
    tests' <- mapM decodeFileStrict stTests
    mapM_ (scriptTest era protocolVersion costModel connection faucet slotConfig stExecutionMode) tests'

