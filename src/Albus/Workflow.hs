{-# LANGUAGE ExistentialQuantification #-}

module Albus.Workflow(
        Step(..),
        Workflow,
        WorkflowState,
        step,
        runWorkflow,
        hydrateWorkflow
    ) where

import Albus.Effects.Store (Codec(..), MonadStore(..), Event(..))
import Control.Comonad.Cofree (Cofree(..), coiter)
import Control.Monad.Free (Free(..), iterM, liftF)
import Control.Comonad (extract)
import Control.Monad (Monad)
import Data.Foldable (foldl')
import Data.Aeson (Value)

data Step m a = forall x. Codec x => Step { performStep :: m x, nextA :: x -> a }

instance Functor (Step m) where
  fmap f (Step s next) = Step s (f . next)

type Workflow m = Free (Step m)

type WorkflowState m a = Cofree ((->) (Event Value)) (Workflow m a)

step :: Codec a => m a -> Workflow m a
step s = liftF $ Step s id

runWorkflow :: MonadStore m => Workflow m a -> m a
runWorkflow = iterM f
  where
    f :: MonadStore m => Step m (m x) -> m x
    f (Step g next) = do
      a <- g
      _ <- register (StepCompleted a)
      next a

fromWorkflow :: Workflow m a -> WorkflowState m a
fromWorkflow = coiter f
  where
    f :: Workflow m a -> Event Value -> Workflow m a
    f (Free (Step _ next)) (StepCompleted p) = either (error "oops") next $ decode p
    f _ _ = error "incoherent state"

hydrateWorkflow :: Workflow m a -> [Event Value] -> Workflow m a
hydrateWorkflow w = extract . foldl' (\(_ :< f) -> f) (fromWorkflow w)
