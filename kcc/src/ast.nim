import strutils, options, strformat, tables
export options

type
  TypeNodeKind* {.pure.} = enum
    UnknownType
    SimpleType
    PointerType
    ArrayType
    ArrayOfUnknownSizeType
    FunctionType
    StructType
    VoidType
  SimpleTypeKind* {.pure.} = enum
    Int32
    Int16
    Int8
    UInt32
    UInt16
    UInt8
  StructAdditionalData* = ref object
    fields*: seq[VarDeclNode]
    ids*: Table[string, int]
    size*, align*: int

  TypeData* = object
    case kind*: TypeNodeKind:
      of UnknownType: nil
      of SimpleType: simpleType*: SimpleTypeKind
      of VoidType: nil
      of PointerType: ptrType*: ref TypeData
      of ArrayType, ArrayOfUnknownSizeType: 
        elemType*: ref TypeData
        elemCount*: int
      of FunctionType: 
        funcReturnType*: ref TypeData
        paramTypes*: seq[TypeData]
      of StructType:
        structName*: string
        structIsDefined*: bool
        structAdditional*: StructAdditionalData

  AstNode* = ref object of RootObj
    line*, pos*, index*: int
  BlockItemNode* = ref object of AstNode
  DeclarationNode* = ref object of BlockItemNode
  StatementNode* = ref object of BlockItemNode
  ExpressionNode* = ref object of AstNode
    typeData*: TypeData
  ProgramNode* = ref object of AstNode
    declarations*: seq[DeclarationNode]
  DeclaratorTypeData* = object
    case kind*: TypeNodeKind:
      of UnknownType: nil
      of VoidType: nil
      of SimpleType: simpleType*: SimpleTypeKind
      of PointerType: ptrType*: ref DeclaratorTypeData
      of ArrayType, ArrayOfUnknownSizeType: 
        elemType*: ref DeclaratorTypeData
        elemCount*: int
      of FunctionType: 
        funcReturnType*: ref DeclaratorTypeData
        paramDecls*: seq[DeclaratorNode]
      of StructType:
        structName*: string
        structIsDefined*: bool
        structAdditional*: StructAdditionalData
        structSize*, structAlign*: int
  DeclaratorNode* = ref object of AstNode
    name*: string
    typeData*: DeclaratorTypeData

  FuncDeclNode* = ref object of DeclarationNode
    name*: string
    returnType*: TypeData
    params*: seq[DeclarationNode]
    statements*: Option[BlockNode]
    maxStack*: uint32
  VarDeclNode* = ref object of DeclarationNode
    varName*: string
    typeData*: TypeData
    init*: Option[ExpressionNode]
    offset*: int
    isGlobal*: bool
  TypeDeclNode* = ref object of DeclarationNode
    typeData*: TypeData
  
  BreakStatNode* = ref object of StatementNode
  ContinueStatNode* = ref object of StatementNode
  ReturnStatNode* = ref object of StatementNode
    exp*: Option[ExpressionNode]
  IfStatNode* = ref object of StatementNode
    cond*: ExpressionNode
    thenClause*: StatementNode
    elseClause*: Option[StatementNode]
  WhileStatNode* = ref object of StatementNode
    cond*: ExpressionNode
    body*: StatementNode
  DoWhileStatNode* = ref object of StatementNode
    cond*: ExpressionNode
    body*: StatementNode
  ForStatNodeKind* {.pure.} = enum
    ForWithExp
    ForWithDecl
    ForWithoutInit
  ForStatNode* = ref object of StatementNode
    case kind*: ForStatNodeKind:
      of ForWithExp: initExp*: ExpressionNode
      of ForWithDecl: initDecl*: DeclarationNode
      of ForWithoutInit: nil
    cond*: Option[ExpressionNode]
    postExp*: Option[ExpressionNode]
    body*: StatementNode
  ExprStatNode* = ref object of StatementNode
    exp*: Option[ExpressionNode]
  BlockNode* = ref object of StatementNode
    items*: seq[BlockItemNode]
  
  AssignExprNode* = ref object of ExpressionNode
    variable*: ExpressionNode
    exp*: ExpressionNode
  UnaryExprNode* = ref object of ExpressionNode
    operator*: string
    exp*: ExpressionNode
  AddressExprNode* = ref object of ExpressionNode
    exp*: ExpressionNode
  DereferenceExprNode* = ref object of ExpressionNode
    exp*: ExpressionNode
  DotExprNode* = ref object of ExpressionNode
    exp*: ExpressionNode
    fields*: seq[string]
    offset*: int
  PostfixExprNode* = ref object of ExpressionNode
    operator*: string
    exp*: ExpressionNode
  BinaryExprNode* = ref object of ExpressionNode
    operator*: string
    exp1*, exp2*: ExpressionNode
  CommaExprNode* = ref object of ExpressionNode
    exp1*, exp2*: ExpressionNode
  BinaryRightConstExprNode* = ref object of ExpressionNode
    operator*: string
    exp1*: ExpressionNode
    num*: int64
  TernaryExprNode* = ref object of ExpressionNode
    cond*, thenClause*, elseClause*: ExpressionNode
  ConstNumberNode* = ref object of ExpressionNode
    num*: int64
  StringLiteralNode* = ref object of ExpressionNode
    str*: string
  VarNode* = ref object of ExpressionNode
    varName*: string
  ResolvedVarNode* = ref object of ExpressionNode
    varName*: string
    isGlobal*: bool
    offset*: int
  FuncCallNode* = ref object of ExpressionNode
    funcName*: string
    args*: seq[ExpressionNode]
    paramTypes*: seq[TypeData]
  ConvertExprNode* = ref object of ExpressionNode
    exp*: ExpressionNode
  ArrayInitializerNode* = ref object of ExpressionNode
    elems*: seq[ExpressionNode]
  ConstArrayInitializerNode* = ref object of ExpressionNode
    elems*: seq[ExpressionNode]

