{-# LANGUAGE DeriveFunctor #-}

module Store(
    Event(..),
    Codec(..),
    EventStore(..),
    InMemoryEventStore(..),
    jsonEncode,
    jsonDecode,
    mkInMemoryStore
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

class EventStore es where
  register  :: Codec a => es -> Event a -> IO ()
  getEvents :: es -> Stream (Of (Event Value)) IO ()

newtype InMemoryEventStore = InMemoryEventStore (IORef [Event Value])

instance EventStore InMemoryEventStore where
  register (InMemoryEventStore ref) e = modifyIORef ref ((:) (fmap encode e))
  getEvents (InMemoryEventStore ref) = effect $ (S.each . reverse) <$> readIORef ref

mkInMemoryStore :: IO InMemoryEventStore
mkInMemoryStore = InMemoryEventStore <$> newIORef []
