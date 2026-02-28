module Systemdnetes.Effects.DnsRegistry
  ( DnsRegistry (..),
    registerPodDns,
    unregisterPodDns,
    listDnsEntries,
  )
where

import Polysemy
import Systemdnetes.Domain.Dns (HostsEntry)
import Systemdnetes.Domain.Pod (PodName)

data DnsRegistry m a where
  RegisterPodDns :: PodName -> HostsEntry -> DnsRegistry m ()
  UnregisterPodDns :: PodName -> DnsRegistry m ()
  ListDnsEntries :: DnsRegistry m [(PodName, HostsEntry)]

makeSem ''DnsRegistry
