module Systemdnetes.Deploy.Skopeo
  ( pushImage,
  )
where

import Data.Text (Text)
import Polysemy
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Effects.Log

-- | Copy a local OCI archive to a remote registry via skopeo.
pushImage :: (Member Cmd r, Member Log r) => Text -> Text -> Sem r (Either Text ())
pushImage localPath remoteRef = do
  logInfo ("Pushing " <> localPath <> " -> " <> remoteRef)
  runCmd_ "skopeo" ["copy", "docker-archive:" <> localPath, "docker://" <> remoteRef]
