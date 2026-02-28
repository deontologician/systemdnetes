module Systemdnetes.Effects.NodeStore.Interpreter
  ( NodeStoreState,
    nodeStoreToPure,
    nodeStoreToIO,
  )
where

import Control.Concurrent.STM (TVar, readTVarIO)
import Control.Concurrent.STM.TVar qualified as TVar
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import GHC.Conc (atomically)
import Polysemy
import Polysemy.State
import Systemdnetes.Domain.Node (Node (..), NodeName)
import Systemdnetes.Effects.NodeStore

type NodeStoreState = Map NodeName Node

nodeStoreToPure ::
  NodeStoreState ->
  Sem (NodeStore ': r) a ->
  Sem r (NodeStoreState, a)
nodeStoreToPure initial =
  runState initial
    . reinterpret
      ( \case
          RegisterNode node -> modify' @NodeStoreState $ Map.insert (nodeName node) node
          ListNodes -> Map.elems <$> get @NodeStoreState
          GetNode name -> Map.lookup name <$> get @NodeStoreState
          RemoveNode name -> modify' @NodeStoreState $ Map.delete name
      )

nodeStoreToIO :: (Member (Embed IO) r) => TVar NodeStoreState -> Sem (NodeStore ': r) a -> Sem r a
nodeStoreToIO var = interpret $ \case
  RegisterNode node ->
    embed $ atomically $ TVar.modifyTVar' var $ Map.insert (nodeName node) node
  ListNodes ->
    embed $ Map.elems <$> readTVarIO var
  GetNode name ->
    embed $ Map.lookup name <$> readTVarIO var
  RemoveNode name ->
    embed $ atomically $ TVar.modifyTVar' var $ Map.delete name
