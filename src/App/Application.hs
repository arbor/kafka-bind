{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE ExplicitForAll             #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeSynonymInstances       #-}

module App.Application where

import App.AppError
import App.Orphans                  ()
import Arbor.Logger
import Control.Lens
import Control.Monad.Catch
import Control.Monad.Except
import Control.Monad.Logger         (LoggingT, MonadLogger)
import Control.Monad.Reader
import Control.Monad.Trans.Resource
import Data.Generics.Product.Any
import Data.Text                    (Text)
import Network.AWS                  as AWS hiding (LogLevel)
import Network.StatsD               as S

import qualified App.AppEnv as E

type AppName = Text

newtype Application o a = Application
  { unApp :: ReaderT (E.AppEnv o) (LoggingT AWS) a
  } deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadThrow
             , MonadCatch
             , MonadReader (E.AppEnv o)
             , MonadAWS
             , MonadLogger
             , MonadResource)

class ( MonadReader (E.AppEnv o) m
      , MonadLogger m
      , MonadAWS m
      , MonadStats m
      , MonadResource m
      , MonadThrow m
      , MonadCatch m
      , MonadIO m) => MonadApp o m where

deriving instance MonadApp o (Application o)

instance MonadStats (Application o) where
  getStatsClient = view $ the @"statsClient"

instance MonadStats (Application o) => MonadStats (ExceptT e (Application o)) where
  getStatsClient = lift getStatsClient

instance MonadApp o (Application o) => MonadApp o ((ExceptT e) (Application o)) where

runApplicationM :: Show o
                => E.AppEnv o
                -> Application o (Either AppError ())
                -> IO (Either AppError ())
runApplicationM envApp f =
  runResourceT
    . runAWS (envApp ^. the @"awsEnv")
    . runTimedLogT (envApp ^. the @"logger" . the @"logLevel") (envApp ^. the @"logger" . the @"logger")
    $ do
        logInfo $ show (envApp ^. the @"options")
        runReaderT (unApp f) envApp
