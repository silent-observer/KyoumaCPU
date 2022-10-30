import ast
import tables, strutils, parseutils, strformat
from sequtils import repeat

type
  TypeResolver = object
    currentReturnType: TypeData
  TypeError* = object of Exception
    line, pos, index: int

let 
  int32Type = TypeData(kind: SimpleType, simpleType: Int32)
  #uint32Type = TypeData(kind: SimpleType, simpleType: UInt32)
  unknownType = TypeData(kind: UnknownType)

proc reportError*(e: TypeError, input: string): string =
  result = "Type Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(ast: AstNode, text: string) {.noReturn.} =
  var e = newException(TypeError, text)
  e.line = ast.line
  e.pos = ast.pos
  e.index = ast.index
  raise e

proc isSignedType(a: TypeData): bool {.inline.} =
  a.kind == SimpleType and a.simpleType in {Int32, Int16, Int8}
#proc isUnsignedType(a: TypeData): bool {.inline.} =
#  a.kind == SimpleType and a.simpleType in {UInt32, UInt16, UInt8}
proc isIntegerType(a: TypeData): bool {.inline.} =
  a.kind == SimpleType and a.simpleType in {Int32, Int16, Int8, UInt32, UInt16, UInt8}
proc isArithmeticType(a: TypeData): bool {.inline.} =
  a.isIntegerType()
proc isScalarType(a: TypeData): bool {.inline.} =
  a.kind == PointerType or a.isArithmeticType()
proc isIncomplete(a: TypeData): bool {.inline.} =
  a.kind == ArrayOfUnknownSizeType or
  a.kind == StructType and a.structAdditional == nil
proc rank(a: TypeData): int =
  if not a.isIntegerType: return 0
  case a.simpleType:
    of Int8, UInt8: 2
    of Int16, UInt16: 3
    of Int32, UInt32: 4
proc toUnsigned(a: TypeData): TypeData =
  if not a.isIntegerType: return unknownType
  case a.simpleType:
    of Int8, UInt8: TypeData(kind: SimpleType, simpleType: UInt8)
    of Int16, UInt16: TypeData(kind: SimpleType, simpleType: UInt16)
    of Int32, UInt32: TypeData(kind: SimpleType, simpleType: UInt32)
proc canRepresentAll(dest, src: TypeData): bool =
  if dest.rank < src.rank: return false
  case dest.simpleType:
    of Int8: src.simpleType in {Int8}
    of UInt8: src.simpleType in {UInt8}
    of Int16: src.simpleType in {Int8, UInt8, Int16}
    of UInt16: src.simpleType in {UInt8, UInt16}
    of Int32: src.simpleType in {Int8, UInt8, Int16, UInt16, Int32}
    of UInt32: src.simpleType in {UInt8, UInt16, UInt32}

proc areCompatible*(a, b: TypeData): bool {.locks: 0.} =
  if a.kind == ArrayOfUnknownSizeType or b.kind == ArrayOfUnknownSizeType:
    let isAArray = a.kind in [ArrayType, ArrayOfUnknownSizeType]
    let isBArray = b.kind in [ArrayType, ArrayOfUnknownSizeType]
    return isAArray and isBArray and areCompatible(a.elemType[], b.elemType[])
  if a.kind == VoidType or b.kind == VoidType: return true
  
  if a.kind != b.kind: return false
  case a.kind:
    of UnknownType: return false
    of VoidType: return true
    of PointerType: return areCompatible(a.ptrType[], b.ptrType[])
    of ArrayType: return a.elemCount == b.elemCount and areCompatible(a.elemType[], b.elemType[])
    of ArrayOfUnknownSizeType: return false
    of SimpleType: return a.simpleType == b.simpleType
    of StructType:
      if a.structName != b.structName: return false
      if not a.structIsDefined or not b.structIsDefined: return true
      if a.structAdditional == nil or b.structAdditional == nil: return true
      let addA = a.structAdditional
      let addB = b.structAdditional
      if addA.fields.len != addB.fields.len: return false
      for i in 0..<addA.fields.len:
        if not areCompatible(addA.fields[i].typeData, addB.fields[i].typeData): return false
        if addA.fields[i].varName != addB.fields[i].varName: return false
      return true
    of FunctionType:
      if not areCompatible(a.funcReturnType[], b.funcReturnType[]):
        return false
      if a.paramTypes.len != b.paramTypes.len:
        return false
      for i in 0..<a.paramTypes.len:
        if not areCompatible(a.paramTypes[i], b.paramTypes[i]):
          return false
      return true

