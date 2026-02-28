module Systemdnetes.Effects.Ssh
  ( Ssh (..),
    runSshCommand,
  )
where

import Data.Text (Text)
import Polysemy
import Systemdnetes.Domain.Node (Node)

data Ssh m a where
  RunSshCommand :: Node -> Text -> Ssh m (Either Text Text)

makeSem ''Ssh
