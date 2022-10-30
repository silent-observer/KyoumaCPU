import token, parseutils, strutils, tables

const Mnemonics = [
  "ADD", "SUB", "LSH", "ASH", "AND", "OR", "XOR", "CND",
  "ADDI", "SUBI", "LSHI", "ASHI", "ANDI", "ORI", "XORI", "LDH",
  "LW", "SW", "SH", "SB", "LHU", "LHS", "LBU", "LBS",
  "LDI", "MLTU", "MLTS", "DIVU", "DIVS",
  "MOV", "JMP", "JMPL", "HALT", "NOP", "LOAD", "CMP", "DB", "DH", "DW"
  ]

const Registers = [
  "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7",
  "R8", "R9", "R10", "R11", "R12", "R13", "R14", "R15",
  "LR", "SR", "FP", "SP", "PC", "HI", "LO"
]

const Conditions = [
  "Z", "EQ", "NZ", "NE", "V", "LT", "GE", "C", "NC"
]

const Directives = [
  "INCLUDE", "TEXT", "DATA", "RODATA", "BSS", "ALIGN"
]

const CompileTimeConsts = {
  "LCD_CTRL": 0xFFFFFFFF'u32,
  "LCD_DATA": 0xFFFFFFFE'u32,
  "CPU_SPEED": 0xFFFFFFFD'u32,
  "CPU_SPEED_MANUAL": 0'u32,
  "CPU_SPEED_SLOW": 1'u32,
  "CPU_SPEED_MAX": 2'u32
}.toTable()

type Lexer = object
  input: string
  line, pos: int
  index: int

type LexingError* = object of Exception
  line, pos, index: int
  lineString: string

proc reportError*(e: LexingError): string =
  result = "Lexing Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  result &= e.lineString & "\n"
  result &= spaces(e.pos - 1) & "^\n"

proc peek(lexer: Lexer): char {.inline.} =
  if lexer.index == lexer.input.len():
    '\0'
  else:
    lexer.input[lexer.index]

proc getOne(lexer: var Lexer): char {.inline.} =
  if lexer.index == lexer.input.len():
    return '\0'
  result = lexer.input[lexer.index]
  lexer.index.inc
  lexer.pos.inc

proc getText(lexer: Lexer, startIndex: int): string {.inline.} =
  result = lexer.input[startIndex..(lexer.index - 1)]

proc getLine(lexer: Lexer): string {.inline.} =
  let lineStart = lexer.index - (lexer.pos - 1)
  discard lexer.input.parseUntil(result, {'\n', '\r'}, lineStart)

proc initToken(lexer: Lexer, text: string, kind: TokenKind, correction: int): Token {.inline.} =
  Token(
    text: text,
    kind: kind,
    line: lexer.line,
    pos: lexer.pos - correction,
    index: lexer.index - correction
  )

