module Systemdnetes.Domain.Node
  ( NodeName (..),
    NodeCapacity (..),
    NodeRole (..),
    Node (..),
    HealthStatus (..),
    NodeStatus (..),
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)
import Systemdnetes.Domain.Resource (Mebibytes, Millicores)

newtype NodeName = NodeName Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)

data NodeCapacity = NodeCapacity
  { capacityCpu :: Millicores,
    capacityMemory :: Mebibytes
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data NodeRole = Orchestrator | Worker
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data Node = Node
  { nodeName :: NodeName,
    nodeAddress :: Text,
    nodeCapacity :: NodeCapacity,
    nodeRole :: NodeRole
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data HealthStatus = Healthy | Unhealthy | Unknown
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data NodeStatus = NodeStatus
  { statusNodeName :: NodeName,
    statusAddress :: Text,
    statusHealth :: HealthStatus,
    statusDetail :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)