const SimpleTypeCount* = SimpleTypeKind.high.ord - SimpleTypeKind.low.ord + 1

iterator mexps*(n: AstNode): var ExpressionNode =
  if n of VarDeclNode:
    if n.VarDeclNode.init.isSome:
      yield n.VarDeclNode.init.get()
  
  elif n of ReturnStatNode:
    if n.ReturnStatNode.exp.isSome():
      yield n.ReturnStatNode.exp.get()
  elif n of IfStatNode:
    yield n.IfStatNode.cond
  elif n of WhileStatNode:
    yield n.WhileStatNode.cond
  elif n of DoWhileStatNode:
    yield n.DoWhileStatNode.cond
  elif n of ForStatNode:
    if n.ForStatNode.kind == ForWithExp:
      yield n.ForStatNode.initExp
    if n.ForStatNode.cond.isSome():
      yield n.ForStatNode.cond.get()
    if n.ForStatNode.postExp.isSome():
      yield n.ForStatNode.postExp.get()
  elif n of ExprStatNode:
    if n.ExprStatNode.exp.isSome:
      yield n.ExprStatNode.exp.get()
  
  elif n of AssignExprNode:
    yield n.AssignExprNode.variable
    yield n.AssignExprNode.exp
  elif n of UnaryExprNode:
    yield n.UnaryExprNode.exp
  elif n of AddressExprNode:
    yield n.AddressExprNode.exp
  elif n of DereferenceExprNode:
    yield n.DereferenceExprNode.exp
  elif n of DotExprNode:
    yield n.DotExprNode.exp
  elif n of PostfixExprNode:
    yield n.PostfixExprNode.exp
  elif n of BinaryExprNode:
    yield n.BinaryExprNode.exp1
    yield n.BinaryExprNode.exp2
  elif n of CommaExprNode:
    yield n.CommaExprNode.exp1
    yield n.CommaExprNode.exp2
  elif n of BinaryRightConstExprNode:
    yield n.BinaryRightConstExprNode.exp1
  elif n of TernaryExprNode:
    yield n.TernaryExprNode.cond
    yield n.TernaryExprNode.thenClause
    yield n.TernaryExprNode.elseClause
  elif n of FuncCallNode:
    for e in n.FuncCallNode.args.mitems:
      yield e
  elif n of ConvertExprNode:
    yield n.ConvertExprNode.exp
  elif n of ArrayInitializerNode:
    for e in n.ArrayInitializerNode.elems.mitems:
      yield e
  elif n of ConstArrayInitializerNode:
    for e in n.ConstArrayInitializerNode.elems.mitems:
      yield e

