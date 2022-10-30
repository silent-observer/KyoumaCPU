import ast

const 
  ConstHigh = 8191
  ConstLow = -8192

proc isConst(ast: AstNode): bool {.locks: 0.} =
  if ast of ConstNumberNode or ast of ConstArrayInitializerNode: return true
  if ast of ArrayInitializerNode:
    for e in ast.ArrayInitializerNode.elems:
      if not e.isConst: return false
    return true
  return false

method optimizeConsts(ast: AstNode): AstNode {.base, locks: 0.} =
  template check(iter, t: untyped): untyped =
    for sub in ast.iter:
      let n = optimizeConsts(sub)
      if not n.isNil():
        sub = n.t
  check(mdecls, DeclarationNode)
  check(mexps, ExpressionNode)
  check(mstats, StatementNode)
  check(mblockItems, BlockItemNode)

method optimizeConsts(ast: UnaryExprNode): AstNode =
  discard procCall optimizeConsts(ast.AstNode)
  if not (ast.exp of ConstNumberNode): return nil
  let op = ast.exp.ConstNumberNode
  if ast.operator == "++" or ast.operator == "--":
    return nil
  let num = 
    case ast.operator:
      of "-": -op.num
      of "~": not op.num
      of "!": (if op.num == 0: 1'i64 else: 0'i64)
      else: assert(false); 0
  result = ConstNumberNode(num: num, typeData: ast.exp.typeData)
  result.setBaseAstFields(ast)

method optimizeConsts(ast: ConvertExprNode): AstNode =
  discard procCall optimizeConsts(ast.AstNode)
  if not (ast.exp of ConstNumberNode): return nil
  result = ast.exp
  result.ConstNumberNode.typeData = ast.typeData

method optimizeConsts(ast: BinaryExprNode): AstNode =
  discard procCall optimizeConsts(ast.AstNode)

  let isLeftConst = ast.exp1 of ConstNumberNode
  let isRightConst = ast.exp2 of ConstNumberNode

  if not isLeftConst and isRightConst:
    let num = ast.exp2.ConstNumberNode.num
    let numSmall = cast[int32](num and 0xFFFFFFFF)
    let usesImmediateInstr = 
      ast.operator in ["+", "-", "==", "!=", "<", ">=", "&", "^", "|", ">>", "<<"]
    if usesImmediateInstr and (numSmall > ConstHigh or numSmall < ConstLow):
      return nil
    result = BinaryRightConstExprNode(
      operator: ast.operator,
      exp1: ast.exp1, 
      num: num
      )
    result.setBaseAstFields(ast)
    return
  if isLeftConst and not isRightConst and 
      ast.operator in ["+", "*", "==", "!=", "<", ">", ">=", "<=", "&", "^", "|"]:
    let num = ast.exp1.ConstNumberNode.num
    let numSmall = int32(num and 0xFFFFFFFF)
    let usesImmediateInstr = ast.operator notin [">", "<="]
    if usesImmediateInstr and (numSmall > ConstHigh or numSmall < ConstLow):
      return nil
    
    if ast.operator in ["+", "*", "==", "!=", "&", "^", "|"]:
      result = BinaryRightConstExprNode(
        operator: ast.operator,
        exp1: ast.exp2, 
        num: num
        )
    else:
      result = BinaryRightConstExprNode(
        operator: (case ast.operator:
          of ">": "<"
          of "<": ">"
          of ">=": "<="
          of "<=": ">="
          else: ""),
        exp1: ast.exp2, 
        num: num
        )
    result.setBaseAstFields(ast)
    return
  elif isLeftConst and ast.operator == "&&":
    if ast.exp1.ConstNumberNode.num == 0:
      result = ConstNumberNode(num: 0, typeData: ast.exp1.typeData)
      result.setBaseAstFields(ast)
      return
    else:
      return ast.exp2
  elif isLeftConst and ast.operator == "||":
    if ast.exp1.ConstNumberNode.num != 0:
      result = ConstNumberNode(num: 1, typeData: ast.exp1.typeData)
      result.setBaseAstFields(ast)
      return
    else:
      return ast.exp2
  elif not isRightConst: return nil

  let op1 = ast.exp1.ConstNumberNode
  let op2 = ast.exp2.ConstNumberNode
  if ast.operator == "++" or ast.operator == "--":
    return nil
  let num = 
    case ast.operator:
      of "-": op1.num - op2.num
      of "+": op1.num + op2.num
      of "*": op1.num * op2.num
      of "/": op1.num div op2.num
      of "%": op1.num mod op2.num
      of "==": (if op1.num == op2.num: 1 else: 0)
      of "!=": (if op1.num != op2.num: 1 else: 0)
      of "<": (if op1.num < op2.num: 1 else: 0)
      of ">=": (if op1.num >= op2.num: 1 else: 0)
      of ">": (if op1.num > op2.num: 1 else: 0)
      of "<=": (if op1.num <= op2.num: 1 else: 0)
      of "<<": op1.num shl op2.num
      of ">>": op1.num shr op2.num
      of "&": op1.num and op2.num
      of "^": op1.num xor op2.num
      of "|": op1.num or op2.num
      else: assert(false); 0
  result = ConstNumberNode(num: num, typeData: ast.exp1.typeData)
  result.setBaseAstFields(ast)

