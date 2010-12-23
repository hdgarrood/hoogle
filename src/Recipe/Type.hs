
module Recipe.Type(
    CmdLine(..), Name, hoo, noDeps,
    keywords, platform, cabals, haddocks, listing, version,
    resetWarnings, putWarning, recapWarnings,
    outStr, outStrLn
    ) where

import CmdLine.All
import Control.Concurrent
import System.IO.Unsafe
import General.Base
import General.System


type Name = String

hoo :: Name -> FilePath
hoo x = x <.> "hoo"


noDeps :: [Name] -> IO ()
noDeps [] = return ()
noDeps xs = error "Internal error: package with no dependencies had dependencies"


---------------------------------------------------------------------
-- DOWNLOADED INFORMATION

keywords = "download/keyword.txt"
platform = "download/haskell-platform.cabal"
cabals = "download/hackage-cabal"
haddocks = "download/hackage-haddock"

listing :: FilePath -> IO [Name]
listing dir = do
    xs <- getDirectoryContents dir
    return $ sortBy (comparing $ map toLower) $ filter (`notElem` [".","..","preferred-versions"]) xs

version :: FilePath -> Name -> IO String
version dir x = do
    ys <- getDirectoryContents $ dir </> x
    when (null ys) $ error $ "Couldn't find version for " ++ x ++ " in " ++ dir
    let f = map (read :: String -> Int) . words . map (\x -> if x == '.' then ' ' else x)
    return $ maximumBy (comparing f) $ filter (all (not . isAlpha)) ys


---------------------------------------------------------------------
-- WARNING MESSAGES

{-# NOINLINE warnings #-}
warnings :: MVar [String]
warnings = unsafePerformIO $ newMVar []

putWarning :: String -> IO ()
putWarning x = do
    outStrLn x
    modifyMVar_ warnings $ return . (x:)

recapWarnings :: IO ()
recapWarnings = do
    xs <- readMVar warnings
    mapM_ outStrLn $ reverse xs

resetWarnings :: IO ()
resetWarnings = modifyMVar_ warnings $ const $ return []


outputLock :: MVar ()
outputLock = unsafePerformIO $ newMVar ()

outStr, outStrLn :: String -> IO ()
outStr x = withMVar outputLock $ \_ -> do putStr x; hFlush stdout
outStrLn x = outStr $ x ++ "\n"
