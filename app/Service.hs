module Service
  ( handleStream
  )
where

import           Conduit
import           Control.Arrow         (left)
import           Control.Lens
import           Control.Monad
import           Control.Monad.Except
import           Data.Aeson            as J
import           Data.Avro
import qualified Data.Avro             as A
import qualified Data.Avro.Decode      as A
import qualified Data.Avro.Schema      as A
import qualified Data.Avro.Types       as A
import           Data.ByteString       (ByteString)
import           Data.ByteString.Char8 as C8
import           Data.ByteString.Lazy  (fromStrict, toStrict)
import           Data.Text             as T
import           Kafka.Avro
import           Kafka.Conduit.Source

import qualified Data.Conduit.List as L

import App
import App.AWS.Sqs
import App.Options

-- | Handles the stream of incoming messages.
-- Emit values downstream because offsets are committed based on their present.
handleStream :: MonadApp m
             => Options
             -> SchemaRegistry
             -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream opt sr =
  mapC crValue                 -- extracting only value from consumer record
  .| L.catMaybes               -- discard empty values
  .| mapMC (decodeMessage sr)  -- decode avro message.
  .| mapC failBadly            -- error on decode failure
  .| mapMC (sendSqs (T.pack (opt ^. outputSqsUrl)) . T.pack . C8.unpack . toStrict . J.encode)

asExceptT :: Monad m => (e -> e') -> m (Either e a) -> ExceptT e' m a
asExceptT f me = ExceptT $ left f <$> me

asExceptTPure :: Monad m => (e -> e') -> Either e a -> ExceptT e' m a
asExceptTPure f e = ExceptT. pure $ left f e

maybeToEither :: e -> Maybe a -> Either e a
maybeToEither e = maybe (Left e) Right

failBadly :: Show e => Either e a -> a
failBadly (Left e)  = error (show e)
failBadly (Right a) = a

decodeMessage :: MonadIO m => SchemaRegistry -> ByteString -> m (Either DecodeError (A.Value A.Type))
decodeMessage sr bs = runExceptT $ do
  (sid, payload) <- asExceptTPure id . maybeToEither BadPayloadNoSchemaId $ extractSchemaId $ fromStrict bs
  sch            <- asExceptT DecodeRegistryError (loadSchema sr sid)
  asExceptT (DecodeError sch) (pure $ A.decodeAvro sch payload)

