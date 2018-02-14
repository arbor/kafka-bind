{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TemplateHaskell        #-}

module App.AppEnv where

import App.Options
import Arbor.Logger   (LogLevel, TimedFastLogger)
import Control.Lens
import Network.AWS    (Env, HasEnv (..))
import Network.StatsD (StatsClient)

data Logger = Logger
  { _lgLogger   :: TimedFastLogger
  , _lgLogLevel :: LogLevel
  }

data AppEnv o = AppEnv
  { _appOptions     :: Options o
  , _appAwsEnv      :: Env
  , _appStatsClient :: StatsClient
  , _appLogger      :: Logger
  }

makeClassy ''Logger
makeClassy ''AppEnv

instance HasEnv (AppEnv o) where
  environment = appEnv . appAwsEnv

class HasStatsClient a where
  statsClient :: Lens' a StatsClient

instance HasStatsClient StatsClient where
  statsClient = id

instance HasStatsClient (AppEnv o) where
  statsClient = appStatsClient

instance HasLogger (AppEnv o) where
  logger = appEnv . appLogger

instance HasStatsConfig (AppEnv o) where
  statsConfig = appOptions . statsConfig

