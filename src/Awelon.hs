

module Awelon 
    ( Word, ModuleName, LocalName
    , WX(..)
    , Module(..)
    , App(..)
    ) where

import qualified Data.Text.Lazy as T
import Control.Exception (assert)
import Data.Char
import Data.Maybe

type Text = T.Text
type Word = Text
type ModuleName = Word
type LocalName = ModuleName
type Import = (ModuleName,LocalName)
type Definition = (Word,Code)

-- Awelon has simple modules
data Module = Module
    { name        :: ModuleName
    , imports     :: [Import] 
    , definitions :: [Definition]
    , other       :: [Text]
    }
data App = App
    { appStart :: Code -- words name modules
    , modules :: [Module]
    }
data AppCX = AppCX
    { prims :: [Prim]
    }
type Code = [ WX ]
data WX 
    = W  ModuleName Word -- words
    | LN Rational        -- 
    | LT Text
    | LB Code
data Prim = Prim
data Type 
    = Unit -- from intro1
    | ST Text -- static text
    | SN Rational -- static number
    | SB BType
    | Prod Type Type 
    | DSum Type Type -- dynamic sum
    | SSum Type Type -- static sum
    | Zero -- from intro0

data BType = Block 
    { nocopy :: Maybe SrcLoc  -- affine type
    , nodrop :: Maybe SrcLoc  -- relevant type
    , code   :: Code 
    , srcid  :: Text          -- fingerprint for construction of block
    }

-- To help with source locators, first we'll treat blocks as words
-- such that a block that is the 3rd item of word `foo` might be 
-- implicitly named `foo:3` (programmers cannot use these words).
-- The composition of blocks must also be named; maybe I'll simply
-- use the combined text e.g. "foo:3 bar:2" to denote this 
-- composition.
--
-- An expansion with first-class functions must also address usage
-- context, i.e. the unique location of 'first' or 'left' (or use
-- of 'foreach', potentially). 
-- 
-- An expansion must address not only source location, but context.
-- For a block, usage context would always be the 

-- A source location is an actual, physical location in a source
-- file. It is specified by module, word, and a list of numbers.
-- The list of numbers describes the deep 
data SrcLoc = SrcLoc ModuleName Word [Int]


-- Expanded location? In an "expansion" of the code, location 
-- might be described by a path (described by data-plumbing) 
-- and depth? Or maybe an alternative is to use a fingerprinting 
-- technique for locations.

-- IDEA: Automatically strip 'blocks' out of definitions and
-- rename them to help with debugging. The name for a block
-- might be `word#pos`. 

 

-- I'm going to start minimal here and build up types as
-- I need them. I already know I might want:
--    sum types, dead types
--    zero types
--    error tracking; modeling errors in the type system*
--    atom types, atomic signals
--    
--    


-- get back to these...



-- code is a list of word-expressions. 
-- (Empty code is equivalent to id.)

-- | a word-expression is a word, a number, text, 
-- or a block of the same. Awelon is very easy to
-- process. 


-- PARSING MODULES
parseModuleText :: ModuleName -> Text -> Module
parseModuleText n = 
    linesToModule n .
    map parseLogicalLine . 
    extractLogicalLines .
    stripLineComments

-- remove all line comments from text. 
-- line comments in Awelon simply start with '%'.
-- NOTE: keeps the newline characters; handles text literals
stripLineComments :: Text -> Text
stripLineComments = cc T.empty where
    -- cc is just the normal state.
    cc tOut tIn = 
        case T.uncons tIn of
            Nothing -> tOut
            Just (c,tIn') ->
                let tOut' = T.snoc tOut c in
                if ('%' == c) then lc tOut tIn' else
                if ('"' /= c) then cc tOut' tIn' 
                              else tc tOut' tIn'
    -- tc, assume we're parsing text literals.
    tc tOut tIn =
        case T.uncons tIn of
            Nothing -> tOut
            Just (c,tIn') ->
                let tOut' = T.snoc tOut c in
                if ('"' == c) then cc tOut' tIn' else
                if ('\\' == c) then tce tOut' tIn'
                               else tc tOut' tIn'
    -- tce is after an escape. 
    tce tOut tIn =
        case T.uncons tIn of
            Nothing -> tOut
            Just (c,tIn') ->
                let tOut' = T.snoc tOut c in
                tc tOut' tIn'
    lc tOut tIn =
        case T.uncons tIn of
            Nothng -> tOut
            Just (c,tIn') -> 
                if ('\n' == c) then cc (T.snoc tOut '\n') tIn'
                               else lc tOut tIn'

-- break code into logical lines; does not lose any characters.
extractLogicalLines :: Text -> [Text]
extractLogicalLines = llc T.empty where
    llc tOut tIn = 
        case T.uncons tIn of
            Nothing -> (tOut:[])
            Just (c,tIn') ->
                let tOut' = T.snoc tOut c in
                if ('\n' == c) then lln tOut' tIn' 
                               else llc tOut' tIn'
    lln tOut tIn =
        case T.uncons tIn of
            Nothing -> (tOut:[])
            Just (c,tIn') ->
                if isSpace c then llc tOut tIn 
                             else tOut:(llc T.empty tIn)


type Line = Either [Import] Definition

parseLogicalLine :: Text -> Line
parseLogicalLine txt = 
    if (T.pack "import ") `isPrefixOf` txt 
        then Left $ parseImports (drop 6 txt)
        else Right $ parseDefinition txt

-- an imports list is a comma-separated list of the form:
--   foo,bar,baz, packageWithLongName AS p, etc
-- module names should be valid words, but they are not 
-- validated here.
parseImports :: Text -> [Import]
parseImports = 
    map toImport . filter (not . T.null) . 
    map strip . splitBy (== ',')
  where
    toImport txt = 
        let (mn0,ln0) = break " AS " txt in
        let ln1 = strip ln0 in
        let mnf = strip mn0 in
        let lnf = if (T.null ln1) then mnf else ln1 in
        (mnf,lnf)

-- a definition has the form:
--   word = code [blocks of code] "text" 42 12.3 numbers
parseDefinition :: Text -> Definition


        


tryWord where
    tryWord tIn = 
        case T.uncons tIn of
            Nothing -> []
            Just (c,tIn') ->
                if 
    pw tx = 
    let tc = stripStart txt in
     


linesToModule :: ModuleName -> [Text] -> Module
linesToModule n ls = mod where
    mod = Module n imps defs
    lsRead = map readLine ls
    readLine txt = 
        


-- appStart code interprets words as module names
--    This allows one to compile an application using text of the
--    form "[myApp] myAppFramework" or similar. 
fixAppWords :: Code -> Code
fixAppWords = map f where
    f (W mn w) = if (T.null mn) 
        then W w (T.pack "this")
        else W mn w
    f (B code) = B (fixAppCode code)
    f x = x


-- Words not starting with '_' are exported.
isExportWord :: Word -> Boolean
isExportWord w = assert ((not . S.null) w) $ ('_' /= head w)




-- cyclic modules are not allowed in Awelon.
-- returns a list of offending pairs. 
--detectCyclicModules :: App -> [(ModuleName,ModuleName)]






































