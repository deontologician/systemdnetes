module Main (main) where

import Systemdnetes.Domain.ClusterSpec qualified as ClusterSpec
import Systemdnetes.Domain.ResourceSpec qualified as ResourceSpec
import Systemdnetes.Effects.LogSpec qualified as LogSpec
import Systemdnetes.Effects.StoreSpec qualified as StoreSpec
import Systemdnetes.Effects.SystemdSpec qualified as SystemdSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes"
      [ ClusterSpec.tests,
        ResourceSpec.tests,
        LogSpec.tests,
        StoreSpec.tests,
        SystemdSpec.tests
      ]
