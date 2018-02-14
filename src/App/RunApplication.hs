module App.RunApplication where

import App.AppEnv
import App.AppError
import App.AppState

class RunApplication c where
  runApplication :: AppEnv c -> IO (Either AppError AppState)