iterator mdecls*(n: AstNode): var DeclarationNode =
  if n of ProgramNode:
    for d in n.ProgramNode.declarations.mitems:
      yield d
  elif n of ForStatNode:
    if n.ForStatNode.kind == ForWithDecl:
      yield n.ForStatNode.initDecl

iterator mstats*(n: AstNode): var StatementNode =
  if n of IfStatNode:
    yield n.IfStatNode.thenClause
    if n.IfStatNode.elseClause.isSome:
      yield n.IfStatNode.elseClause.get()
  elif n of WhileStatNode:
    yield n.WhileStatNode.body
  elif n of DoWhileStatNode:
    yield n.DoWhileStatNode.body
  elif n of ForStatNode:
    yield n.ForStatNode.body

iterator mblockItems*(n: AstNode): var BlockItemNode =
  if n of FuncDeclNode:
    if n.FuncDeclNode.statements.isSome():
      for s in n.FuncDeclNode.statements.get().items.mitems:
        yield s
  if n of BlockNode:
    for s in n.BlockNode.items.mitems:
      yield s

const SpacesInLevel = 2

# array of pointers to int = int *a[10] = int *[10]
# pointer to array of ints = int (*a)[10] = int (*)[10]
proc `$`*(n: AstNode): string {.inline, locks: 0.}
proc toString*(t: TypeData, showStructDefs: bool): string {.locks: 0.} =
  result = (case t.kind:
    of UnknownType: "<unknown type>"
    of VoidType: "void"
    of PointerType: "ptr to " & t.ptrType[].toString(showStructDefs)
    of ArrayType: 
      "array[" & $t.elemCount & "] of " & t.elemType[].toString(showStructDefs)
    of ArrayOfUnknownSizeType:
      "array[] of " & t.elemType[].toString(showStructDefs)
    of FunctionType: 
      var r = "function("
      if t.paramTypes.len > 0:
        r &= t.paramTypes[0].toString(showStructDefs)
        for param in t.paramTypes[1..^1]:
          r &= ", " & param.toString(showStructDefs)
      r & ") returning " & t.funcReturnType[].toString(showStructDefs)
    of SimpleType:
      case t.simpleType:
        of Int32: "int"
        of Int16: "short"
        of Int8: "signed char"
        of UInt32: "unsigned int"
        of UInt16: "unsigned short"
        of UInt8: "char"
    of StructType:
      var r = "struct " & t.structName
      if t.structIsDefined and showStructDefs:
        r &= " {"
        for d in t.structAdditional.fields:
          r &= strip($d) & "; "
        r &= "}"
      r
    )
proc `$`*(t: TypeData): string {.locks: 0, inline.} = t.toString(false)

