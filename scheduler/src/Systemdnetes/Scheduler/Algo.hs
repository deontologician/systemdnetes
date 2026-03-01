module Systemdnetes.Scheduler.Algo
  ( buildNodeResources,
    scheduleOne,
    schedule,
  )
where

import Data.List (foldl', sortOn)
import Systemdnetes.Domain.Node (Node (..), NodeCapacity (..), NodeName, NodeRole (..))
import Systemdnetes.Domain.Pod (Pod (..), PodName, PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..), parseCpu, parseMemory)
import Systemdnetes.Scheduler.Types

-- | Build a resource ledger from current nodes and pods.
-- Only includes Worker nodes. Sums resource requests of pods already
-- assigned to each node.
buildNodeResources :: [Node] -> [Pod] -> [NodeResources]
buildNodeResources nodes pods =
  let workers = filter (\n -> nodeRole n == Worker) nodes
      initialLedger =
        [ NodeResources
            { nrNodeName = nodeName n,
              nrCapacityCpu = capacityCpu (nodeCapacity n),
              nrCapacityMemory = capacityMemory (nodeCapacity n),
              nrCommittedCpu = Millicores 0,
              nrCommittedMemory = Mebibytes 0
            }
          | n <- workers
        ]
      assignedPods = filter (\p -> podNode p /= Nothing && podState p /= Pending) pods
   in foldl' addPodCommitment initialLedger assignedPods

-- | Add a pod's resource requests to its assigned node in the ledger.
addPodCommitment :: [NodeResources] -> Pod -> [NodeResources]
addPodCommitment ledger pod =
  case podNode pod of
    Nothing -> ledger
    Just targetNode ->
      case parseResources (podResources (podSpec pod)) of
        Nothing -> ledger
        Just (cpuReq, memReq) ->
          map
            ( \nr ->
                if nrNodeName nr == targetNode
                  then
                    nr
                      { nrCommittedCpu = nrCommittedCpu nr + cpuReq,
                        nrCommittedMemory = nrCommittedMemory nr + memReq
                      }
                  else nr
            )
            ledger

-- | Schedule a single pod. Returns updated ledger + decision.
-- Best-fit: pick the node with the smallest remaining capacity that still fits.
scheduleOne :: [NodeResources] -> Pod -> ([NodeResources], ScheduleDecision)
scheduleOne ledger pod
  | null ledger =
      (ledger, Unschedulable name NoNodes)
  | otherwise =
      case parseResources (podResources (podSpec pod)) of
        Nothing ->
          (ledger, Unschedulable name InvalidResources)
        Just (cpuReq, memReq) ->
          let candidates =
                [ (nr, remainCpu + remainMem)
                  | nr <- ledger,
                    let remainCpu = nrCapacityCpu nr - nrCommittedCpu nr - cpuReq,
                    let remainMem = nrCapacityMemory nr - nrCommittedMemory nr - memReq,
                    remainCpu >= Millicores 0,
                    remainMem >= Mebibytes 0
                ]
           in case candidates of
                [] -> (ledger, classifyShortage ledger cpuReq memReq name)
                _ ->
                  let (bestNode, _) = minimumByRemainder candidates
                      updatedLedger = commitToNode (nrNodeName bestNode) cpuReq memReq ledger
                   in (updatedLedger, Assigned name (nrNodeName bestNode))
  where
    name = podName (podSpec pod)

-- | Schedule all Pending pods (podState == Pending, podNode == Nothing).
-- Threads the ledger through so earlier assignments affect later ones.
schedule :: [Node] -> [Pod] -> ScheduleResult
schedule nodes pods =
  let ledger = buildNodeResources nodes pods
      pending = filter (\p -> podState p == Pending && podNode p == Nothing) pods
      (_, decisions) = foldl' step (ledger, []) pending
   in buildResult (reverse decisions)
  where
    step (l, ds) pod =
      let (l', d) = scheduleOne l pod
       in (l', d : ds)

-- | Parse CPU and memory from a pod's resource requests.
parseResources :: ResourceRequests -> Maybe (Millicores, Mebibytes)
parseResources rr = do
  c <- parseCpu (cpu rr)
  m <- parseMemory (memory rr)
  pure (c, m)

-- | Classify why a pod can't be scheduled: insufficient CPU, memory, or both.
classifyShortage :: [NodeResources] -> Millicores -> Mebibytes -> PodName -> ScheduleDecision
classifyShortage ledger cpuReq memReq name =
  let anyCpuFits = any (\nr -> nrCapacityCpu nr - nrCommittedCpu nr >= cpuReq) ledger
      anyMemFits = any (\nr -> nrCapacityMemory nr - nrCommittedMemory nr >= memReq) ledger
   in case (anyCpuFits, anyMemFits) of
        (False, False) -> Unschedulable name InsufficientResources
        (False, True) -> Unschedulable name InsufficientCpu
        (True, False) -> Unschedulable name InsufficientMemory
        (True, True) -> Unschedulable name InsufficientResources

-- | Pick the candidate with the smallest remaining capacity (best-fit).
minimumByRemainder :: [(NodeResources, Millicores)] -> (NodeResources, Millicores)
minimumByRemainder = head . sortOn snd

-- | Commit resources to a specific node in the ledger.
commitToNode :: NodeName -> Millicores -> Mebibytes -> [NodeResources] -> [NodeResources]
commitToNode targetNode cpuReq memReq =
  map
    ( \nr ->
        if nrNodeName nr == targetNode
          then
            nr
              { nrCommittedCpu = nrCommittedCpu nr + cpuReq,
                nrCommittedMemory = nrCommittedMemory nr + memReq
              }
          else nr
    )

-- | Partition schedule decisions into assignments and unschedulable.
buildResult :: [ScheduleDecision] -> ScheduleResult
buildResult decisions =
  ScheduleResult
    { srAssignments = [(p, n) | Assigned p n <- decisions],
      srUnschedulable = [(p, e) | Unschedulable p e <- decisions]
    }
