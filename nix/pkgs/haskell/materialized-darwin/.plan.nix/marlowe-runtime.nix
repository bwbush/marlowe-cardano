{ system
  , compiler
  , flags
  , pkgs
  , hsPkgs
  , pkgconfPkgs
  , errorHandler
  , config
  , ... }:
  {
    flags = { defer-plugin-errors = false; };
    package = {
      specVersion = "2.4";
      identifier = { name = "marlowe-runtime"; version = "0.0.0.0"; };
      license = "Apache-2.0";
      copyright = "";
      maintainer = "jamie.bertram@iohk.io";
      author = "Jamie Bertram";
      homepage = "";
      url = "";
      synopsis = "Runtime system for running Marlowe financial contracts on the Cardano Computation Layer";
      description = "Runtime system for running and monitoring Marlowe financial contracts on\nCardano. It provides query access to search for and inspect contracts,\ncommand access for creating and interacting with contracts, and streaming\naccess for real-time updates to contracts.";
      buildType = "Simple";
      isLocal = true;
      detailLevel = "FullDetails";
      licenseFiles = [ "LICENSE" "NOTICE" ];
      dataDir = ".";
      dataFiles = [];
      extraSrcFiles = [];
      extraTmpFiles = [];
      extraDocFiles = [];
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."aeson" or (errorHandler.buildDepError "aeson"))
          (hsPkgs."async" or (errorHandler.buildDepError "async"))
          (hsPkgs."base16" or (errorHandler.buildDepError "base16"))
          (hsPkgs."binary" or (errorHandler.buildDepError "binary"))
          (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
          (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
          (hsPkgs."marlowe" or (errorHandler.buildDepError "marlowe"))
          (hsPkgs."marlowe-chain-sync" or (errorHandler.buildDepError "marlowe-chain-sync"))
          (hsPkgs."marlowe-protocols" or (errorHandler.buildDepError "marlowe-protocols"))
          (hsPkgs."plutus-ledger-api" or (errorHandler.buildDepError "plutus-ledger-api"))
          (hsPkgs."semialign" or (errorHandler.buildDepError "semialign"))
          (hsPkgs."split" or (errorHandler.buildDepError "split"))
          (hsPkgs."stm" or (errorHandler.buildDepError "stm"))
          (hsPkgs."text" or (errorHandler.buildDepError "text"))
          (hsPkgs."these" or (errorHandler.buildDepError "these"))
          (hsPkgs."time" or (errorHandler.buildDepError "time"))
          (hsPkgs."transformers" or (errorHandler.buildDepError "transformers"))
          (hsPkgs."typed-protocols" or (errorHandler.buildDepError "typed-protocols"))
          (hsPkgs."witherable" or (errorHandler.buildDepError "witherable"))
          ];
        buildable = true;
        modules = [
          "Language/Marlowe/Protocol/Sync/Client"
          "Language/Marlowe/Protocol/Sync/Codec"
          "Language/Marlowe/Protocol/Sync/Server"
          "Language/Marlowe/Protocol/Sync/Types"
          "Language/Marlowe/Runtime/Core/Api"
          "Language/Marlowe/Runtime/History"
          "Language/Marlowe/Runtime/History/Api"
          "Language/Marlowe/Runtime/History/Follower"
          "Language/Marlowe/Runtime/History/FollowerSupervisor"
          "Language/Marlowe/Runtime/History/JobServer"
          "Language/Marlowe/Runtime/History/QueryServer"
          "Language/Marlowe/Runtime/History/Store"
          "Language/Marlowe/Runtime/History/Store/Memory"
          "Language/Marlowe/Runtime/History/Store/Model"
          "Language/Marlowe/Runtime/History/SyncServer"
          ];
        hsSourceDirs = [ "src" ];
        };
      exes = {
        "marlowed" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."marlowe-runtime" or (errorHandler.buildDepError "marlowe-runtime"))
            ];
          buildable = true;
          modules = [ "Paths_marlowe_runtime" ];
          hsSourceDirs = [ "app" ];
          mainPath = [
            "Main.hs"
            ] ++ (pkgs.lib).optional (flags.defer-plugin-errors) "";
          };
        "marlowe-history" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."ansi-terminal" or (errorHandler.buildDepError "ansi-terminal"))
            (hsPkgs."async" or (errorHandler.buildDepError "async"))
            (hsPkgs."base16" or (errorHandler.buildDepError "base16"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            (hsPkgs."marlowe" or (errorHandler.buildDepError "marlowe"))
            (hsPkgs."marlowe-protocols" or (errorHandler.buildDepError "marlowe-protocols"))
            (hsPkgs."marlowe-runtime" or (errorHandler.buildDepError "marlowe-runtime"))
            (hsPkgs."marlowe-chain-sync" or (errorHandler.buildDepError "marlowe-chain-sync"))
            (hsPkgs."network" or (errorHandler.buildDepError "network"))
            (hsPkgs."typed-protocols" or (errorHandler.buildDepError "typed-protocols"))
            (hsPkgs."optparse-applicative" or (errorHandler.buildDepError "optparse-applicative"))
            (hsPkgs."stm" or (errorHandler.buildDepError "stm"))
            (hsPkgs."text" or (errorHandler.buildDepError "text"))
            (hsPkgs."wl-pprint" or (errorHandler.buildDepError "wl-pprint"))
            ];
          buildable = true;
          modules = [ "Paths_marlowe_runtime" ];
          hsSourceDirs = [ "marlowe-history" ];
          mainPath = [
            "Main.hs"
            ] ++ (pkgs.lib).optional (flags.defer-plugin-errors) "";
          };
        "marlowe-history-cli" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."ansi-terminal" or (errorHandler.buildDepError "ansi-terminal"))
            (hsPkgs."async" or (errorHandler.buildDepError "async"))
            (hsPkgs."base16" or (errorHandler.buildDepError "base16"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            (hsPkgs."marlowe" or (errorHandler.buildDepError "marlowe"))
            (hsPkgs."marlowe-chain-sync" or (errorHandler.buildDepError "marlowe-chain-sync"))
            (hsPkgs."marlowe-protocols" or (errorHandler.buildDepError "marlowe-protocols"))
            (hsPkgs."marlowe-runtime" or (errorHandler.buildDepError "marlowe-runtime"))
            (hsPkgs."network" or (errorHandler.buildDepError "network"))
            (hsPkgs."typed-protocols" or (errorHandler.buildDepError "typed-protocols"))
            (hsPkgs."optparse-applicative" or (errorHandler.buildDepError "optparse-applicative"))
            (hsPkgs."stm" or (errorHandler.buildDepError "stm"))
            (hsPkgs."text" or (errorHandler.buildDepError "text"))
            (hsPkgs."wl-pprint" or (errorHandler.buildDepError "wl-pprint"))
            ];
          buildable = true;
          modules = [ "Paths_marlowe_runtime" ];
          hsSourceDirs = [ "marlowe-history-cli" ];
          mainPath = [
            "Main.hs"
            ] ++ (pkgs.lib).optional (flags.defer-plugin-errors) "";
          };
        "marlowe-follower" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."ansi-terminal" or (errorHandler.buildDepError "ansi-terminal"))
            (hsPkgs."async" or (errorHandler.buildDepError "async"))
            (hsPkgs."base16" or (errorHandler.buildDepError "base16"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            (hsPkgs."marlowe" or (errorHandler.buildDepError "marlowe"))
            (hsPkgs."marlowe-protocols" or (errorHandler.buildDepError "marlowe-protocols"))
            (hsPkgs."marlowe-runtime" or (errorHandler.buildDepError "marlowe-runtime"))
            (hsPkgs."marlowe-chain-sync" or (errorHandler.buildDepError "marlowe-chain-sync"))
            (hsPkgs."network" or (errorHandler.buildDepError "network"))
            (hsPkgs."typed-protocols" or (errorHandler.buildDepError "typed-protocols"))
            (hsPkgs."optparse-applicative" or (errorHandler.buildDepError "optparse-applicative"))
            (hsPkgs."stm" or (errorHandler.buildDepError "stm"))
            (hsPkgs."text" or (errorHandler.buildDepError "text"))
            (hsPkgs."wl-pprint" or (errorHandler.buildDepError "wl-pprint"))
            ];
          buildable = true;
          modules = [ "Paths_marlowe_runtime" "Options" ];
          hsSourceDirs = [ "marlowe-follower" ];
          mainPath = [
            "Main.hs"
            ] ++ (pkgs.lib).optional (flags.defer-plugin-errors) "";
          };
        };
      tests = {
        "marlowe-runtime-test" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."async" or (errorHandler.buildDepError "async"))
            (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            (hsPkgs."hspec" or (errorHandler.buildDepError "hspec"))
            (hsPkgs."marlowe" or (errorHandler.buildDepError "marlowe"))
            (hsPkgs."marlowe-chain-sync" or (errorHandler.buildDepError "marlowe-chain-sync"))
            (hsPkgs."marlowe-protocols" or (errorHandler.buildDepError "marlowe-protocols"))
            (hsPkgs."marlowe-protocols-test" or (errorHandler.buildDepError "marlowe-protocols-test"))
            (hsPkgs."marlowe-runtime" or (errorHandler.buildDepError "marlowe-runtime"))
            (hsPkgs."plutus-tx" or (errorHandler.buildDepError "plutus-tx"))
            (hsPkgs."plutus-ledger-api" or (errorHandler.buildDepError "plutus-ledger-api"))
            (hsPkgs."QuickCheck" or (errorHandler.buildDepError "QuickCheck"))
            (hsPkgs."some" or (errorHandler.buildDepError "some"))
            (hsPkgs."stm" or (errorHandler.buildDepError "stm"))
            (hsPkgs."tasty" or (errorHandler.buildDepError "tasty"))
            (hsPkgs."tasty-hunit" or (errorHandler.buildDepError "tasty-hunit"))
            (hsPkgs."tasty-quickcheck" or (errorHandler.buildDepError "tasty-quickcheck"))
            (hsPkgs."time" or (errorHandler.buildDepError "time"))
            (hsPkgs."transformers" or (errorHandler.buildDepError "transformers"))
            ];
          build-tools = [
            (hsPkgs.buildPackages.hspec-discover.components.exes.hspec-discover or (pkgs.buildPackages.hspec-discover or (errorHandler.buildToolDepError "hspec-discover:hspec-discover")))
            ];
          buildable = true;
          modules = [
            "Language/Marlowe/Runtime/History/FollowerSpec"
            "Language/Marlowe/Runtime/History/Script"
            "Language/Marlowe/Runtime/History/StoreSpec"
            "Language/Marlowe/Runtime/History/Store/ModelSpec"
            "Language/Marlowe/Runtime/HistorySpec"
            "Spec/Marlowe/Semantics/Arbitrary"
            "Spec/Marlowe/Semantics/Golden"
            "Spec/Marlowe/Semantics/Golden/Escrow"
            "Spec/Marlowe/Semantics/Golden/Pangram"
            "Spec/Marlowe/Semantics/Golden/Swap"
            "Spec/Marlowe/Semantics/Golden/Trivial"
            "Spec/Marlowe/Semantics/Golden/ZeroCouponBond"
            "Paths_marlowe_runtime"
            ];
          hsSourceDirs = [ "test" "../marlowe/test" ];
          mainPath = [ "Spec.hs" ];
          };
        };
      };
    } // rec { src = (pkgs.lib).mkDefault ../marlowe-runtime; }