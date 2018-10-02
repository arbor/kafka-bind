{-# LANGUAGE ScopedTypeVariables #-}

module App.AWS.Sqs
  ( sendSqs
  , getSqsApproximateNumberOfMessages
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
            -> [Text]
            -> m ()
sendSqs sqsUrl msgBodies = do
  let idxs = T.pack . show <$> [1 :: Int ..]
  let entries = (\(r, i) -> sendMessageBatchRequestEntry i r) <$> zip msgBodies idxs
  void . send $ sendMessageBatch sqsUrl & smbEntries .~ entries

getSqsApproximateNumberOfMessages
  :: (MonadResource m, MonadAWS m)
  => Text
  -> m (Maybe Int)
getSqsApproximateNumberOfMessages sqsUrl = do
  resp <- send $ getQueueAttributes sqsUrl & gqaAttributeNames .~ [QANApproximateNumberOfMessages]

  return $ resp ^. gqarsAttributes . at QANApproximateNumberOfMessages <&> T.unpack >>= T.readMaybe
