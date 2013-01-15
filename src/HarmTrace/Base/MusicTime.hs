{-# LANGUAGE TypeSynonymInstances             #-}
{-# LANGUAGE FlexibleInstances                #-}
{-# LANGUAGE DeriveFunctor                    #-}

--------------------------------------------------------------------------------
-- |
-- Module      :  HarmTrace.Base.MusicTime
-- Copyright   :  (c) 2010-2012 Universiteit Utrecht, 2012 University of Oxford
-- License     :  GPL3
--
-- Maintainer  :  bash@cs.uu.nl, jpm@cs.ox.ac.uk
-- Stability   :  experimental
-- Portability :  non-portable
--
-- Summary: A set of types and classes for representing musical time, mainly
-- (but not necessarily) in the context of recognising chords 
-- from an arbitrary audio source.
--------------------------------------------------------------------------------

module HarmTrace.Base.MusicTime (
  
  -- * Datatypes
  -- ** Types for representing Chords and their probabilities
    ChordAnnotation 
  , ProbChordSeg (..)
  , ProbChord (..)
  , ChordCand (..)
  
  -- ** Representing musical time
  , TimedData (..)
  , Beat (..)
  , BarTime (..)
  , BarTimeTrackData 
  , NumData 
  
  -- ** Representing raw audio data 
  , AudioFeat (..)
  , ChordinoData 
  , ChordinoLine (..)
  , KeyStrengthData 
  , BeatTrackerData 
  , BeatChroma 
  , ChordStruct 

  -- * Functions
  -- ** Data access
  , timedData
  , timedDataBT
  , getBarTime 
  , getBeat 
  , onset
  , offset
  , setData
  -- ** Type conversion and other utilities
  , getBeatTrack
  , concatTimedData
  , nextBeat
  , prevBeat 
  , updateTPChord
  , dropProb
  , dropTimed
  , timeStamp
  , beat 

) where
             
import HarmTrace.Base.MusicRep


-- | When reducing and expaninding 'TimedData' types there might be rounding
-- errors in the floating point time stamps. The 'roundingError' parameter
-- sets the acceptable rounding error that is used in the comparison of 
-- time stamps (e.g. see 'timeComp')
roundingError :: NumData 
roundingError = 0.0001 -- = one milisecond  

-- | A type synonym is defined for our main numerical representation, this 
-- allows us to easily change the precision.
type NumData = Double

--------------------------------------------------------------------------------
-- High-level structure
--------------------------------------------------------------------------------

-- | A chord annotation consists of a
-- list with chords and segment boundaries.
type ChordAnnotation = [TimedData ProbChord]

-- | A datatype that wraps around an arbitrary datatype, adding (in this order)
-- a 'Beat', an onset, and an offset.
data TimedData a = TimedData { -- | Returns the contained datatype 
                               getData :: a 
                               -- | Returns the list of TimeStamps
                             , getTimeStamps :: [BarTime]
                             } deriving (Functor, Show, Eq)

-- | Clustering 'ProbChord's in a collection of chords that share a key
data ProbChordSeg = Segment { segKey    :: Key 
                            , segChords :: [TimedData [ProbChord]] 
                            } deriving (Show, Eq)
                            
  
-- | Combines a 'ChordLabel' with a probability.
data ProbChord = ProbChord { chordLab :: ChordLabel
                           , prob :: NumData
                           }

-- | A chord candidate: an intermediate datatype that matches shorthand, 
-- chord structure and root note (plus inversion)
data ChordCand = ChordCand { originalRootCC   :: Root
                           , inversionRootCC  :: Root
                           , shorthardCC      :: Shorthand
                           , chordStructCC    :: ChordStruct 
                           } deriving (Show, Eq)

-- | A chord template is list of 'NumData's
type ChordStruct = [NumData] 

-- | For now, we fix the number of available beats to four, because this is also
-- hard-coded into the bar and beat-tracker.
data Beat = One | Two | Three | Four | NoBeat deriving (Eq, Enum)

--------------------------------------------------------------------------------
-- Instances of high-level data structure
--------------------------------------------------------------------------------

-- TODO to be replaced by a deriving instance
instance Eq (ProbChord) where
  a == b = chordLab a == chordLab b
  
instance Show (ProbChord) where
  show (ProbChord c _p) = show c -- ++ ':' : printf "%.2f" p
  
instance Show Beat where
  show One   = "1"
  show Two   = "2"
  show Three = "3"
  show Four  = "4"
  show NoBeat = "x"

instance Show BarTime where
  show (BarTime t bt) = '(' : show t ++ ", " ++ show bt ++ ")"
  show (Time t)       = '(' : show t ++ ")"

    
--------------------------------------------------------------------------------
-- numerical data representation
--------------------------------------------------------------------------------

-- | Groups the three types of VAMP plug-in data: 'ChordinoData', 
-- 'BarTimeTrackData', and 'KeyStrengthData'. See for more information:
--
-- * <http://www.vamp-plugins.org>
--
-- * <http://isophonics.net/nnls-chroma>
--
-- * <http://omras2.org/SonicAnnotator>
data AudioFeat = AudioFeat { getChroma      :: ChordinoData 
                           , getBeats       :: BarTimeTrackData
                           , getKeys        :: KeyStrengthData 
                           , getAudioFeatId :: FilePath}

type ChordinoData = [ChordinoLine]  

-- | Represents two chroma features and a time stamp. 
data ChordinoLine = ChordinoLine -- TODO remove useless type synonym
  { 
  -- | Returns the time stamp of the chroma features
    time ::  NumData 
  -- | Returns the bass chroma feature
  , bass :: [NumData]   -- each of the lists has always 12 elements 
  -- | Returns the treble chroma feature
  , treb :: [NumData]   -- A, Bb, B, C, Db, D, Eb, E, F, F#, G, Ab 
  } deriving (Eq, Show) -- and is shifted 3 positions to match C, Db, .., B
  
type KeyStrengthData = ChordinoData  

type BeatTrackerData = [NumData]

-- TODO Rename to BeatTime
-- | Combines a 'Beat' and a timestamp
data BarTime = BarTime NumData Beat
             | Time    NumData      deriving Eq

type BarTimeTrackData = [BarTime]

type BeatChroma = TimedData [ChordinoLine] -- one list per beat

-- we compare based on the timestamp only
instance Ord BarTime where
  compare a b = compare (timeStamp a) (timeStamp b)

--------------------------------------------------------------------------------
-- Some type conversion utilities
--------------------------------------------------------------------------------

-- | alternative 'TimedData' constructor
timedData :: a -> NumData -> NumData -> TimedData a
timedData d x y = TimedData d [Time x, Time y]

-- | alternative 'TimedData' constructor
timedDataBT :: a -> BarTime -> BarTime -> TimedData a
timedDataBT d x y = TimedData d [x, y]

-- | concatenates the 'BarTime' timestamps of two 'TimedData's and 
-- creates a new 'TimedData' that stores the first argument. 
concatTimedData :: a -> TimedData a -> TimedData a -> TimedData a
concatTimedData dat (TimedData _ ta) (TimedData _ tb) = 
  TimedData dat (mergeBeatTime ta tb) where

  mergeBeatTime :: [BarTime] -> [BarTime] -> [BarTime]
  mergeBeatTime [] b = b
  mergeBeatTime a [] = a
  mergeBeatTime a b = case timeComp (timeStamp . last $ a) 
                                    (timeStamp . head $ b) of
    GT -> error ("HarmTrace.Base.MusicTime.mergeBeatTime: " ++
                 "cannot merge BeatTimes "  ++ show a ++ " and " ++ show b)
    EQ -> a ++ tail b -- do not include the same timestamp twice
    LT -> a ++ b  
 
-- | compares to 'NumData' timestamps taking a rounding error 'roundingError'
-- into account.
timeComp :: NumData -> NumData -> Ordering
timeComp a b 
 | a > (b + roundingError) = GT
 | a < (b - roundingError) = LT
 | otherwise               = EQ

-- | Converts  'BarTimeTrackData' into 'BeatTrackerData'
getBeatTrack :: BarTimeTrackData -> BeatTrackerData
getBeatTrack = map timeStamp

-- | wraps a datatype in 'TimedData'
setData :: TimedData a -> b -> TimedData b
setData td d = td {getData = d}

-- | Returns the start time stamp
getBarTime :: TimedData a -> BarTime
getBarTime td = case getTimeStamps td of
  []    -> error "HarmTrace.Base.MusicTime.getBarTime: no timestamps are stored"
  (h:_) -> h

-- | Returns the start 'Beat'
getBeat :: TimedData a -> Beat
getBeat = beat . getBarTime 

-- | Returns the 'NumData' timestamp, given a 'BarTime'
timeStamp :: BarTime -> NumData
timeStamp (BarTime t _bt) = t
timeStamp (Time    t    ) = t  

-- | Returns the 'NumData' timestamp, given a 'BarTime'
beat :: BarTime -> Beat
beat (BarTime _t bt) = bt
beat (Time    _t   ) = NoBeat

-- | Returns the onset time stamp
onset :: TimedData a -> NumData
onset = timeStamp . getBarTime 

-- | Returns the offset time stamp
offset :: TimedData a -> NumData
offset td = case getTimeStamps td of
  []  -> error "HarmTrace.Base.MusicTime.offset: no timestamps are stored"
  l   -> timeStamp . last $ l

-- TODO: replace by ad-hoc enum instance?
-- | returns the next beat, e.g. @ nextBeat Two = Three @. 
-- Following the (current) definition of 'Beat', we still assume 4/4, in the 
-- future this function should also have the meter as an argument.
nextBeat, prevBeat :: Beat -> Beat 
nextBeat Four = One
nextBeat b    = succ b

-- | returns the previous 'Beat', similar to 'prevBeat'.
prevBeat One  = Four
prevBeat b    = pred b

-- | Updates transforms ChordLabel wrapped in a 'ProbChord' and 'TimedData'
updateTPChord :: (ChordLabel -> ChordLabel) -> TimedData ProbChord 
              -> TimedData ProbChord
updateTPChord f = fmap (update f) where
  update g (ProbChord c p) = (ProbChord (g c) p)

-- | drops the probabilties paired with chordlabels (in a list of 'ProbChord's)
-- and returns a list of 'ChordLabel's
dropProb :: [TimedData ProbChord] -> [TimedData ChordLabel]
dropProb = map (fmap chordLab)

-- | drops the time (with or without 'Beat') information of a list 
-- 'Timed' data structure 
dropTimed :: [TimedData a] -> [a]
dropTimed = map getData
