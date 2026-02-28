module Systemdnetes.App
  ( AppEffects,
    runApp,
  )
where

import Polysemy
import Systemdnetes.Effects.Log
import Systemdnetes.Effects.Log.Interpreter

type AppEffects = '[Log, Embed IO, Final IO]

runApp :: Sem AppEffects a -> IO a
runApp = runFinal . embedToFinal . logToIO
