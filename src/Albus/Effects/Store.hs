{-# LANGUAGE DeriveFunctor #-}

module Albus.Effects.Store(
    Event(..),
    Codec(..),
    MonadStore(..),
    jsonEncode,
    jsonDecode
    ) where

import Data.IORef (modifyIORef, readIORef, newIORef, IORef(..))
import Streaming
import qualified Streaming.Prelude as S
import Data.Aeson (Value, FromJSON, ToJSON, Result(..))
import qualified Data.Aeson as JSON

data Event a = StepCompleted a | StepFailed String deriving (Eq, Show, Functor)

--data Envelope a = Envelope { event :: Event a } deriving (Eq, Show, Functor)

class Codec a where
  encode :: a -> Value
  decode :: Value -> Either String a

jsonEncode :: ToJSON a => a -> Value
jsonEncode = JSON.toJSON

jsonDecode :: FromJSON a => Value -> Either String a
jsonDecode v = case JSON.fromJSON v of
    Error e -> Left e
    Success a -> Right a

class Monad m => MonadStore m where
  register  :: Codec a => Event a -> m ()
  getEvents :: Stream (Of (Event Value)) m ()
