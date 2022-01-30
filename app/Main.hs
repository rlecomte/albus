{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ExistentialQuantification #-}

module Main where

import Data.Functor (($>))
import qualified Streaming.Prelude as S
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics hiding (C)
import Store (Codec(..), Event(..), EventStore(..), jsonEncode, jsonDecode, mkInMemoryStore)
import Workflow (Workflow(..), step, hydrateWorkflow, runWorkflow)

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

example :: Workflow (A, B, C)
example = do
  a <- step $ putStrLn "Step A" $> A
  b <- step $ putStrLn "Step B" $> B a
  c <- step $ putStrLn "Step C" $> C b
  return (a, b, c)

main :: IO ()
main = do
  store     <- mkInMemoryStore
  (a, b, c) <- runWorkflow store example
  putStrLn $ "Result : " <> (show a) <> ", " <> (show b) <> ", " <> (show c)

  events    <- S.toList_ $ getEvents store
  let recoveredWorflow = hydrateWorkflow example events

  -- recover previous workflow (nothing should happen : the workflow is already done)
  _         <- runWorkflow store recoveredWorflow
  pure ()


