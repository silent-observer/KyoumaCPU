import lexer, token, ast, parser, generator, 
       allocator, verifier, optimizer, typeResolver,
       structResolver
import os, parseopt

const Optimize = true

proc compile*(input: string, output: string, print: bool = true): bool =
  let content = input.readFile()
  try:
    let tokens = content.lex()
    #echo "Tokens:"
    #for t in tokens:
    #  echo t
    
    let ast = tokens.parse()
    #if print:
    #  echo "\pAST:"
    #  echo ast

    if Optimize:
      ast.optimizeBeforeAlloc()
    
    ast.resolveStructs()

    #if print:
    #  echo "\pAST (resolved structs):"
    #  echo ast

    ast.verifyFuncs()

    ast.allocateStack()
    
    #if print:
    #  echo "\pAST (allocated):"
    #  echo ast
    
    ast.resolveTypes()

    #if print:
    #  echo "\pAST (typed):"
    #  echo ast

    if Optimize:
      ast.optimizeAfterTyping()
      if print:
        echo "\pAST (postoptimized):"
        echo ast
    
    let code = ast.generate(Optimize)
    if print:
      echo "\pCode:"
      echo code
    
    output.writeFile(code)
    return true
  except LexingError as e:
    echo e[].reportError(content)
  except ParsingError as e:
    echo e[].reportError(content)
  except VerificationError as e:
    echo e[].reportError(content)
  except TypeError as e:
    echo e[].reportError(content)
  except AllocationError as e:
    echo e[].reportError(content)
  except GenerationError as e:
    echo e[].reportError(content)
  return false

when isMainModule:
  var inputs: seq[string]
  var output = ""
  var p = initOptParser("")
  for kind, key, val in p.getopt():
    case kind:
      of cmdArgument: inputs.add key
      of cmdShortOption:
        if key == "o": output = val
        else: 
          echo "Syntax: kcc <input.c> [-o <output.kasm>]"
          quit(1)
      of cmdLongOption: 
        echo "Syntax: kcc <input.c> [-o <output.kasm>]"
        quit(1)
      of cmdEnd: discard
  if inputs.len == 0:
    echo "Syntax: kcc <input.c> [-o <output.kasm>]"
    quit(1)
  elif inputs.len == 1:
    if output == "":
      discard compile(inputs[0], inputs[0].changeFileExt(".kasm"))
    else:
      discard compile(inputs[0], output)
  else:
    if output != "":
      echo "Syntax: kcc <input.c> [-o <output.kasm>]"
      quit(1)
    else:
      for input in inputs:
        discard compile(input, input.changeFileExt(".kasm"))
  
