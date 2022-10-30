import strformat, strutils, parseutils, macros, sequtils
import ../ast, ../cpuData
from math import isPowerOfTwo
from bitops import fastLog2

type 
  GenerationError* = object of Exception
    line, pos, index: int
  Generator = object
    currentFunc: FuncDeclNode
    currentLabelCounter: int
    output: string
    outputData, outputRodata, outputBss: string
    breakStack, continueStack: seq[string]
    shouldOptimize: bool
  AddressKind {.pure.} = enum
    RelativeFP
    Label
    Expression
  Address = object
    offset: int
    case kind: AddressKind:
      of RelativeFP: fpOffset: int
      of Label: label: string
      of Expression: exp: ExpressionNode

proc reportError*(e: GenerationError, input: string): string =
  result = "Generation Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(n: AstNode, text: string) {.noReturn.} =
  var e = newException(GenerationError, text)
  e.line = n.line
  e.pos = n.pos
  e.index = n.index
  raise e

proc initGenerator(shouldOptimize: bool): Generator =
  result.currentFunc = nil
  result.currentLabelCounter = 1
  result.output = "#text\p"
  result.outputData = "#data\p"
  result.outputRodata = "#rodata\p"
  result.outputBss = "#bss\p"
  result.shouldOptimize = shouldOptimize

proc generateLabel(g: var Generator, s: string): string =
  let name = if g.currentFunc.isNil(): "" else: g.currentFunc.name
  result = "_" & name & "_" & s & "_" & $ g.currentLabelCounter
  g.currentLabelCounter += 1

proc isOneLevel(exp: ExpressionNode): bool {.locks: 0.} =
  if (exp of ConstNumberNode) or (exp of ResolvedVarNode):
    return true
  elif exp of AssignExprNode:
    if exp.AssignExprNode.exp of DereferenceExprNode: 
      return false
    return exp.AssignExprNode.exp.isOneLevel() and exp.AssignExprNode.variable.isOneLevel()
  elif exp of UnaryExprNode:
    if exp.UnaryExprNode.operator in ["++", "--"]: return false
    return exp.UnaryExprNode.exp.isOneLevel()
  elif exp of DereferenceExprNode:
    return exp.DereferenceExprNode.exp.isOneLevel()
  elif exp of AddressExprNode:
    return exp.AddressExprNode.exp.isOneLevel()
  elif exp of ConvertExprNode:
    return exp.ConvertExprNode.exp.isOneLevel()
  elif (exp of BinaryRightConstExprNode) and 
      (exp.BinaryRightConstExprNode.operator in 
        ["||", "&&", "+", "-", "&", "^", "|", "==", "!=", "<", ">=", "<<", ">>"]):
    return exp.BinaryRightConstExprNode.exp1.isOneLevel()
  return false

method generate(ast: AstNode, g: var Generator) {.base, locks: 0.} =
  raise newException(Exception, "Unknown AST Node!")
method generate(ast: ExpressionNode, g: var Generator, target: Register) {.base, locks: 0.} =
  raise newException(Exception, "Unknown Expression Node!")
method generate(ast: ExpressionNode, g: var Generator) {.locks: 0.} = ast.generate(g, Register(1))
method jumpIf(ast: ExpressionNode, g: var Generator, ifTrue, ifFalse: string) {.base, locks: 0.}
method getAddress(ast: ExpressionNode, g: var Generator): Address {.base, locks: 0.}
when not declared(IncludeFix):
  method jumpIf(ast: ExpressionNode, g: var Generator, ifTrue, ifFalse: string) {.base, locks: 0.} = discard
  method getAddress(ast: ExpressionNode, g: var Generator): Address {.base, locks: 0.} = discard

type ImplementTypeData = object
  simpleTypes: seq[SimpleTypeKind]
  ptrType: bool

proc parseTableBody(table: NimNode): ImplementTypeData =
  table.expectKind(nnkTableConstr)
  for n in table:
    n.expectKind(nnkExprColonExpr)
    let label = n[0]
    let data = n[1]
    label.expectKind(nnkIdent)
    case label.strVal:
      of "simpleType":
        data.expectKind(nnkBracket)
        for t in data:
          t.expectKind(nnkIdent)
          let simpleKind = parseEnum[SimpleTypeKind](t.strVal)
          result.simpleTypes.add simpleKind
      of "ptrType":
        data.expectKind(nnkIdent)
        result.ptrType = data.strVal == "true"
      else: error("Can only use simpleType", label)

