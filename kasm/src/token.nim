type 
  TokenKind* {.pure.} = enum
    Mnemonic
    RegisterName
    Condition
    FreezeFlags
    LabelDef
    Label
    Number
    String
    Directive
    LeftParen
    RightParen
    LeftBracket
    RightBracket
    Plus
    Minus
    Comma
    Newline
    Eof
  Token* = object
    text*: string
    case kind*: TokenKind:
      of Number: num*: int
      else: nil
    line*, pos*, index*: int
  TokenList* = seq[Token]

proc `$`*(t: Token): string =
  if t.kind == Number:
    result = "Number(\"" & t.text & "\", " & $t.num & ")"
  else:
    result = $t.kind & "(\"" & t.text & "\")"
  result &= " at (" & $t.line & ", " & $t.pos & ")"