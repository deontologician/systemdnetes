module Systemdnetes.Effects.FileServer
  ( FileServer (..),
    readStaticFile,
  )
where

import Data.ByteString.Lazy (ByteString)
import Polysemy

data FileServer m a where
  ReadStaticFile :: FilePath -> FileServer m ByteString

makeSem ''FileServer
