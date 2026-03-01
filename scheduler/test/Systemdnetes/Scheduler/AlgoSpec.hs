module Systemdnetes.Scheduler.AlgoSpec (tests) where

import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Node (Node (..), NodeCapacity (..), NodeName (..), NodeRole (..))
import Systemdnetes.Domain.Pod (FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..), parseCpu, parseMemory)
import Systemdnetes.Scheduler
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Scheduler.Algo"
    [ testPropertyNamed "zero nodes makes all pods unschedulable with NoNodes" "prop_zeroNodesAllUnschedulable" prop_zeroNodesAllUnschedulable,
      testPropertyNamed "already-scheduled pods are ignored" "prop_alreadyScheduledIgnored" prop_alreadyScheduledIgnored,
      testPropertyNamed "every assignment fits within node capacity" "prop_assignmentsFit" prop_assignmentsFit,
      testPropertyNamed "no node over-committed after scheduling" "prop_noOvercommit" prop_noOvercommit,
      testPropertyNamed "best-fit prefers smaller remaining space" "prop_bestFitPreference" prop_bestFitPreference,
      testPropertyNamed "buildNodeResources sums match scheduled pods" "prop_buildNodeResourcesSumsMatch" prop_buildNodeResourcesSumsMatch,
      testPropertyNamed "unparseable resources are Unschedulable InvalidResources" "prop_invalidResourcesUnschedulable" prop_invalidResourcesUnschedulable,
      testPropertyNamed "total decisions equals number of pending pods" "prop_totalDecisionsEqualsPending" prop_totalDecisionsEqualsPending
    ]

-- Generators

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genPodName :: Gen PodName
genPodName = PodName <$> genText

genNodeName :: Gen NodeName
genNodeName = NodeName <$> genText

genMillicores :: Gen Int
genMillicores = Gen.int (Range.linear 100 2000)

genMebibytes :: Gen Int
genMebibytes = Gen.int (Range.linear 64 4096)

mkCpu :: Int -> Text
mkCpu n = T.pack (show n) <> "m"

mkMem :: Int -> Text
mkMem n = T.pack (show n) <> "Mi"

mkValidResources :: Int -> Int -> ResourceRequests
mkValidResources cpuVal memVal = ResourceRequests (mkCpu cpuVal) (mkMem memVal)

genPodSpec :: Gen PodSpec
genPodSpec = do
  cpuVal <- genMillicores
  memVal <- genMebibytes
  PodSpec
    <$> genPodName
    <*> (FlakeRef <$> genText)
    <*> pure (mkValidResources cpuVal memVal)
    <*> Gen.int (Range.linear 1 5)

genPendingPod :: Gen Pod
genPendingPod = do
  spec <- genPodSpec
  pure Pod {podSpec = spec, podState = Pending, podNode = Nothing, podNetwork = Nothing}

-- | Generate a list of pending pods with unique names.
genUniquePendingPods :: Range Int -> Gen [Pod]
genUniquePendingPods range = do
  n <- Gen.int range
  names <- Gen.list (Range.singleton n) genText
  let uniqueNames = map (PodName . \(i, t) -> t <> T.pack (show i)) (zip [(0 :: Int) ..] names)
  mapM (genPendingPodWithName) uniqueNames

genPendingPodWithName :: PodName -> Gen Pod
genPendingPodWithName name = do
  cpuVal <- genMillicores
  memVal <- genMebibytes
  flake <- FlakeRef <$> genText
  replicas <- Gen.int (Range.linear 1 5)
  let spec = PodSpec {podName = name, podFlakeRef = flake, podResources = mkValidResources cpuVal memVal, podReplicas = replicas}
  pure Pod {podSpec = spec, podState = Pending, podNode = Nothing, podNetwork = Nothing}

genWorkerNode :: Gen Node
genWorkerNode = do
  name <- genNodeName
  cpuCap <- Millicores <$> Gen.int (Range.linear 1000 8000)
  memCap <- Mebibytes <$> Gen.int (Range.linear 1024 16384)
  pure
    Node
      { nodeName = name,
        nodeAddress = "10.0.0.1",
        nodeCapacity = NodeCapacity cpuCap memCap,
        nodeRole = Worker
      }

-- Properties

prop_zeroNodesAllUnschedulable :: Property
prop_zeroNodesAllUnschedulable = property $ do
  pods <- forAll $ Gen.list (Range.linear 1 10) genPendingPod
  let result = schedule [] pods
  length (srAssignments result) === 0
  length (srUnschedulable result) === length pods
  assert $ all (\(_, e) -> e == NoNodes) (srUnschedulable result)

prop_alreadyScheduledIgnored :: Property
prop_alreadyScheduledIgnored = property $ do
  node <- forAll genWorkerNode
  spec <- forAll genPodSpec
  assignedNode <- forAll genNodeName
  let scheduledPod =
        Pod
          { podSpec = spec,
            podState = Scheduled,
            podNode = Just assignedNode,
            podNetwork = Nothing
          }
  let result = schedule [node] [scheduledPod]
  srAssignments result === []
  srUnschedulable result === []

