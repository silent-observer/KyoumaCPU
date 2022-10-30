import ast
import tables, strutils, parseutils, strformat
from sequtils import repeat

type
  StructData = object
    id: int
    typeData: TypeData
    line: int
  StructTable = object
    t: Table[string, int]
    data: seq[StructData]
  StructTableStack = seq[StructTable]
  StructResolver = object
    structTableStack: StructTableStack
  StructTypeError* = object of Exception
    line, pos, index: int

proc reportError*(e: StructTypeError, input: string): string =
  result = "Struct Type Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(ast: AstNode, text: string) {.noReturn.} =
  var e = newException(StructTypeError, text)
  e.line = ast.line
  e.pos = ast.pos
  e.index = ast.index
  raise e

proc addTable(s: var StructTableStack) =
  let t = initTable[string, int]()
  if s.len == 0:
    s = @[
      StructTable(
        t: t,
        data: @[]
        )
      ]
  else:
    s.add StructTable(
      t: t,
      data: @[]
      )

proc popTable(s: var StructTableStack) {.inline.} =
  discard s.pop()

proc initStructResolver(): StructResolver =
  result.structTableStack.addTable()

proc addStruct(s: var StructTable, name: string, typeData: TypeData, ast: AstNode)  =
  if name in s.t:
    ast.raiseError("Struct with name " & name & " is already defined!")
  let id = s.data.len
  s.data.add StructData(id: id, typeData: typeData, line: ast.line)
  s.t.add(name, id)

proc addStruct(s: var StructTableStack, name: string, typeData: TypeData, ast: AstNode) =
  s[^1].addStruct(name, typeData, ast)

proc findStruct(s: StructTableStack, name: string): Option[StructData] =
  for i in countdown(s.len-1, 0):
    if name in s[i].t:
      let id = s[i].t[name]
      return s[i].data[id].some()
  return none(StructData)

proc findStruct(r: StructResolver, name: string, ast: AstNode): StructData =
  let d = r.structTableStack.findStruct(name)
  if d.isSome(): 
    return d.get()
  else: 
    ast.raiseError("No struct with name " & name & "!")

method resolveStructs(ast: AstNode, r: var StructResolver) {.base, locks: 0.} =
  template check(iter, t: untyped): untyped =
    for sub in ast.iter:
      resolveStructs(sub, r)
  check(mdecls, DeclarationNode)
  check(mexps, ExpressionNode)
  check(mstats, StatementNode)
  check(mblockItems, BlockItemNode)

proc allocateFields(data: StructAdditionalData) =
  data.ids = initTable[string, int]()
  var currentAlign = 1
  var currentOffset = 0
  for i, f in data.fields:
    let fieldSize = f.typeData.getSize()
    let fieldAlign = f.typeData.getAlign()
    while currentOffset mod fieldAlign != 0:
      currentOffset += 1
    f.offset = currentOffset
    data.ids.add(f.varName, i)
    currentOffset += fieldSize
    currentAlign = max(currentAlign, fieldAlign)
  data.align = currentAlign
  data.size = currentOffset

proc defineStruct(typeData: TypeData, ast: AstNode, r: var StructResolver) {.locks: 0.} =
  let name = typeData.structName
  let entry = r.structTableStack.findStruct(name)
  if entry.isSome():
    let line = entry.get().line
    ast.raiseError("Struct with name " & name & " is already defined at line " & $line & "!")
  r.structTableStack.addStruct(name, typeData, ast)
  for f in typeData.structAdditional.fields:
    f.resolveStructs(r)
  typeData.structAdditional.allocateFields()

method resolveStructs(ast: TypeDeclNode, r: var StructResolver) {.locks: 0.} =
  if ast.typeData.structIsDefined:
    ast.typeData.defineStruct(ast, r)
  else:
    let name = ast.typeData.structName
    let entry = r.findStruct(name, ast)
    ast.typeData.structAdditional = entry.typeData.structAdditional

proc resolveStructsInType(t: var TypeData, r: var StructResolver, ast: AstNode) {.locks: 0.} =
  case t.kind:
    of UnknownType, VoidType, SimpleType: return
    of PointerType: 
      t.ptrType[].resolveStructsInType(r, ast)
    of ArrayType, ArrayOfUnknownSizeType:
      t.elemType[].resolveStructsInType(r, ast)
    of FunctionType:
      t.funcReturnType[].resolveStructsInType(r, ast)
      for p in t.paramTypes.mitems:
        p.resolveStructsInType(r, ast)
    of StructType:
      if t.structIsDefined:
        t.defineStruct(ast, r)
      else:
        let name = t.structName
        let entry = r.findStruct(name, ast)
        t.structAdditional = entry.typeData.structAdditional

method resolveStructs(ast: VarDeclNode, r: var StructResolver) {.locks: 0.} =
  ast.typeData.resolveStructsInType(r, ast)

method resolveStructs(ast: FuncDeclNode, r: var StructResolver) =
  r.structTableStack.addTable()
  ast.returnType.resolveStructsInType(r, ast)
  for p in ast.params.mitems:
    p.resolveStructs(r)
  procCall resolveStructs(ast.AstNode, r)
  r.structTableStack.popTable()
method resolveStructs(ast: BlockNode, r: var StructResolver) =
  r.structTableStack.addTable()
  procCall resolveStructs(ast.AstNode, r)
  r.structTableStack.popTable()
method resolveStructs(ast: ForStatNode, r: var StructResolver) =
  if ast.kind == ForWithDecl:
    r.structTableStack.addTable()
    procCall resolveStructs(ast.AstNode, r)
    r.structTableStack.popTable()
  else:
    procCall resolveStructs(ast.AstNode, r)

proc resolveStructs*(ast: ProgramNode) =
  var r = initStructResolver()
  for n in ast.declarations:
    n.resolveStructs(r)