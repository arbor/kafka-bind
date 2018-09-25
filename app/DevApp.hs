{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}

module DevApp where

import App.AWS.Env
import App.Orphans                  ()
import Arbor.Logger
import Arbor.Network.StatsD         (MonadStats)
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Logger         (LoggingT, MonadLogger)
import Control.Monad.Trans.Resource
import Network.AWS                  as AWS hiding (LogLevel)

import qualified Arbor.Network.StatsD      as S
import qualified Arbor.Network.StatsD.Type as Z

newtype DevApp a = DevApp
  { unDevApp :: (LoggingT AWS) a
  } deriving ( Functor, Applicative, Monad, MonadIO, MonadThrow, MonadCatch
             , MonadMask, MonadAWS, MonadLogger, MonadResource)

instance MonadStats DevApp where
  getStatsClient = pure Z.Dummy

runDevApp' :: HasEnv e => e -> TimedFastLogger -> DevApp a -> IO a
runDevApp' e logger f = runResourceT . runAWS e $ runTimedLogT LevelInfo logger (unDevApp f)


runDevApp :: DevApp a -> IO a
runDevApp f =
  withStdOutTimedFastLogger $ \logger -> do
    env <- mkEnv Oregon LevelInfo logger
    runDevApp' env logger f
