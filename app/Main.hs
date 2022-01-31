{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveFunctor #-}

module Main where

import Data.Functor (($>))
import qualified Streaming.Prelude as S
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics hiding (C)
import Streaming
import qualified Streaming.Prelude as S
import Albus.Effects.Store (Codec(..), Event(..), MonadStore(..), jsonEncode, jsonDecode)
import Albus.Workflow (Workflow(..), step, hydrateWorkflow, runWorkflow)
import Control.Monad.Reader (ReaderT, MonadReader(..), runReaderT)
import Data.IORef (modifyIORef, readIORef, newIORef, IORef(..))
import Data.Aeson (Value)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Applicative


type AppEnv = IORef [Event Value]

newtype AppT m a = AppT { unAppT :: ReaderT AppEnv m a
                     } deriving (Functor, Applicative, Monad, MonadIO, MonadReader AppEnv)

instance MonadIO m => MonadStore (AppT m) where
  register e = do
    ref <- ask
    liftIO $ modifyIORef ref ((:) (fmap encode e))

  getEvents  = do
    ref <- ask
    effect $ fmap (S.each . reverse) (liftIO $ readIORef ref)

data A = A deriving (Show, Eq, Generic)

instance FromJSON A
instance ToJSON A
instance Codec A where
  encode = jsonEncode
  decode = jsonDecode

data B = B { fromA :: A } deriving (Show, Eq, Generic)

instance FromJSON B
instance ToJSON B
instance Codec B where
  encode = jsonEncode
  decode = jsonDecode

data C = C { fromB :: B } deriving (Show, Eq, Generic)
instance FromJSON C
instance ToJSON C
instance Codec C where
  encode = jsonEncode
  decode = jsonDecode

mkEnv :: IO AppEnv
mkEnv = newIORef []

example :: Workflow (AppT IO) (A, B, C)
example = do
  a <- step $ liftIO $ putStrLn "Step A" $> A
  b <- step $ liftIO $ putStrLn "Step B" $> B a
  c <- step $ liftIO $ putStrLn "Step C" $> C b
  return (a, b, c)

program :: AppT IO ()
program = do
  (a, b, c) <- runWorkflow example
  liftIO $ putStrLn $ "Result : " <> (show a) <> ", " <> (show b) <> ", " <> (show c)

  events    <- S.toList_ $ getEvents
  let recoveredWorflow = hydrateWorkflow example events

  -- recover previous workflow (nothing should happen : the workflow is already done)
  _         <- runWorkflow recoveredWorflow
  pure ()

main :: IO ()
main = runReaderT (unAppT program) =<< mkEnv


