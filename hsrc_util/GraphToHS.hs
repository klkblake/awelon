
-- | Compile a graphical IR to Haskell text to support JIT.
--
-- This is an *imperative* interpretation of the ABC graph.
--
module GraphToHS 
    ( abc2hs
    ) where

import Control.Monad.Trans.State
import Control.Monad.Trans.Error
import Data.Functor.Identity
import qualified Data.Map as M
import ABC.Imperative.Value
import ABC.Operators
import ABCGraph
import Util (indent)

data CX = CX
    { cx_subs :: M.Map [Op] ProgName -- subroutines...
    , cx_txts :: M.Map String TextName -- texts
    , cx_code :: [HaskellDef] -- toplevel definitions
    }
type ProgName = String
type TextName = String
type ModuleName = String
type ModuleString = String
type HaskellDef = String
type ErrorString = String

type MkHS = StateT CX (ErrorT ErrorString Identity)
evalMkHS :: MkHS a -> Either ErrorString a
evalMkHS = runIdentity . runErrorT . flip evalStateT cx0

cx0 :: CX
cx0 = CX M.empty M.empty []

-- | abc2hs takes a module name and the primary resource
-- it will export both the 'resource' and perhaps the
-- 'source' (an ABC string). 
abc2hs :: ModuleName -> [Op] -> Either ErrorString ModuleString
abc2hs modName ops = evalMkHS $ 
    mkSub ops >>= \ mainFn ->
    gets cx_code >>= \ subDefs ->
    return (moduleText modName mainFn subDefs)

moduleText :: ModuleName -> ProgName -> [HaskellDef] -> ModuleString
moduleText modName mainFn defs = fullTxt "" where
    fullTxt = lang.p.mod.p.imps.p.rsc.p.(ss defs).p
    -- lang = showString "{-# LANGUAGE NoImplicitPrelude #-}"
    lang = id
    mod = showString "module " . showString modName .
          showString " ( resource ) where "
    imps = showString "import ABC.Imperative.Prelude"
    rsc = showString "resource :: Resource" . p .
          showString "resource = Resource " . showString mainFn
    ss (d:ds) = showString d . p . ss ds
    ss [] = id
    p = showChar '\n'

mkSub :: [Op] -> MkHS ProgName
mkSub ops =
    get >>= \ cx ->
    let m = cx_subs cx in
    case M.lookup ops m of
        Just pn -> return pn
        Nothing ->
            let pn = 'p' : show (M.size m) in
            let m' = M.insert ops pn m in
            let cx' = cx { cx_subs = m' } in
            put cx' >> 
            defSub pn ops >>
            return pn

defSub :: ProgName -> [Op] -> MkHS ()
defSub pn ops = 
    case abc2graph ops of
        Left err -> fail $ err ++ " @ " ++ show (BL ops)  
        Right g -> buildSubTxt pn g >>= emitCode