converter toDeclType*(t: TypeData): DeclaratorTypeData =
  result = DeclaratorTypeData(kind: t.kind)
  case t.kind:
    of UnknownType: discard
    of VoidType: discard
    of PointerType: 
      new(result.ptrType)
      result.ptrType[] = t.ptrType[].toDeclType
    of ArrayType, ArrayOfUnknownSizeType: 
      new(result.elemType)
      result.elemType[] = t.elemType[].toDeclType
      result.elemCount = t.elemCount
    of FunctionType: 
      new(result.funcReturnType)
      result.funcReturnType[] = t.funcReturnType[].toDeclType
      for param in t.paramTypes:
        result.paramDecls.add DeclaratorNode(
          name: "",
          typeData: param.toDeclType
        )
    of StructType: 
      result.structName = t.structName
      result.structAdditional = t.structAdditional
      result.structIsDefined = t.structIsDefined
    of SimpleType: result.simpleType = t.simpleType
converter toType*(t: DeclaratorTypeData): TypeData =
  result = TypeData(kind: t.kind)
  case t.kind:
    of UnknownType: discard
    of VoidType: discard
    of PointerType: 
      new(result.ptrType)
      result.ptrType[] = t.ptrType[].toType
    of ArrayType, ArrayOfUnknownSizeType: 
      new(result.elemType)
      result.elemType[] = t.elemType[].toType
      result.elemCount = t.elemCount
    of FunctionType: 
      new(result.funcReturnType)
      result.funcReturnType[] = t.funcReturnType[].toType
      for param in t.paramDecls:
        result.paramTypes.add param.typeData.toType
    of StructType: 
      result.structName = t.structName
      result.structAdditional = t.structAdditional
      result.structIsDefined = t.structIsDefined
    of SimpleType: result.simpleType = t.simpleType

method toString(n: AstNode, level: int): string {.base.} =
  spaces(level * SpacesInLevel) & "<AstNode>\p"
method toString(n: ProgramNode, level: int): string =
  for d in n.declarations:
    result &= d.toString(level)
method toString(n: FuncDeclNode, level: int): string =
  result = spaces(level * SpacesInLevel) & &"FuncDeclNode {n.name} (returns {n.returnType}):\p"
  if n.params.len > 0:
    result &= spaces((level+1) * SpacesInLevel) & "Parameters:\p"
    for s in n.params:
      result &= s.toString(level + 2)
  if n.statements.isSome():
    result &= spaces((level+1) * SpacesInLevel) & "Statements:\p"
    for s in n.statements.get().items:
      result &= s.toString(level + 2)
method toString(n: VarDeclNode, level: int): string =
  result = spaces(level * SpacesInLevel) & 
    &"VarDeclNode \"{n.typeData} {n.varName}\" at {n.offset}"
  if n.isGlobal:
    result &= " (global)"
  if n.init.isSome:
    result &= ":\p" & n.init.get().toString(level + 1)
  else:
    result &= "\p"
method toString(n: TypeDeclNode, level: int): string =
  spaces(level * SpacesInLevel) & &"TypeDeclNode {n.typeData.toString(true)}\p"

method toString(n: BreakStatNode, level: int): string =
  spaces(level * SpacesInLevel) & "BreakStatNode\p"
method toString(n: ContinueStatNode, level: int): string =
  spaces(level * SpacesInLevel) & "ContinueStatNode\p"
method toString(n: ReturnStatNode, level: int): string =
  result = spaces(level * SpacesInLevel) & "ReturnStatNode"
  if n.exp.isSome():
    result &= ":\p" & n.exp.get().toString(level + 1)
  else:
    result &= "\p"
method toString(n: IfStatNode, level: int): string =
  result = spaces(level * SpacesInLevel) & "IfStatNode:\p"
  result &= spaces((level+1) * SpacesInLevel) & "Condition:\p" & n.cond.toString(level + 2)
  result &= spaces((level+1) * SpacesInLevel) & "Then:\p" & n.thenClause.toString(level + 2)
  if n.elseClause.isSome:
    result &= spaces((level+1) * SpacesInLevel) & "Else:\p" & n.elseClause.get().toString(level + 2)
