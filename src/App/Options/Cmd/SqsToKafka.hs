{-# LANGUAGE DeriveAnyClass   #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell  #-}

module App.Options.Cmd.SqsToKafka
  ( CmdSqsToKafka(..)
  , parserCmdSqsToKafka
  ) where

import Control.Lens
import Options.Applicative

data CmdSqsToKafka = CmdSqsToKafka deriving (Show, Eq)

makeLenses ''CmdSqsToKafka

parserCmdSqsToKafka :: Parser CmdSqsToKafka
parserCmdSqsToKafka = pure CmdSqsToKafka
