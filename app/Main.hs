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
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (schemaRegistry)
import Kafka.Conduit.Source
import Network.StatsD                       as S
import System.Environment

import qualified App.Action.KafkaToSqs as C
import qualified Data.Text             as T

main :: IO ()
main = do
  opt <- parseOptions
  progName <- T.pack <$> getProgName
  let logLvk  = opt ^. optLogLevel
  let statsConf = opt ^. optStatsConfig

  withStdOutTimedFastLogger $ \lgr -> do
    withStatsClient progName statsConf $ \stats -> do
      envAws <- mkEnv (opt ^. optRegion) logLvk lgr
      case opt ^. optCmd of
        CmdOfCmdKafkaToSqs cmd -> do
          let newOpt = opt { _optCmd = cmd }
          let envApp = AppEnv newOpt envAws stats (Logger lgr logLvk)
          res <- runApplication envApp
          case res of
            Left err -> pushLogMessage lgr LevelError ("Exiting: " <> show err)
            Right _  -> pure ()
    pushLogMessage lgr LevelError ("Premature exit, must not happen." :: String)
