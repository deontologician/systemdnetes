module Systemdnetes.Domain.Cluster
  ( NodeCapacity (..),
    PodView (..),
    NodeView (..),
    ClusterState (..),
    buildClusterState,
  )
where

import Data.Aeson (ToJSON)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import GHC.Generics (Generic)
import Systemdnetes.Domain.Network (ipToText)
import Systemdnetes.Domain.Node (Node (..), NodeCapacity (..))
import Systemdnetes.Domain.Pod (NetworkInfo (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Domain.Resource

data PodView = PodView
  { pvName :: Text,
    pvState :: PodState,
    pvCpu :: Millicores,
    pvMemory :: Mebibytes,
    pvReplicas :: Int,
    pvIp :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON)

data NodeView = NodeView
  { nvNode :: Node,
    nvCapacity :: NodeCapacity,
    nvUsage :: NodeCapacity,
    nvPods :: [PodView]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON)

data ClusterState = ClusterState
  { csNodes :: [NodeView],
    csUnscheduledPods :: [PodView],
    csTotalCpu :: Millicores,
    csTotalMemory :: Mebibytes,
    csUsedCpu :: Millicores,
    csUsedMemory :: Mebibytes
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON)

-- | Build a cluster state view from nodes and pods.
--
-- Pods with a 'podNode' matching a known node are grouped under that node.
-- Pods without a node assignment (or assigned to an unknown node) go into
-- the unscheduled list.
buildClusterState :: [Node] -> [Pod] -> ClusterState
buildClusterState nodes pods =
  let nodeMap = Map.fromList [(nodeName n, n) | n <- nodes]

      -- Partition pods by node assignment
      (scheduled, unscheduled) = foldl' partitionPod (Map.empty, []) pods
        where
          partitionPod (acc, unsched) pod =
            case podNode pod of
              Just nn
                | Map.member nn nodeMap ->
                    (Map.insertWith (++) nn [pod] acc, unsched)
              _ -> (acc, pod : unsched)

      -- Build node views
      nodeViews =
        [ let nodePods = Map.findWithDefault [] nn scheduled
              podViews = map toPodView nodePods
              usage = sumUsage podViews
              cap = nodeCapacity node
           in NodeView node cap usage podViews
        | (nn, node) <- Map.toAscList nodeMap
        ]

      unscheduledViews = map toPodView (reverse unscheduled)

      totalCpu = sum [capacityCpu (nodeCapacity n) | n <- nodes]
      totalMem = sum [capacityMemory (nodeCapacity n) | n <- nodes]
      usedCpu = sum [capacityCpu (nvUsage nv) | nv <- nodeViews]
      usedMem = sum [capacityMemory (nvUsage nv) | nv <- nodeViews]
   in ClusterState
        { csNodes = nodeViews,
          csUnscheduledPods = unscheduledViews,
          csTotalCpu = totalCpu,
          csTotalMemory = totalMem,
          csUsedCpu = usedCpu,
          csUsedMemory = usedMem
        }

toPodView :: Pod -> PodView
toPodView pod =
  let spec = podSpec pod
      res = podResources spec
      (PodName rawName) = podName spec
      cpuVal = fromMaybe (Millicores 0) (parseCpu (cpu res))
      memVal = fromMaybe (Mebibytes 0) (parseMemory (memory res))
   in PodView
        { pvName = rawName,
          pvState = podState pod,
          pvCpu = cpuVal,
          pvMemory = memVal,
          pvReplicas = podReplicas spec,
          pvIp = ipToText . netIp <$> podNetwork pod
        }

sumUsage :: [PodView] -> NodeCapacity
sumUsage pvs =
  NodeCapacity
    { capacityCpu = sum (map pvCpu pvs),
      capacityMemory = sum (map pvMemory pvs)
    }
