{-# LANGUAGE ScopedTypeVariables #-}
module App.AWS.Sqs
( sendSqs
) where

import Control.Monad
import Control.Monad.Trans.Resource
import Data.Text
import Network.AWS                  (MonadAWS, send)
import Network.AWS.SQS

sendSqs :: (MonadResource m, MonadAWS m)
            => Text
            -> Text
            -> m ()
sendSqs sqsUrl msgBody = do
  void $ send $ sendMessage sqsUrl msgBody
  return ()
