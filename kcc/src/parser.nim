import token, ast
import parseutils, strutils, strformat
from optimizer import optimizeConstExpr

type 
  Parser = object
    input: TokenSequence
    index: int
  ParsingError* = object of Exception
    line, pos, index: int

const UnaryOperators = ["-", "~", "!", "++", "--", "*", "&"]

proc reportError*(e: ParsingError, input: string): string =
  result = "Parsing Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(t: Token, text: string) {.noReturn.} =
  var e = newException(ParsingError, text)
  e.line = t.line
  e.pos = t.pos
  e.index = t.index
  raise e

proc peek(parser: Parser): Token {.inline.} =
  if parser.index >= parser.input.len:
    let t = parser.input[^1]
    Token(kind: Eof, line: t.line, pos: t.pos, index: t.index)
  else:
    parser.input[parser.index]

proc advance(parser: var Parser) {.inline.} =
  parser.index.inc

proc getOne(parser: var Parser): Token {.inline.} =
  result = parser.peek()
  parser.advance()

proc parseIdent(parser: var Parser, errorMsg: string): string =
  let t = parser.getOne()
  if t.kind != Identifier:
    t.raiseError(errorMsg)
  t.identText

proc checkKeyword(t: Token, keyword: KeywordKind): bool {.inline.} =
  t.kind == Keyword and t.keyword == keyword
proc parseKeyword(parser: var Parser, keyword: KeywordKind, errorMsg: string) =
  let t = parser.getOne()
  if not t.checkKeyword(keyword):
    t.raiseError(errorMsg)

proc checkSymbol(t: Token, symbol: string): bool {.inline.} =
  t.kind == Symbol and t.symbol == symbol
proc parseSymbol(parser: var Parser, symbol: string, errorMsg: string) =
  let t = parser.getOne()
  if not t.checkSymbol(symbol):
    t.raiseError(errorMsg)

proc isType(t: Token): bool {.inline.} =
  if t.kind == Keyword:
    return t.keyword in {Int, Short, Char, Unsigned, Signed, Struct, Void};
  return false;

proc parseExpression(parser: var Parser): ExpressionNode
proc parseAssignment(parser: var Parser): ExpressionNode
proc parseFactor(parser: var Parser): ExpressionNode
proc parseStatement(parser: var Parser): StatementNode
proc parseBlockItem(parser: var Parser): BlockItemNode
proc parseDeclarator(parser: var Parser, baseType: TypeData, canSkipIdent: bool): DeclaratorNode
proc parseLocalVarDecl(parser: var Parser): VarDeclNode {.inline.}

template initNode(parser: Parser, nodetype: typedesc): untyped =
  var n: nodetype
  new(n)
  let t = parser.peek()
  n.line = t.line
  n.pos = t.pos
  n.index = t.index
  n

proc parseStructType(parser: var Parser): TypeData =
  parser.parseKeyword(Struct, "Expected \"struct\"!")
  result = TypeData(kind: StructType)
  result.structName = parser.parseIdent("Expected struct name!")
  if parser.peek().checkSymbol("{"):
    parser.advance()
    result.structIsDefined = true
    var t = parser.peek()
    new(result.structAdditional)
    while t.kind != Eof and not t.checkSymbol("}"):
      result.structAdditional.fields.add parser.parseLocalVarDecl()
      t = parser.peek()
    parser.parseSymbol("}", "Expected right brace!")
  else:
    result.structIsDefined = false

