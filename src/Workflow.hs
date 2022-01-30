{-# LANGUAGE ExistentialQuantification #-}

module Workflow(
        Step(..),
        Workflow,
        WorkflowState,
        step,
        runWorkflow,
        hydrateWorkflow
    ) where

import Store (Codec(..), EventStore(..), Event(..))
import Control.Comonad.Cofree (Cofree(..), coiter)
import Control.Monad.Free (Free(..), iterM, liftF)
import Control.Comonad (extract)
import Data.Foldable (foldl')
import Data.Aeson (Value)

data Step a = forall x. Codec x => Step { performStep :: IO x, nextA :: x -> a }

instance Functor Step where
  fmap f (Step s next) = Step s (f . next)

type Workflow = Free Step

type WorkflowState x = Cofree ((->) (Event Value)) (Workflow x)

step :: Codec a => IO a -> Workflow a
step s = liftF $ Step s id

runWorkflow :: EventStore es => es -> Workflow x -> IO x
runWorkflow es = iterM f
  where
    f :: Step (IO x) -> IO x
    f (Step g next) = do
      a <- g
      _ <- register es (StepCompleted a)
      next a

fromWorkflow :: Workflow x -> WorkflowState x
fromWorkflow = coiter f
  where
    f :: Workflow x -> Event Value -> Workflow x
    f (Free (Step _ next)) (StepCompleted p) = either (error "oops") next $ decode p
    f _ _ = error "incoherent state"

hydrateWorkflow :: Workflow x -> [Event Value] -> Workflow x
hydrateWorkflow w = extract . foldl' (\(_ :< f) -> f) (fromWorkflow w)
