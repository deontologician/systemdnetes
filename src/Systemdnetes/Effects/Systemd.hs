module Systemdnetes.Effects.Systemd
  ( Systemd (..),
    listContainers,
    getContainer,
    startContainer,
    stopContainer,
    rebuildContainer,
  )
where

import Polysemy
import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.Pod (ContainerInfo, ContainerState, FlakeRef, PodName)

data Systemd m a where
  ListContainers :: NodeName -> Systemd m [ContainerInfo]
  GetContainer :: NodeName -> PodName -> Systemd m (Maybe ContainerState)
  StartContainer :: NodeName -> PodName -> Systemd m ()
  StopContainer :: NodeName -> PodName -> Systemd m ()
  RebuildContainer :: NodeName -> PodName -> FlakeRef -> Systemd m ()

makeSem ''Systemd
