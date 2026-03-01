module Main (main) where

import Systemdnetes.Scheduler.AlgoSpec qualified as AlgoSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes-scheduler"
      [ AlgoSpec.tests
      ]
