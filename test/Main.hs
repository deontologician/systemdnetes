module Main (main) where

import Systemdnetes.Effects.LogSpec qualified as LogSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes"
      [ LogSpec.tests
      ]
