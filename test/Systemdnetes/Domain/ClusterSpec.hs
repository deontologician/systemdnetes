module Systemdnetes.Domain.ClusterSpec (tests) where

import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Cluster
import Systemdnetes.Domain.Network (IPv4 (..), ipToText)
import Systemdnetes.Domain.Node (Node (..), NodeName (..), NodeRole (..))
import Systemdnetes.Domain.Pod
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..))
import Systemdnetes.Domain.WireGuard (WgKeyPair (..), WgPrivateKey (..), WgPublicKey (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Cluster"
    [ testPropertyNamed "empty cluster has zero usage" "prop_emptyZero" prop_emptyZero,
      testPropertyNamed "all pods accounted for" "prop_allPodsAccountedFor" prop_allPodsAccountedFor,
      testPropertyNamed "scheduled pod usage sums correctly" "prop_usageSums" prop_usageSums,
      testPropertyNamed "unscheduled pods have no node" "prop_unscheduledNoNode" prop_unscheduledNoNode,
      testPropertyNamed "pod view preserves IP" "prop_podViewPreservesIp" prop_podViewPreservesIp
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genCapacity :: Gen NodeCapacity
genCapacity =
  (NodeCapacity . Millicores <$> Gen.int (Range.linear 1000 8000))
    <*> (Mebibytes <$> Gen.int (Range.linear 512 8192))

genNode :: Gen Node
genNode =
  (Node . NodeName <$> genText)
    <*> genText
    <*> genCapacity
    <*> pure Worker

genPodSpec :: Gen PodSpec
genPodSpec =
  (PodSpec . PodName <$> genText)
    <*> (FlakeRef <$> genText)
    <*> (ResourceRequests <$> Gen.element ["100m", "500m", "1000m"] <*> Gen.element ["128Mi", "256Mi", "512Mi"])
    <*> Gen.int (Range.linear 1 5)

genNetworkInfo :: Gen NetworkInfo
genNetworkInfo =
  (NetworkInfo . IPv4 <$> Gen.word32 (Range.linear 0 maxBound))
    <*> ( (WgKeyPair . WgPrivateKey <$> genText)
            <*> (WgPublicKey <$> genText)
        )

genPod :: Maybe NodeName -> Gen Pod
genPod mNode =
  Pod
    <$> genPodSpec
    <*> Gen.element [Pending, Scheduled, Running]
    <*> pure mNode
    <*> pure Nothing

genPodWithNetwork :: Maybe NodeName -> Maybe NetworkInfo -> Gen Pod
genPodWithNetwork mNode mNet =
  Pod
    <$> genPodSpec
    <*> Gen.element [Pending, Scheduled, Running]
    <*> pure mNode
    <*> pure mNet

prop_emptyZero :: Property
prop_emptyZero = property $ do
  nodes <- forAll $ Gen.list (Range.linear 0 5) genNode
  let cs = buildClusterState nodes []
  csUsedCpu cs === Millicores 0
  csUsedMemory cs === Mebibytes 0
  csUnscheduledPods cs === []

prop_allPodsAccountedFor :: Property
prop_allPodsAccountedFor = property $ do
  node <- forAll genNode
  scheduledPods <- forAll $ Gen.list (Range.linear 0 5) (genPod (Just (nodeName node)))
  unscheduledPods <- forAll $ Gen.list (Range.linear 0 5) (genPod Nothing)
  let cs = buildClusterState [node] (scheduledPods ++ unscheduledPods)
      totalInViews = sum [length (nvPods nv) | nv <- csNodes cs]
      totalUnsched = length (csUnscheduledPods cs)
  totalInViews + totalUnsched === length scheduledPods + length unscheduledPods

prop_usageSums :: Property
prop_usageSums = property $ do
  node <- forAll genNode
  pods <- forAll $ Gen.list (Range.linear 1 5) (genPod (Just (nodeName node)))
  let cs = buildClusterState [node] pods
  -- Used CPU should equal sum of all pod CPUs in node views
  csUsedCpu cs === sum [pvCpu pv | nv <- csNodes cs, pv <- nvPods nv]
  csUsedMemory cs === sum [pvMemory pv | nv <- csNodes cs, pv <- nvPods nv]

prop_unscheduledNoNode :: Property
prop_unscheduledNoNode = property $ do
  node <- forAll genNode
  pods <- forAll $ Gen.list (Range.linear 1 5) (genPod Nothing)
  let cs = buildClusterState [node] pods
  -- All pods should be unscheduled
  length (csUnscheduledPods cs) === length pods
  -- Node should have no pods
  all (null . nvPods) (csNodes cs) === True

prop_podViewPreservesIp :: Property
prop_podViewPreservesIp = property $ do
  node <- forAll genNode
  netInfo <- forAll genNetworkInfo
  pod <- forAll $ genPodWithNetwork (Just (nodeName node)) (Just netInfo)
  let cs = buildClusterState [node] [pod]
      podViews = concatMap nvPods (csNodes cs)
  case podViews of
    [pv] -> pvIp pv === Just (ipToText (netIp netInfo))
    _ -> failure
