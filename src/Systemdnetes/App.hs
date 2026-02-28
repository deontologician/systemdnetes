module Systemdnetes.App
  ( AppEffects,
    runApp,
  )
where

import Control.Concurrent.STM (TVar)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Polysemy
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
  '[ Log,
     Store,
     NodeStore,
     IpAllocator,
     WireGuardControl,
     DnsRegistry,
     Systemd,
     Ssh,
     FileServer,
     Embed IO,
     Final IO
   ]

runApp ::
  TVar (Map PodName Pod) ->
  TVar (Map NodeName Node) ->
  TVar IpAllocatorState ->
  Text ->
  FilePath ->
  Sem AppEffects a ->
  IO a
runApp podStore nodeStore allocatorState wgIface hostsDir =
  runFinal
    . embedToFinal
    . fileServerToIO
    . sshToIO
    . systemdToIO
    . dnsRegistryToIO hostsDir
    . wireGuardControlToIO wgIface
    . ipAllocatorToIO allocatorState
    . nodeStoreToIO nodeStore
    . storeToIO podStore
    . logToIO
