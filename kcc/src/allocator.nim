import ast, typeResolver
import tables, strutils, parseutils

type
  Allocator = object
    localVarTableStack: VariableTableStack
    globalVarTable: VariableTable
    isGlobal: bool
  AllocationError* = object of Exception
    line, pos, index: int
  VariableData = object
    name: string
    typeData: TypeData
    offset: int
    isGlobal: bool
  VariableTable = object
    t: Table[string, VariableData]
    currentOffset: int
    maxOffset: int
    funcParamOffset: int
  VariableTableStack = seq[VariableTable]
  VariableKind {.pure.} = enum
    Local
    Global
    Parameter

const
  WordSize = 4
  StartOffset = 3
  ParameterStartOffset = 8

proc reportError*(e: AllocationError, input: string): string =
  result = "Allocation Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(ast: AstNode, text: string) {.noReturn.} =
  var e = newException(AllocationError, text)
  e.line = ast.line
  e.pos = ast.pos
  e.index = ast.index
  raise e

proc addTable(s: var VariableTableStack) =
  let t = initTable[string, VariableData]()
  if s.len == 0:
    s = @[
      VariableTable(
        t: t,
        currentOffset: StartOffset,
        maxOffset: 0,
        funcParamOffset: ParameterStartOffset
        )
      ]
  else:
    s.add VariableTable(
      t: t,
      currentOffset: s[^1].currentOffset,
      maxOffset: s[^1].maxOffset,
      funcParamOffset: ParameterStartOffset
      )

proc popTable(s: var VariableTableStack) {.inline.} =
  if s.len > 1:
    if abs(s[^1].maxOffset) > abs(s[^2].maxOffset):
      s[^2].maxOffset = s[^1].maxOffset
  discard s.pop()

proc alignAddress(address: int, down: bool, align: int): int =
  result = address
  if down:
    while result mod align != 0:
      result.dec
  else:
    while result mod align != 0:
      result.inc

proc calcOffset(typeData: TypeData, offset: var int, kind: VariableKind): int =
  #echo typeData
  let size = typeData.getSize()
  let align = if kind == Parameter: WordSize else: typeData.getAlign()
  #echo align
  let down = kind == Local
  if down:
    #echo "Start: ", offset
    offset -= size
    #echo "-size: ", offset
    offset = alignAddress(offset + 1, true, align) - 1
    #echo "aligned: ", offset
    result = offset + 1
    #echo "result: ", result
  else:
    result = offset
    offset += size
    offset = alignAddress(offset, false, align)
proc addVar(s: var VariableTableStack, name: string, typeData: TypeData, 
    kind: VariableKind, ast: AstNode): int  =
  if name in s[^1].t:
    ast.raiseError("Variable with name " & name & " is already defined!")
  result = case kind: 
    of Local, Global: calcOffset(typeData, s[^1].currentOffset, kind)
    of Parameter: calcOffset(typeData, s[^1].funcParamOffset, kind)
  s[^1].t.add(name, 
    VariableData(
      name: name, 
      typeData: typeData,
      offset: result, 
      isGlobal: kind == Global
      ))
  
  if kind == Local:
    let alignedOffset = min(s[^1].currentOffset.alignAddress(true, WordSize), 0)
    if abs(alignedOffset) > abs(s[^1].maxOffset):
      s[^1].maxOffset = alignedOffset
  elif kind == Global:
    if s[^1].currentOffset > s[^1].maxOffset:
      s[^1].maxOffset = s[^1].currentOffset

proc addVar(s: var VariableTable, name: string, typeData: TypeData, 
    kind: VariableKind, ast: AstNode): int  =
  if name in s.t:
    ast.raiseError("Variable with name " & name & " is already defined!")
  result = case kind: 
    of Local, Global: calcOffset(typeData, s.currentOffset, kind)
    of Parameter: calcOffset(typeData, s.funcParamOffset, kind)
  s.t.add(name, 
    VariableData(
      name: name, 
      typeData: typeData,
      offset: result, 
      isGlobal: kind == Global
      ))