method toString(n: WhileStatNode, level: int): string =
  result = spaces(level * SpacesInLevel) & "WhileStatNode:\p"
  result &= spaces((level+1) * SpacesInLevel) & "Condition:\p" & n.cond.toString(level + 2)
  result &= spaces((level+1) * SpacesInLevel) & "Body:\p" & n.body.toString(level + 2)
method toString(n: DoWhileStatNode, level: int): string =
  result = spaces(level * SpacesInLevel) & "DoWhileStatNode:\p"
  result &= spaces((level+1) * SpacesInLevel) & "Body:\p" & n.body.toString(level + 2)
  result &= spaces((level+1) * SpacesInLevel) & "Condition:\p" & n.cond.toString(level + 2)
method toString(n: ForStatNode, level: int): string =
  result = spaces(level * SpacesInLevel) & "ForStatNode:\p"
  result &= spaces((level+1) * SpacesInLevel) & "Init:" & 
    (case n.kind:
      of ForWithDecl: "\p" & n.initDecl.toString(level + 2)
      of ForWithExp: "\p" & n.initExp.toString(level + 2)
      of ForWithoutInit: " (none)\p")
  result &= spaces((level+1) * SpacesInLevel) & "Condition:" & 
    (if n.cond.isSome(): "\p" & n.cond.get().toString(level + 2) else: " (none)")
  result &= spaces((level+1) * SpacesInLevel) & "Post expression:" & 
    (if n.postExp.isSome(): "\p" & n.postExp.get().toString(level + 2) else: " (none)")
  result &= spaces((level+1) * SpacesInLevel) & "Body:\p" & n.body.toString(level + 2)
method toString(n: ExprStatNode, level: int): string =
  if n.exp.isNone():
    spaces(level * SpacesInLevel) & "NullStatNode\p"
  else:
    n.exp.get().toString(level)
method toString(n: BlockNode, level: int): string =
  result = spaces(level * SpacesInLevel) & "BlockNode:\p"
  for node in n.items:
    result &= node.toString(level+1)