proc parseSimpleType(parser: var Parser): TypeData =
  result = TypeData(kind: UnknownType)
  var t = parser.peek()
  if not t.isType():
    t.raiseError("Expected type!")
  if t.kind == Keyword:
    if t.keyword == Struct:
      return parser.parseStructType()
    if t.keyword == Void:
      parser.advance()
      return TypeData(kind: VoidType)
    
    var 
      typeSigned = false 
      typeUnsigned = false
    if t.keyword == Unsigned:
      parser.advance()
      typeUnsigned = true
      result = TypeData(
        kind: SimpleType,
        simpleType: UInt32
      )
      t = parser.peek()
      if t.kind != Keyword: return
    elif t.keyword == Signed:
      parser.advance()
      typeSigned = true
      result = TypeData(
        kind: SimpleType,
        simpleType: Int32
      )
      t = parser.peek()
      if t.kind != Keyword: return
    if t.keyword in {Int, Short, Char}:
      parser.advance()
      let simpleType = case t.keyword:
        of Int: 
          if typeUnsigned: UInt32 
          else: Int32
        of Short: 
          if typeUnsigned: UInt16 
          else: Int16
        of Char: 
          if typeSigned: Int8
          else: UInt8
        else: assert(false); Int32
      result = TypeData(
        kind: SimpleType,
        simpleType: simpleType
      )
  if result.kind == UnknownType:
    t.raiseError("Invalid type!")

proc parseNoPtrDeclarator(parser: var Parser, baseType: TypeData, canSkipIdent: bool): DeclaratorNode =
  #echo "START NOPTR"
  result = parser.initNode(DeclaratorNode)
  result.typeData = baseType
  var t = parser.peek()
  if t.kind == Symbol and t.symbol == "(":
    result = parser.parseDeclarator(baseType, canSkipIdent)
    parser.parseSymbol(")", "Expected right paren!")
  elif not canSkipIdent or t.kind == Identifier:
    result.name = parser.parseIdent("Expected variable name!")

  t = parser.peek()
  #echo result.typeData.toType
  while t.kind == Symbol and t.symbol in ["(", "["]:
    if t.symbol == "(":
      parser.advance()
      var typeRef = new(DeclaratorTypeData)
      typeRef[] = result.typeData
      result.typeData = DeclaratorTypeData(kind: FunctionType, funcReturnType: typeRef)
      t = parser.peek()
      if t.checkSymbol(")"):
        parser.advance()
      else:
        while true:
          let paramBaseType = parser.parseSimpleType()
          let decl = parser.parseDeclarator(paramBaseType, true)
          result.typeData.paramDecls.add decl
          t = parser.peek()
          if t.checkSymbol(")"):
            parser.advance()
            break
          elif t.checkSymbol(","):
            parser.advance()
      t = parser.peek()
    elif t.symbol == "[":
      parser.advance()
      var typeRef = new(DeclaratorTypeData)
      typeRef[] = result.typeData
      
      if parser.peek().checkSymbol("]"):
        result.typeData = DeclaratorTypeData(kind: ArrayOfUnknownSizeType, elemType: typeRef)
      else:
        result.typeData = DeclaratorTypeData(kind: ArrayType, elemType: typeRef)
        var count = parser.parseExpression()
        count.optimizeConstExpr()
        if not (count of ConstNumberNode):
          parser.peek().raiseError("Non constant expression as array element count!")
        result.typeData.elemCount = count.ConstNumberNode.num.int
      parser.parseSymbol("]", "Expected right bracket")
      t = parser.peek()
  #echo "END"

proc parseDeclarator(parser: var Parser, baseType: TypeData, canSkipIdent: bool): DeclaratorNode =
  #echo "START"
  var currentBase = baseType
  var t = parser.peek()
  while t.kind == Symbol and t.symbol == "*":
    parser.advance()
    var typeRef = new(DeclaratorTypeData)
    typeRef[] = currentBase
    currentBase = DeclaratorTypeData(kind: PointerType, ptrType: typeRef)
    t = parser.peek()
  return parser.parseNoPtrDeclarator(currentBase, canSkipIdent)

proc parseType(parser: var Parser): TypeData {.inline.} =
  let t = parser.parseSimpleType()
  parser.parseDeclarator(t, true).typeData

proc parseConstNumber(parser: var Parser): ConstNumberNode =
  result = parser.initNode(ConstNumberNode)
  result.num = parser.getOne().num
  result.typeData = TypeData(kind: SimpleType, simpleType: Int32)

