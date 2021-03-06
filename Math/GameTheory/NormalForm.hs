-- | Representation and algorithms for normal form / strategic form games

-- TODO: don't export the constructor for games! force people to use the <\> construct

module Math.GameTheory.NormalForm (
  -- * Definitions
    module Math.GameTheory.Common
  , Game,Player(),Action,Strategy
  , dims -- FIXME: maybe don't export?
  , utility,playerUtility
  , expectedUtility
  -- * Constructing games
  , mkGame2
  , mkGame3
  -- * Algorithms
  -- ** Maximin
  , maxiMin
  -- ** Dominance
  , dominated
  , iteratedDominance
  -- ** Stackelberg games  
  -- $stackelberg
  , stackelbergMixedCommitment
  -- ** Nash Equilibrium
  , pureNash
  , mixedNash
  )
  where

import Math.GameTheory.Internal.NormalForm
import Math.GameTheory.Common
import TypeLevel.NaturalNumber
import Data.Array
import Numeric.LinearProgramming
import Data.List((\\))

---------------------- Definitions ----------------------

-- | A player. Should not be 0, and not exceed the number of players in a game where it is used.
type Player = Int

-- | A specific action for some player
type Action = Int

-- | A mixed strategy. Values in the strategy should sum up to 1, and have length equal to the number of actions in the game for the corresponding player
type Strategy = [Double]

-- type Outcome = Pos Int n

-- | Dimensions (size) of a game.
dims :: (NaturalNumber n, Ord n) => Game n -> Pos Int n
dims (Game arr) = snd $ bounds arr

-- | The utility for all players for a specific position in the game
utility :: (NaturalNumber n, Ord n) => Game n -> Pos Action n -> Pos Double n
utility (Game arr) pos = arr ! pos

-- | Extract the utility for a specific player from the utilities for all player at a position
playerUtility :: (NaturalNumber n) => Pos Double n -> Player -> Double
playerUtility (Pos l _) p = l !! (p - 1)

-- a default position. for use with replaceAt
-- defaultPos :: (NaturalNumber n, Ord n) => Game n -> (Pos Int n)
-- defaultPos game = dims game

replacePos ::  (NaturalNumber n) => (Pos Int n) -> Player -> Int -> (Pos Int n)
replacePos (Pos l n) player v = Pos (replaceAt v l (player - 1)) n

replaceAt :: a -> [a] -> Int -> [a]
replaceAt _ [] _ = []
replaceAt y (_:xs) 0 = y:xs
replaceAt y (x:xs) i = x : (replaceAt y xs (i - 1))

-- | Expected utility of some player for a strategy profile of all players
expectedUtility :: (NaturalNumber n, Ord n) => Game n -> Player -> Pos Strategy n -> Double
expectedUtility g player (Pos strategies _) = sum weightedUtilities
  where (Pos dimensions n) = dims g
        actions :: [[Action]]
        actions = map (\x -> [1..x]) dimensions
        outcomes :: [[Action]]
        outcomes = crossProduct actions
        utilities = map (\outcome -> playerUtility (utility g (Pos outcome n)) player) outcomes
        weightedUtilities = zipWith weightUtility outcomes utilities
        weightUtility outcome util = util * (product (zipWith (\strategy i -> strategy !! (i - 1)) strategies outcome))
        
---------------------- Constructing Games ----------------------
        
-- | Easily build a two-player game by giving a two-dimensional list
mkGame2 :: [[Pos Double N2]] -> Game N2
mkGame2 payoffs =
  Game (listArray (Pos [1,1] n2,Pos [dimRow, dimCol] n2) (concat payoffs))
    where dimRow = (length payoffs)
          dimCol = length $ head payoffs

-- | Easily build a three-player game with a three-dimensional list
mkGame3 :: [[[Pos Double N3]]] -> Game N3
mkGame3 payoffs =
  Game $ listArray (Pos [1,1,1] n3, Pos [dimRow, dimCol, dimMat] n3) (concatMap concat payoffs)
    where dimRow = length $ head payoffs
          dimCol = length $ head $ head payoffs
          dimMat = length $ payoffs
          
-- TODO: n-player game
-- mkGame :: (NaturalNumber n) => n -> [] -> Game n
          
          
          
---------------------- Algorithms ----------------------

