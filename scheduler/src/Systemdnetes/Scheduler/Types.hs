module Systemdnetes.Scheduler.Types
  ( NodeResources (..),
    ScheduleDecision (..),
    ScheduleError (..),
    ScheduleResult (..),
  )
where

import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.Pod (PodName)
import Systemdnetes.Domain.Resource (Mebibytes, Millicores)

-- | Resource accounting for a single node: capacity minus committed.
data NodeResources = NodeResources
  { nrNodeName :: NodeName,
    nrCapacityCpu :: Millicores,
    nrCapacityMemory :: Mebibytes,
    nrCommittedCpu :: Millicores,
    nrCommittedMemory :: Mebibytes
  }
  deriving stock (Eq, Show)

data ScheduleDecision
  = Assigned PodName NodeName
  | Unschedulable PodName ScheduleError
  deriving stock (Eq, Show)

data ScheduleError
  = InsufficientCpu
  | InsufficientMemory
  | InsufficientResources
  | NoNodes
  | InvalidResources
  deriving stock (Eq, Show)

data ScheduleResult = ScheduleResult
  { srAssignments :: [(PodName, NodeName)],
    srUnschedulable :: [(PodName, ScheduleError)]
  }
  deriving stock (Eq, Show)
