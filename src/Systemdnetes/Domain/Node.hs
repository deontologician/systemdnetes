module Systemdnetes.Domain.Node
  ( NodeName (..),
    Node (..),
    HealthStatus (..),
    NodeStatus (..),
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

newtype NodeName = NodeName Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)

data Node = Node
  { nodeName :: NodeName,
    nodeAddress :: Text
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
