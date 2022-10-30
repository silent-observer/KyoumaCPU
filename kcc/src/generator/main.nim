const IncludeFix {.used.} = 0

when not declared(Generator):
  include common

include typeInt32, typeInt16, typeInt8
include typeUInt32, typeUInt16, typeUInt8
include typePointer

defineChooseByType:
  proc test0(g: var Generator, r: Register) {.inline.} =
    {simpleType: [Int32, UInt32], ptrType: true}
  proc testTwo(g: var Generator, r1, r2: Register) {.inline.} =
    {simpleType: [Int32, UInt32], ptrType: true}
  proc testConst(g: var Generator, r1: Register, num: int64) {.inline.} =
    {simpleType: [Int32, UInt32], ptrType: true}
  proc ltCondition(): string {.inline.} =
    {simpleType: [Int32, UInt32], ptrType: true}
  proc geCondition(): string {.inline.} =
    {simpleType: [Int32, UInt32], ptrType: true}
  proc pushOnStack(g: var Generator, r: Register) {.inline.} =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}
  proc popFromStack(g: var Generator, r: Register) {.inline.} =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}
  proc loadConst(g: var Generator, r: Register, num: int64) {.inline.} =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}
  proc writeToAddr(address: Address, g: var Generator, dataReg: Register) =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}
  proc readFromAddr(address: Address, g: var Generator, target: Register) =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}
  proc writeToAddrInReg(g: var Generator, dataReg, addrReg: Register, offset: int) =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}
  proc getOtherReg(r: Register): Register {.inline.} =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}
  proc moveRegs(g: var Generator, dest, src: Register) {.inline.} =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}

method jumpIf(ast: ExpressionNode, g: var Generator, ifTrue, ifFalse: string) {.base.} =
  ast.generate(g, Register(1))
  g.test0(Register(1), ast.typeData)
  if ifTrue != "":
    g.output &= &"  JMP?NZ* {ifTrue}\p"
  if ifFalse != "":
    g.output &= &"  JMP?Z* {ifFalse}\p"

method jumpIf(ast: ConstNumberNode, g: var Generator, ifTrue, ifFalse: string) =
  if not g.shouldOptimize:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)
    return
  
  if ast.num == 0:
    if ifFalse != "":
      g.output &= &"  JMP {ifFalse}\p"
  else:
    if ifTrue != "":
      g.output &= &"  JMP {ifTrue}\p"
method jumpIf(ast: UnaryExprNode, g: var Generator, ifTrue, ifFalse: string) =
  if not g.shouldOptimize:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)
    return

  if ast.operator == "!":
    ast.exp.jumpIf(g, ifFalse, ifTrue)
  else:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)
method jumpIf(ast: ConvertExprNode, g: var Generator, ifTrue, ifFalse: string) =
  if not g.shouldOptimize:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)
    return

  ast.exp.jumpIf(g, ifTrue, ifFalse)
