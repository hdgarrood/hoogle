{-# LANGUAGE ViewPatterns, PatternGuards, TupleSections #-}

module Input.Cabal(parseCabal) where

import Data.List.Extra
import System.FilePath
import Control.Applicative
import Data.Maybe
import Data.Tuple.Extra
import qualified Data.Map as Map
import qualified Data.ByteString.Lazy.Char8 as LBS
import Util


-- items are stored as:
-- QuickCheck/2.7.5/QuickCheck.cabal
-- QuickCheck/2.7.6/QuickCheck.cabal
parseCabal :: (String -> Bool) -> IO (Map.Map String [String])
parseCabal want = do
    rename <- map (both trim . second (drop 1) . break (== '=')) . lines <$> readFile "misc/tag-rename.txt"
    foldl (f rename) Map.empty <$> tarballReadFiles "input/cabal.tar.gz"
    where
        -- rely on the fact the highest version is last, and lazy evaluation
        -- skips us from actually parsing the previous values
        f rename mp (name, body)
            | want pkg = Map.insert pkg (extractCabal rename $ LBS.unpack body) mp
            | otherwise = mp
            where pkg = takeBaseName name

extractCabal :: [(String, String)] -> String -> [String]
extractCabal rename src = f ["license"] ++ f ["category"] ++ f ["author","maintainer"]
    where
        f name = nub [ "@" ++ head name ++ " " ++ intercalate ", " [fromMaybe x $ lookup x rename | x <- xs]
                     | x <- lines src, let (a,b) = break (== ':') x, lower a `elem` name
                     , let xs = filter (/= "") $ map g $ concatMap (splitOn "and") $ split (`elem` ",&") $ drop 1 b
                     , not $ null xs]
        g = unwords . filter ('@' `notElem`) . words . takeWhile (`notElem` "<(")
