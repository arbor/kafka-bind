{-# LANGUAGE DeriveAnyClass   #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell  #-}

module App.Options.Cmd where

import App.Options.Cmd.Help       as C
import App.Options.Cmd.KafkaToSqs as C
import App.Options.Cmd.SqsToKafka as C
import App.Options.Cmd.StdinToSqs as C
import Control.Lens
import Data.Monoid
import Options.Applicative

data Cmd
  = CmdOfCmdHelp        { _cmdHelp        :: CmdHelp        }
  | CmdOfCmdKafkaToSqs  { _cmdKafkaToSqs  :: CmdKafkaToSqs  }
  | CmdOfCmdSqsToKafka  { _cmdSqsToKafka  :: CmdSqsToKafka  }
  | CmdOfCmdStdinToSqs  { _cmdStdinToSqs  :: CmdStdinToSqs  }
  deriving (Show, Eq)

makeLenses ''Cmd

cmds :: Parser Cmd
cmds = subparser
  (   command "help"          (info (CmdOfCmdHelp       <$> parserCmdHelp       ) $ progDesc "Help"         )
  <>  command "kafka-to-sqs"  (info (CmdOfCmdKafkaToSqs <$> parserCmdKafkaToSqs ) $ progDesc "Kafka to SQS" )
  <>  command "sqs-to-kafka"  (info (CmdOfCmdSqsToKafka <$> parserCmdSqsToKafka ) $ progDesc "SQS to Kafka" )
  <>  command "stdin-to-sqs"  (info (CmdOfCmdStdinToSqs <$> parserCmdStdinToSqs ) $ progDesc "Cmdline to Sqs" )
  )
