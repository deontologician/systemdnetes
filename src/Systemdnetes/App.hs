module Systemdnetes.App
  ( AppEffects,
    runApp,
  )
where

import Control.Concurrent.STM (TVar)
import Data.Map.Strict (Map)
import Polysemy
import Systemdnetes.Domain.Pod (Pod, PodName)
import Systemdnetes.Effects.Log
import Systemdnetes.Effects.Log.Interpreter
import Systemdnetes.Effects.Store
import Systemdnetes.Effects.Store.Interpreter
import Systemdnetes.Effects.Systemd
import Systemdnetes.Effects.Systemd.Interpreter

type AppEffects = '[Log, Store, Systemd, Embed IO, Final IO]

runApp :: TVar (Map PodName Pod) -> Sem AppEffects a -> IO a
runApp store =
  runFinal
    . embedToFinal
    . systemdToIO
    . storeToIO store
    . logToIO