proc parseConstChar(parser: var Parser): ConstNumberNode =
  result = parser.initNode(ConstNumberNode)
  result.num = parser.getOne().character.int64
  result.typeData = TypeData(kind: SimpleType, simpleType: UInt8)

proc parseConstString(parser: var Parser): StringLiteralNode =
  result = parser.initNode(StringLiteralNode)
  while parser.peek().kind == StringConstant:
    result.str &= parser.getOne().str
  var elemType = new TypeData
  elemType[] = TypeData(kind: SimpleType, simpleType: UInt8)
  result.typeData = TypeData(kind: ArrayType, elemType: elemType, elemCount: result.str.len + 1)

proc parseIdentifier(parser: var Parser): ExpressionNode =
  let text = parser.getOne().identText
  if parser.peek().checkSymbol("("):
    var n = parser.initNode(FuncCallNode)
    n.funcName = text
    parser.advance()
    if not parser.peek().checkSymbol(")"):
      n.args.add parser.parseAssignment()
      while parser.peek().checkSymbol(","):
        parser.advance()
        n.args.add parser.parseAssignment()
    parser.parseSymbol(")", "Expected right paren!")
    return n
  else:
    var n = parser.initNode(VarNode)
    n.varName = text
    return n

proc parseUnaryExpr(parser: var Parser): ExpressionNode =
  let s = parser.peek().symbol
  if s == "*":
    result = parser.initNode(DereferenceExprNode)
    parser.advance()
    result.DereferenceExprNode.exp = parser.parseFactor()
  elif s == "&":
    result = parser.initNode(AddressExprNode)
    parser.advance()
    result.AddressExprNode.exp = parser.parseFactor()
  else:
    result = parser.initNode(UnaryExprNode)
    parser.advance()
    result.UnaryExprNode.operator = s
    result.UnaryExprNode.exp = parser.parseFactor()

proc parseAtomic(parser: var Parser): ExpressionNode =
  let t = parser.peek()
  case t.kind:
    of Identifier: return parser.parseIdentifier()
    of NumberConstant: return parser.parseConstNumber()
    of CharacterConstant: return parser.parseConstChar()
    of StringConstant: return parser.parseConstString()
    of Symbol:
      if t.symbol == "(":
        parser.advance()
        if parser.peek().isType():
          result = parser.initNode(ConvertExprNode)
          result.typeData = parser.parseType()
          parser.parseSymbol(")", "Expected right paren!")
          result.ConvertExprNode.exp = parser.parseFactor()
        else:
          result = parser.parseExpression()
          parser.parseSymbol(")", "Expected right paren!")
        return
      else: t.raiseError("Expected expression!")
    else: t.raiseError("Expected expression!")

proc parsePostfix(parser: var Parser): ExpressionNode =
  result = parser.parseAtomic()
  var t = parser.peek()
  while true:
    if t.kind != Symbol:
      return
    elif t.symbol == "[":
      var n = parser.initNode(DereferenceExprNode)
      var nAdd = parser.initNode(BinaryExprNode)
      parser.advance()
      nAdd.operator = "+"
      nAdd.exp1 = result
      nAdd.exp2 = parser.parseExpression()
      n.exp = nAdd
      result = n
      parser.parseSymbol("]", "Expected right bracket!")
    elif t.symbol in ["++", "--"]:
      var n = parser.initNode(PostfixExprNode)
      n.exp = result
      n.operator = t.symbol
      result = n
      parser.advance()
    elif t.symbol == ".":
      var n = parser.initNode(DotExprNode)
      n.exp = result
      while t.symbol == ".":
        parser.advance()
        n.fields.add parser.parseIdent("Expected field name!")
        t = parser.peek()
      result = n
    elif t.symbol == "->":
      var n = parser.initNode(DotExprNode)
      var n2 = parser.initNode(DereferenceExprNode)
      n2.exp = result
      n.exp = n2

      parser.advance()
      n.fields.add parser.parseIdent("Expected field name!")
      t = parser.peek()
      
      while t.symbol == ".":
        parser.advance()
        n.fields.add parser.parseIdent("Expected field name!")
        t = parser.peek()
      result = n
    else:
      return
    t = parser.peek()

