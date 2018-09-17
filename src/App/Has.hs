{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module App.Has where

import Control.Lens
import Data.Generics.Product.Any
import Network.StatsD            (StatsClient)

import qualified App.AppEnv        as Z
import qualified App.Options.Types as Z

class HasKafkaConfig c where
  kafkaConfig :: Lens' c Z.KafkaConfig

class HasStatsClient a where
  statsClient :: Lens' a StatsClient

instance HasStatsClient StatsClient where
  statsClient = id

instance HasStatsClient (Z.AppEnv o) where
  statsClient = the @"statsClient"

class HasLogger c where
  logger :: Lens' c Z.Logger

instance HasLogger (Z.AppEnv o) where
  logger = the @"logger"