proc promoteType(a: TypeData): TypeData =
  if not a.isArithmeticType: return a
  if a.simpleType in {Int16, Int8, UInt16, UInt8}:
    return int32Type
  return a

proc arithmeticCommonType(a, b: TypeData): TypeData =
  if not a.isArithmeticType or not b.isArithmeticType: 
    return unknownType
  let aPromoted = a.promoteType()
  let bPromoted = b.promoteType()
  let aSig = aPromoted.isSignedType()
  let bSig = bPromoted.isSignedType()
  if areCompatible(aPromoted, bPromoted):
    return aPromoted
  if aSig == bSig:
    if aPromoted.rank > bPromoted.rank: 
      return aPromoted
    else:
      return bPromoted
  else:
    let (unsig, sig) = 
      if aSig: (bPromoted, aPromoted)
      else: (aPromoted, bPromoted)
    if unsig.rank >= sig.rank: return unsig
    elif sig.rank > unsig.rank:
      if sig.canRepresentAll(unsig): return sig
      else: return sig.toUnsigned()
  return unknownType

proc isImplicitlyConvertible*(t, target: TypeData): bool =
  if t.kind == VoidType: return false
  if areCompatible(t, target): return true
  if t.isIntegerType and target.isIntegerType: 
    return true
  return false

proc isCastable(t, target: TypeData): bool =
  if t.isImplicitlyConvertible(target): return true
  if t.kind == PointerType and target.isIntegerType(): return true
  if target.kind == PointerType and t.isIntegerType(): return true
  if target.kind == PointerType and t.kind == PointerType: return true
  return false

proc insertConvertIfNeeded(exp: var ExpressionNode, t: TypeData) =
  if areCompatible(exp.typeData, t): return
  if exp of ConstNumberNode:
    exp.typeData = t
  else:
    let convert = ConvertExprNode(typeData: t, exp: exp)
    convert.setBaseAstFields(exp)
    exp = convert
proc arrayToAddr(exp: var ExpressionNode) =
  if exp.typeData.kind != ArrayType: return
  let t = TypeData(kind: PointerType, ptrType: exp.typeData.elemType)
  let addrOp = AddressExprNode(typeData: t, exp: exp)
  addrOp.setBaseAstFields(exp)
  exp = addrOp
proc checkIncomplete(t: TypeData, ast: AstNode) {.locks: 0.} =
  case t.kind:
    of UnknownType: ast.raiseError("Unknown type!")
    of SimpleType: return
    of VoidType: return
    of PointerType: t.ptrType[].checkIncomplete(ast)
    of StructType:
      if t.structAdditional == nil or not t.structIsDefined: return
      for f in t.structAdditional.fields:
        if f.typeData.isIncomplete():
          ast.raiseError("Cannot have incomplete type {t.elemType} as field of a string!")
        f.typeData.checkIncomplete(ast)
    of FunctionType:
      t.funcReturnType[].checkIncomplete(ast)
      for p in t.paramTypes:
        p.checkIncomplete(ast)
    of ArrayOfUnknownSizeType, ArrayType:
      if t.elemType[].isIncomplete:
        ast.raiseError("Cannot construct array of incomplete type {t.elemType}!")
      t.elemType[].checkIncomplete(ast)

method resolveTypes(ast: AstNode, r: var TypeResolver) {.base, locks: 0.} =
  template check(iter, t: untyped): untyped =
    for sub in ast.iter:
      resolveTypes(sub, r)
  check(mdecls, DeclarationNode)
  check(mexps, ExpressionNode)
  check(mstats, StatementNode)
  check(mblockItems, BlockItemNode)

