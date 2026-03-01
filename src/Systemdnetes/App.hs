module Systemdnetes.App
  ( AppEffects,
    PureAppConfig (..),
    PureResult (..),
    defaultPureConfig,
    runApp,
    runAppPure,
  )
where

import Control.Concurrent.STM (TVar)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Polysemy
import Systemdnetes.Domain.Network (CidrBlock (..), IPv4 (..))
import Systemdnetes.Domain.Node (Node, NodeName)
import Systemdnetes.Domain.Pod (Pod, PodName)
import Systemdnetes.Effects.DnsRegistry
import Systemdnetes.Effects.DnsRegistry.Interpreter
import Systemdnetes.Effects.FileServer
import Systemdnetes.Effects.FileServer.Interpreter
import Systemdnetes.Effects.IpAllocator
import Systemdnetes.Effects.IpAllocator.Interpreter
import Systemdnetes.Effects.Log
import Systemdnetes.Effects.Log.Interpreter
import Systemdnetes.Effects.NodeStore
import Systemdnetes.Effects.NodeStore.Interpreter
import Systemdnetes.Effects.Ssh
import Systemdnetes.Effects.Ssh.Interpreter
import Systemdnetes.Effects.Store
import Systemdnetes.Effects.Store.Interpreter
import Systemdnetes.Effects.Systemd
import Systemdnetes.Effects.Systemd.Interpreter
import Systemdnetes.Effects.WireGuardControl
import Systemdnetes.Effects.WireGuardControl.Interpreter

type AppEffects =
  '[ Store,
     Systemd,
     IpAllocator,
     WireGuardControl,
     DnsRegistry,
     NodeStore,
     Log,
     Ssh,
     FileServer,
     Embed IO,
     Final IO
   ]

runApp ::
  SshConfig ->
  TVar (Map PodName Pod) ->
  TVar (Map NodeName Node) ->
  TVar IpAllocatorState ->
  Text ->
  FilePath ->
  Sem AppEffects a ->
  IO a
runApp sshCfg podStore nodeStore allocatorState wgIface hostsDir =
  runFinal
    . embedToFinal
    . fileServerToIO
    . sshToIO sshCfg
    . logToIO
    . nodeStoreToIO nodeStore
    . dnsRegistryToIO hostsDir
    . wireGuardControlToIO wgIface
    . ipAllocatorToIO allocatorState
    . systemdToIO
    . storeToIO podStore

-- | Configuration for the pure interpreter stack, mirroring 'runApp'.
data PureAppConfig = PureAppConfig
  { pureStoreState :: StoreState,
    pureNodeStoreState :: NodeStoreState,
    pureIpAllocatorState :: IpAllocatorState,
    pureDnsRegistryState :: DnsRegistryState,
    pureSystemdState :: SystemdState,
    pureSshResponses :: Map NodeName Text,
    pureFiles :: Map FilePath LBS.ByteString
  }

-- | All stores empty, no SSH responses, no files.
-- Uses 10.0.0.0/24 as a test CIDR for the IP allocator.
defaultPureConfig :: PureAppConfig
defaultPureConfig =
  PureAppConfig
    { pureStoreState = Map.empty,
      pureNodeStoreState = Map.empty,
      pureIpAllocatorState = mkAllocatorState (CidrBlock (IPv4 0x0A000000) 24),
      pureDnsRegistryState = Map.empty,
      pureSystemdState = Map.empty,
      pureSshResponses = Map.empty,
      pureFiles = Map.empty
    }

-- | Result of running through the pure interpreter stack.
data PureResult a = PureResult
  { pureResultLogs :: [LogMessage],
    pureResultStore :: StoreState,
    pureResultNodeStore :: NodeStoreState,
    pureResultIpAllocator :: IpAllocatorState,
    pureResultWireGuard :: WgPureState,
    pureResultDnsRegistry :: DnsRegistryState,
    pureResultSystemd :: SystemdState,
    pureResultValue :: a
  }
  deriving stock (Show)

-- | Pure counterpart of 'runApp'. Interprets the full 'AppEffects' stack
-- (minus @Embed IO@ / @Final IO@) using in-memory state.
runAppPure ::
  PureAppConfig ->
  Sem '[Store, Systemd, IpAllocator, WireGuardControl, DnsRegistry, NodeStore, Log, Ssh, FileServer] a ->
  PureResult a
runAppPure cfg =
  toPureResult
    . run
    . fileServerToPure (pureFiles cfg)
    . sshToPure (pureSshResponses cfg)
    . logToList
    . nodeStoreToPure (pureNodeStoreState cfg)
    . dnsRegistryToPure (pureDnsRegistryState cfg)
    . wireGuardControlToPure
    . ipAllocatorToPure (pureIpAllocatorState cfg)
    . systemdToPure (pureSystemdState cfg)
    . storeToPure (pureStoreState cfg)
  where
    toPureResult (logs, (nodeStore, (dns, (wg, (ipAlloc, (systemd, (store, a))))))) =
      PureResult
        { pureResultLogs = logs,
          pureResultStore = store,
          pureResultNodeStore = nodeStore,
          pureResultIpAllocator = ipAlloc,
          pureResultWireGuard = wg,
          pureResultDnsRegistry = dns,
          pureResultSystemd = systemd,
          pureResultValue = a
        }
