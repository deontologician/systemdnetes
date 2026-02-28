module Systemdnetes.Domain.ClusterSpec (tests) where

import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Cluster
import Systemdnetes.Domain.Node (Node (..), NodeName (..))
import Systemdnetes.Domain.Pod
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Cluster"
    [ testPropertyNamed "empty cluster has zero usage" "prop_emptyZero" prop_emptyZero,
      testPropertyNamed "all pods accounted for" "prop_allPodsAccountedFor" prop_allPodsAccountedFor,
      testPropertyNamed "scheduled pod usage sums correctly" "prop_usageSums" prop_usageSums,
      testPropertyNamed "unscheduled pods have no node" "prop_unscheduledNoNode" prop_unscheduledNoNode
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genNode :: Gen Node
genNode =
  (Node . NodeName <$> genText)
    <*> genText

genCapacity :: Gen NodeCapacity
genCapacity =
  (NodeCapacity . Millicores <$> Gen.int (Range.linear 1000 8000))
    <*> (Mebibytes <$> Gen.int (Range.linear 512 8192))

genPodSpec :: Gen PodSpec
genPodSpec =
  (PodSpec . PodName <$> genText)
    <*> (FlakeRef <$> genText)
    <*> (ResourceRequests <$> Gen.element ["100m", "500m", "1000m"] <*> Gen.element ["128Mi", "256Mi", "512Mi"])
    <*> Gen.int (Range.linear 1 5)

genPod :: Maybe NodeName -> Gen Pod
genPod mNode =
  Pod
    <$> genPodSpec
    <*> Gen.element [Pending, Scheduled, Running]
    <*> pure mNode
    <*> pure Nothing

prop_emptyZero :: Property
prop_emptyZero = property $ do
  nodes <- forAll $ Gen.list (Range.linear 0 5) ((,) <$> genNode <*> genCapacity)
  let cs = buildClusterState nodes []
  csUsedCpu cs === Millicores 0
  csUsedMemory cs === Mebibytes 0
  csUnscheduledPods cs === []

prop_allPodsAccountedFor :: Property
prop_allPodsAccountedFor = property $ do
  node <- forAll genNode
  cap <- forAll genCapacity
  scheduledPods <- forAll $ Gen.list (Range.linear 0 5) (genPod (Just (nodeName node)))
  unscheduledPods <- forAll $ Gen.list (Range.linear 0 5) (genPod Nothing)
  let cs = buildClusterState [(node, cap)] (scheduledPods ++ unscheduledPods)
      totalInViews = sum [length (nvPods nv) | nv <- csNodes cs]
      totalUnsched = length (csUnscheduledPods cs)
  totalInViews + totalUnsched === length scheduledPods + length unscheduledPods

prop_usageSums :: Property
prop_usageSums = property $ do
  node <- forAll genNode
  cap <- forAll genCapacity
  pods <- forAll $ Gen.list (Range.linear 1 5) (genPod (Just (nodeName node)))
  let cs = buildClusterState [(node, cap)] pods
  -- Used CPU should equal sum of all pod CPUs in node views
  csUsedCpu cs === sum [pvCpu pv | nv <- csNodes cs, pv <- nvPods nv]
  csUsedMemory cs === sum [pvMemory pv | nv <- csNodes cs, pv <- nvPods nv]

prop_unscheduledNoNode :: Property
prop_unscheduledNoNode = property $ do
  node <- forAll genNode
  cap <- forAll genCapacity
  pods <- forAll $ Gen.list (Range.linear 1 5) (genPod Nothing)
  let cs = buildClusterState [(node, cap)] pods
  -- All pods should be unscheduled
  length (csUnscheduledPods cs) === length pods
  -- Node should have no pods
  all (null . nvPods) (csNodes cs) === True
