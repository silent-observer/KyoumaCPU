import ast, typeResolver
import tables, strutils, parseutils, strformat

type
  Verifier = object
    funcTable: Table[string, FuncData]
  VerificationError* = object of Exception
    line, pos, index: int
  FuncData = object
    name: string
    returnType: TypeData
    params: seq[ParameterData]
    isDefined: bool
    line: int
  ParameterData = object
    name: string
    typeData: TypeData

proc reportError*(e: VerificationError, input: string): string =
  result = &"Verification Error occured!\n{e.msg}\nLine {e.line}:\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(ast: AstNode, text: string) {.noReturn.} =
  var e = newException(VerificationError, text)
  e.line = ast.line
  e.pos = ast.pos
  e.index = ast.index
  raise e

proc initVerifier(): Verifier =
  result.funcTable = initTable[string, FuncData]()

proc paramsCompatible(a, b: seq[ParameterData]): bool =
  if a.len != b.len: return false
  for i in 0..<a.len:
    if not areCompatible(a[i].typeData, b[i].typeData):
      return false
  return true
proc testArgsCompatible(ast: AstNode, params: seq[ParameterData], args: seq[ExpressionNode]) =
  if params.len != args.len:
    ast.raiseError(&"Expected {params.len} parameters, but got {args.len}!")

method verifyFuncs(ast: AstNode, v: var Verifier) {.base, locks: 0.} =
  template check(iter, t: untyped): untyped =
    for sub in ast.iter:
      verifyFuncs(sub, v)
  check(mdecls, DeclarationNode)
  check(mexps, ExpressionNode)
  check(mstats, StatementNode)
  check(mblockItems, BlockItemNode)

method verifyFuncs(ast: FuncDeclNode, v: var Verifier) =
  let name = ast.name
  var params: seq[ParameterData]
  for p in ast.params:
    params.add ParameterData(name: p.VarDeclNode.varName, typeData: p.VarDeclNode.typeData)
  let newEntry = FuncData(
    name: name,
    params: params,
    returnType: ast.returnType,
    isDefined: ast.statements.isSome(),
    line: ast.line
  )
  if name in v.funcTable:
    let entry = v.funcTable[name]
    if newEntry.isDefined and entry.isDefined:
      ast.raiseError("Second definition of function " & name & 
                     " (First definition at line " & $entry.line & ")!")
    if not areCompatible(newEntry.returnType, entry.returnType):
      ast.raiseError("Return type of func " & name & 
                     "is not compatible with its declaration" & 
                     " (First declaration at line " & $entry.line & ")!")
    if not paramsCompatible(newEntry.params, entry.params):
      ast.raiseError("Parameters of func " & name & 
                     "are not compatible with its declaration" & 
                     " (First declaration at line " & $entry.line & ")!")
    if newEntry.isDefined:
      v.funcTable[name] = newEntry
  else:
    v.funcTable[name] = newEntry
  if ast.statements.isSome():
    for s in ast.statements.get().items:
      s.verifyFuncs(v)
method verifyFuncs(ast: FuncCallNode, v: var Verifier) =
  let name = ast.funcName
  if name notin v.funcTable:
    ast.raiseError("Calling undeclared function " & name & "!")
  let entry = v.funcTable[name]
  ast.testArgsCompatible(entry.params, ast.args)
  for param in entry.params:
    ast.paramTypes.add param.typeData
  ast.typeData = entry.returnType

proc verifyFuncs*(ast: ProgramNode) =
  var v: Verifier = initVerifier()
  for n in ast.declarations:
    n.verifyFuncs(v)