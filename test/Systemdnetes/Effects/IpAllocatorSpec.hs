module Systemdnetes.Effects.IpAllocatorSpec (tests) where

import Data.List (nub)
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Network (CidrBlock (..), cidrContains, cidrHostCount, parseCidr)
import Systemdnetes.Domain.Pod (PodName (..))
import Systemdnetes.Effects.IpAllocator
import Systemdnetes.Effects.IpAllocator.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.IpAllocator"
    [ testPropertyNamed "allocate then get returns the IP" "prop_allocateGet" prop_allocateGet,
      testPropertyNamed "no double allocation" "prop_noDoubleAlloc" prop_noDoubleAlloc,
      testPropertyNamed "release then reuse" "prop_releaseThenReuse" prop_releaseThenReuse,
      testPropertyNamed "CIDR exhaustion" "prop_exhaustion" prop_exhaustion,
      testPropertyNamed "all IPs distinct and within CIDR" "prop_distinctWithinCidr" prop_distinctWithinCidr
    ]

genPodName :: Gen PodName
genPodName = PodName <$> Gen.text (Range.linear 1 20) Gen.alphaNum

-- Use a small /28 CIDR (14 usable hosts) for manageable tests.
testCidr :: CidrBlock
testCidr = case parseCidr "10.200.0.0/28" of
  Just c -> c
  Nothing -> error "bad test CIDR"

runPure :: Sem (IpAllocator ': r) a -> Sem r (IpAllocatorState, a)
runPure = ipAllocatorToPure (mkAllocatorState testCidr)

prop_allocateGet :: Property
prop_allocateGet = property $ do
  name <- forAll genPodName
  let (_, (mip, got)) = run $ runPure $ do
        mip' <- allocateIp name
        got' <- getPodIp name
        pure (mip', got')
  assert $ isJust mip
  mip === got

prop_noDoubleAlloc :: Property
prop_noDoubleAlloc = property $ do
  name <- forAll genPodName
  let (_, (ip1, ip2)) = run $ runPure $ do
        ip1' <- allocateIp name
        ip2' <- allocateIp name
        pure (ip1', ip2')
  -- Second allocation of same pod returns same IP (idempotent)
  ip1 === ip2

prop_releaseThenReuse :: Property
prop_releaseThenReuse = property $ do
  name1 <- forAll genPodName
  name2 <- forAll $ Gen.filter (/= name1) genPodName
  let (_, (ip1, ip2)) = run $ runPure $ do
        ip1' <- allocateIp name1
        releaseIp name1
        ip2' <- allocateIp name2
        pure (ip1', ip2')
  -- After release, the freed IP can be reused
  ip1 === ip2

prop_exhaustion :: Property
prop_exhaustion = property $ do
  let count = cidrHostCount testCidr
      names = [PodName (T.pack ("pod-" <> show i)) | i <- [0 .. count]]
      (_, results) = run $ runPure $ mapM allocateIp names
  -- First `count` allocations succeed
  all isJust (take (fromIntegral count) results) === True
  -- The (count+1)th fails
  isNothing (last results) === True

prop_distinctWithinCidr :: Property
prop_distinctWithinCidr = property $ do
  names <- forAll $ Gen.list (Range.linear 1 14) genPodName
  let uniqueNames = nub names
      (_, (ips, listed)) = run $ runPure $ do
        ips' <- mapM allocateIp uniqueNames
        listed' <- listAllocations
        pure (ips', listed')
      justIps = [ip | Just ip <- ips]
  -- All allocated IPs are distinct
  length (nub justIps) === length justIps
  -- All are within the CIDR
  assert $ all (cidrContains testCidr) justIps
  -- Listed allocations match
  length listed === length uniqueNames
