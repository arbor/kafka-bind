{-# LANGUAGE ScopedTypeVariables #-}

module App.AWS.Sqs
  ( sendSqs
  , getSqsQueueAttributes
  ) where

import Control.Lens
import Control.Monad
import Control.Monad.Trans.Resource
import Data.Text                    (Text)
import Network.AWS                  (MonadAWS, send)
import Network.AWS.SQS

import qualified Data.Text as T
import qualified Text.Read as T

sendSqs :: (MonadResource m, MonadAWS m)
            => Text
            -> Text
            -> m ()
sendSqs sqsUrl msgBody = do
  void $ send $ sendMessage sqsUrl msgBody
  return ()

getSqsQueueAttributes
  :: (MonadResource m, MonadAWS m)
  => Text
  -> m (Maybe Int)
getSqsQueueAttributes sqsUrl = do
  resp <- send $ getQueueAttributes sqsUrl & gqaAttributeNames .~ [QANApproximateNumberOfMessages]

  return $ resp ^. gqarsAttributes . at QANApproximateNumberOfMessages <&> T.unpack >>= T.readMaybe
