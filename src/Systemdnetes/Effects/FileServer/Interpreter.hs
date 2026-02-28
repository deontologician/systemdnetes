module Systemdnetes.Effects.FileServer.Interpreter
  ( fileServerToPure,
    fileServerToIO,
  )
where

import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Polysemy
import Systemdnetes.Effects.FileServer

-- | Pure interpreter: looks up files from a provided map.
fileServerToPure ::
  Map FilePath LBS.ByteString ->
  Sem (FileServer ': r) a ->
  Sem r a
fileServerToPure files = interpret $ \case
  ReadStaticFile path ->
    pure $ Map.findWithDefault "" path files

-- | IO interpreter: reads files from disk.
fileServerToIO :: (Member (Embed IO) r) => Sem (FileServer ': r) a -> Sem r a
fileServerToIO = interpret $ \case
  ReadStaticFile path -> embed $ LBS.readFile path