method jumpIf(ast: BinaryExprNode, g: var Generator, ifTrue, ifFalse: string) =
  if not g.shouldOptimize:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)
    return
  
  let r1 = Register(1)
  let r2 = r1.getOtherReg(ast.typeData)
  
  if ast.operator in ["==", "!=", "<", ">", "<=", ">="]:
    if g.shouldOptimize and ast.exp2.isOneLevel():
      ast.exp1.generate(g, r2)
      ast.exp2.generate(g, r1)
    elif g.shouldOptimize and ast.exp1.isOneLevel():
      ast.exp2.generate(g, r1)
      ast.exp1.generate(g, r2)
    else:
      ast.exp1.generate(g, r1)
      g.pushOnStack(r1, ast.typeData)
      ast.exp2.generate(g, r1)
      g.popFromStack(r2, ast.typeData)
    # Order: R2 <op> R1
    case ast.operator:
      of "==": 
        g.testTwo(r1, r2, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?Z* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?NZ* {ifFalse}\p")
      of "!=": 
        g.testTwo(r1, r2, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?NZ* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?Z* {ifFalse}\p")
      of "<": 
        g.testTwo(r2, r1, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifFalse}\p")
      of ">=": 
        g.testTwo(r2, r1, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifFalse}\p")
      of ">": 
        g.testTwo(r1, r2, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifFalse}\p")
      of "<=":
        g.testTwo(r1, r2, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifFalse}\p")
  elif ast.operator == "||":
    if ifTrue != "":
      ast.exp1.jumpIf(g, ifTrue, "")
      ast.exp2.jumpIf(g, ifTrue, ifFalse)
    else:
      let label = g.generateLabel("jumpIfOr")
      ast.exp1.jumpIf(g, label, "")
      ast.exp2.jumpIf(g, "", ifFalse)
      g.output &= &"{label}:\p"
  elif ast.operator == "&&":
    if ifFalse != "":
      ast.exp1.jumpIf(g, "", ifFalse)
      ast.exp2.jumpIf(g, ifTrue, ifFalse)
    else:
      let label = g.generateLabel("jumpIfAnd")
      ast.exp1.jumpIf(g, "", label)
      ast.exp2.jumpIf(g, ifTrue, "")
      g.output &= &"{label}:\p"
  else:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)
method jumpIf(ast: BinaryRightConstExprNode, g: var Generator, ifTrue, ifFalse: string) =
  if not g.shouldOptimize:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)
    return
  
  let r1 = Register(1)
  let r2 = r1.getOtherReg(ast.typeData)

  if ast.operator in ["==", "!=", "<", ">", "<=", ">="]:
    ast.exp1.generate(g, r1)
    # Order: R1 <op> num
    case ast.operator:
      of "==":
        g.testConst(r1, ast.num, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?Z* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?NZ* {ifFalse}\p")
      of "!=": 
        g.testConst(r1, ast.num, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?NZ* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?Z* {ifFalse}\p")
      of "<": 
        g.testConst(r1, ast.num, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifFalse}\p")
      of ">=": 
        g.testConst(r1, ast.num, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifFalse}\p")
      of ">": 
        g.loadConst(r2, ast.num, ast.typeData)
        g.testTwo(r2, r1, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifFalse}\p")
      of "<=": 
        g.loadConst(r2, ast.num, ast.typeData)
        g.testTwo(r2, r1, ast.typeData)
        g.output &= 
          (if ifTrue == "": "" else: &"  JMP?{ast.typeData.geCondition}* {ifTrue}\p") &
          (if ifFalse == "": "" else: &"  JMP?{ast.typeData.ltCondition}* {ifFalse}\p")
  elif ast.operator == "||":
    if ast.num == 0:
      ast.exp1.jumpIf(g, ifTrue, "")
      if ifFalse != "":
        g.output &= &"  JMP {ifFalse}\p"
    else:
      ast.exp1.generate(g, r1)
      if ifTrue != "":
        g.output &= &"  JMP {ifTrue}\p"
  elif ast.operator == "&&":
    if ast.num != 0:
      ast.exp1.jumpIf(g, "", ifFalse)
      if ifTrue != "":
        g.output &= &"  JMP {ifTrue}\p"
    else:
      ast.exp1.generate(g, r1)
      if ifFalse != "":
        g.output &= &"  JMP {ifFalse}\p"
  else:
    procCall jumpIf(ast.ExpressionNode, g, ifTrue, ifFalse)

method generate(ast: ProgramNode, g: var Generator) =
  for d in ast.declarations:
    d.generate(g)

proc generate*(ast: ProgramNode, shouldOptimize: bool): string =
  var g = initGenerator(shouldOptimize)
  ast.generate(g)
  g.output & g.outputData & g.outputRodata & g.outputBss

method generate(ast: FuncDeclNode, g: var Generator) =
  if ast.statements.isNone():
    return
  g.output &= ast.name & ":\p"
  g.currentFunc = ast
  g.currentLabelCounter = 1

  g.output &= "  SW (SP), FP\p" &
              "  SUBI SP, 4\p" &
              "  MOV FP, SP\p"
  if ast.maxStack != 0:
    g.output &= &"  SUBI SP, {ast.maxStack}\p"
  g.output &= "\p"
  for s in ast.statements.get().items:
    s.generate(g)
  if ast.statements.get().items.len == 0 or 
      not (ast.statements.get().items[^1] of ReturnStatNode):
    if ast.name == "main":
      g.output &= &"  MOV R1, R0\p"
    if g.currentFunc.maxStack != 0:
      g.output &= &"  ADDI SP, {g.currentFunc.maxStack}\p"
    g.output &= "  ADDI SP, FP, 4\p" &
                "  LW FP, (SP)\p" &
                "  MOV PC, LR\p\p"
  g.output &= "\p"

method generate(ast: ReturnStatNode, g: var Generator) =
  if ast.exp.isSome():
    ast.exp.get().generate(g, Register(1))
  if g.currentFunc.maxStack != 0:
    g.output &= &"  ADDI SP, {g.currentFunc.maxStack}\p"
  g.output &= "  ADDI SP, FP, 4\p" &
              "  LW FP, (SP)\p" &
              "  MOV PC, LR\p\p"
method generate(ast: ExprStatNode, g: var Generator) =
  if ast.exp.isSome():
    ast.exp.get().generate(g, Register(1))
    g.output &= "\p"
method generate(ast: IfStatNode, g: var Generator) =
  let endLabel = g.generateLabel("ifEnd")
  let elseLabel = if ast.elseClause.isSome: g.generateLabel("ifElse") else: ""

  if ast.elseClause.isSome:
    ast.cond.jumpIf(g, "", elseLabel)
    ast.thenClause.generate(g)
    g.output &= &"  JMP {endLabel}\p" &
                &"{elseLabel}:\p"
    ast.elseClause.get().generate(g)
    g.output &= &"{endLabel}:\p"
  else:
    ast.cond.jumpIf(g, "", endLabel)
    ast.thenClause.generate(g)
    g.output &= &"{endLabel}:\p"

method generate(ast: WhileStatNode, g: var Generator) =
  let startLabel = g.generateLabel("whileStart")
  let endLabel = g.generateLabel("whileEnd")
  
  g.output &= &"{startLabel}:\p"
  ast.cond.jumpIf(g, "", endLabel)

  g.continueStack.add startLabel
  g.breakStack.add endLabel
  ast.body.generate(g)
  discard g.continueStack.pop()
  discard g.breakStack.pop()

  g.output &= &"  JMP {startLabel}\p" &
              &"{endLabel}:\p"

method generate(ast: DoWhileStatNode, g: var Generator) =
  let startLabel = g.generateLabel("doWhileStart")
  let testLabel = g.generateLabel("doWhileTest")
  let endLabel = g.generateLabel("doWhileEnd")
  
  g.output &= &"{startLabel}:\p"

  g.continueStack.add testLabel
  g.breakStack.add endLabel
  ast.body.generate(g)
  discard g.continueStack.pop()
  discard g.breakStack.pop()

  g.output &= &"{testLabel}:\p"
  ast.cond.jumpIf(g, startLabel, "")
  g.output &= &"{endLabel}:\p"

method generate(ast: ForStatNode, g: var Generator) =
  let startLabel = g.generateLabel("forStart")
  let continueLabel = g.generateLabel("forContinue")
  let endLabel = g.generateLabel("forEnd")
  
  case ast.kind:
    of ForWithDecl: ast.initDecl.generate(g)
    of ForWithExp: ast.initExp.generate(g, Register(1))
    of ForWithoutInit: discard

  g.output &= &"{startLabel}:\p"
  if ast.cond.isSome():
    ast.cond.get().jumpIf(g, "", endLabel)

  g.continueStack.add continueLabel
  g.breakStack.add endLabel
  ast.body.generate(g)
  discard g.continueStack.pop()
  discard g.breakStack.pop()

  g.output &= &"{continueLabel}:\p"

  if ast.postExp.isSome():
    ast.postExp.get().generate(g, Register(1))

  g.output &= &"  JMP {startLabel}\p" &
              &"{endLabel}:\p"

method generate(ast: BreakStatNode, g: var Generator) =
  if g.breakStack.len == 0:
    ast.raiseError("Cannot use \"break\" when outside of loops!")
  g.output &= &"  JMP {g.breakStack[^1]}\p"
method generate(ast: ContinueStatNode, g: var Generator) =
  if g.continueStack.len == 0:
    ast.raiseError("Cannot use \"continue\" when outside of loops!")
  g.output &= &"  JMP {g.continueStack[^1]}\p"

method generate(ast: BlockNode, g: var Generator) =
  for i in ast.items:
    i.generate(g)

proc defineDataByValue(size, num: int64): string {.locks: 0.} =
  case size:
    of 1: &"  DB {num and 0xFF}\p"
    of 2: &"  DH {num and 0xFFFF}\p"
    of 4: &"  DW {num}\p"
    else: ""
proc defineDataByValue(ast: ExpressionNode): string {.locks: 0.} =
  if ast of ConstNumberNode:
    return defineDataByValue(ast.typeData.getSize, ast.ConstNumberNode.num)
  elif ast of ConstArrayInitializerNode:
    for e in ast.ConstArrayInitializerNode.elems:
      let size = e.typeData.getSize
      let alignedSize = e.typeData.getAlignedSize
      result &= defineDataByValue(e)
      for i in size+1..alignedSize:
        result &= "  DB 0\p"
  elif ast of StringLiteralNode:
    result &= "  ; " & ast.StringLiteralNode.str.escape & "\p"
    result &= "  DB "
    for c in ast.StringLiteralNode.str:
      result &= $c.byte & ", "
    result &= "0\p"

proc valueToBytes(size, num: int64): seq[byte] {.locks: 0.} =
  case size:
    of 1: @[byte(num and 0xFF)]
    of 2: @[byte(num and 0xFF), byte(num shr 8 and 0xFF)]
    of 4: @[byte(num and 0xFF), byte(num shr 8 and 0xFF), 
            byte(num shr 16 and 0xFF), byte(num shr 24 and 0xFF)]
    else: @[]
proc valueToBytes(ast: ExpressionNode): seq[byte] {.locks: 0.} =
  if ast of ConstNumberNode:
    return valueToBytes(ast.typeData.getSize, ast.ConstNumberNode.num)
  elif ast of ConstArrayInitializerNode:
    for e in ast.ConstArrayInitializerNode.elems:
      let size = e.typeData.getSize
      let alignedSize = e.typeData.getAlignedSize
      result &= valueToBytes(e)
      for i in size+1..alignedSize:
        result.add 0

proc initWithConstArray(init: ConstArrayInitializerNode, ast: VarDeclNode, g: var Generator) {.locks: 0.} =
  if ast.isGlobal:
    g.outputData &= &"{ast.varName}:\p";
    g.outputData &= init.defineDataByValue()
  elif ast.typeData.getAlignedSize <= 20:
    let data = init.valueToBytes()
    let size = ast.typeData.getSize

    var i = 0
    let lwSize = size div 4

    var lastX = 0
    var hadX = false
    for j in 0..<lwSize:
      let x = data[i].int32 or 
              data[i+1].int32 shl 8 or
              data[i+2].int32 shl 16 or
              data[i+3].int32 shl 24
      if x == 0:
        g.output &= &"  SW (FP{ast.offset+i:+}), R0\p"
      else:
        if not hadX or x != lastX:
          g.output &= &"  LOAD R1, {x}\p"
          hadX = true
          lastX = x
        g.output &= &"  SW (FP{ast.offset+i:+}), R1\p"
      i += 4
    case size mod 4:
      of 0: discard
      of 1: g.output &= 
        &"  LOAD R1, {data[i]}\p" &
        &"  SB (FP{ast.offset+i:+}), R1\p"
      of 2: 
        let x = data[i].int32 or data[i+1].int32 shl 8
        g.output &= 
          &"  LOAD R1, {x}\p" &
          &"  SH (FP{ast.offset+i:+}), R1\p"
      of 3:
        let x = data[i].int32 or data[i+1].int32 shl 8
        g.output &= 
          &"  LOAD R1, {x}\p" &
          &"  SH (FP{ast.offset+i:+}), R1\p" &
          &"  LOAD R1, {data[i+2]}\p" &
          &"  SB (FP{ast.offset+i+2:+}), R1\p"
      else: discard
  else:
    let rodataLabel = g.generateLabel("initRodata")
    let loopLabel = g.generateLabel("initLoop")
    g.outputRodata &= 
      &"#align 4\p" &
      &"{rodataLabel}:\p"
    g.outputRodata &= init.defineDataByValue()
    let size = ast.typeData.getSize
    let lwSize = size div 4

    g.output &= 
      &"  LOAD R1, {rodataLabel}\p" &
      &"  ADDI R2, FP, {ast.offset}\p" &
      &"  LOAD R3, {lwSize}\p" &
      &"{loopLabel}:\p" &
      &"  LW R4, (R1)\p" &
      &"  SW (R2), R4\p" &
      &"  ADDI R1, 4\p" &
      &"  ADDI R2, 4\p" &
      &"  SUBI R3, 1\p" &
      &"  JMP?NZ {loopLabel}\p"
    case size mod 4:
      of 0: discard
      of 1: g.output &= 
        &"  LBU R4, (R1)\p" &
        &"  SB (R2), R4\p"
      of 2: g.output &= 
        &"  LHU R4, (R1)\p" &
        &"  SH (R2), R4\p"
      of 3: g.output &= 
        &"  LHU R4, (R1)\p" &
        &"  SH (R2), R4\p" &
        &"  LBU R4, (R1+2)\p" &
        &"  SB (R2+2), R4\p"
      else: discard

proc initWithString(init: StringLiteralNode, ast: VarDeclNode, g: var Generator) {.locks: 0.} =
  if ast.isGlobal:
    g.outputData &= &"{ast.varName}:\p"
    g.outputData &= init.defineDataByValue()
  else:
    let rodataLabel = g.generateLabel("initRodata")
    let loopLabel = g.generateLabel("initLoop")
    g.outputRodata &= 
      &"#align 4\p" &
      &"{rodataLabel}:\p"
    g.outputRodata &= init.defineDataByValue()
    let size = ast.typeData.getSize
    let lwSize = size div 4

    g.output &= 
      &"  LOAD R1, {rodataLabel}\p" &
      &"  ADDI R2, FP, {ast.offset}\p" &
      &"  LOAD R3, {lwSize}\p" &
      &"{loopLabel}:\p" &
      &"  LW R4, (R1)\p" &
      &"  SW (R2), R4\p" &
      &"  ADDI R1, 4\p" &
      &"  ADDI R2, 4\p" &
      &"  SUBI R3, 1\p" &
      &"  JMP?NZ {loopLabel}\p"
    case size mod 4:
      of 0: discard
      of 1: g.output &= 
        &"  LBU R4, (R1)\p" &
        &"  SB (R2), R4\p"
      of 2: g.output &= 
        &"  LHU R4, (R1)\p" &
        &"  SH (R2), R4\p"
      of 3: g.output &= 
        &"  LHU R4, (R1)\p" &
        &"  SH (R2), R4\p" &
        &"  LBU R4, (R1+2)\p" &
        &"  SB (R2+2), R4\p"
      else: discard

proc initWithArray(init: ArrayInitializerNode, ast: VarDeclNode, g: var Generator) {.locks: 0.} =
  let elemSize = ast.typeData.elemType[].getAlignedSize
  var i = 0
  for e in init.elems:
    e.generate(g, Register(1))
    let address = Address(kind: RelativeFP, fpOffset: ast.offset, offset: i)
    address.writeToAddr(g, Register(1), ast.typeData)
    i += elemSize

method generate(ast: TypeDeclNode, g: var Generator) =
  discard
method generate(ast: VarDeclNode, g: var Generator) =
  if ast.isGlobal:
    if ast.init.isNone():
      g.outputBss &= &"{ast.varName}:\p"
      var s = ast.typeData.getSize
      if s >= 4:
        g.outputBss &= "  DW "
        while s >= 4:
          g.outputBss &= "0"
          if s >= 8: g.outputBss &= ", "
          s -= 4
        g.outputBss &= "\p"
      g.outputBss &= (case s:
        of 1: "  DB 0\p"
        of 2: "  DH 0\p"
        of 3: "  DH 0\p" & "  DB 0\p"
        of 4: "  DW 0\p"
        else: "")
    else:
      let init = ast.init.get()
      if init of ConstNumberNode:
        g.outputData &= &"{ast.varName}:\p";
        g.outputData &= init.defineDataByValue()
      elif init of ConstArrayInitializerNode:
        init.ConstArrayInitializerNode.initWithConstArray(ast, g)
      else:
        ast.raiseError("Cannot initialize global variable with non-const expression!")
  elif ast.init.isSome:
    let init = ast.init.get()
    if init of ConstArrayInitializerNode:
      init.ConstArrayInitializerNode.initWithConstArray(ast, g)
      g.output &= "\p"
    elif init of ArrayInitializerNode:
      init.ArrayInitializerNode.initWithArray(ast, g)
      g.output &= "\p"
    elif init of StringLiteralNode:
      init.StringLiteralNode.initWithString(ast, g)
      g.output &= "\p"
    else:
      init.generate(g, Register(1))
      let address = Address(kind: RelativeFP, fpOffset: ast.offset, offset: 0)
      address.writeToAddr(g, Register(1), ast.typeData)
      g.output &= "\p"

method generate(ast: AssignExprNode, g: var Generator, target: Register) =
  if ast.variable of DereferenceExprNode:
    # (<target>) <- <otherReg>
    let otherReg = target.getOtherReg(ast.typeData)
    if g.shouldOptimize and ast.variable.isOneLevel():
      ast.exp.generate(g, otherReg)
      ast.variable.DereferenceExprNode.exp.generate(g, target)
    elif g.shouldOptimize and ast.exp.isOneLevel():
      ast.variable.DereferenceExprNode.exp.generate(g, target)
      ast.exp.generate(g, otherReg)
    else:
      ast.exp.generate(g, target)
      g.pushOnStack(target, ast.exp.typeData)
      ast.variable.DereferenceExprNode.exp.generate(g, target)
      g.popFromStack(otherReg, ast.exp.typeData)
    g.writeToAddrInReg(otherReg, target, 0, ast.exp.typeData)
  elif ast.variable of VarNode:
    ast.raiseError("Unresolved assignment!")
  elif not ast.variable.isLvalue:
    ast.raiseError("Attempt to assign to rvalue!")
  else:
    ast.exp.generate(g, target)
    let address = ast.variable.getAddress(g)
    address.writeToAddr(g, target, ast.typeData)

method generate(ast: CommaExprNode, g: var Generator, target: Register) =
  ast.exp1.generate(g, target)
  ast.exp2.generate(g, target)

method generate(ast: VarNode, g: var Generator, target: Register) =
  ast.raiseError("Unresolved variable!")
method generate(ast: ResolvedVarNode, g: var Generator, target: Register) =
  let address = ast.getAddress(g)
  address.readFromAddr(g, target, ast.typeData)
method generate(ast: DotExprNode, g: var Generator, target: Register) =
  let address = ast.getAddress(g)
  address.readFromAddr(g, target, ast.typeData)

method generate(ast: DereferenceExprNode, g: var Generator, target: Register) =
  let address = Address(kind: Expression, exp: ast.exp, offset: 0)
  address.readFromAddr(g, target, ast.typeData)

method generate(ast: AddressExprNode, g: var Generator, target: Register) =
  let address = ast.exp.getAddress(g)
  case address.kind:
    of Label: 
      g.output &= &"  LOAD {target}, {address.label}"
      if address.offset != 0:
        g.output &= &"{address.offset:+}"
      g.output &= "\p"
    of RelativeFP:
      g.output &= &"  ADDI {target}, FP, {address.fpOffset + address.offset}\p"
    of Expression:
      address.exp.generate(g, target)
      if address.offset != 0:
        g.output &= &"  ADDI {target}, {address.offset}\p"

method generate(ast: FuncCallNode, g: var Generator, target: Register) =
  g.output &= "  SW (SP), LR\p" &
              "  SUBI SP, 4\p"
  for i in countdown(ast.args.len - 1, 0):
    ast.args[i].generate(g, target)
    g.pushOnStack(target, ast.args[i].typeData)
  g.output &= &"  ADDI LR, PC, 8\p" &
              &"  JMPL {ast.funcName}\p"
  let offset = ast.args.len * 4 + 4
  g.output &= &"  ADDI SP, {offset}\p" &
              &"  LW LR, (SP)\p"
  if target != Register(1):
    g.moveRegs(target, Register(1), ast.typeData)

method generate(ast: ConstNumberNode, g: var Generator, target: Register) =
  g.loadConst(target, ast.num, ast.typeData)

method generate(ast: TernaryExprNode, g: var Generator, target: Register) =
  let endLabel = g.generateLabel("ternaryEnd")
  let elseLabel = g.generateLabel("ternaryElse")

  ast.cond.jumpIf(g, "", elseLabel)
  ast.thenClause.generate(g, target)
  g.output &= &"  JMP {endLabel}\p" &
              &"{elseLabel}:\p"
  ast.thenClause.generate(g, target)
  g.output &= &"{endLabel}:\p"

method getAddress(ast: ExpressionNode, g: var Generator): Address {.base.} =
  ast.raiseError("Cannot take address of rvalue!")
method getAddress(ast: VarNode, g: var Generator): Address =
  ast.raiseError("Unresolved address!")
method getAddress(ast: StringLiteralNode, g: var Generator): Address =
  let rodataLabel = g.generateLabel("strRodata")
  g.outputRodata &= 
    &"#align 4\p" &
    &"{rodataLabel}:\p"
  g.outputRodata &= ast.defineDataByValue()
  Address(kind: Label, label: rodataLabel, offset: 0)
method getAddress(ast: ResolvedVarNode, g: var Generator): Address =
  if ast.isGlobal:
    Address(kind: Label, label: ast.varName, offset: 0)
  else:
    Address(kind: RelativeFP, fpOffset: ast.offset, offset: 0)
method getAddress(ast: DereferenceExprNode, g: var Generator): Address =
  Address(kind: Expression, exp: ast.exp, offset: 0)
method getAddress(ast: DotExprNode, g: var Generator): Address =
  result = ast.exp.getAddress(g)
  result.offset += ast.offset

defineChooseByType:
  method generate(ast: UnaryExprNode, g: var Generator, target: Register) =
    {simpleType: [Int32, UInt32], ptrType: true}
  method generate(ast: PostfixExprNode, g: var Generator, target: Register) =
    {simpleType: [Int32, UInt32], ptrType: true}
  method generate(ast: BinaryExprNode, g: var Generator, target: Register) =
    {simpleType: [Int32, UInt32], ptrType: true}
  method generate(ast: BinaryRightConstExprNode, g: var Generator, target: Register) =
    {simpleType: [Int32, UInt32], ptrType: true}
  method generate(ast: ConvertExprNode, g: var Generator, target: Register) =
    {simpleType: [Int8, Int16, Int32, UInt8, UInt16, UInt32], ptrType: true}