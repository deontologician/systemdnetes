module Systemdnetes.Domain.Pod
  ( PodName (..),
    FlakeRef (..),
    ResourceRequests (..),
    PodSpec (..),
    PodState (..),
    NetworkInfo (..),
    Pod (..),
    ContainerInfo (..),
    ContainerState (..),
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)
import Systemdnetes.Domain.Network (IPv4)
import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.WireGuard (WgKeyPair)

newtype PodName = PodName Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)

newtype FlakeRef = FlakeRef Text
  deriving stock (Eq, Show, Generic)
  deriving newtype (FromJSON, ToJSON)

data ResourceRequests = ResourceRequests
  { cpu :: Text,
    memory :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PodSpec = PodSpec
  { podName :: PodName,
    podFlakeRef :: FlakeRef,
    podResources :: ResourceRequests,
    podReplicas :: Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PodState = Pending | Scheduled | Running | Rebuilding | Failed
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Networking info assigned to a pod after IP allocation and WG key generation.
data NetworkInfo = NetworkInfo
  { netIp :: IPv4,
    netKeyPair :: WgKeyPair
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data Pod = Pod
  { podSpec :: PodSpec,
    podState :: PodState,
    podNode :: Maybe NodeName,
    podNetwork :: Maybe NetworkInfo
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ContainerState = ContainerRunning | ContainerStopped | ContainerFailed
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ContainerInfo = ContainerInfo
  { containerPod :: PodName,
    containerState :: ContainerState
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)
