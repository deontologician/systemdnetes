module Systemdnetes.Domain.Dns
  ( HostsEntry (..),
    renderHostsEntry,
    renderHostsFile,
    hostsFileName,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Systemdnetes.Domain.Network (IPv4, ipToText)
import Systemdnetes.Domain.Pod (PodName (..))

-- | A single hosts-file entry mapping an IP to a hostname.
data HostsEntry = HostsEntry
  { hostsIp :: IPv4,
    hostsHostname :: Text,
    hostsPodName :: PodName
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Render a single hosts entry: "10.100.0.1  my-pod.pod.cluster.local"
renderHostsEntry :: HostsEntry -> Text
renderHostsEntry entry =
  ipToText (hostsIp entry) <> "\t" <> hostsHostname entry

-- | Render a complete hosts file from a list of entries (one line per entry).
renderHostsFile :: [HostsEntry] -> Text
renderHostsFile = T.unlines . map renderHostsEntry

-- | Generate the hosts file name for a pod: "<pod-name>.hosts"
hostsFileName :: PodName -> FilePath
hostsFileName (PodName name) = T.unpack name <> ".hosts"