proc parseFactor(parser: var Parser): ExpressionNode =
  let t = parser.peek()
  if t.kind == Symbol and t.symbol in UnaryOperators:
    return parser.parseUnaryExpr()
  else:
    return parser.parsePostfix()

template defineParseBinary(name, previous: untyped, symbols: openArray[string]): untyped =
  proc name(parser: var Parser): ExpressionNode =
    result = parser.previous()
    var next = parser.peek()
    while next.kind == Symbol and next.symbol in symbols:
      var exp = parser.initNode(BinaryExprNode)
      parser.advance()
      let exp2 = parser.previous()
      
      exp.operator = next.symbol
      exp.exp1 = result
      exp.exp2 = exp2
      result = exp
      next = parser.peek()

defineParseBinary(parseTerm, parseFactor, ["*", "/", "%"])
defineParseBinary(parseAdditive, parseTerm, ["+", "-"])
defineParseBinary(parseShifts, parseAdditive, ["<<", ">>"])
defineParseBinary(parseRelational, parseShifts, ["<", ">", "<=", ">="])
defineParseBinary(parseEquality, parseRelational, ["==", "!="])
defineParseBinary(parseBitwiseAnd, parseEquality, ["&"])
defineParseBinary(parseBitwiseXor, parseBitwiseAnd, ["^"])
defineParseBinary(parseBitwiseOr, parseBitwiseXor, ["|"])
defineParseBinary(parseLogicalAnd, parseBitwiseOr, ["&&"])
defineParseBinary(parseLogicalOr, parseLogicalAnd, ["||"])
proc parseTernary(parser: var Parser): ExpressionNode =
  result = parser.parseLogicalOr()
  if parser.peek().checkSymbol("?"):
    let cond = result
    result = parser.initNode(TernaryExprNode)
    parser.advance()
    result.TernaryExprNode.cond = cond
    result.TernaryExprNode.thenClause = parser.parseExpression()
    parser.parseSymbol(":", "Expected colon!")
    result.TernaryExprNode.elseClause = parser.parseTernary()
proc parseAssignment(parser: var Parser): ExpressionNode =
  result = parser.parseTernary()

  let t = parser.peek()
  if t.kind != Symbol:
    return
  if t.symbol == "=":
    var n = parser.initNode(AssignExprNode)
    parser.advance()
    n.variable = result
    n.exp = parser.parseAssignment()
    result = n
  elif t.symbol in ["+=", "-=", "*=", "/=", "%=", "<<=", ">>=", "&=", "^=", "|="]:
    var nBin = parser.initNode(BinaryExprNode)
    var n = parser.initNode(AssignExprNode)
    parser.advance()

    nBin.operator = t.symbol[0..^2]
    nBin.exp1 = result
    nBin.exp2 = parser.parseAssignment()
    
    n.variable = result
    n.exp = nBin
    result = n
proc parseExpression(parser: var Parser): ExpressionNode =
  result = parser.parseAssignment()
  var next = parser.peek()
  while next.kind == Symbol and next.symbol == ",":
    var exp = parser.initNode(CommaExprNode)
    parser.advance()
    let exp2 = parser.parseAssignment()
    
    exp.exp1 = result
    exp.exp2 = exp2
    result = exp
    next = parser.peek()

proc parseInitializer(parser: var Parser): ExpressionNode

proc parseBraceInitializer(parser: var Parser): ExpressionNode =
  result = parser.initNode(ArrayInitializerNode)
  parser.parseSymbol("{", "Expected left brace")
  result.ArrayInitializerNode.elems.add parser.parseInitializer()
  if parser.peek().checkSymbol("}"):
    parser.advance()
    return
  
  while parser.peek().checkSymbol(","):
    parser.advance()
    result.ArrayInitializerNode.elems.add parser.parseInitializer()
  parser.parseSymbol("}", "Expected right brace")

