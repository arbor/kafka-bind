{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import App
import App.AWS.Env
import App.Options.Cmd
import App.Options.Cmd.KafkaToSqs
import App.Options.Parser
import App.RunApplication
import Arbor.Logger
import Control.Lens
import Control.Monad.IO.Class
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (schemaRegistry)
import Kafka.Conduit.Source
import Network.AWS.Env
import Network.StatsD                       as S
import System.Environment

import qualified App.Action.KafkaToSqs as C
import qualified Data.Text             as T

mkAppEnv :: RunApplication c => StatsClient -> Logger -> Env -> GlobalOptions c -> c -> AppEnv c
mkAppEnv stats logger envAws opt cmd =
  let newOpt = opt { _optCmd = cmd }
      envApp = AppEnv newOpt envAws stats logger
  in envApp

main :: IO ()
main = do
  opt <- parseOptions
  progName <- T.pack <$> getProgName
  let logLvk    = opt ^. optLogLevel
  let statsConf = opt ^. optStatsConfig

  withStdOutTimedFastLogger $ \lgr -> do
    withStatsClient progName statsConf $ \stats -> do
      envAws <- mkEnv (opt ^. optRegion) logLvk lgr
      let mkAppEnv2 :: RunApplication c => c -> AppEnv c
          mkAppEnv2 cmd = mkAppEnv stats (Logger lgr logLvk) envAws (opt { _optCmd = cmd }) cmd
      res <- case opt ^. optCmd of
        CmdOfCmdKafkaToSqs cmd -> runApplication (mkAppEnv2 cmd)
        CmdOfCmdSqsToKafka cmd -> runApplication (mkAppEnv2 cmd)
        cmd                    -> return $ Left (AppErr ("Not implemented: " <> show cmd))
      case res of
        Left err -> pushLogMessage lgr LevelError ("Exiting: " <> show err)
        Right _  -> pure ()
    pushLogMessage lgr LevelError ("Premature exit, must not happen." :: String)
