{-
    BNF Converter: C++ Main file
    Copyright (C) 2004  Author:  Markus Forsberg, Michael Pellauer
-}

module BNFC.Backend.CPP.NoSTL (makeCppNoStl) where

import Data.Char
import Data.List (nub)
import qualified Data.Map as Map

import BNFC.Utils
import BNFC.CF
import BNFC.Options
import BNFC.Backend.Base
import BNFC.Backend.C            (bufferH, bufferC)
import BNFC.Backend.C.CFtoBisonC (unionBuiltinTokens)
import BNFC.Backend.CPP.Makefile
import BNFC.Backend.CPP.NoSTL.CFtoCPPAbs
import BNFC.Backend.CPP.NoSTL.CFtoFlex
import BNFC.Backend.CPP.NoSTL.CFtoBison
import BNFC.Backend.CPP.STL.CFtoCVisitSkelSTL
import BNFC.Backend.CPP.PrettyPrinter
import qualified BNFC.Backend.Common.Makefile as Makefile

makeCppNoStl :: SharedOptions -> CF -> MkFiles ()
makeCppNoStl opts cf = do
    let (hfile, cfile) = cf2CPPAbs name cf
    mkfile "Absyn.H" hfile
    mkfile "Absyn.C" cfile
    mkfile "Buffer.H" bufferH
    mkfile "Buffer.C" $ bufferC "Buffer.H"
    let (flex, env) = cf2flex Nothing name cf
    mkfile (name ++ ".l") flex
    let bison = cf2Bison name cf env
    mkfile (name ++ ".y") bison
    let header = mkHeaderFile cf (allParserCats cf) (allEntryPoints cf) (Map.elems env)
    mkfile "Parser.H" header
    let (skelH, skelC) = cf2CVisitSkel False Nothing cf
    mkfile "Skeleton.H" skelH
    mkfile "Skeleton.C" skelC
    let (prinH, prinC) = cf2CPPPrinter False Nothing cf
    mkfile "Printer.H" prinH
    mkfile "Printer.C" prinC
    mkfile "Test.C" (cpptest cf)
    Makefile.mkMakefile opts $ makefile name
  where name = lang opts


cpptest :: CF -> String
cpptest cf =
  unlines
   [
    "/*** Compiler Front-End Test automatically generated by the BNF Converter ***/",
    "/*                                                                          */",
    "/* This test will parse a file, print the abstract syntax tree, and then    */",
    "/* pretty-print the result.                                                 */",
    "/*                                                                          */",
    "/****************************************************************************/",
    "#include <stdio.h>",
    "#include <string.h>",
    "#include \"Parser.H\"",
    "#include \"Printer.H\"",
    "#include \"Absyn.H\"",
    "",
    "void usage() {",
    "  printf(\"usage: Call with one of the following argument " ++
      "combinations:\\n\");",
    "  printf(\"\\t--help\\t\\tDisplay this help message.\\n\");",
    "  printf(\"\\t(no arguments)\\tParse stdin verbosely.\\n\");",
    "  printf(\"\\t(files)\\t\\tParse content of files verbosely.\\n\");",
    "  printf(\"\\t-s (files)\\tSilent mode. Parse content of files " ++
      "silently.\\n\");",
    "}",
    "",
    "int main(int argc, char ** argv)",
    "{",
    "  FILE *input;",
    "  int quiet = 0;",
    "  char *filename = NULL;",
    "",
    "  if (argc > 1) {",
    "    if (strcmp(argv[1], \"-s\") == 0) {",
    "      quiet = 1;",
    "      if (argc > 2) {",
    "        filename = argv[2];",
    "      } else {",
    "        input = stdin;",
    "      }",
    "    } else {",
    "      filename = argv[1];",
    "    }",
    "  }",
    "",
    "  if (filename) {",
    "    input = fopen(filename, \"r\");",
    "    if (!input) {",
    "      usage();",
    "      exit(1);",
    "    }",
    "  } else input = stdin;",
    "  /* The default entry point is used. For other options see Parser.H */",
    "  " ++ dat ++ " *parse_tree = p" ++ def ++ "(input);",
    "  if (parse_tree)",
    "  {",
    "    printf(\"\\nParse Successful!\\n\");",
    "    if (!quiet) {",
    "      printf(\"\\n[Abstract Syntax]\\n\");",
    "      ShowAbsyn *s = new ShowAbsyn();",
    "      printf(\"%s\\n\\n\", s->show(parse_tree));",
    "      printf(\"[Linearized Tree]\\n\");",
    "      PrintAbsyn *p = new PrintAbsyn();",
    "      printf(\"%s\\n\\n\", p->print(parse_tree));",
    "    }",
    "    return 0;",
    "  }",
    "  return 1;",
    "}",
    ""
   ]
  where
   cat = head (allEntryPoints cf)
   dat = identCat $ normCat cat
   def = identCat cat

mkHeaderFile cf cats eps env = unlines $ concat
  [ [ "#ifndef PARSER_HEADER_FILE"
    , "#define PARSER_HEADER_FILE"
    , ""
    ]
  , map mkForwardDec $ nub $ map normCat cats
  , [ "typedef union"
    , "{"
    ]
  , map ("  " ++) unionBuiltinTokens
  , concatMap mkVar cats
  , [ "} YYSTYPE;"
    , ""
    , "#define _ERROR_ 258"
    , mkDefines (259 :: Int) env
    , "extern YYSTYPE yylval;"
    , ""
    ]
  , map mkFunc eps
  , [ ""
    , "#endif"
    ]
  ]
  where
  mkForwardDec s = "class " ++ identCat s ++ ";"
  mkVar s | normCat s == s = [ "  " ++ identCat s ++"*" +++ map toLower (identCat s) ++ "_;" ]
  mkVar _ = []
  mkDefines n [] = mkString n
  mkDefines n (s:ss) = "#define " ++ s +++ show n ++ "\n" ++ mkDefines (n+1) ss
  mkString n =  if isUsedCat cf (TokenCat catString)
   then ("#define _STRING_ " ++ show n ++ "\n") ++ mkChar (n+1)
   else mkChar n
  mkChar n =  if isUsedCat cf (TokenCat catChar)
   then ("#define _CHAR_ " ++ show n ++ "\n") ++ mkInteger (n+1)
   else mkInteger n
  mkInteger n =  if isUsedCat cf (TokenCat catInteger)
   then ("#define _INTEGER_ " ++ show n ++ "\n") ++ mkDouble (n+1)
   else mkDouble n
  mkDouble n =  if isUsedCat cf (TokenCat catDouble)
   then ("#define _DOUBLE_ " ++ show n ++ "\n") ++ mkIdent(n+1)
   else mkIdent n
  mkIdent n =  if isUsedCat cf (TokenCat catIdent)
   then "#define _IDENT_ " ++ show n ++ "\n"
   else ""
  mkFunc s = identCat (normCat s) ++ "*" +++ "p" ++ identCat s ++ "(FILE *inp);"