proc parseInitializer(parser: var Parser): ExpressionNode =
  if parser.peek().checkSymbol("{"):
    parser.parseBraceInitializer()
  else:
    parser.parseAssignment()

proc parseVarDeclWithoutSemi(parser: var Parser, decl: DeclaratorNode, canHaveInit: bool): VarDeclNode =
  result = parser.initNode(VarDeclNode)
  result.setBaseAstFields(decl)
  result.varName = decl.name
  result.typeData = decl.typeData
  let t = parser.peek()
  if canHaveInit and t.checkSymbol("="):
    parser.advance()
    result.init = parser.parseInitializer().some
  else:
    result.init = none(ExpressionNode)

proc parseVarDecl(parser: var Parser, decl: DeclaratorNode): VarDeclNode {.inline.} =
  result = parser.parseVarDeclWithoutSemi(decl, true)
  parser.parseSymbol(";", "Expected semicolon!")

proc parseLocalVarDecl(parser: var Parser): VarDeclNode {.inline.} =
  let baseType = parser.parseSimpleType()
  let decl = parser.parseDeclarator(baseType, false)
  parser.parseVarDecl(decl)

proc parseReturnStat(parser: var Parser): ReturnStatNode =
  result = parser.initNode(ReturnStatNode)
  parser.advance()
  if parser.peek().checkSymbol(";"):
    result.exp = none(ExpressionNode)
  else:
    result.exp = parser.parseExpression().some()
  parser.parseSymbol(";", "Expected semicolon!")
proc parseIfStat(parser: var Parser): IfStatNode =
  result = parser.initNode(IfStatNode)
  parser.advance()
  parser.parseSymbol("(", "Expected left paren!")
  result.cond = parser.parseExpression()
  parser.parseSymbol(")", "Expected right paren!")
  result.thenClause = parser.parseStatement()
  if parser.peek().checkKeyword(Else):
    parser.advance()
    result.elseClause = parser.parseStatement().some()
  else:
    result.elseClause = none(StatementNode)
proc parseWhileStat(parser: var Parser): WhileStatNode =
  result = parser.initNode(WhileStatNode)
  parser.advance()
  parser.parseSymbol("(", "Expected left paren!")
  result.cond = parser.parseExpression()
  parser.parseSymbol(")", "Expected right paren!")
  result.body = parser.parseStatement()
proc parseDoWhileStat(parser: var Parser): DoWhileStatNode =
  result = parser.initNode(DoWhileStatNode)
  parser.advance()
  result.body = parser.parseStatement()
  parser.parseKeyword(While, "Expected \"while\" keyword!")
  parser.parseSymbol("(", "Expected left paren!")
  result.cond = parser.parseExpression()
  parser.parseSymbol(")", "Expected right paren!")
  parser.parseSymbol(";", "Expected semicolon!")
proc parseForStat(parser: var Parser): ForStatNode =
  let n = parser.initNode(ForStatNode)
  parser.advance()
  parser.parseSymbol("(", "Expected left paren!")
  var t = parser.peek()
  if t.checkSymbol(";"):
    result = ForStatNode(kind: ForWithoutInit)
    result.setBaseAstFields(n)
    parser.advance()
  elif t.isType():
    result = ForStatNode(kind: ForWithDecl)
    result.setBaseAstFields(n)
    result.initDecl = parser.parseLocalVarDecl()
  else:
    result = ForStatNode(kind: ForWithExp)
    result.setBaseAstFields(n)
    result.initExp = parser.parseExpression()
    parser.parseSymbol(";", "Semicolon expected!")
  
  t = parser.peek()
  if t.checkSymbol(";"):
    result.cond = none(ExpressionNode)
  else:
    result.cond = parser.parseExpression().some()
  parser.parseSymbol(";", "Semicolon expected!")

  t = parser.peek()
  if t.checkSymbol(")"):
    result.postExp = none(ExpressionNode)
  else:
    result.postExp = parser.parseExpression().some()
  parser.parseSymbol(")", "Expected right paren!")

  result.body = parser.parseStatement()
