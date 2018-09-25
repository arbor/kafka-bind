{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE TypeApplications      #-}

module App.AppEnv where

import Arbor.Logger              (LogLevel, TimedFastLogger)
import Arbor.Network.StatsD      (StatsClient)
import Control.Concurrent.STM    (TVar)
import Data.Generics.Product.Any
import GHC.Generics
import Network.AWS               (Env, HasEnv (..))

import qualified App.Options.Types as Z

data Logger = Logger
  { logger   :: TimedFastLogger
  , logLevel :: LogLevel
  } deriving (Generic)

newtype AppCounters = AppCounters
  { processedMessages :: TVar Int
  } deriving (Generic)

data AppEnv o = AppEnv
  { options     :: Z.GlobalOptions o
  , awsEnv      :: Env
  , statsClient :: StatsClient
  , logger      :: Logger
  , counters    :: AppCounters
  } deriving (Generic)

instance HasEnv (AppEnv o) where
  environment = the @"awsEnv"