proc findVar(s: VariableTableStack, name: string): Option[VariableData] =
  for i in countdown(s.len-1, 0):
    if name in s[i].t:
      return s[i].t[name].some()
  return none(VariableData)

proc findVar(a: Allocator, name: string, ast: AstNode): VariableData =
  let d = a.localVarTableStack.findVar(name)
  if d.isSome(): return d.get()
  if name notin a.globalVarTable.t:
    ast.raiseError("No variable with name " & name & "!")
  return a.globalVarTable.t[name]

method allocateStack(ast: AstNode, a: var Allocator): AstNode {.base, locks: 0.} =
  template check(iter, t: untyped): untyped =
    for sub in ast.iter:
      let n = allocateStack(sub, a)
      if not n.isNil():
        sub = n.t
  a.isGlobal = false
  check(mdecls, DeclarationNode)
  check(mexps, ExpressionNode)
  check(mstats, StatementNode)
  check(mblockItems, BlockItemNode)

proc adjustParameterType(t: TypeData): TypeData =
  if t.kind == ArrayOfUnknownSizeType or t.kind == ArrayType:
    TypeData(kind: PointerType, ptrType: t.elemType)
  else:
    t

method allocateStack(ast: FuncDeclNode, a: var Allocator): AstNode =
  a.localVarTableStack.addTable()
  for p in ast.params.mitems:
    template param: untyped = p.VarDeclNode
    param.typeData = param.typeData.adjustParameterType()
    param.offset = 
      a.localVarTableStack.addVar(
        param.varName, 
        param.typeData, 
        Parameter, ast)
  discard procCall allocateStack(ast.AstNode, a)
  ast.maxStack = uint32(-a.localVarTableStack[^1].maxOffset)
  a.localVarTableStack.popTable()
method allocateStack(ast: BlockNode, a: var Allocator): AstNode =
  a.localVarTableStack.addTable()
  discard procCall allocateStack(ast.AstNode, a)
  a.localVarTableStack.popTable()
method allocateStack(ast: ForStatNode, a: var Allocator): AstNode =
  if ast.kind == ForWithDecl:
    a.localVarTableStack.addTable()
    discard procCall allocateStack(ast.AstNode, a)
    a.localVarTableStack.popTable()
  else:
    discard procCall allocateStack(ast.AstNode, a)

method allocateStack(ast: VarNode, a: var Allocator): AstNode =
  let astVar = ast
  let name = astVar.varName
  let d = a.findVar(name, ast)
    
  return ResolvedVarNode(
    line: ast.line, pos: ast.pos, index: ast.index,
    typeData: d.typeData,
    varName: name,
    offset: d.offset,
    isGlobal: d.isGlobal
  )

method allocateStack(ast: VarDeclNode, a: var Allocator): AstNode =
  if ast.init.isSome():
    let wereGlobal = a.isGlobal
    a.isGlobal = false
    let n = ast.init.get().allocateStack(a)
    if not n.isNil():
      ast.init = n.ExpressionNode.some()
    a.isGlobal = wereGlobal
    let init = ast.init.get()
    if init of ArrayInitializerNode:
      discard init.ArrayInitializerNode.fixArrayInit(ast.typeData, 0, true)
    elif ast.typeData.kind == ArrayOfUnknownSizeType and init of StringLiteralNode:
      ast.typeData = TypeData(
        kind: ArrayType, 
        elemType: ast.typeData.elemType, 
        elemCount: init.typeData.elemCount)
  if a.isGlobal:
    ast.offset = a.globalVarTable.addVar(ast.varName, ast.typeData, Global, ast)
  else:
    ast.offset = a.localVarTableStack.addVar(ast.varName, ast.typeData, Local, ast)
  ast.isGlobal = a.isGlobal

proc allocateStack*(ast: ProgramNode) =
  var a: Allocator
  for n in ast.declarations:
    a.isGlobal = true
    discard n.allocateStack(a)