method toString(n: UnaryExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"UnaryExprNode ({n.typeData}) \"{n.operator}\" :\p" & n.exp.toString(level + 1)
method toString(n: AddressExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"AddressExprNode ({n.typeData}):\p" & n.exp.toString(level + 1)
method toString(n: DereferenceExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"DereferenceExprNode ({n.typeData}):\p" & n.exp.toString(level + 1)
method toString(n: DotExprNode, level: int): string =
  result &= spaces(level * SpacesInLevel) & 
    &"DotExprNode ({n.typeData}):\p" & n.exp.toString(level + 1)
  result &= spaces((level + 1) * SpacesInLevel)
  for f in n.fields:
    result &= "." & f
  result &= "\p"
method toString(n: ConvertExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"ConvertExprNode ({n.typeData}):\p" & n.exp.toString(level + 1)
method toString(n: PostfixExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"PostfixExprNode ({n.typeData}) \"{n.operator}\" :\p" & n.exp.toString(level + 1)
method toString(n: BinaryExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"BinaryExprNode ({n.typeData}) \"{n.operator}\" :\p" &
    n.exp1.toString(level + 1) & 
    n.exp2.toString(level + 1)
method toString(n: CommaExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"CommaExprNode ({n.typeData}):\p" &
    n.exp1.toString(level + 1) & 
    n.exp2.toString(level + 1)
method toString(n: BinaryRightConstExprNode, level: int): string =
  spaces(level * SpacesInLevel) & 
    &"BinaryRightConstExprNode ({n.typeData}) \"{n.operator}\" :\p" & 
    n.exp1.toString(level + 1) & 
    spaces((level + 1) * SpacesInLevel) & "ConstNumberNode(" & $n.num & ")\p"
method toString(n: TernaryExprNode, level: int): string =
  result = spaces(level * SpacesInLevel) & &"TernaryExprNode ({n.typeData}):\p"
  result &= spaces((level+1) * SpacesInLevel) & "Condition:\p" & n.cond.toString(level + 2)
  result &= spaces((level+1) * SpacesInLevel) & "Then:\p" & n.thenClause.toString(level + 2)
  result &= spaces((level+1) * SpacesInLevel) & "Else:\p" & n.elseClause.toString(level + 2)

method toString(n: AssignExprNode, level: int): string =
  result = spaces(level * SpacesInLevel) & &"AssignExprNode ({n.typeData}) "
  if n.variable of VarNode:
    result &= n.variable.VarNode.varName
  elif n.variable of ResolvedVarNode:
    let v = n.variable.ResolvedVarNode
    result &= v.varName & " at " & $v.offset
    if v.isGlobal:
      result &= " (global)"
  result &= ":\p" & n.exp.toString(level + 1)

method toString(n: ConstNumberNode, level: int): string =
  spaces(level * SpacesInLevel) & &"ConstNumberNode ({n.typeData}) {n.num}\p"
method toString(n: StringLiteralNode, level: int): string =
  spaces(level * SpacesInLevel) & &"StringLiteralNode ({n.typeData}) {n.str.escape}\p"
method toString(n: VarNode, level: int): string =
  spaces(level * SpacesInLevel) & "VarNode " & n.varName & "\p"
method toString(n: ResolvedVarNode, level: int): string =
  result = spaces(level * SpacesInLevel) & 
    &"VarNode ({n.typeData}) {n.varName} at {n.offset}"
  if n.isGlobal:
    result &= " (global)"
  result &= "\p"
method toString(n: FuncCallNode, level: int): string =
  result = spaces(level * SpacesInLevel) & &"FuncCallNode ({n.typeData}) {n.funcName} (params: {n.paramTypes}):\p"
  for e in n.args:
    result &= e.toString(level + 1)
method toString(n: ArrayInitializerNode, level: int): string =
  result = spaces(level * SpacesInLevel) & &"ArrayInitializerNode:\p"
  for e in n.elems:
    result &= e.toString(level + 1)
method toString(n: ConstArrayInitializerNode, level: int): string =
  result = spaces(level * SpacesInLevel) & &"ConstArrayInitializerNode:\p"
  for e in n.elems:
    result &= e.toString(level + 1)

proc `$`*(n: AstNode): string {.inline.} = n.toString(0)

proc setBaseAstFields*(result: AstNode, source: AstNode) =
  result.index = source.index
  result.line = source.line
  result.pos = source.pos

proc getAlignedSize*(t: TypeData): int {.locks: 0.}
proc getAlign*(t: TypeData): int {.locks: 0.} =
  case t.kind:
    of UnknownType: assert(false); 0
    of FunctionType: assert(false); 0
    of VoidType: 1
    of PointerType: 4
    of ArrayType, ArrayOfUnknownSizeType: max(4, t.elemType[].getAlign)
    of StructType: t.structAdditional.align
    of SimpleType:
      case t.simpleType:
        of Int8, UInt8: 1
        of Int16, UInt16: 2
        of Int32, UInt32: 4

proc getSize*(t: TypeData): int {.locks: 0.} =
  case t.kind:
    of UnknownType: assert(false); 0
    of FunctionType: assert(false); 0
    of ArrayOfUnknownSizeType: assert(false); 0
    of VoidType: 1
    of PointerType: 4
    of ArrayType:
      t.elemType[].getAlignedSize * t.elemCount
    of StructType: t.structAdditional.size
    of SimpleType:
      case t.simpleType:
        of Int8, UInt8: 1
        of Int16, UInt16: 2
        of Int32, UInt32: 4

proc getAlignedSize*(t: TypeData): int =
  result = t.getSize()
  let align = t.getAlign()
  while result mod align != 0:
    result.inc

proc isLvalue*(ast: AstNode): bool =
  ast of ResolvedVarNode or
  ast of DereferenceExprNode or
  ast of DotExprNode