macro defineChooseByType*(defs: untyped): untyped =
  var resultDefinitions: seq[NimNode]
  for def in defs:
    #echo "DEF:"
    #echo def.astGenRepr
    let isMethod = 
      if def.kind == nnkMethodDef: true
      else:
        def.expectKind(nnkProcDef)
        false
    let funcNameNode = def[0]
    let funcName = funcNameNode.basename.strVal
    var params = def[3].toSeq()
    let returnType = params[0]
    let elseAddition = 
      if returnType.kind == nnkIdent:
        "\ndefault(" & returnType.strVal & ")"
      else: ""
    let pragmas = def[4]
    var args: seq[NimNode]
    var assertFuncName = funcName
    for param in params[1..^1]:
      args.add param[0..^3]
      if param[0].strVal == "ast":
        assertFuncName = funcName & "(" & param[^2].toStrLit().strVal & ")"
    let initialBody = def[6]
    initialBody.expectKind(nnkStmtList)
    let table = initialBody[0]
    let implTypeData = table.parseTableBody()
    var simpleCases: seq[NimNode]
    for simpleTypeKind in implTypeData.simpleTypes:
      simpleCases.add  nnkOfBranch.newTree(
        ident($simpleTypeKind),
        newStmtList(
          newCall(funcName & $simpleTypeKind, args)
        )
      )
    let needElse = implTypeData.simpleTypes.len < SimpleTypeCount
    let simpleCaseOperator = nnkCaseStmt.newTree(
      @[newDotExpr(ident("t"), ident("simpleType"))] &
      simpleCases &
      (if needElse:
        @[nnkElse.newTree(
          parseStmt("assert(false, &\"Type {t} at " & assertFuncName & "\")" & elseAddition)
        )] else: newSeq[NimNode]())
    )
    let mainCase = nnkCaseStmt.newTree(
      newDotExpr(ident("t"), ident("kind")),
      nnkOfBranch.newTree(
        ident("UnknownType"), parseStmt("assert(false, \"Unknown type at " & assertFuncName & "\")" & elseAddition)
      ),
      nnkOfBranch.newTree(
        ident("VoidType"), parseStmt("assert(false, \"Void type at " & assertFuncName & "\")" & elseAddition)
      ),
      nnkOfBranch.newTree(
        ident("FunctionType"), parseStmt("assert(false, \"Function type at " & assertFuncName & "\")" & elseAddition)
      ),
      nnkOfBranch.newTree(
        ident("StructType"), parseStmt("assert(false, \"Struct type at " & assertFuncName & "\")" & elseAddition)
      ),
      nnkOfBranch.newTree(
        ident("ArrayType"), ident("ArrayOfUnknownSizeType"), 
        parseStmt("assert(false, \"Array type at " & assertFuncName & "\")" & elseAddition)
      ),
      nnkOfBranch.newTree(
        ident("PointerType"), 
          if implTypeData.ptrType:
            newStmtList(
              newCall(funcName & "Pointer", args)
            )
          else:
            parseStmt("assert(false, &\"Type {t} at " & assertFuncName & "\")" & elseAddition)
      ),
      nnkOfBranch.newTree(
        ident("SimpleType"), newStmtList(simpleCaseOperator)
      )
    )
    if isMethod:
      let procBody = newStmtList(
        parseStmt("let t = ast.typeData"),
        mainCase)
      resultDefinitions.add newProc(
        funcNameNode, params, procBody, nnkMethodDef, pragmas
      )
    else:
      let procBody = newStmtList(mainCase)
      params.add newIdentDefs(
        ident("t"), 
        ident("TypeData"),
        newEmptyNode())
      resultDefinitions.add newProc(
        funcNameNode, params, procBody, nnkProcDef, pragmas
      )
  result = newStmtList(resultDefinitions)
  #echo result.toStrLit()

proc isOneLevelConstMult(x: int): bool {.locks: 0.} =
  if x == 0: return true
  if x < 0: return isOneLevelConstMult(-x)
  return false

proc multiplyByConst(g: var Generator, r: Register, num: int) {.locks: 0.} =
  if num == 0:
    g.output &= &"  MOV {r}, R0\p"
    return
  let otherReg = if r == Register(1): Register(2) else: Register(1)
  if num == 1: discard
  elif num == -1:
    g.output &= &"  SUB {r}, R0, {r}\p"
  elif isPowerOfTwo(num):
    let shift = fastLog2(num)
    g.output &= &"  ASHI {r}, {shift}\p"
  elif isPowerOfTwo(-num):
    let shift = fastLog2(-num)
    g.output &= 
      &"  SUB {r}, R0, {r}\p" &
      &"  ASHI {r}, {shift}\p"
  else: g.output &= 
    &"  LOAD {otherReg}, {num and 0xFFFFFFFF}\p" &
    &"  MLTS {r}, {otherReg}\p" &
    &"  MOV {r}, LO\p"

proc loadAddr(address: Address, g: var Generator, r: Register, includeOffset: bool) =
  let offset = address.offset
  case address.kind:
    of Label:
      if offset != 0 and includeOffset:
        g.output &= &"  LOAD {r}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {r}, {address.label}\p"
    of RelativeFP:
      g.output &= &"  ADDI {r}, FP, {offset + address.fpOffset}\p"
    of Expression:
      address.exp.generate(g, r)
      if offset != 0 and includeOffset:
        g.output &= &"  ADDI {r}, {offset}\p"

proc toSignedByte(num: int64): int64 =
  if num >= -128 and num < 256:
    return num
  else:
    if (num and 0x80) != 0: return (num and 0xFF) - 256
    else: return num and 0xFF

proc toSignedHalfWord(num: int64): int64 =
  if num >= -65536 and num < 65536:
    return num
  else:
    if (num and 0x8000) != 0: return (num and 0xFFFF) - 65536
    else: return num and 0xFFFF

proc toSignedWord(num: int64): int64 =
  if num >= -0x100000000 and num < 0x100000000:
    return num
  else:
    if (num and 0x80000000) != 0: return (num and 0xFFFFFFFF) - 0x100000000
    else: return num and 0xFFFFFFFF