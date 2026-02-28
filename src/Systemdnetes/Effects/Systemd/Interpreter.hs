module Systemdnetes.Effects.Systemd.Interpreter
  ( systemdToPure,
    systemdToIO,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Polysemy
import Polysemy.State
import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.Pod (ContainerInfo (..), ContainerState (..), PodName)
import Systemdnetes.Effects.Systemd

type SystemdState = Map NodeName (Map PodName ContainerState)

systemdToPure ::
  SystemdState ->
  Sem (Systemd ': r) a ->
  Sem r (SystemdState, a)
systemdToPure initial =
  runState initial . reinterpret (\case
    ListContainers node -> do
      s <- get @SystemdState
      let containers = maybe [] Map.toList (Map.lookup node s)
      pure [ContainerInfo pod st | (pod, st) <- containers]
    GetContainer node pod -> do
      s <- get @SystemdState
      pure $ Map.lookup node s >>= Map.lookup pod
    StartContainer node pod -> do
      modify' @SystemdState $
        Map.alter
          ( Just . maybe (Map.singleton pod ContainerRunning) (Map.insert pod ContainerRunning)
          )
          node
    StopContainer node pod -> do
      modify' @SystemdState $
        Map.adjust (Map.insert pod ContainerStopped) node)

-- | Stubbed IO interpreter. Returns empty results / no-ops.
-- Real machinectl + SSH integration comes later.
systemdToIO :: (Member (Embed IO) r) => Sem (Systemd ': r) a -> Sem r a
systemdToIO = interpret $ \case
  ListContainers _ -> pure []
  GetContainer _ _ -> pure Nothing
  StartContainer _ _ -> pure ()
  StopContainer _ _ -> pure ()
