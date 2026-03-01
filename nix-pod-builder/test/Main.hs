module Main (main) where

import Systemdnetes.NixPodBuilder.CommandSpec qualified as CommandSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes-nix-pod-builder"
      [ CommandSpec.tests
      ]