emitCode :: HaskellDef -> MkHS ()
emitCode def = modify $ \ cx ->
    let code' = def : cx_code cx in
    cx { cx_code = code' }

buildSubTxt :: ProgName -> (WireLabel,[Node],Wire) -> MkHS HaskellDef
buildSubTxt pn (w0,ns,wf) =
    mkHS wf ns >>= \ bodyTxt ->
    return (progText pn w0 bodyTxt)

-- full haskell text from appropriately sorted graph
mkHS :: Wire -> [Node] -> MkHS HaskellDef
mkHS (Var s) (ap@(Apply (src,w) s') : nodes) | (s == s') = -- tail-call
    if null nodes then return $ "b_prog " ++ show src ++ " " ++ wirePattern w
                  else mkHS (Var s) (nodes ++ [ap])
mkHS w [] = return $ "return " ++ wirePattern w -- normal return
mkHS w (n:ns) = 
    mkNHS n >>= \ op ->
    mkHS w ns >>= \ ops ->
    return (op ++ ('\n' : ops))

-- capture a pattern as a value
wirePattern :: Wire -> HaskellDef
wirePattern = flip wp "" where
    wp (Var v) = shows v
    wp (Num n) = showString "(N " . shows n . showChar ')'
    wp (ABCGraph.Block cb) = 
        showString "(B " . shows (cb_src cb) . 
        showString "{ b_aff = " . shows (cb_aff cb) . 
        showString ", b_rel = " . shows (cb_rel cb) . 
        showString "})"
    wp (Prod a b) = showString "(P " . wp a . showChar ' ' . wp b . showChar ')'
    wp Unit = showChar 'U'
    wp (Sum c a b) = showString "(sum3toV " . shows c . showChar ' ' . 
                     wp a . showChar ' ' . wp b . showChar ')'
    wp (Seal s v) = showString "(S " . shows s . showChar ' ' . wp v . showChar ')'

-- Translate nodes to fragments of monadic Haskell code.
-- This is monadic mostly to support `SrcConst`.
mkNHS :: Node -> MkHS HaskellDef
mkNHS (Void () w) = return $ "let " ++ show w ++ " = voidVal in "
mkNHS (ElabSum w (c,a,b)) = return $ "exSum3 " ++ show w ++ 
    " >>= \\ (" ++ show c ++ "," ++ show a ++ "," ++ show b ++ ") -> "
mkNHS (ElabProd w (a,b)) = return $ "exProd " ++ show w ++ 
    " >>= \\ (" ++ show a ++ "," ++ show b ++ ") -> "
mkNHS (ElabNum w n) = return $ "exNum " ++ show w ++ " >>= \\ " ++ show n ++ " -> "
mkNHS (ElabCode w cb) = return $ "exBKF " ++ show w ++ 
    let b = show $ cb_src cb in
    let k = show $ cb_rel cb in
    let f = show $ cb_aff cb in
    " >>= \\ (" ++ b ++ "," ++ k ++ "," ++ f ++ ") ->"
mkNHS (ElabUnit w ()) = return $ "exUnit " ++ show w ++ " >>= \\ () -> "
mkNHS (ElabSeal s w v) = return $ "exSeal " ++ show s ++ " " ++ show w ++ 
    " >>= \\ " ++ show v ++ " -> "
mkNHS (NumConst r w) = return $ "let " ++ show w ++ " = " ++ show r ++ " in "
mkNHS (Add (a,b) c) = return $ "let " ++ show c ++ " = " ++ show a ++ " + " ++ show b ++ " in "
mkNHS (Neg a b) = return $ "let " ++ show b ++ " = negate " ++ show a ++ " in "
mkNHS (Mul (a,b) c) = return $ "let " ++ show c ++ " = " ++ show a ++ " * " ++ show b ++ " in "
mkNHS (Inv a b) = return $ "let " ++ show b ++ " = recip " ++ show a ++ " in "
mkNHS (DivMod (a,b) (q,r)) = return $ "let (" ++ show q ++ "," ++ show r ++ 
    ") = divModR " ++ show a ++ " " ++ show b ++ " in "
mkNHS (IsNonZero n b) = return $ "let " ++ show b ++ " = (0 /= " ++ show n ++ ") in "
mkNHS (GreaterThan (x,y) b) = return $ "let " ++ show b ++ " = (" ++ show x ++ " > " ++ show y ++ ") in "
mkNHS (BoolConst bc b) = return $ "let " ++ show b ++ " = " ++ show bc ++ " in "
mkNHS (BoolOr (a,b) c) = return $ "let " ++ show c ++ " = (" ++ show a ++ " || " ++ show b ++ ") in "
mkNHS (BoolAnd (a,b) c) = return $ "let " ++ show c ++ " = (" ++ show a ++ " && " ++ show b ++ ") in "
mkNHS (BoolNot a b) = return $ "let " ++ show b ++ " = not " ++ show a ++ " in "
mkNHS (BoolCopyable a b) = return $ "let " ++ show b ++ " = copyable " ++ show a ++ " in "
mkNHS (BoolDroppable a b) = return $ "let " ++ show b ++ " = droppable " ++ show b ++ " in "
mkNHS (BoolAssert b ()) = return $ "rtAssert " ++ show b ++ " >>= \\ () -> "
mkNHS (SrcConst ops b) = 
    mkSub ops >>= \ pn -> -- block as subprogram
    addText (show ops) >>= \ tn -> -- preserve ABC code in block
    return $ "let " ++ show b ++ " = blockVal " ++ tn ++ " " ++ pn ++ " in "
mkNHS (Quote w b) = return $ "let " ++ show b ++ " = quoteVal " ++ wirePattern w ++ " in "
mkNHS (Compose (xy,yz) xz) = return $ "let " ++ show xz ++ 
    " = bcomp " ++ show xy ++ " " ++ show yz ++ " in "
mkNHS (Apply (src,arg) result) = return $ "b_prog " ++ show src ++ 
    " " ++ wirePattern arg ++ " >>= \\ " ++ show result ++ " -> "
mkNHS (CondAp (c,src,arg) result) = return $ "condAp " ++ show c ++ 
    "(b_prog " ++ show src ++ ") " ++ wirePattern arg ++ " >>= \\ " ++ show result ++ " -> "
mkNHS (Merge (c,a,b) r) = return $ "let " ++ show r ++ " = mergeSum3 " ++ show c ++
    " " ++ wirePattern a ++ " " ++ wirePattern b ++ " in "
mkNHS (Invoke s w r) = return $ "invoke " ++ show s ++ 
    " " ++ wirePattern w ++ " >>= \\ " ++ show r ++ " -> "


progText :: ProgName -> WireLabel -> String -> HaskellDef
progText pn w0 body = (hdr.p.onMatch.p)"" where
    hdr = showString pn . showString " :: (Runtime cx) => Prog cx"
    onMatch = showString pn . showChar ' ' . shows w0 . 
              showString " = \n" . showString (indent "  " body)
    p = showChar '\n'

addText :: String -> MkHS TextName 
addText s = 
    get >>= \ cx ->
    let m = cx_txts cx in
    case M.lookup s m of
        Just tn -> return tn
        Nothing ->
            let tn = 't' : show (M.size m) in
            let m' = M.insert s tn m in
            let cx' = cx { cx_txts = m' } in
            put cx' >>
            defText tn s >>
            return tn

defText :: TextName -> String -> MkHS ()
defText tn s = emitCode (showProg "") where
    showProg = hdr.p.body.p
    hdr = showString tn . showString " :: String "
    body = showString tn . showString " = " . shows s
    p = showChar '\n'