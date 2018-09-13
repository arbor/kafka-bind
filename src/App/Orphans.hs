{-# OPTIONS_GHC -fno-warn-orphans #-}
module App.Orphans where

import Control.Monad.Logger       (LoggingT)
import Control.Monad.State.Strict (lift)
import Network.AWS                as AWS hiding (LogLevel)

instance MonadAWS m => MonadAWS (LoggingT m) where
  liftAWS = lift . liftAWS
