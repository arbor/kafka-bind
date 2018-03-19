{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TemplateHaskell        #-}

module App.AppState where

import Control.Lens

newtype AppState = AppState
  { _appStateProcessedMessages :: Int
  } deriving Show

appStateEmpty :: AppState
appStateEmpty = AppState
  { _appStateProcessedMessages = 0
  }

makeFields ''AppState
