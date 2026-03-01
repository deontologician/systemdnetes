module Main (main) where

import Systemdnetes.Reconciler.LoopSpec qualified as LoopSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes-reconciler"
      [ LoopSpec.tests
      ]
