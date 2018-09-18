module App.RunApplication where

import App.AppError

import qualified App.AppEnv as E

class RunApplication c where
  runApplication :: E.AppEnv c -> IO (Either AppError ())
