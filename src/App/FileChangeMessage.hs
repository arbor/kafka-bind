{-# LANGUAGE TemplateHaskell #-}

module App.FileChangeMessage
where

import Data.Avro.Deriving

-- automagically creates data types and ToAvro/FromAvro instances
-- for a given schema.
deriveAvro "contract/file_change_message.avsc"
