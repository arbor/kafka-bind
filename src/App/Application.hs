{-# LANGUAGE ExplicitForAll             #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeSynonymInstances       #-}

module App.Application
where

import Arbor.Logger
import Control.Lens
import Control.Monad.Catch
import Control.Monad.Except
import Control.Monad.Logger         (LoggingT, MonadLogger)
import Control.Monad.Reader
import Control.Monad.State.Strict   (MonadState (..), StateT, execStateT)
import Control.Monad.Trans.Resource
import Data.Text                    (Text)
import Network.AWS                  as AWS hiding (LogLevel)
import Network.StatsD               as S

import App.AppEnv
import App.AppError
import App.AppState
import App.Orphans  ()

type AppName = Text

newtype Application o a = Application
  { unApp :: ReaderT (AppEnv o) (StateT AppState (ExceptT AppError (LoggingT AWS))) a
  } deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadThrow
             , MonadCatch
             , MonadReader (AppEnv o)
             , MonadState AppState
             , MonadError AppError
             , MonadAWS
             , MonadLogger
             , MonadResource)

-- This is here to simplify the constraint
-- it also helps to avoid propagating FlexibleContexts requirements
class MonadError AppError m => MonadAppError m where

class ( MonadReader (AppEnv o) m
      , MonadState AppState m
      , MonadLogger m
      , MonadAWS m
      , MonadStats m
      , MonadResource m
      , MonadThrow m
      , MonadCatch m
      , MonadError AppError m
      , MonadAppError m
      , MonadIO m) => MonadApp o m where

deriving instance MonadAppError (Application o)
deriving instance MonadApp o (Application o)

instance MonadStats (Application o) where
  getStatsClient = reader _appStatsClient

runApplicationM :: Show o
                => AppEnv o
                -> Application o ()
                -> IO (Either AppError AppState)
runApplicationM envApp f =
  runResourceT
    . runAWS (envApp ^. appAwsEnv)
    . runTimedLogT (envApp ^. appLogger . lgLogLevel) (envApp ^. appLogger . lgLogger)
    . runExceptT
    . flip execStateT appStateEmpty
    $ do
        logInfo $ show (envApp ^. appOptions)
        runReaderT (unApp f) envApp

