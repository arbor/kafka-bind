{-# LANGUAGE FlexibleInstances #-}

module App.Options.Parser where

import App.Options
import App.Options.Cmd
import Control.Monad.Logger (LogLevel (..))
import Data.Semigroup       ((<>))
import Network.AWS.S3.Types (Region (..))
import Options.Applicative

optParser :: Parser (Options Cmd)
optParser = Options
  <$> readOptionMsg "Valid values are LevelDebug, LevelInfo, LevelWarn, LevelError"
        (  long "log-level"
        <> metavar "LOG_LEVEL"
        <> showDefault <> value LevelInfo
        <> help "Log level.")
  <*> readOrFromTextOption
        (  long "region"
        <> metavar "AWS_REGION"
        <> showDefault <> value Oregon
        <> help "The AWS region in which to operate"
        )
  <*> cmds
  <*> statsConfigParser

optParserInfo :: ParserInfo (Options Cmd)
optParserInfo = info (helper <*> optParser)
  (  fullDesc
  <> progDesc "Bind a kafka topic to another endpoint"
  <> header "Kafka Bind"
  )

parseOptions :: IO (Options Cmd)
parseOptions = customExecParser (prefs showHelpOnEmpty) optParserInfo
