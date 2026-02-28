module Systemdnetes.Effects.IpAllocator.Interpreter
  ( IpAllocatorState (..),
    mkAllocatorState,
    ipAllocatorToPure,
    ipAllocatorToIO,
  )
where

import Control.Concurrent.STM (TVar)
import Control.Concurrent.STM.TVar qualified as TVar
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Word (Word32)
import GHC.Conc (atomically)
import Polysemy
import Polysemy.State
import Systemdnetes.Domain.Network (CidrBlock, IPv4, cidrHostCount, cidrNthHost)
import Systemdnetes.Domain.Pod (PodName)
import Systemdnetes.Effects.IpAllocator

data IpAllocatorState = IpAllocatorState
  { allocCidr :: CidrBlock,
    allocByPod :: Map PodName IPv4,
    allocUsed :: Set IPv4
  }
  deriving stock (Eq, Show)

mkAllocatorState :: CidrBlock -> IpAllocatorState
mkAllocatorState cidr =
  IpAllocatorState
    { allocCidr = cidr,
      allocByPod = Map.empty,
      allocUsed = Set.empty
    }

-- | Pure interpreter via State — used in property tests.
ipAllocatorToPure ::
  IpAllocatorState ->
  Sem (IpAllocator ': r) a ->
  Sem r (IpAllocatorState, a)
ipAllocatorToPure initial =
  runState initial
    . reinterpret
      ( \case
          AllocateIp podName -> do
            s <- get @IpAllocatorState
            case Map.lookup podName (allocByPod s) of
              Just ip -> pure (Just ip)
              Nothing ->
                case findFreeIp s of
                  Nothing -> pure Nothing
                  Just ip -> do
                    put
                      s
                        { allocByPod = Map.insert podName ip (allocByPod s),
                          allocUsed = Set.insert ip (allocUsed s)
                        }
                    pure (Just ip)
          ReleaseIp podName -> do
            s <- get @IpAllocatorState
            case Map.lookup podName (allocByPod s) of
              Nothing -> pure ()
              Just ip ->
                put
                  s
                    { allocByPod = Map.delete podName (allocByPod s),
                      allocUsed = Set.delete ip (allocUsed s)
                    }
          GetPodIp podName -> do
            s <- get @IpAllocatorState
            pure $ Map.lookup podName (allocByPod s)
          ListAllocations -> do
            s <- get @IpAllocatorState
            pure $ Map.toList (allocByPod s)
      )

-- | IO interpreter backed by a TVar.
ipAllocatorToIO :: (Member (Embed IO) r) => TVar IpAllocatorState -> Sem (IpAllocator ': r) a -> Sem r a
ipAllocatorToIO var = interpret $ \case
  AllocateIp podName -> embed $ atomically $ do
    s <- TVar.readTVar var
    case Map.lookup podName (allocByPod s) of
      Just ip -> pure (Just ip)
      Nothing ->
        case findFreeIp s of
          Nothing -> pure Nothing
          Just ip -> do
            TVar.writeTVar
              var
              s
                { allocByPod = Map.insert podName ip (allocByPod s),
                  allocUsed = Set.insert ip (allocUsed s)
                }
            pure (Just ip)
  ReleaseIp podName -> embed $ atomically $ do
    s <- TVar.readTVar var
    case Map.lookup podName (allocByPod s) of
      Nothing -> pure ()
      Just ip ->
        TVar.writeTVar
          var
          s
            { allocByPod = Map.delete podName (allocByPod s),
              allocUsed = Set.delete ip (allocUsed s)
            }
  GetPodIp podName -> embed $ do
    s <- TVar.readTVarIO var
    pure $ Map.lookup podName (allocByPod s)
  ListAllocations -> embed $ do
    s <- TVar.readTVarIO var
    pure $ Map.toList (allocByPod s)

-- | Find the first free IP in the CIDR by scanning host indices.
findFreeIp :: IpAllocatorState -> Maybe IPv4
findFreeIp s = go 0
  where
    count = cidrHostCount (allocCidr s)
    go :: Word32 -> Maybe IPv4
    go n
      | n >= count = Nothing
      | otherwise = case cidrNthHost (allocCidr s) n of
          Nothing -> Nothing
          Just ip
            | Set.member ip (allocUsed s) -> go (n + 1)
            | otherwise -> Just ip
