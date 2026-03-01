module Systemdnetes.Reconciler.Loop
  ( ReconcileConfig (..),
    defaultReconcileConfig,
    reconcileOnce,
    executeAction,
    reconcileLoop,
  )
where

import Control.Concurrent (threadDelay)
import Data.Text (Text)
import Polysemy
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.Pod (FlakeRef, Pod (..), PodName (..), PodSpec (..), PodState (..))
import Systemdnetes.Domain.Reconcile (ReconcileAction (..), reconcilePod)
import Systemdnetes.Effects.Log (Log, logInfo, logWarn)
import Systemdnetes.Effects.NodeStore (NodeStore, listNodes)
import Systemdnetes.Effects.Store (Store, assignPodNode, getPod, listPods, setPodState)
import Systemdnetes.Effects.Systemd (Systemd, getContainer, rebuildContainer, stopContainer)
import Systemdnetes.Scheduler (ScheduleResult (..), schedule)

data ReconcileConfig = ReconcileConfig
  { rcIntervalMicroseconds :: Int
  }
  deriving stock (Eq, Show)

defaultReconcileConfig :: ReconcileConfig
defaultReconcileConfig = ReconcileConfig {rcIntervalMicroseconds = 10_000_000}

-- | One full reconciliation pass.
--
-- 1. List nodes + pods
-- 2. Call scheduler for Pending pods, apply assignments via assignPodNode
-- 3. For each pod with a node, check container state and reconcile
-- 4. Execute each action
--
-- Returns the list of actions taken.
reconcileOnce ::
  (Member Store r, Member NodeStore r, Member Systemd r, Member Log r) =>
  Sem r [ReconcileAction]
reconcileOnce = do
  -- Phase 1: Gather state
  nodes <- listNodes
  pods <- listPods

  -- Phase 2: Schedule pending pods
  let sr = schedule nodes pods
  mapM_
    ( \(pName, nName) -> do
        assignPodNode pName nName
        logInfo $ "Scheduled " <> showPodName pName <> " on " <> showNodeName nName
    )
    (srAssignments sr)

  mapM_
    ( \(pName, _err) -> do
        logWarn $ "Unschedulable: " <> showPodName pName
    )
    (srUnschedulable sr)

  -- Re-read pods after scheduling (assignments changed node/state)
  updatedPods <- listPods

  -- Phase 3: Reconcile each pod that has a node
  actions <- mapM reconcileOnePod updatedPods

  -- Phase 4: Execute actions
  mapM_ executeAction actions

  pure actions

-- | Reconcile a single pod: check container state, decide action.
reconcileOnePod ::
  (Member Systemd r) =>
  Pod ->
  Sem r ReconcileAction
reconcileOnePod pod = do
  let name = podName (podSpec pod)
  case podNode pod of
    Nothing -> pure $ NoAction name
    Just node -> do
      containerState <- getContainer node name
      let desiredFlake = case podState pod of
            Running -> Just (podFlakeRef (podSpec pod))
            _ -> Nothing
      pure $ reconcilePod pod containerState desiredFlake

-- | Execute a single ReconcileAction.
--
-- StartPod calls rebuildContainer (which builds + starts) since the
-- machine directory may not exist yet.
executeAction ::
  (Member Store r, Member Systemd r, Member Log r) =>
  ReconcileAction ->
  Sem r ()
executeAction = \case
  StartPod pName nName -> do
    logInfo $ "Starting " <> showPodName pName <> " on " <> showNodeName nName
    -- Look up the pod's flake ref from the store
    mPod <- getPod pName
    case mPod of
      Just pod -> do
        let flakeRef = podFlakeRef (podSpec pod)
        rebuildContainer nName pName flakeRef
        setPodState pName Running
      Nothing ->
        logWarn $ "StartPod: pod " <> showPodName pName <> " not found in store"
  RebuildPod pName nName flakeRef -> do
    logInfo $ "Rebuilding " <> showPodName pName <> " on " <> showNodeName nName
    setPodState pName Rebuilding
    stopContainer nName pName
    rebuildContainer nName pName flakeRef
    setPodState pName Running
  StopPod pName nName -> do
    logInfo $ "Stopping " <> showPodName pName <> " on " <> showNodeName nName
    stopContainer nName pName
  SchedulePod pName -> do
    logWarn $ "SchedulePod action for " <> showPodName pName <> " should have been handled in phase 1"
  NoAction _ -> pure ()

-- | Run reconcileOnce in a loop with threadDelay.
reconcileLoop ::
  (Member Store r, Member NodeStore r, Member Systemd r, Member Log r, Member (Embed IO) r) =>
  ReconcileConfig ->
  Sem r ()
reconcileLoop cfg = do
  logInfo "Starting reconciliation loop"
  go
  where
    go = do
      _ <- reconcileOnce
      embed $ threadDelay (rcIntervalMicroseconds cfg)
      go

showPodName :: PodName -> Text
showPodName (PodName n) = n

showNodeName :: NodeName -> Text
showNodeName (NodeName n) = n
