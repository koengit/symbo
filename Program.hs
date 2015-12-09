module Program where

import qualified Data.Map as M
import Data.Map( Map )
import Data.Maybe( fromJust )
import Data.List( intersperse )

import Object

--------------------------------------------------------------------------------------------

data Expr
  = Var Name
  | Con Cons [Expr]
  | App Name [Expr]
  | Later Expr
  | Let Name Expr Expr
  | LetApp Name [Name] Expr Expr
  | Case Expr [(Cons,[Name],Expr)]
 deriving ( Eq, Ord, Show )

type Program = Map Name ([Name],Expr)

--------------------------------------------------------------------------------------------

data Mode = Direct | Prolog deriving ( Eq, Ord, Show )

--------------------------------------------------------------------------------------------

eval :: Mode -> Program -> Map Name (Object,[Object],Object) -> Map Name Object -> Expr -> M Object
eval mode prog apps env (Var x) =
  do return (fromJust (M.lookup x env))

eval mode prog apps env (Con c as) =
  do ys <- sequence [ eval mode prog apps env a | a <- as ]
     return (cons c ys)
     
eval mode prog apps env (App f as) =
  case (M.lookup f apps, M.lookup f prog) of
    (Just (trig,ys,z), _) ->
      do isCons trig true $ \_ ->
           sequence_ [ evalInto mode prog apps env a y | (a,y) <- zipp ("App/LetApp:" ++ show f) as ys ]
         return z

    (_, Just (xs,rhs)) ->
      --case mode of
      --  Direct ->
          do ys <- sequence [ eval mode prog apps env a | a <- as ]
             eval mode prog M.empty (M.fromList (zipp ("App:" ++ show f) xs ys)) rhs

      --  Prolog ->
      --    do res <- new
      --       evalInto mode prog apps env (App f as) res
      --       return res

eval mode prog apps env (Later a) =
  do y <- new
     evalInto mode prog apps env (Later a) y
     return y

eval mode prog apps env (Let x a b) =
  do y <- eval mode prog apps env a
     eval mode prog apps (M.insert x y env) b

eval mode prog apps env (LetApp f xs a b) =
  do trig <- new
     ys   <- sequence [ new | x <- xs ]
     z    <- new
     ifCons trig true $ \_ ->
       evalInto mode prog apps (inserts (zipp ("LetApp:" ++ show f) xs ys) env) a z
     eval mode prog (M.insert f (trig,ys,z) apps) env b

eval mode prog apps env (Case a alts) =
  do res <- new
     evalInto mode prog apps env (Case a alts) res
     return res

--------------------------------------------------------------------------------------------

evalInto :: Mode -> Program -> Map Name (Object,[Object],Object) -> Map Name Object -> Expr -> Object -> M ()
evalInto mode prog apps env (Var x) res =
  do fromJust (M.lookup x env) >>> res

evalInto mode prog apps env (Con c as) res =
  do isCons res c $ \ys ->
       sequence_ [ evalInto mode prog apps env a y | (a,y) <- zipp ("Con:" ++ show c ++ "->") as ys ]

evalInto mode prog apps env (App f as) res =
  case (M.lookup f apps, M.lookup f prog) of
    (Just (trig,ys,z), _) ->
      do isCons trig true $ \_ ->
           sequence_ [ evalInto mode prog apps env a y | (a,y) <- zipp ("App/LetApp:" ++ show f ++ "->") as ys ]
         z >>> res

    (_, Just (xs,rhs)) ->
      --(case mode of
      --  Direct -> id
      --  Prolog -> later) $
      do ys <- sequence [ eval mode prog apps env a | a <- as ]
         evalInto mode prog M.empty (M.fromList (zipp ("App:" ++ show f ++ "->") xs ys)) rhs res

evalInto mode prog apps env (Later a) res =
  do later (evalInto mode prog apps env a res)

evalInto mode prog apps env (Let x a b) res =
  do y <- eval mode prog apps env a
     evalInto mode prog apps (M.insert x y env) b res

evalInto mode prog apps env (LetApp f xs a b) res =
  do trig <- new
     ys   <- sequence [ new | x <- xs ]
     z    <- new
     ifCons trig true $ \_ ->
       evalInto mode prog apps (inserts (zipp ("LetApp:" ++ show f ++ "->") xs ys) env) a z
     evalInto mode prog (M.insert f (trig,ys,z) apps) env b res

evalInto mode prog apps env (Case a alts) res =
  do y <- eval mode prog apps env a
     case mode of
       Direct ->
         sequence_
           [ ifCons y c $ \ys ->
                 evalInto mode prog apps (inserts (zipp ("Case:" ++ show c) xs ys) env) rhs res
           | (c,xs,rhs) <- alts
           ]

       Prolog ->
         choice
           [ isCons y c $ \ys ->
                 evalInto mode prog apps (inserts (zipp ("Case:" ++ show c) xs ys) env) rhs res
           | (c,xs,rhs) <- alts
           ]

--------------------------------------------------------------------------------------------

zipp :: String -> [a] -> [b] -> [(a,b)]
zipp s []     []     = []
zipp s (x:xs) (y:ys) = (x,y) : zipp s xs ys
zipp s _      _      = error ("zipp (" ++ s ++ "): unequal lengths")

inserts :: Ord a => [(a,b)] -> Map a b -> Map a b
inserts xys mp = foldr (\(x,y) -> M.insert x y) mp xys

--------------------------------------------------------------------------------------------


