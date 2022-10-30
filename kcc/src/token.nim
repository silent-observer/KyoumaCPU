import strformat
from strutils import escape

const 
  Keywords* = [
    "break", "continue", "char", "do", "else", 
    "for", "if", "int", "return", "short", "signed", "struct", "unsigned", "void", "while"
    ]
type
  KeywordKind* {.pure.} = enum
    Break
    Continue
    Char
    Do
    Else
    For
    If
    Int
    Return
    Short
    Signed
    Struct
    Unsigned
    Void
    While

type
  TokenKind* {.pure.} = enum
    Keyword
    Identifier
    Symbol
    NumberConstant
    CharacterConstant
    StringConstant
    Eof
  
  Token* = object
    case kind*: TokenKind:
      of Keyword: keyword*: KeywordKind
      of Identifier: identText*: string
      of Symbol: symbol*: string
      of NumberConstant: num*: int64
      of CharacterConstant: character*: char
      of StringConstant: str*: string
      of Eof: nil
    line*, pos*, index*: int
  TokenSequence* = seq[Token]


proc `$`*(t: Token): string =
  result = case t.kind:
    of Keyword: &"Keyword({t.keyword})"
    of Identifier: &"Ident(\"{t.identText}\")"
    of Symbol: &"Symbol(\"{t.symbol}\")"
    of NumberConstant: &"NumConst({t.num})"
    of CharacterConstant:
      let s = escape($t.character, "'", "'")
      &"CharConst({s})"
    of StringConstant: &"StringConst({t.str.escape})"
    of Eof: "Eof"
  result &= &" at ({t.line}, {t.pos})"