method optimizeConsts(ast: TernaryExprNode): AstNode =
  discard procCall optimizeConsts(ast.AstNode)
  if not (ast.cond of ConstNumberNode): return nil

  let cond = ast.cond.ConstNumberNode
  if cond.num != 0:
    return ast.thenClause
  else:
    return ast.elseClause

method optimizeIncDec(ast: AstNode): AstNode {.base, locks: 0.} =
  template check(iter, t: untyped): untyped =
    for sub in ast.iter:
      let n = optimizeIncDec(sub)
      if not n.isNil():
        sub = n.t
  check(mstats, StatementNode)
  check(mblockItems, BlockItemNode)

method optimizeIncDec(ast: ExprStatNode): AstNode =
  if ast.exp.isSome() and ast.exp.get() of PostfixExprNode:
    ast.exp = UnaryExprNode(
      operator: ast.exp.get().PostfixExprNode.operator, 
      exp: ast.exp.get().PostfixExprNode.exp).ExpressionNode.some()
  return nil
method optimizeIncDec(ast: ForStatNode): AstNode =
  if ast.postExp.isSome() and ast.postExp.get() of PostfixExprNode:
    ast.postExp = UnaryExprNode(
      operator: ast.postExp.get().PostfixExprNode.operator, 
      exp: ast.postExp.get().PostfixExprNode.exp).ExpressionNode.some()
  if ast.kind == ForWithExp and ast.initExp of PostfixExprNode:
    ast.initExp = UnaryExprNode(
      operator: ast.initExp.PostfixExprNode.operator, 
      exp: ast.initExp.PostfixExprNode.exp)
  return nil

proc optimizeConstExpr*(ast: var ExpressionNode) =
  let n = ast.optimizeConsts()
  if not n.isNil():
    ast = n.ExpressionNode

proc optimizeBeforeAlloc*(ast: ProgramNode) =
  discard ast.optimizeConsts()
  discard ast.optimizeIncDec()

method optimizeConstInits(ast: AstNode): AstNode {.base, locks: 0.} =
  template check(iter, t: untyped): untyped =
    for sub in ast.iter:
      let n = optimizeConstInits(sub)
      if not n.isNil():
        sub = n.t
  check(mdecls, DeclarationNode)
  check(mexps, ExpressionNode)
  check(mstats, StatementNode)
  check(mblockItems, BlockItemNode)

method optimizeConstInits(ast: ArrayInitializerNode): AstNode =
  discard procCall optimizeConstInits(ast.AstNode)
  if ast.isConst():
    result = ConstArrayInitializerNode(elems: ast.elems)
    result.setBaseAstFields(ast)

proc optimizeAfterTyping*(ast: ProgramNode) =
  discard ast.optimizeConstInits()