-- | Computes a maximin strategy for a player and returns it together with the security level that can be achieved with it.
maxiMin :: (NaturalNumber n, Ord n) => Game (SuccessorTo n) -> Player -> (Double, Strategy)
maxiMin game player = (secLevel, probabilities)
  where (secLevel, probs') = case (simplex problem constraints []) of
          Optimal r -> r
          _ -> undefined
        probabilities = tail probs'
        problem     = Maximize (1 : (take ownD zeros))
        constraints = Dense $
                      ((0 : (take ownD (repeat 1))) :==: 1) : -- all probabilities add up to 1
                      (map (nonzero ownD) [1..ownD]) ++  -- all probabilities are greater than 0
                      (map constraint otherDs) -- [-1, ...] :=>: 0 for each row/column
        nonzero d i = ((take i zeros) ++ (1 : (take (d - i) zeros))) :=>: 0
        (ownD,otherDs',n) = case dims game of
          (Pos ds n') -> case yank (player - 1) ds of (a,b) -> (a,b,n')
          
        constraint pos' = ((-1) : map (\ownIdx -> playerUtility 
                                                 (utility game (insertPos pos' player ownIdx)) player)
                           [1..ownD])
                          :=>: 0
        otherDs = map (\d -> Pos d (predecessorOf n)) $ go $ map (\i -> [1..i]) otherDs'
        go [] = [[]]
        go (x:xs) = concatMap (\y -> map (\z -> z : y) x) (go xs)                                                 
        zeros     = repeat 0
        
----------- Dominance -----------                        
-- | Checks if an action of a player is dominated in the game
dominated :: (NaturalNumber n, Ord n) => Game (SuccessorTo n) -> Player -> Action -> Bool
dominated game player action = val < 1
  where (val, _) = case simplex problem constraints [] of
          Optimal r -> r
          _ -> undefined
          
        -- variables in the LP are s_i(b_i), and their sum should be minimized
        -- i.e minimize over all possible values for strategies
        -- one strategy for each action
        problem = Minimize (ones ownD)
        ones i | i <= 0 = []
        ones i = 1 : (ones (i - 1))
        
        constraints = Dense $
                      (map (nonzero ownD) [1..ownD]) ++ -- s_i(b_i) >= 0 forall b_i
                      (map constraint otherDs)
                      
        nonzero d i = ((take (i - 1) zeros) ++ (1 : (take (d - i) zeros))) :=>: 0
        zeros       = repeat 0              
        
        -- for each a_{-i} \in A_{-i}: 
        --     \sum_{b_i \in A_i} s_i(b_i) * u_i(b_i,a_{-i})    >=   u_i(a_i,a_-i)
        -- s_i(b_i) is implicit, see the constraints for s_i(b_i) >= 0
        constraint otherActions = (map (\b_i -> playerUtility (utility game (otherPos b_i)) player) ownActions) 
                                   :=>: (playerUtility (utility game pos) player) -- u_i(a_i, a_{-i})
          where
            pos = insertPos otherActions player action -- a_i,a_{-i}
            otherPos b_i = insertPos otherActions player b_i
            ownActions = [1..ownD]
            
        -- FIXME: the following lines were just copy-pasted. explain them.
        go [] = [[]]
        go (x:xs) = concatMap (\y -> map (\z -> z : y) x) (go xs)  
        otherDs           = map (\d -> Pos d (predecessorOf n)) $ go $ map (\i -> [1..i]) otherDs'
        (ownD,otherDs',n) = case dims game of
          (Pos ds n') -> case yank (player - 1) ds of (a,b) -> (a,b,n')
                                                     
outcomeDominated :: (NaturalNumber n, Ord n) => Game n -> Pos Int n -> Bool
outcomeDominated g outcome = any outcomeDominated' players
  where 
    (dimensions, players) = case dims g of (Pos ds n) -> (ds, [1..(naturalNumberAsInt n)])
    outcomeDominated' player = any (\pos -> (playerUtility (utility g pos) player) > outcomeUtil) allOutcomes
          where outcomeUtil = playerUtility (utility g outcome) player
                ownD = dimensions !! (player - 1)
                allOutcomes = map (\i -> replacePos outcome player i) [1..ownD]
                                                     
-- | Eliminate a given action for a given player for the game
-- action should be a possible action, ideally statically.
eliminate :: (NaturalNumber n, Ord n) => Game n -> (Player, Action) -> Game n
eliminate (Game arr) (player, action) = 
  Game (listArray (lowerBound,upperBound') (map (arr !) filteredIndices))
  where
    filteredIndices = filter (\(Pos i _) -> (i !! (player - 1)) /= action) (indices arr)
    (lowerBound,Pos upperBound n) = bounds arr
    (restBounds',playerBound:restBounds'') = splitAt (player - 1) upperBound
    upperBound' = Pos (restBounds' ++ ((playerBound - 1) : restBounds'')) n
          
-- TODO: change the game type so that it makes sense to return the game with the dominated actions eliminated as well
-- | Iterated strict dominance. Returns for each player the list of dominated actions
iteratedDominance :: (NaturalNumber n, Ord n) => Game (SuccessorTo n) -> Pos [Action] (SuccessorTo n)
iteratedDominance origGame = iteratedDominance' origGame
  where
    iteratedDominance' game = if all (null . snd) dominatedActions 
                              then Pos (map snd dominatedActions) n 
                              else Pos dominatedActions'' n
      where
        (dimensions,n) = case dims game of (Pos ds n') -> (ds,n')
        actions = map (\d -> [1..d]) dimensions
        dominatedActions = map (\(i,actions') -> (i,filter (dominated game i) actions')) $ -- FIXME: Infinite loop here
                           zip [1..] actions
        gameEliminatedActions = foldl 
                                (\g (i,actions') -> elimActions g i actions') 
                                game dominatedActions
        elimActions g i actions' = foldl (\g' action -> eliminate g' (i, action)) g actions'
        Pos dominatedActions' _ = iteratedDominance' gameEliminatedActions
        dominatedActions'' = zipWith 
                             (\dAs dAs' -> dAs ++ (shift dAs dAs')) 
                             (map snd dominatedActions) dominatedActions'
        shift dAs dAs' = map (\i -> i + (length (filter (<= i) dAs))) dAs'
        
-- TODO: iteratedWeakDominance, with note that efficiency is not guaranteed
        
----------- Stackelberg games -----------

-- $stackelberg
-- In Stackelberg games, one player (the leader) may commit to a strategy before the game, and the other player (the follower) plays its action based on that information

-- | Compute the optimal strategy and expected utility for the leader in a Stackelberg Game
stackelbergMixedCommitment :: Game N2 -> Player -> (Double, Strategy)
stackelbergMixedCommitment game leader = 
  foldr 
  (\a_2 (u,s) -> case optim a_2 of
      Just (u',s') | u' > u -> (u',s')
      _ -> (u,s))
  (- (1/0.0),take otherD (repeat 1)) 
  otherActions
  where 
    (ownActions,otherActions) = ([1..ownD],[1..otherD])
    (ownD,otherD,follower) = case (leader,dims game) of
      (1, Pos [d1,d2] _) -> (d1,d2, 2)
      (2, Pos [d1,d2] _) -> (d2,d1, 1)
      _ -> error "Invalid player in two-person game."
    
    optim a_2 = case simplex (problem a_2) (constraints a_2) varBounds of
      Optimal r -> Just r
      _         -> Nothing
      
    varBounds = map (\i -> i :=>: 0) [1..ownD]
    problem a_2 = Maximize $ map (\a_1 -> leaderUtil $ utility game (mkPos a_1 a_2)) ownActions
    mkPos a_1 a_2 = case leader of 
      1 -> Pos [a_1,a_2] n2
      2 -> Pos [a_2,a_2] n2
      _ -> error "Invalid player in two-person game."
    constraints a_2 = Dense $
                      ((map (\_ -> 1) ownActions) :==: 1) : 
                      (map (constraint a_2) otherActions)
                      
    constraint a_2 a_2' = (map (\a_1 -> (followerUtil $ utility game (mkPos a_1 a_2)) -  
                                       (followerUtil $ utility game (mkPos a_1 a_2')))
                           ownActions)
                          :=>: 0
    
    leaderUtil utils = playerUtility utils leader
    followerUtil utils = playerUtility utils follower
    
    
    
----------- Nash Equilibrium -----------


-- | Find all pure strategy Nash equilibria
pureNash :: (NaturalNumber n, Ord n) => Game (SuccessorTo n) -> [Pos Action (SuccessorTo n)]
pureNash g = equilibriumOutcomes
  where (Pos dimensions n) = dims g
        actions = map (\x -> [1..x]) dimensions
        -- outcomes = map (\x -> Pos x n) (crossProduct actions)
        (Pos dominatedActions _) = iteratedDominance g
        
        -- actions that are not dominated. 
        -- outcomes, however, might still be dominated, i.e someone has incentive to unilaterally deviate!
        undominated = zipWith (\as ds -> as \\ ds) actions dominatedActions 
        outcomes = map (flip Pos n) (crossProduct undominated)
        
        equilibriumOutcomes = filter (not . (outcomeDominated g)) outcomes
        
        
        
{-
For each player, look at all possible outcomes for that player when the actions of other players are fixed and remove those that are strictly less than the maximum.
The Nash equilibria are the remaining outcomes.
-}

crossProduct :: [[a]] -> [[a]]
crossProduct [] = [[]]
crossProduct (x:xs) = concatMap (\y -> map (: y) x) (crossProduct xs)


-- http://oyc.yale.edu/sites/default/files/mixed_strategies_handout_0.pdf

-- based on support enumeration. 
-- parallel algorithm for n player game: http://www.cs.wayne.edu/~dgrosu/pub/cse09.pdf
-- also need to handle degenerate games?
-- check and handle special cases for zero sum games (NEs are computable faster)

-- | Find all mixed-strategy nash equilibria
mixedNash :: (NaturalNumber n, Ord n) => Game n -> Pos Strategy n
mixedNash _ = undefined
