{-# LANGUAGE FlexibleInstances #-}

module App.Options.Parser where

import App.Options
import Control.Monad.Logger (LogLevel (..))
import Data.Semigroup       ((<>))
import Network.AWS.S3.Types (Region (..))
import Options.Applicative

import qualified App.Options.Cmd   as Z
import qualified App.Options.Types as Z

optParser :: Parser (Z.GlobalOptions Z.Cmd)
optParser = Z.GlobalOptions
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
  <*> Z.cmds
  <*> statsConfigParser

optParserInfo :: ParserInfo (Z.GlobalOptions Z.Cmd)
optParserInfo = info (helper <*> optParser)
  (  fullDesc
  <> progDesc "Bind a kafka topic to another endpoint"
  <> header "Kafka Bind"
  )

parseOptions :: IO (Z.GlobalOptions Z.Cmd)
parseOptions = customExecParser (prefs showHelpOnEmpty) optParserInfo
