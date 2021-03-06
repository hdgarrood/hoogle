{-# LANGUAGE ViewPatterns, TupleSections, RecordWildCards, ScopedTypeVariables, PatternGuards #-}

module Action.Generate(actionGenerate) where

import Control.Applicative
import Data.List.Extra
import System.FilePath
import System.Directory.Extra
import System.Time.Extra
import Data.Tuple.Extra
import qualified Data.ByteString.Lazy.UTF8 as UTF8
import Control.Exception.Extra
import qualified Data.Set as Set
import qualified Data.Map as Map
import Debug.Trace
import Control.Monad.Extra
import Prelude

import Output.Items
import Output.Tags
import Output.Names
import Output.Types
import Input.Cabal
import Input.Hoogle
import Input.Download
import Input.Reorder
import Input.Set
import General.Util
import General.Store
import System.Mem
import GHC.Stats
import Action.CmdLine

{-


data GenList
    = GenList_Package String -- a literally named package
    | GenList_GhcPkg String -- command to run, or "" for @ghc-pkg list@
    | GenList_Stackage String -- URL of stackage file, defaults to @http://www.stackage.org/lts/cabal.config@
    | GenList_Dependencies String -- dependencies in a named .cabal file
    | GenList_Sort String -- URL of file to sort by, defaults to @http://packdeps.haskellers.com/reverse@

data GenTags
    = GenTags_GhcPkg String -- command to run, or "" for @ghc-pkg dump@
    | GenTags_Diff FilePath -- a diff to apply to previous metadata
    | GenTags_Tarball String -- tarball of Cabal files, defaults to http://hackage.haskell.org/packages/index.tar.gz
    | GetTags_Cabal FilePath -- tarball to get tag information from

data GenData
    = GenData_File FilePath -- a file containing package data
    | GenData_Tarball String -- URL where a tarball of data files resides


* `hoogle generate` - generate for all things in Stackage based on Hackage information.
* `hoogle generate --source=file1.txt --source=local --source=stackage --source=hackage --source=tarball.tar.gz`

Which files you want to index. Currently the list on stackage, could be those locally installed, those in a .cabal file etc. A `--list` flag, defaults to `stackage=url`. Can also be `ghc-pkg`, `ghc-pkg=user` `ghc-pkg=global`. `name=p1`.

Extra metadata you want to apply. Could be a file. `+shake author:Neil-Mitchell`, `-shake author:Neil-Mitchel`. Can be sucked out of .cabal files. A `--tags` flag, defaults to `tarball=url` and `diff=renamings.txt`.

Where the haddock files are. Defaults to `tarball=hackage-url`. Can also be `file=p1.txt`. Use `--data` flag.

Defaults to: `hoogle generate --list=ghc-pkg --list=constrain=stackage-url`.

Three pieces of data:

* Which packages to index, in order.
* Metadata.


generate :: Maybe Int -> [GenList] -> [GenTags] -> [GenData] -> IO ()
-- how often to redownload, where to put the files



generate :: FilePath -> [(String, [(String, String)])] -> [(String, LBS.ByteString)] -> IO ()
generate output metadata  = undefined
-}


-- -- generate all
-- @tagsoup -- generate tagsoup
-- @tagsoup filter -- search the tagsoup package
-- filter -- search all

actionGenerate :: CmdLine -> IO ()
actionGenerate Generate{..} = do
    downloadInputs
    (n,_) <- duration $ generate include
    putStrLn $ "Took " ++ showDuration n


generate :: [String] -> IO ()
generate xs = do
    setStackage <- setStackage
    setPlatform <- setPlatform
    setGHC <- setGHC
    createDirectoryIfMissing True "output"
    let want = Set.fromList $ if null xs then setStackage ++ setPlatform ++ setGHC else xs

    cbl <- parseCabal (`Set.member` want)
    let extra pkg = [("set","included-with-ghc") | pkg `elem` setGHC] ++
                    [("set","haskell-platform") | pkg `elem` setPlatform] ++
                    [("set","stackage")] ++
                    Map.findWithDefault [] pkg cbl

    let f seen (takeBaseName -> pkg, body)
            | pkg `Set.member` want
            = (Set.insert pkg seen,
                trace ("[" ++ show (Set.size seen + 1) ++ "/" ++ show (Set.size want) ++ "] " ++ pkg) $
                    UTF8.toString body)
        f seen _ = (seen, "")
    (seen, xs) <- second (parseHoogle . filter (/= '\r') . unlines) . mapAccumL f Set.empty <$> tarballReadFiles "input/hoogle.tar.gz"
    let out = "output" </> (if Set.size want == 1 then head $ Set.toList want else "all")
    storeWriteFile (out <.> "hoo") $ \store -> do
        xs <- writeItems store out xs
        putStrLn $ "Packages not found: " ++ unwords (Set.toList $ want `Set.difference` seen)
        xs <- timed "Reodering items" $ reorderItems xs
        timed "Writing tags" $ writeTags store extra xs
        timed "Writing names" $ writeNames store xs
        timed "Writing types" $ writeTypes store xs

        whenM getGCStatsEnabled $ do
            performGC
            print =<< getGCStats
            void $ evaluate xs
