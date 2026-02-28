module Main (main) where

import Systemdnetes.ApiSpec qualified as ApiSpec
import Systemdnetes.Domain.ClusterSpec qualified as ClusterSpec
import Systemdnetes.Domain.DnsSpec qualified as DnsSpec
import Systemdnetes.Domain.NetworkSpec qualified as NetworkSpec
import Systemdnetes.Domain.NodeSpec qualified as NodeSpec
import Systemdnetes.Domain.PodSpec qualified as PodSpec
import Systemdnetes.Domain.ReconcileSpec qualified as ReconcileSpec
import Systemdnetes.Domain.ResourceSpec qualified as ResourceSpec
import Systemdnetes.Domain.WireGuardSpec qualified as WireGuardSpec
import Systemdnetes.Effects.FileServerSpec qualified as FileServerSpec
import Systemdnetes.Effects.IpAllocatorSpec qualified as IpAllocatorSpec
import Systemdnetes.Effects.LogSpec qualified as LogSpec
import Systemdnetes.Effects.NodeStoreSpec qualified as NodeStoreSpec
import Systemdnetes.Effects.SshSpec qualified as SshSpec
import Systemdnetes.Effects.StoreSpec qualified as StoreSpec
import Systemdnetes.Effects.SystemdSpec qualified as SystemdSpec
import Systemdnetes.Effects.UpdateChainSpec qualified as UpdateChainSpec
import Systemdnetes.Effects.WireGuardControlSpec qualified as WireGuardControlSpec
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "systemdnetes"
      [ ApiSpec.tests,
        ClusterSpec.tests,
        DnsSpec.tests,
        NetworkSpec.tests,
        NodeSpec.tests,
        PodSpec.tests,
        ResourceSpec.tests,
        WireGuardSpec.tests,
        FileServerSpec.tests,
        IpAllocatorSpec.tests,
        LogSpec.tests,
        NodeStoreSpec.tests,
        SshSpec.tests,
        StoreSpec.tests,
        SystemdSpec.tests,
        ReconcileSpec.tests,
        UpdateChainSpec.tests,
        WireGuardControlSpec.tests
      ]
