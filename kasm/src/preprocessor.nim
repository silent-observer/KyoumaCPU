import token, lexer, strutils, parseutils

type PreprocessingError* = object of Exception
  line, pos, index: int

proc reportError*(e: PreprocessingError, input: string): string =
  result = "Preprocessing Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(t: Token, text: string) {.noReturn.} =
  var e = newException(PreprocessingError, text)
  e.line = t.line
  e.pos = t.pos
  e.index = t.index
  raise e

proc preprocess*(input: TokenList): TokenList =
  var i = 0
  while i < input.len:
    if input[i].kind != Directive:
      result.add input[i]
      i += 1
    else:
      let t = input[i].text.toUpperAscii
      if t == "INCLUDE":
        let s = input[i + 1]
        if s.kind != String:
          s.raiseError("#include argument should be a string")
        try:
          let data = s.text.readFile()
          let tokens = data.lex()
          result.add tokens
        except IOError:
          s.raiseError("Error reading file " & s.text)
        i += 3
      if t in ["TEXT", "DATA", "RODATA", "BSS"]:
        result.add input[i]
        i += 1
      elif t in ["ALIGN"]:
        result.add input[i]
        if input[i+1].kind != Number:
          input[i+1].raiseError("#align argument should be a number")
        result.add input[i + 1]
        i += 2
      else:
        input[i].raiseError("Unknown assembler directive")