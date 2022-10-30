import strutils, parseutils
import token

type
  Lexer = object
    input: string
    line, pos: int
    index: int
  LexingError* = object of Exception
    line, pos, index: int

proc reportError*(e: LexingError, input: string): string =
  result = "Lexing Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"
proc raiseError(lexer: Lexer, msg: string, correction: int) {.noReturn.} =
  var e = newException(LexingError, msg)
  e.line = lexer.line
  e.pos = lexer.pos - correction
  e.index = lexer.index - correction
  raise e
  
proc peek(lexer: Lexer): char {.inline.} =
  if lexer.index == lexer.input.len():
    '\0'
  else:
    lexer.input[lexer.index]

proc advance(lexer: var Lexer) {.inline.} =
  lexer.index.inc
  lexer.pos.inc

proc unwind(lexer: var Lexer) {.inline.} =
  lexer.index.dec
  lexer.pos.dec

proc getOne(lexer: var Lexer): char {.inline.} =
  result = lexer.peek()
  lexer.advance()

#[proc getText(lexer: Lexer, startIndex: int): string {.inline.} =
  result = lexer.input[startIndex..(lexer.index - 1)]
]#

proc initKeyword(lexer: Lexer, kind: KeywordKind, correction: int): Token {.inline.} =
  Token(
    kind: Keyword,
    keyword: kind,
    line: lexer.line,
    pos: lexer.pos - correction,
    index: lexer.index - correction
  )
proc initIdent(lexer: Lexer, text: string, correction: int): Token {.inline.} =
  Token(
    kind: Identifier,
    identText: text,
    line: lexer.line,
    pos: lexer.pos - correction,
    index: lexer.index - correction
  )
proc initSymbol(lexer: Lexer, text: string, correction: int): Token {.inline.} =
  Token(
    kind: Symbol,
    symbol: text,
    line: lexer.line,
    pos: lexer.pos - correction,
    index: lexer.index - correction
  )
proc initNumConst(lexer: Lexer, num: int64, correction: int): Token {.inline.} =
  Token(
    kind: NumberConstant,
    num: num,
    line: lexer.line,
    pos: lexer.pos - correction,
    index: lexer.index - correction
  )
proc initCharConst(lexer: Lexer, character: char, correction: int): Token {.inline.} =
  Token(
    kind: CharacterConstant,
    character: character,
    line: lexer.line,
    pos: lexer.pos - correction,
    index: lexer.index - correction
  )
proc initStringConst(lexer: Lexer, str: string, correction: int): Token {.inline.} =
  Token(
    kind: StringConstant,
    str: str,
    line: lexer.line,
    pos: lexer.pos - correction,
    index: lexer.index - correction
  )
proc initEof(lexer: Lexer): Token {.inline.} =
  Token(
    kind: Eof,
    line: lexer.line,
    pos: lexer.pos,
    index: lexer.index
  )

proc lexWord(lexer: var Lexer): Token =
  var text: string
  let count = lexer.input.parseIdent(text, start = lexer.index)
  lexer.index += count
  lexer.pos += count
  if text in Keywords:
    let index = Keywords.find(text)
    return lexer.initKeyword(index.KeywordKind, count)
  else:
    return lexer.initIdent(text, count)

proc lexDec(lexer: var Lexer, startIndex: int): Token =
  var val = 0'i64
  while true:
    let c = lexer.peek()
    if c notin {'0'..'9'}:
      if val == 0:
        lexer.raiseError("Invalid number constant!", lexer.index - startIndex)
      else:
        return lexer.initNumConst(val, lexer.index - startIndex)
    else:
      val = (c.int64 - '0'.int64) + val * 10
    lexer.advance()

proc lexOct(lexer: var Lexer, startIndex: int): Token =
  var val = 0'i64
  while true:
    let c = lexer.peek()
    if c notin {'0'..'7'}:
      if val == 0:
        lexer.raiseError("Invalid number constant!", lexer.index - startIndex)
      else:
        return lexer.initNumConst(val, lexer.index - startIndex)
    else:
      val = (c.int64 - '0'.int64) + val * 8
    lexer.advance()

proc lexHex(lexer: var Lexer, startIndex: int): Token =
  var val = 0'i64
  while true:
    let c = lexer.peek()
    if c in {'0'..'9'}:
      val = (c.int64 - '0'.int64) + val * 16
    elif c in {'A'..'F'}:
      val = (c.int64 - 'A'.int64 + 10) + val * 16
    elif c in {'a'..'f'}:
      val = (c.int64 - 'a'.int64 + 10) + val * 16
    else:
      if val == 0:
        lexer.raiseError("Invalid number constant!", lexer.index - startIndex)
      else:
        return lexer.initNumConst(val, lexer.index - startIndex)
    lexer.advance()
      

proc lexNum(lexer: var Lexer): Token =
  let startIndex = lexer.index
  let c1 = lexer.peek()
  if c1 == '0':
    lexer.advance()
    let c2 = lexer.peek()
    case c2:
      of 'x', 'X': 
        lexer.advance()
        return lexer.lexHex(startIndex)
      of '0'..'9':
        return lexer.lexOct(startIndex)
      else:
        return lexer.initNumConst(0, 1)
  else:
    return lexer.lexDec(startIndex)

