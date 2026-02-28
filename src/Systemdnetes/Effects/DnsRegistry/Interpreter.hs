module Systemdnetes.Effects.DnsRegistry.Interpreter
  ( DnsRegistryState,
    dnsRegistryToPure,
    dnsRegistryToIO,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Polysemy
import Polysemy.State
import System.Directory (removeFile)
import System.FilePath ((</>))
import Systemdnetes.Domain.Dns (HostsEntry, hostsFileName, renderHostsEntry)
import Systemdnetes.Domain.Pod (PodName)
import Systemdnetes.Effects.DnsRegistry

type DnsRegistryState = Map PodName HostsEntry

-- | Pure interpreter via State — used in property tests.
dnsRegistryToPure ::
  DnsRegistryState ->
  Sem (DnsRegistry ': r) a ->
  Sem r (DnsRegistryState, a)
dnsRegistryToPure initial =
  runState initial
    . reinterpret
      ( \case
          RegisterPodDns podName entry ->
            modify' @DnsRegistryState $ Map.insert podName entry
          UnregisterPodDns podName ->
            modify' @DnsRegistryState $ Map.delete podName
          ListDnsEntries -> do
            s <- get @DnsRegistryState
            pure $ Map.toList s
      )

-- | IO interpreter: writes hosts files to a directory that dnsmasq watches
--   via inotify. Each pod gets its own file: @<hostsDir>/<podName>.hosts@.
dnsRegistryToIO ::
  (Member (Embed IO) r) =>
  FilePath ->
  Sem (DnsRegistry ': r) a ->
  Sem r a
dnsRegistryToIO hostsDir = interpret $ \case
  RegisterPodDns podName entry -> embed $ do
    let path = hostsDir </> hostsFileName podName
    writeFile path (T.unpack (renderHostsEntry entry) <> "\n")
  UnregisterPodDns podName -> embed $ do
    let path = hostsDir </> hostsFileName podName
    removeFile path
  ListDnsEntries ->
    -- In production, would scan the hostsDir for .hosts files and parse them.
    -- For now, returns empty — the source of truth is the effect caller's state.
    pure []
