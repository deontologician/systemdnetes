module Systemdnetes.Effects.NodeStore
  ( NodeStore (..),
    registerNode,
    listNodes,
    getNode,
    removeNode,
  )
where

import Polysemy
import Systemdnetes.Domain.Node (Node, NodeName)

data NodeStore m a where
  RegisterNode :: Node -> NodeStore m ()
  ListNodes :: NodeStore m [Node]
  GetNode :: NodeName -> NodeStore m (Maybe Node)
  RemoveNode :: NodeName -> NodeStore m ()

makeSem ''NodeStore