proc skipWhitespaceAndComments(lexer: var Lexer) =
  while true:
    let c = lexer.peek()
    if c in {' ', '\t', '\r'}:
      lexer.advance()
    elif c == '\n':
      lexer.pos = 1
      lexer.index += 1
      lexer.line += 1
    elif c == '/':
      lexer.advance()
      let c2 = lexer.peek()
      if c2 == '/':
        lexer.advance()
        while true:
          let c = lexer.getOne()
          if c == '\n':
            lexer.pos = 1
            lexer.line += 1
            break
      elif c2 == '*':
        lexer.advance()
        while true:
          let c = lexer.getOne()
          if c == '\n':
            lexer.pos = 1
            lexer.line += 1
          elif c == '*':
            if lexer.peek() == '/':
              lexer.advance()
              break
      else:
        lexer.unwind()
        return
    else:
      return

proc lexEscapeSeq(lexer: var Lexer, startIndex: int): char =
  let c = lexer.peek()
  if c notin '0'..'7':
    lexer.advance()
  case c:
    of '\'': '\''
    of '"': '"'
    of '?': '?'
    of '\\': '\\'
    of 'a': '\a'
    of 'b': '\b'
    of 'f': '\f'
    of 'n': '\n'
    of 'r': '\r'
    of 't': '\t'
    of 'v': '\v'
    of '0'..'7': 
      let t = lexer.lexOct(startIndex)
      char(t.num and 0xFF)
    of 'x': 
      let t = lexer.lexHex(startIndex)
      char(t.num and 0xFF)
    else:
      lexer.raiseError("Invalid escape sequence!", lexer.index - startIndex)

proc lexChar(lexer: var Lexer): Token =
  let startIndex = lexer.index
  lexer.advance()
  let c = lexer.getOne()
  if c == '\n':
    lexer.raiseError("Invalid character constant!", lexer.index - startIndex)
  elif c != '\\':
    if lexer.getOne() != '\'':
      lexer.raiseError("Invalid character constant!", lexer.index - startIndex)
    return lexer.initCharConst(c, lexer.index - startIndex)
  else:
    lexer.advance()
    let c1 = lexer.lexEscapeSeq(startIndex)
    if lexer.getOne() != '\'':
      lexer.raiseError("Invalid character constant!", lexer.index - startIndex)
    return lexer.initCharConst(c1, lexer.index - startIndex)

proc lexString(lexer: var Lexer): Token =
  let startIndex = lexer.index
  lexer.advance()
  var str = ""
  while true:
    let c = lexer.getOne()
    if c == '\"':
      break
    elif c == '\n':
      lexer.raiseError("Invalid string constant!", lexer.index - startIndex)
    elif c != '\\':
      str.add c
    else:
      lexer.advance()
      str.add lexer.lexEscapeSeq(lexer.index - 1)
  lexer.initStringConst(str, lexer.index - startIndex)

proc lexToken*(lexer: var Lexer): Token =
  lexer.skipWhitespaceAndComments()
  let c = lexer.peek()
  if c == '\0':
    return lexer.initEof()
  elif c.isAlphaAscii() or c == '_':
    return lexer.lexWord()
  elif c.isDigit():
    return lexer.lexNum()
  elif c == '\'':
    return lexer.lexChar()
  elif c == '\"':
    return lexer.lexString()
  else:
    case c:
      of '<', '>': # c, c=, cc, cc=
        lexer.advance()
        if lexer.peek() == '=':
          lexer.advance()
          return lexer.initSymbol($c & '=', 2)
        elif lexer.peek() == c:
          lexer.advance()
          if lexer.peek() == '=':
            lexer.advance()
            return lexer.initSymbol($c & $c & '=', 3)
          else:
            return lexer.initSymbol($c & $c, 2)
        else:
          return lexer.initSymbol($c, 1)
      of '&', '|', '+': # c, c=, cc
        lexer.advance()
        if lexer.peek() == '=':
          lexer.advance()
          return lexer.initSymbol($c & '=', 2)
        elif lexer.peek() == c:
          lexer.advance()
          return lexer.initSymbol($c & $c, 2)
        else:
          return lexer.initSymbol($c, 1)
      of '-': # c, c=, cc, c>
        lexer.advance()
        if lexer.peek() == '=':
          lexer.advance()
          return lexer.initSymbol($c & '=', 2)
        elif lexer.peek() == '>':
          lexer.advance()
          return lexer.initSymbol($c & '>', 2)
        elif lexer.peek() == c:
          lexer.advance()
          return lexer.initSymbol($c & $c, 2)
        else:
          return lexer.initSymbol($c, 1)
      of '!', '*', '/', '%', '^', '=': # c, c=
        lexer.advance()
        if lexer.peek() == '=':
          lexer.advance()
          return lexer.initSymbol($c & '=', 2)
        else:
          return lexer.initSymbol($c, 1)
      of '(', ')', '[', ']', '{', '}', ':', ';', '~', ',', '?', '.':  # c
        lexer.advance()
        return lexer.initSymbol($c, 1)
      else: lexer.raiseError("Unknown symbol!", 0)

proc lex*(input: string): TokenSequence =
  var lexer = Lexer(input: input, line: 1, pos: 1, index: 0)
  while lexer.index < input.len:
    let t = lexer.lexToken()
    result.add t
    if t.kind == Eof:
      return
  result.add lexer.initEof()