proc lexRadixInt[R: static[int]](lexer: var Lexer, startIndex: int): Token =
  var val: int64
  let count = 
    when R == 16:
      lexer.input.parseHex(val, start = startIndex)
    elif R == 8:
      lexer.input.parseOct(val, start = startIndex)
    elif R == 2:
      lexer.input.parseBin(val, start = startIndex)
    elif R == 10:
      lexer.input.parseBiggestInt(val, start = startIndex)
  lexer.index += count
  lexer.pos += count
  let correction = when R == 10: 0 else: 2
  result = lexer.initToken(lexer.getText(startIndex - correction), Number, count)
  result.num = cast[int](val and 0xFFFFFFFF'i64)

proc skipWhitespace(lexer: var Lexer): bool =
  while lexer.peek().isSpaceAscii():
    let c = lexer.getOne()
    if c == '\0':
      break
    if c == '\n':
      lexer.pos = 1
      lexer.line.inc
      return true
  return false

proc lexNumber(lexer: var Lexer): Token =
  let startIndex = lexer.index
  var c = lexer.peek()

  if c == '0':
    discard lexer.getOne()
    c = lexer.peek()
    case c:
      of 'x': 
        discard lexer.getOne()
        lexRadixInt[16](lexer, startIndex + 2)
      of 'o':
        discard lexer.getOne()
        lexRadixInt[8](lexer, startIndex + 2)
      of 'b': 
        discard lexer.getOne()
        lexRadixInt[2](lexer, startIndex + 2)
      else: 
        Token(
          text: lexer.getText(startIndex),
          kind: Number,
          line: lexer.line,
          pos: lexer.pos,
          index: lexer.index,
          num: 0)
  else: lexRadixInt[10](lexer, startIndex)

proc lexWord(lexer: var Lexer): Token =
  let startIndex = lexer.index
  var text: string
  let count = lexer.input.parseIdent(text, start = startIndex)
  lexer.index += count
  lexer.pos += count
  let textUpper = text.toUpperAscii()
  if (textUpper in CompileTimeConsts):
    result = lexer.initToken(text, Number, count)
    result.num = cast[int](CompileTimeConsts[textUpper])
    return
  let kind = 
    if (textUpper in Mnemonics): 
      Mnemonic
    elif (textUpper in Registers) or
         (textUpper[0] in ['S', 'U'] and textUpper[1..^1] in Registers):
      RegisterName
    elif lexer.peek() == ':':
      discard lexer.getOne()
      LabelDef
    else: Label
  result = lexer.initToken(text, kind, count)

proc lexCondition(lexer: var Lexer): Token =
  let startIndex = lexer.index
  var text: string
  let count = lexer.input.parseIdent(text, start = startIndex)
  lexer.index += count
  lexer.pos += count
  if text notin Conditions:
    var e = newException(LexingError, "Invalid condition!")
    e.line = lexer.line
    e.pos = lexer.pos - count
    e.index = lexer.index - count
    e.lineString = lexer.getLine()
    raise e
  else:
    lexer.initToken(text, Condition, count)

proc lexString(lexer: var Lexer): Token =
  var text: string
  while true:
    var t: string
    let c = lexer.input.parseUntil(t, {'"', '\\', '\n'}, lexer.index)
    lexer.index += c
    lexer.pos += c
    text &= t
    if lexer.peek() == '"':
      discard lexer.getOne()
      break
    elif lexer.peek() == '\n':
      text &= '\n'
      lexer.pos = 1
      lexer.line.inc
    else:
      discard lexer.getOne()
      let next = lexer.getOne()
      case next:
        of 'n': text &= '\n'
        of 'r': text &= '\r'
        of '0': text &= '\0'
        of 't': text &= '\t'
        of 'x': 
          let x1 = lexer.getOne()
          let x2 = lexer.getOne()
          var v = case x1:
            of '0'..'9': x1.byte - '0'.byte
            of 'a'..'f': 0xa'u8 + x1.byte - 'a'.byte
            of 'A'..'F': 0xA'u8 + x1.byte - 'A'.byte
            else:
              var e = newException(LexingError, "Invalid escape sequence!")
              e.line = lexer.line
              e.pos = lexer.pos
              e.index = lexer.index
              e.lineString = lexer.getLine()
              raise e
          v = v shl 4 or (case x2:
            of '0'..'9': x1.byte - '0'.byte
            of 'a'..'f': 0xa'u8 + x1.byte - 'a'.byte
            of 'A'..'F': 0xA'u8 + x1.byte - 'A'.byte
            else:
              var e = newException(LexingError, "Invalid escape sequence!")
              e.line = lexer.line
              e.pos = lexer.pos
              e.index = lexer.index
              e.lineString = lexer.getLine()
              raise e)
          text &= v.char
        else: text &= next
  lexer.initToken(text, String, text.len + 2)

proc lexDirective(lexer: var Lexer): Token =
  let startIndex = lexer.index
  var text: string
  let count = lexer.input.parseIdent(text, start = startIndex)
  lexer.index += count
  lexer.pos += count
  text = text.toUpperAscii()
  if text notin Directives:
    var e = newException(LexingError, "Invalid directive!")
    e.line = lexer.line
    e.pos = lexer.pos - count
    e.index = lexer.index - count
    e.lineString = lexer.getLine()
    raise e
  else:
    result = lexer.initToken(text, Directive, count)

proc lexToken(lexer: var Lexer): Token =
  if lexer.peek().isSpaceAscii:
    if lexer.skipWhitespace():
      return lexer.initToken("", Newline, 0)

  let c = lexer.peek()
  if c == ';':
    let count = lexer.input.skipUntil('\n', lexer.index)
    lexer.index += count + 1
    lexer.line.inc
    lexer.pos = 1
    return lexer.initToken("", Newline, 0)
  elif c.isDigit:
    return lexer.lexNumber()
  elif c.isAlphaAscii or c == '_':
    return lexer.lexWord()
  else:
    discard lexer.getOne()
    case c:
      of '*': return lexer.initToken("*", FreezeFlags, 1)
      of '?': return lexer.lexCondition()
      of '"': return lexer.lexString() 
      of '#': return lexer.lexDirective()
      of '\0': return lexer.initToken("", Eof, 0)
      of '(': return lexer.initToken("(", LeftParen, 1)
      of ')': return lexer.initToken(")", RightParen, 1)
      of '[': return lexer.initToken("[", LeftBracket, 1)
      of ']': return lexer.initToken("]", RightBracket, 1)
      of '+': return lexer.initToken("+", Plus, 1)
      of '-': return lexer.initToken("-", Minus, 1)
      of ',': return lexer.initToken(",", Comma, 1)
      else:
        var e = newException(LexingError, "Invalid token!")
        e.line = lexer.line
        e.pos = lexer.pos - 1
        e.index = lexer.index - 1
        e.lineString = lexer.getLine()
        raise e
  

proc lex*(input: string): TokenList =
  var lexer = Lexer(line: 1, pos: 1, index: 0, input: input)
  while true:
    let t = lexer.lexToken()
    if t.kind == Eof:
      if result[^1].kind != Newline:
        lexer.pos = 1
        lexer.line.inc
        result.add lexer.initToken("", Newline, 0)
      return
    result.add t