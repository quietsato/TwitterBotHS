module Data.Block (Block, createBlock, getW1, getW2, getW3, getWords, getBId) where

import qualified Data.Text as T
import           Lib
import           Prelude   hiding (id, words)

data Block = MkBlock { words :: (String, String, String), id :: Integer }
  deriving Show

instance Eq Block where
  (MkBlock (a, b, c) _) == (MkBlock (a', b', c') _) =
    a == a' && b == b' && c == c'

createBlock = MkBlock

getW1 = get1 . words

getW2 = get2 . words

getW3 = get3 . words

getWords = words

getBId = id
