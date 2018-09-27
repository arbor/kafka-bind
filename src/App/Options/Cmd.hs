{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE DeriveAnyClass   #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE TypeApplications #-}

module App.Options.Cmd where

import App.Options.Cmd.Help       as C
import App.Options.Cmd.KafkaToSqs as C
import App.Options.Cmd.SqsToKafka as C
import Control.Lens
import GHC.Generics
import Options.Applicative

data Cmd
  = CmdOfCmdHelp        { help        :: CmdHelp        }
  | CmdOfCmdKafkaToSqs  { kafkaToSqs  :: CmdKafkaToSqs  }
  | CmdOfCmdSqsToKafka  { sqsToKafka  :: CmdSqsToKafka  }
  deriving (Show, Eq, Generic)

makeLenses ''Cmd

cmds :: Parser Cmd
cmds = subparser
  (   command "help"          (info (CmdOfCmdHelp       <$> parserCmdHelp       ) $ progDesc "Help"         )
  <>  command "kafka-to-sqs"  (info (CmdOfCmdKafkaToSqs <$> parserCmdKafkaToSqs ) $ progDesc "Kafka to SQS" )
  <>  command "sqs-to-kafka"  (info (CmdOfCmdSqsToKafka <$> parserCmdSqsToKafka ) $ progDesc "SQS to Kafka" )
  )
