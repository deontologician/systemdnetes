module Main (main) where

import Systemdnetes.Domain.ClusterSpec qualified as ClusterSpec
import Systemdnetes.Domain.ReconcileSpec qualified as ReconcileSpec
import Systemdnetes.Domain.ResourceSpec qualified as ResourceSpec
import Systemdnetes.Effects.LogSpec qualified as LogSpec
import Systemdnetes.Effects.NodeStoreSpec qualified as NodeStoreSpec
import Systemdnetes.Effects.SshSpec qualified as SshSpec
import Systemdnetes.Effects.StoreSpec qualified as StoreSpec
import Systemdnetes.Effects.SystemdSpec qualified as SystemdSpec
import Systemdnetes.Effects.UpdateChainSpec qualified as UpdateChainSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes"
      [ ClusterSpec.tests,
        ResourceSpec.tests,
        LogSpec.tests,
        NodeStoreSpec.tests,
        SshSpec.tests,
        StoreSpec.tests,
        SystemdSpec.tests,
        ReconcileSpec.tests,
        UpdateChainSpec.tests
      ]
