module Systemdnetes.Effects.Store.Interpreter
  ( StoreState,
    storeToPure,
    storeToIO,
  )
where

import Control.Concurrent.STM (TVar, readTVarIO)
import Control.Concurrent.STM.TVar qualified as TVar
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import GHC.Conc (atomically)
import Polysemy
import Polysemy.State
import Systemdnetes.Domain.Pod (Pod (..), PodName, PodSpec (..), PodState (..))
import Systemdnetes.Effects.Store

type StoreState = Map PodName Pod

storeToPure ::
  StoreState ->
  Sem (Store ': r) a ->
  Sem r (StoreState, a)
storeToPure initial =
  runState initial
    . reinterpret
      ( \case
          SubmitPod spec -> do
            let pod = Pod {podSpec = spec, podState = Pending, podNode = Nothing, podNetwork = Nothing}
            modify' @StoreState $ Map.insert (podName spec) pod
          ListPods -> do
            s <- get @StoreState
            pure $ Map.elems s
          GetPod name -> do
            s <- get @StoreState
            pure $ Map.lookup name s
          DeletePod name ->
            modify' @StoreState $ Map.delete name
          UpdatePodSpec name spec ->
            modify' @StoreState $
              Map.adjust (\pod -> pod {podSpec = spec, podState = Rebuilding}) name
          SetPodState name st ->
            modify' @StoreState $
              Map.adjust (\pod -> pod {podState = st}) name
          AssignPodNode name node ->
            modify' @StoreState $
              Map.adjust (\pod -> pod {podNode = Just node, podState = Scheduled}) name
      )

-- | IO interpreter backed by a TVar for concurrent access across requests.
storeToIO :: (Member (Embed IO) r) => TVar StoreState -> Sem (Store ': r) a -> Sem r a
storeToIO var = interpret $ \case
  SubmitPod spec -> embed $ atomically $ TVar.modifyTVar' var $ \s ->
    let pod = Pod {podSpec = spec, podState = Pending, podNode = Nothing, podNetwork = Nothing}
     in Map.insert (podName spec) pod s
  ListPods -> embed $ Map.elems <$> readTVarIO var
  GetPod name -> embed $ Map.lookup name <$> readTVarIO var
  DeletePod name -> embed $ atomically $ TVar.modifyTVar' var $ Map.delete name
  UpdatePodSpec name spec ->
    embed $
      atomically $
        TVar.modifyTVar' var $
          Map.adjust (\pod -> pod {podSpec = spec, podState = Rebuilding}) name
  SetPodState name st ->
    embed $
      atomically $
        TVar.modifyTVar' var $
          Map.adjust (\pod -> pod {podState = st}) name
  AssignPodNode name node ->
    embed $
      atomically $
        TVar.modifyTVar' var $
          Map.adjust (\pod -> pod {podNode = Just node, podState = Scheduled}) name
