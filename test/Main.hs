module Main (main) where

import Systemdnetes.Effects.LogSpec qualified as LogSpec
import Systemdnetes.Effects.NodeStoreSpec qualified as NodeStoreSpec
import Systemdnetes.Effects.SshSpec qualified as SshSpec
import Systemdnetes.Effects.StoreSpec qualified as StoreSpec
import Systemdnetes.Effects.SystemdSpec qualified as SystemdSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes"
      [ LogSpec.tests,
        NodeStoreSpec.tests,
        SshSpec.tests,
        StoreSpec.tests,
        SystemdSpec.tests
      ]