prop_assignmentsFit :: Property
prop_assignmentsFit = property $ do
  nodes <- forAll $ Gen.list (Range.linear 1 5) genWorkerNode
  pods <- forAll $ genUniquePendingPods (Range.linear 1 10)
  let result = schedule nodes pods
      ledger = buildNodeResources nodes []
  mapM_
    ( \(pName, nName) ->
        case find (\p -> podName (podSpec p) == pName) pods of
          Nothing -> failure
          Just pod ->
            case find (\nr -> nrNodeName nr == nName) ledger of
              Nothing -> failure
              Just nr -> do
                let rr = podResources (podSpec pod)
                case (,) <$> parseCpu (cpu rr) <*> parseMemory (memory rr) of
                  Nothing -> failure
                  Just (cpuReq, memReq) -> do
                    assert $ nrCapacityCpu nr >= cpuReq
                    assert $ nrCapacityMemory nr >= memReq
    )
    (srAssignments result)

prop_noOvercommit :: Property
prop_noOvercommit = property $ do
  nodes <- forAll $ Gen.list (Range.linear 1 5) genWorkerNode
  pods <- forAll $ genUniquePendingPods (Range.linear 1 10)
  let result = schedule nodes pods
      assignedPods =
        [ pod {podState = Scheduled, podNode = Just assignedNode}
        | (pName, assignedNode) <- srAssignments result,
          pod <- pods,
          podName (podSpec pod) == pName
        ]
      finalLedger = buildNodeResources nodes assignedPods
  mapM_
    ( \nr -> do
        assert $ nrCommittedCpu nr <= nrCapacityCpu nr
        assert $ nrCommittedMemory nr <= nrCapacityMemory nr
    )
    finalLedger

prop_bestFitPreference :: Property
prop_bestFitPreference = property $ do
  let smallNode =
        Node
          { nodeName = NodeName "small",
            nodeAddress = "10.0.0.1",
            nodeCapacity = NodeCapacity (Millicores 1000) (Mebibytes 1024),
            nodeRole = Worker
          }
      largeNode =
        Node
          { nodeName = NodeName "large",
            nodeAddress = "10.0.0.2",
            nodeCapacity = NodeCapacity (Millicores 4000) (Mebibytes 4096),
            nodeRole = Worker
          }
      spec =
        PodSpec
          { podName = PodName "test-pod",
            podFlakeRef = FlakeRef "github:test/test",
            podResources = mkValidResources 200 256,
            podReplicas = 1
          }
      pod = Pod {podSpec = spec, podState = Pending, podNode = Nothing, podNetwork = Nothing}
      result = schedule [smallNode, largeNode] [pod]
  srAssignments result === [(PodName "test-pod", NodeName "small")]

prop_buildNodeResourcesSumsMatch :: Property
prop_buildNodeResourcesSumsMatch = property $ do
  node <- forAll genWorkerNode
  numPods <- forAll $ Gen.int (Range.linear 1 5)
  podPairs <- forAll $ Gen.list (Range.singleton numPods) ((,) <$> genMillicores <*> genMebibytes)
  let assignedPods =
        [ Pod
            { podSpec =
                PodSpec
                  { podName = PodName (T.pack $ "pod-" ++ show i),
                    podFlakeRef = FlakeRef "github:test/test",
                    podResources = mkValidResources c m,
                    podReplicas = 1
                  },
              podState = Scheduled,
              podNode = Just (nodeName node),
              podNetwork = Nothing
            }
        | ((c, m), i) <- zip podPairs [(0 :: Int) ..]
        ]
      ledger = buildNodeResources [node] assignedPods
  case ledger of
    [nr] -> do
      nrCommittedCpu nr === Millicores (sum [c | (c, _) <- podPairs])
      nrCommittedMemory nr === Mebibytes (sum [m | (_, m) <- podPairs])
    _ -> failure

prop_invalidResourcesUnschedulable :: Property
prop_invalidResourcesUnschedulable = property $ do
  node <- forAll genWorkerNode
  pName <- forAll genPodName
  let badPod =
        Pod
          { podSpec =
              PodSpec
                { podName = pName,
                  podFlakeRef = FlakeRef "github:test/test",
                  podResources = ResourceRequests "not-a-number" "also-bad",
                  podReplicas = 1
                },
            podState = Pending,
            podNode = Nothing,
            podNetwork = Nothing
          }
      result = schedule [node] [badPod]
  srAssignments result === []
  case srUnschedulable result of
    [(n, InvalidResources)] -> n === pName
    _ -> failure

prop_totalDecisionsEqualsPending :: Property
prop_totalDecisionsEqualsPending = property $ do
  nodes <- forAll $ Gen.list (Range.linear 0 5) genWorkerNode
  pods <- forAll $ genUniquePendingPods (Range.linear 0 15)
  let result = schedule nodes pods
      totalDecisions = length (srAssignments result) + length (srUnschedulable result)
  totalDecisions === length pods