method resolveTypes(ast: ConvertExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.exp.arrayToAddr()
  let t = ast.exp.typeData
  if not t.isCastable(ast.typeData):
    ast.raiseError(fmt"Cannot cast {t} to {ast.typeData}")

method resolveTypes(ast: DereferenceExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.exp.arrayToAddr()
  let t = ast.exp.typeData
  if t.kind != PointerType:
    ast.raiseError(fmt"Attempted to dereference non-pointer type ""{t}""")
  ast.typeData = t.ptrType[]

method resolveTypes(ast: AddressExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  if ast.exp.typeData.kind == ArrayType:
    ast.exp.arrayToAddr()
    ast.typeData = ast.exp.typeData
  else:
    var ptrType = new(TypeData)
    ptrType[] = ast.exp.typeData
    ast.typeData = TypeData(kind: PointerType, ptrType: ptrType)

method resolveTypes(ast: DotExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  var t = ast.exp.typeData
  var i = 0
  ast.offset = 0
  while i < ast.fields.len:
    if t.kind != StructType:
      ast.raiseError(fmt"Cannot get field of non-struct type ""{t}""")
    if ast.fields[i] notin t.structAdditional.ids:
      ast.raiseError(fmt"Struct ""{t}"" has no field {ast.fields[i]}")
    let id = t.structAdditional.ids[ast.fields[i]]
    ast.offset += t.structAdditional.fields[id].offset
    t = t.structAdditional.fields[id].typeData
    i += 1
  ast.typeData = t

method resolveTypes(ast: UnaryExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.exp.arrayToAddr()
  let t = ast.exp.typeData
  let (isError, expected) = case ast.operator:
    of "!": (not t.isScalarType, "scalar type")
    of "+", "-": (not t.isArithmeticType, "arithmetic type")
    of "~": (not t.isIntegerType, "integer type")
    of "++", "--": (not t.isIntegerType and t.kind != PointerType, "integer or pointer type")
    else: (false, "")
  if isError:
    ast.raiseError(fmt"Not {expected} ""{t}"" as operand of ""{ast.operator}""")
  
  if ast.operator == "!":
    ast.typeData = int32Type
  else:
    ast.typeData = t.promoteType()
  ast.exp.insertConvertIfNeeded(ast.typeData)

method resolveTypes(ast: PostfixExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.exp.arrayToAddr()
  let t = ast.exp.typeData
  let (isError, expected) = case ast.operator:
    of "++", "--": (not t.isIntegerType and t.kind != PointerType, "integer or pointer type")
    else: (false, "")
  if isError:
    ast.raiseError(fmt"Not {expected} ""{t}"" as operand of ""{ast.operator}""")
  
  ast.typeData = t.promoteType()
  ast.exp.insertConvertIfNeeded(ast.typeData)

method resolveTypes(ast: BinaryExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.exp1.arrayToAddr()
  ast.exp2.arrayToAddr()
  let t1 = ast.exp1.typeData
  let t2 = ast.exp2.typeData

  if ast.operator == "+":
    if t1.kind == PointerType or t2.kind == PointerType:
      let ptrExpr = if t1.kind == PointerType: ast.exp1 else: ast.exp2
      let intExpr = if t1.kind == PointerType: ast.exp2 else: ast.exp1
      if not intExpr.typeData.isIntegerType:
        ast.raiseError(fmt"Attempted to add ""{t1}"" and ""{t2}""")
      ast.typeData = ptrExpr.typeData
      return
  elif ast.operator == "-":
    if t1.kind == PointerType and t2.kind == PointerType:
      if not areCompatible(t1, t2):
        ast.raiseError(fmt"Attempted to subtract ""{t1}"" from ""{t2}""")
      ast.typeData = int32Type
      return
    elif t1.kind == PointerType:
      if not t2.isIntegerType:
        ast.raiseError(fmt"Attempted to subtract ""{t1}"" from ""{t2}""")
      ast.typeData = t1
      return
  elif ast.operator in ["==", "!=", "<", ">", "<=", ">="]:
    if t1.kind == PointerType and t2.kind == PointerType:
      if not areCompatible(t1, t2):
        ast.raiseError(fmt"Attempted to compare ""{t1}"" with ""{t2}""")
      ast.typeData = int32Type
      return

  let (isError1, isError2, expected) = case ast.operator:
    of "&&", "||":
      (not t1.isScalarType, not t2.isScalarType, "scalar type")
    of "+", "-", "*", "/", "==", "!=", "<", ">", "<=", ">=": 
      (not t1.isArithmeticType, not t2.isArithmeticType, "arithmetic type")
    of "%", "&", "|", "^", "<<", ">>": 
      (not t1.isIntegerType, not t2.isIntegerType, "integer type")
    else: (false, false, "")
  
  if isError1:
    ast.raiseError(fmt"Not {expected} ""{t1}"" as operand of ""{ast.operator}""")
  elif isError2:
    ast.raiseError(fmt"Not {expected} ""{t2}"" as operand of ""{ast.operator}""")
  
  if ast.operator == "&&" or ast.operator == "||":
    ast.typeData = int32Type
  else:
    ast.typeData = arithmeticCommonType(t1, t2)
  ast.exp1.insertConvertIfNeeded(ast.typeData)
  ast.exp2.insertConvertIfNeeded(ast.typeData)

method resolveTypes(ast: BinaryRightConstExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.exp1.arrayToAddr()
  let t = ast.exp1.typeData

  if (ast.operator == "+" or ast.operator == "-") and t.kind == PointerType:
    ast.typeData = t
    return

  let (isError, expected) = case ast.operator:
    of "&&", "||":
      (not t.isScalarType, "scalar type")
    of "+", "-", "*", "/", "==", "!=", "<", ">", "<=", ">=": 
      (not t.isArithmeticType, "arithmetic type")
    of "%", "&", "|", "^", "<<", ">>": 
      (not t.isIntegerType, "integer type")
    else: (false, "")
  
  if isError:
    ast.raiseError(fmt"Not {expected} ""{t}"" as operand of ""{ast.operator}""")
  
  if ast.operator == "&&" or ast.operator == "||":
    ast.typeData = int32Type
  else:
    ast.typeData = arithmeticCommonType(t, t)
  ast.exp1.insertConvertIfNeeded(ast.typeData)

method resolveTypes(ast: TernaryExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.cond.arrayToAddr()
  ast.thenClause.arrayToAddr()
  ast.elseClause.arrayToAddr()
  let t1 = ast.cond.typeData
  let t2 = ast.thenClause.typeData
  let t3 = ast.elseClause.typeData

  if not t1.isScalarType:
    ast.raiseError(fmt"Not scalar type ""{t1}"" as first operand of ternary operator")
  if t2.isArithmeticType:
    if not t3.isArithmeticType:
      ast.raiseError(fmt"Attempted to calculate {t1}? {t2} : {t3}")
    ast.typeData = arithmeticCommonType(t2, t3)
  elif t2.kind == PointerType:
    if not areCompatible(t2, t3):
      ast.raiseError(fmt"Attempted to calculate {t1}? {t2} : {t3}")
    ast.typeData = t2
  
  ast.cond.insertConvertIfNeeded(t1.promoteType())
  ast.thenClause.insertConvertIfNeeded(ast.typeData)
  ast.elseClause.insertConvertIfNeeded(ast.typeData)

method resolveTypes(ast: AssignExprNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  
  let target = ast.variable.typeData
  let t = ast.exp.typeData
  

  if target.kind == ArrayType or 
      not t.isImplicitlyConvertible(target):
    ast.raiseError(fmt"Attempt to assign type ""{t}"" to variable of type ""{target}""")
  
  ast.typeData = target
  ast.exp.insertConvertIfNeeded(target)

method resolveTypes(ast: FuncCallNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  for i in 0..<ast.args.len:
    ast.args[i].arrayToAddr()
    let target = ast.paramTypes[i]
    let t = ast.args[i].typeData
    if not t.isImplicitlyConvertible(target):
      ast.raiseError(fmt"Function argument mismatch at position {i+1}: " &
                     fmt"expected type ""{target}"" but got ""{t}""")
    ast.args[i].insertConvertIfNeeded(target)

proc initWith(target: var TypeData, initExpr: var ExpressionNode) =
  if initExpr of ArrayInitializerNode:
    return
  
  if not initExpr.typeData.isImplicitlyConvertible(target):
    initExpr.arrayToAddr()
  let t = initExpr.typeData
  if not t.isImplicitlyConvertible(target):
    initExpr.raiseError(fmt"Attempt to initialize variable of type ""{target}"" with type ""{t}""")
  
  initExpr.insertConvertIfNeeded(target)
  if target.kind == ArrayOfUnknownSizeType and initExpr of StringLiteralNode:
    target = TypeData(kind: ArrayType, elemType: target.elemType, elemCount: initExpr.typeData.elemCount)

proc initDefault(target: TypeData): ExpressionNode {.locks: 0.} =
  case target.kind:
    of UnknownType, FunctionType, ArrayOfUnknownSizeType, VoidType: assert(false); ExpressionNode()
    of SimpleType, PointerType: ConstNumberNode(num: 0, typeData: target)
    of StructType: assert(false, "TODO"); ExpressionNode()
    of ArrayType:
      let s = target.elemType[].initDefault().repeat(target.elemCount)
      ArrayInitializerNode(elems: s)

proc fixArrayInit*(init: ArrayInitializerNode, 
    t: var TypeData, startIndex: int = 0, noTypes: bool = false): (seq[ExpressionNode], int) {.locks: 0.} =
  var i = startIndex
  let hasMaxCount = t.kind == ArrayOfUnknownSizeType
  let maxCount = if t.kind == ArrayType: t.elemCount else: 0
  template subtype: var TypeData = t.elemType[]
  let isSubtypeAggregate = subtype.kind in [ArrayType, ArrayOfUnknownSizeType]

  while i < init.elems.len:
    if hasMaxCount and result[0].len >= maxCount:
      result[1] = startIndex - i
      return
    let currentObject = init.elems[i]
    if isSubtypeAggregate:
      if currentObject of ArrayInitializerNode:
        let (subSeq, _) = currentObject.ArrayInitializerNode.fixArrayInit(subtype)
        var subInit = ArrayInitializerNode(elems: subSeq)
        subInit.setBaseAstFields(currentObject)
        result[0].add subInit
      else:
        let (subSeq, consumed) = init.fixArrayInit(subtype, i)
        var subInit = ArrayInitializerNode(elems: subSeq)
        subInit.setBaseAstFields(currentObject)
        result[0].add subInit
        i += consumed
    else:
      if currentObject of ArrayInitializerNode:
        let arr = currentObject.ArrayInitializerNode
        if arr.elems.len != 1:
          arr.raiseError("Attempt to initialize 1 element with {arr.elems.len}!")
        elif arr.elems[0] of ArrayInitializerNode:
          arr.raiseError("Too nested array initialization!")
        else:
          result[0].add arr.elems[0]
          if not noTypes:
            subtype.initWith(result[0][^1])
          i += 1
      else:
        result[0].add currentObject
        if not noTypes:
          subtype.initWith(result[0][^1])
        i += 1
  if t.kind == ArrayOfUnknownSizeType:
    t = TypeData(kind: ArrayType, elemType: t.elemType, elemCount: result[0].len)
  if hasMaxCount:
    while result[0].len < maxCount:
      result[0].add subtype.initDefault()
  result[1] = startIndex - init.elems.len
  return

method resolveTypes(ast: VarDeclNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.typeData.checkIncomplete(ast)
  if ast.typeData.kind == VoidType:
    ast.raiseError("Cannot define variable of void type!")
  if ast.init.isNone(): return
  if ast.init.get() of ArrayInitializerNode:
    let (x, _) = ast.init.get().ArrayInitializerNode.fixArrayInit(ast.typeData)
    ast.init.get().ArrayInitializerNode.elems = x
  ast.typeData.initWith(ast.init.get())

method resolveTypes(ast: IfStatNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.cond.arrayToAddr()
  let t = ast.cond.typeData
  if not t.isScalarType:
    ast.raiseError(fmt"Not scalar type ""{t}"" as condition")
  ast.cond.insertConvertIfNeeded(t.promoteType())
method resolveTypes(ast: WhileStatNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.cond.arrayToAddr()
  let t = ast.cond.typeData
  if not t.isScalarType:
    ast.raiseError(fmt"Not scalar type ""{t}"" as condition")
  ast.cond.insertConvertIfNeeded(t.promoteType())
method resolveTypes(ast: DoWhileStatNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  ast.cond.arrayToAddr()
  let t = ast.cond.typeData
  if not t.isScalarType:
    ast.raiseError(fmt"Not scalar type ""{t}"" as condition")
  ast.cond.insertConvertIfNeeded(t.promoteType())
method resolveTypes(ast: ForStatNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  if ast.cond.isSome():
    ast.cond.get().arrayToAddr()
    let t = ast.cond.get().typeData
    if not t.isScalarType:
      ast.raiseError(fmt"Not scalar type ""{t}"" as condition")
    ast.cond.get().insertConvertIfNeeded(t.promoteType())

method resolveTypes(ast: FuncDeclNode, r: var TypeResolver) =
  r.currentReturnType = ast.returnType
  procCall resolveTypes(ast.AstNode, r)
method resolveTypes(ast: ReturnStatNode, r: var TypeResolver) =
  procCall resolveTypes(ast.AstNode, r)
  if r.currentReturnType.kind == VoidType:
    if ast.exp.isSome():
      ast.raiseError(fmt"Attempt to return something, but current function is void!")
  else:
    ast.exp.get().arrayToAddr()
    let t = ast.exp.get().typeData
    if not t.isImplicitlyConvertible(r.currentReturnType):
      ast.raiseError(fmt"Attempt to return type ""{t}"", expected {r.currentReturnType}")
    ast.exp.get().insertConvertIfNeeded(r.currentReturnType)

proc resolveTypes*(ast: VarDeclNode) =
  var r: TypeResolver
  ast.resolveTypes(r)

proc resolveTypes*(ast: ProgramNode) =
  var r: TypeResolver
  for n in ast.declarations:
    n.resolveTypes(r)