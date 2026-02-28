module Systemdnetes.Effects.Log.Interpreter
  ( logToIO,
    logToList,
  )
where

import Data.Bifunctor (first)
import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import Polysemy.State
import Systemdnetes.Effects.Log

logToIO :: (Member (Embed IO) r) => Sem (Log ': r) a -> Sem r a
logToIO = interpret $ \case
  LogMsg level msg -> embed $ putStrLn (formatLog level msg)

formatLog :: LogLevel -> Text -> String
formatLog level msg = "[" <> show level <> "] " <> T.unpack msg

logToList :: Sem (Log ': r) a -> Sem r ([LogMessage], a)
logToList =
  fmap (first reverse)
    . runState []
    . reinterpret @Log @(State [LogMessage]) (\case LogMsg level msg -> modify' (LogMessage level msg :))
