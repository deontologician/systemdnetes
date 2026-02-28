module Systemdnetes.Effects.Systemd
  ( Systemd (..),
    listContainers,
    getContainer,
    startContainer,
    stopContainer,
  )
where

import Polysemy
import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.Pod (ContainerInfo, ContainerState, PodName)

data Systemd m a where
  ListContainers :: NodeName -> Systemd m [ContainerInfo]
  GetContainer :: NodeName -> PodName -> Systemd m (Maybe ContainerState)
  StartContainer :: NodeName -> PodName -> Systemd m ()
  StopContainer :: NodeName -> PodName -> Systemd m ()

makeSem ''Systemd
