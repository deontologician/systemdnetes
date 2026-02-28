module Systemdnetes.Effects.IpAllocator
  ( IpAllocator (..),
    allocateIp,
    releaseIp,
    getPodIp,
    listAllocations,
  )
where

import Polysemy
import Systemdnetes.Domain.Network (IPv4)
import Systemdnetes.Domain.Pod (PodName)

data IpAllocator m a where
  AllocateIp :: PodName -> IpAllocator m (Maybe IPv4)
  ReleaseIp :: PodName -> IpAllocator m ()
  GetPodIp :: PodName -> IpAllocator m (Maybe IPv4)
  ListAllocations :: IpAllocator m [(PodName, IPv4)]

makeSem ''IpAllocator
