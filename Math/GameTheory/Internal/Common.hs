{-# LANGUAGE GADTs, StandaloneDeriving #-}

-- | Definitions for internal use.

module Math.GameTheory.Internal.Common (
    Pos(..)
  , yank
  ) where

import Data.Ix
import Data.List(elemIndex, intercalate)
import TypeLevel.NaturalNumber

data Pos a n where 
  Pos :: (NaturalNumber n) => [a] -> n -> Pos a n 
  
deriving instance (Eq a, Eq n) => Eq (Pos a n)
deriving instance (Ord a, Ord n) => Ord (Pos a n)

instance (Show a, NaturalNumber n) => Show (Pos a n) where
  show (Pos elms _) = intercalate " \\ " $ map show elms

instance (Ix a, NaturalNumber n, Ord n) => Ix (Pos a n) where
  range (Pos g1 n, Pos g2 _) = go n (zipWith (curry range) g1 g2)
    where go :: (NaturalNumber n) => n -> [[a]] -> [Pos a n]
          go n' [] = [Pos [] n']
          go n' (x : xs) = concatMap (\i -> map (\(Pos g n'') -> Pos (i : g) n'') (go n' xs)) x
  index (g1, g2) g3 = case elemIndex g3 (range (g1, g2)) of -- FIXME: inefficient
    (Just i) -> i
    Nothing -> 0
  inRange (Pos g1 _, Pos g2 _) (Pos g3 _) = (and (zipWith (<=) g1 g3)) && (and (zipWith (<=) g3 g2))
  
yank :: Int -> [a] -> (a, [a])
yank 0 (x:xs) = (x, xs)
yank n l =
    let (a, (b:c)) = splitAt n l
    in  (b, (a ++ c))