proc parseExprStat(parser: var Parser): ExprStatNode =
  result = parser.initNode(ExprStatNode)
  result.exp = parser.parseExpression().some()
  parser.parseSymbol(";", "Expected semicolon!")
  
proc parseBlock(parser: var Parser): BlockNode =
  result = parser.initNode(BlockNode)
  let startToken = parser.getOne()
  var t = parser.peek()
  while t.kind != Eof and not t.checkSymbol("}"):
    result.items.add parser.parseBlockItem()
    t = parser.peek()
  if t.kind == Eof:
    startToken.raiseError("Couldn't find closing brace!")
  else:
    parser.advance()

proc parseStatement(parser: var Parser): StatementNode =
  let t = parser.peek()
  if t.kind == Keyword:
    case t.keyword:
      of Return: parser.parseReturnStat()
      of If: parser.parseIfStat()
      of While: parser.parseWhileStat()
      of Do: parser.parseDoWhileStat()
      of For: parser.parseForStat()
      of Break: 
        let r = parser.initNode(BreakStatNode)
        parser.advance()
        parser.parseSymbol(";", "Expected semicolon!")
        r
      of Continue: 
        let r = parser.initNode(ContinueStatNode)
        parser.advance()
        parser.parseSymbol(";", "Expected semicolon!")
        r
      else: t.raiseError("Expected statement!")
  elif t.checkSymbol("{"):
    parser.parseBlock()
  else:
    parser.parseExprStat()

proc parseBlockItem(parser: var Parser): BlockItemNode =
  let t = parser.peek()
  if t.isType():
    parser.parseLocalVarDecl()
  elif t.kind == Keyword:
    case t.keyword:
      of Return, If, Do, While, For, Break, Continue: 
        parser.parseStatement()
      else: t.raiseError("Expected statement or declaration!")
  elif t.checkSymbol("{"):
    parser.parseBlock()
  else:
    parser.parseExprStat()

proc parseFuncDecl(parser: var Parser, decl: DeclaratorNode): FuncDeclNode =
  result = parser.initNode(FuncDeclNode)
  result.setBaseAstFields(decl)
  result.name = decl.name
  result.params = @[]
  result.returnType = decl.typeData.funcReturnType[]
  for param in decl.typeData.paramDecls:
    var paramDecl = parser.initNode(VarDeclNode)
    paramDecl.setBaseAstFields(param)
    paramDecl.varName = param.name
    paramDecl.typeData = param.typeData
    result.params.add paramDecl
  if parser.peek().checkSymbol("{"):
    for param in decl.typeData.paramDecls:
      if param.name == "":
        parser.peek().raiseError("Cannot have unnamed arguments in function definition!")
    result.statements = parser.parseBlock().some()
  else:
    parser.parseSymbol(";", "Expected semicolon!")
    result.statements = none(BlockNode)

proc parseTypeDecl(parser: var Parser, decl: DeclaratorNode): TypeDeclNode {.inline.} =
  result = parser.initNode(TypeDeclNode)
  if decl.typeData.kind != StructType:
    parser.peek().raiseError("Cannot define types other than structs or unions!")
  result.setBaseAstFields(decl)
  result.typeData = decl.typeData
  parser.parseSymbol(";", "Expected semicolon!")

proc parseDeclaration(parser: var Parser): DeclarationNode =
  let baseType = parser.parseSimpleType()
  let decl = parser.parseDeclarator(baseType, true)
  if decl.typeData.kind == FunctionType:
    parser.parseFuncDecl(decl)
  elif decl.name == "":
    parser.parseTypeDecl(decl)
  else:
    parser.parseVarDecl(decl)

proc parseProgram(parser: var Parser): ProgramNode =
  result = parser.initNode(ProgramNode)
  while parser.peek().kind != Eof:
    result.declarations.add parser.parseDeclaration()

proc parse*(ts: TokenSequence): ProgramNode =
  var parser = Parser(input: ts, index: 0)
  parser.parseProgram()