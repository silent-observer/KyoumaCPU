import ast, token, lexer, parser, replacer, generator, strformat, os, parseopt, preprocessor

const SyntaxString = """Syntax: kasm <input.kasm> [flags]
Available flags:
-v, --verbose - print more data
-b, --bin - output raw binary"""

when isMainModule:
  if paramCount() == 0:
    echo SyntaxString
    quit(1)
  var inFile: string
  var format = Elf
  var isVerbose = false

  for kind, key, val in getopt():
    if kind == cmdArgument:
      if inFile == "":
        inFile = key
      else:
        echo SyntaxString
        quit(1)
    else: 
      case key:
        of "v", "verbose": isVerbose = true
        of "b", "bin": format = Binary
        else:
          echo SyntaxString
          quit(1)
  
  let assembly = readFile(inFile)
  try:
    let tokens = assembly.lex()
    let preprocTokens = tokens.preprocess()
    
    var data = preprocTokens.parse(format)
    if isVerbose:
      echo "Labels:"
      for l in data.labelTable.labels:
        echo l
      
      echo "Instuctions:"
      for i in data.instrs:
        echo i
      
    
    data.replaceAll(format)

    if isVerbose:
      echo "\pReplaced instuctions:"
      for i in data.instrs:
        echo i
      
      echo "\pReplaced labels:"
      for i in data.labelTable.labels:
        echo i
      
      echo "\pRelocations:"
      for r in data.relocations:
        echo r

    let code = data.generate(format)
    let ext = case format:
      of Binary: ".bin"
      of Elf: ".obj"
    let outFile = inFile.changeFileExt(ext).open(fmWrite)
    defer: outFile.close()
    discard outFile.writeBytes(code, 0, code.len)

  except LexingError as e:
    echo e[].reportError()
  except ParsingError as e:
    echo e[].reportError(assembly)
  except ReplacementError as e:
    echo e[].reportError()
  except GenerationError as e:
    echo e[].reportError()