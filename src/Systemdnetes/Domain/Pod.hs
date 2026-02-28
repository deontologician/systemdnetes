module Systemdnetes.Domain.Pod
  ( PodName (..),
    FlakeRef (..),
    ResourceRequests (..),
    PodSpec (..),
    PodState (..),
    Pod (..),
    ContainerInfo (..),
    ContainerState (..),
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)
import Systemdnetes.Domain.Node (NodeName)

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

data PodState = Pending | Scheduled | Running | Failed
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data Pod = Pod
  { podSpec :: PodSpec,
    podState :: PodState,
    podNode :: Maybe NodeName
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
