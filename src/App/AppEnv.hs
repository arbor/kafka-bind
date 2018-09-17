{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE DuplicateRecordFields  #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TemplateHaskell        #-}
{-# LANGUAGE TypeApplications       #-}

module App.AppEnv where

import Arbor.Logger              (LogLevel, TimedFastLogger)
import Data.Generics.Product.Any
import GHC.Generics
import Network.AWS               (Env, HasEnv (..))
import Network.StatsD            (StatsClient)

import qualified App.Options.Types as Z

data Logger = Logger
  { logger   :: TimedFastLogger
  , logLevel :: LogLevel
  } deriving (Generic)

data AppEnv o = AppEnv
  { options     :: Z.GlobalOptions o
  , awsEnv      :: Env
  , statsClient :: StatsClient
  , logger      :: Logger
  } deriving (Generic)

instance HasEnv (AppEnv o) where
  environment = the @"awsEnv"
