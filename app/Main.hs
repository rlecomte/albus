{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}

module Main where

import Lib
import Control.Comonad.Cofree
import Control.Monad.Free
import Control.Comonad (extract)
import Data.Foldable (foldl')
import Data.IORef
import Streaming
import qualified Streaming.Prelude as S

---------------------------------------------------------------------------------------

class EventStore es where
  register  :: es -> Event -> IO ()
  getEvents :: es -> Stream (Of Event) IO ()

newtype InMemoryEventStore = InMemoryEventStore (IORef [Event])

instance EventStore InMemoryEventStore where
  register (InMemoryEventStore ref) e = modifyIORef ref ((:) e)
  getEvents (InMemoryEventStore ref) = effect $ (S.each . reverse) <$> readIORef ref

mkInMemoryStore :: IO InMemoryEventStore
mkInMemoryStore = InMemoryEventStore <$> newIORef []

---------------------------------------------------------------------------------------

data A = A deriving (Show, Eq)
data B = B { fromA :: A } deriving (Show, Eq)
data C = C { fromB :: B } deriving (Show, Eq)

---------------------------------------------------------------------------------------

data Step x = StepA { makeA :: IO A, nextA :: A -> x }
            | StepB { makeB :: IO B, nextB :: B -> x }
            | StepC { makeC :: IO C, nextC :: C -> x }
            deriving Functor

type Workflow = Free Step

stepA :: Workflow A
stepA = liftF $ StepA (putStrLn "Create A" *> pure A) id

stepB :: A -> Workflow B
stepB a = liftF $ StepB (putStrLn "Create B" *> pure (B a)) id

stepC :: B -> Workflow C
stepC b = liftF $ StepC (putStrLn "Create C" *> pure (C b)) id

runWorkflow :: EventStore es => es -> Workflow x -> IO x
runWorkflow es = iterM f
  where
    f :: Step (IO x) -> IO x
    f (StepA g next) = do
      a <- g
      _ <- register es (FeedA a)
      next a
    f (StepB g next) = do
      b <- g
      _ <- register es (FeedB b)
      next b
    f (StepC g next) = do
      c <- g
      _ <- register es (FeedC c)
      next c

---------------------------------------------------------------------------------------

data Event = FeedA A | FeedB B | FeedC C

type WorkflowState x = Cofree ((->) Event) (Workflow x)

fromWorkflow :: Workflow x -> WorkflowState x
fromWorkflow = coiter f
  where
    f :: Workflow x -> Event -> Workflow x
    f (Free (StepA _ next)) (FeedA a) = next a
    f (Free (StepB _ next)) (FeedB b) = next b
    f (Free (StepC _ next)) (FeedC c) = next c
    f _ _ = error "incoherent state"

hydrateWorkflow :: Workflow x -> [Event] -> Workflow x
hydrateWorkflow w = extract . foldl' (\(_ :< f) -> f) (fromWorkflow w)

---------------------------------------------------------------------------------------

example :: Workflow (A, B, C)
example = do
  a <- stepA
  b <- stepB a
  c <- stepC b
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


