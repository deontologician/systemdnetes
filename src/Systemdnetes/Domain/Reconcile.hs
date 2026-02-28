module Systemdnetes.Domain.Reconcile
  ( ReconcileAction (..),
    reconcilePod,
  )
where

import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.Pod (ContainerState (..), FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..))

data ReconcileAction
  = SchedulePod PodName
  | StartPod PodName NodeName
  | RebuildPod PodName NodeName FlakeRef
  | StopPod PodName NodeName
  | NoAction PodName
  deriving stock (Eq, Show)

-- | Decide what action to take for a pod given the current container state
-- and an optional desired flake ref (from the pod spec).
reconcilePod :: Pod -> Maybe ContainerState -> Maybe FlakeRef -> ReconcileAction
reconcilePod pod containerState desiredFlake =
  let name = podName (podSpec pod)
   in case (podState pod, podNode pod, containerState) of
        (Pending, Nothing, _) ->
          SchedulePod name
        (_, Just node, Nothing) ->
          StartPod name node
        (_, Just node, Just ContainerStopped) ->
          StartPod name node
        (_, Just node, Just ContainerFailed) ->
          StartPod name node
        (_, Just node, Just ContainerRunning) ->
          case desiredFlake of
            Just desired
              | desired == podFlakeRef (podSpec pod) ->
                  NoAction name
            _ ->
              RebuildPod name node (podFlakeRef (podSpec pod))
        _ ->
          NoAction name
