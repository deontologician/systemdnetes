module Systemdnetes.Deploy.Cmd
  ( Cmd (..),
    CmdResult (..),
    runCmd,
    runCmd_,
    readCmd,
    checkCmd,
  )
where

import Data.Text (Text)
import Polysemy

data CmdResult = CmdResult
  { cmdExitCode :: Int,
    cmdStdout :: Text,
    cmdStderr :: Text
  }
  deriving stock (Eq, Show)

data Cmd m a where
  RunCmd :: Text -> [Text] -> Text -> Cmd m CmdResult

makeSem ''Cmd

-- | Run a command, ignoring its output. Fails with Left on non-zero exit.
runCmd_ :: (Member Cmd r) => Text -> [Text] -> Sem r (Either Text ())
runCmd_ prog args = do
  result <- runCmd prog args ""
  pure $
    if cmdExitCode result == 0
      then Right ()
      else Left (cmdStderr result)

-- | Run a command and return its stdout. Fails with Left on non-zero exit.
readCmd :: (Member Cmd r) => Text -> [Text] -> Sem r (Either Text Text)
readCmd prog args = do
  result <- runCmd prog args ""
  pure $
    if cmdExitCode result == 0
      then Right (cmdStdout result)
      else Left (cmdStderr result)

-- | Check if a command is available (exit 0 from --version or similar).
checkCmd :: (Member Cmd r) => Text -> Sem r Bool
checkCmd prog = do
  result <- runCmd prog ["--version"] ""
  pure (cmdExitCode result == 0)
