module Language.Marlowe.Runtime.Core.ScriptRegistrySpec
  ( spec
  ) where

import Control.Monad (unless)
import Data.Foldable (traverse_)
import qualified Data.Set as Set
import Language.Marlowe.Runtime.ChainSync.Api (ScriptHash(..))
import Language.Marlowe.Runtime.Core.Api (MarloweVersion, withSomeMarloweVersion)
import Language.Marlowe.Runtime.Core.ScriptRegistry
import Language.Marlowe.Scripts (rolePayoutValidatorHash, smallMarloweValidatorHash)
import Plutus.V1.Ledger.Api (ValidatorHash(..), fromBuiltin)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec = traverse_ (withSomeMarloweVersion scriptSetSpec) [minBound..maxBound]

scriptSetSpec :: MarloweVersion v -> Spec
scriptSetSpec marloweVersion = do
  describe (show marloweVersion) do
    let currentScripts = getCurrentScripts marloweVersion
    let scripts = getScripts marloweVersion
    it "Contains the current scripts in its script set." do
      unless (Set.member currentScripts scripts) do
        expectationFailure $ unwords
          ["Expected the script set to contain"
          , show currentScripts
          , "but it does not."
          ]
    it "Should specify the correct current scripts" do
      let payoutScript = fromPlutusValidatorHash rolePayoutValidatorHash
      let marloweScript = fromPlutusValidatorHash smallMarloweValidatorHash
      let currentAddresses' = MarloweScripts{..}
      currentScripts `shouldBe` currentAddresses'

fromPlutusValidatorHash :: ValidatorHash -> ScriptHash
fromPlutusValidatorHash (ValidatorHash hash) = ScriptHash $ fromBuiltin hash
