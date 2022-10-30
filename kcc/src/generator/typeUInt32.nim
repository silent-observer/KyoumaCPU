when not declared(Generator):
  include common

proc getOtherRegUInt32(r: Register): Register {.inline.} =
  if r == Register(1): Register(2) else: Register(1)

proc test0UInt32(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  CMP {r}\p"
proc testTwoUInt32(g: var Generator, r1, r2: Register) {.inline.} =
  g.output &= &"  CMP {r1}, {r2}\p"
proc testConstUInt32(g: var Generator, r1: Register, num: int64) {.inline.} =
  if num == 0:
    g.output &= &"  CMP {r1}\p"
  else:
    g.output &= &"  CMP {r1}, {num}\p"
proc ltConditionUInt32(): string {.inline.} = "C"
proc geConditionUInt32(): string {.inline.} = "NC"

proc loadConstUInt32(g: var Generator, r: Register, num: int64) {.inline.} =
  g.output &= &"  LOAD {r}, {num and 0xFFFFFFFF}\p"

proc pushOnStackUInt32(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  SW (SP), {r}\p" &
              &"  SUBI SP, 4\p"

proc popFromStackUInt32(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  ADDI SP, 4\p" &
              &"  LW {r}, (SP)\p"

proc writeToAddrUInt32(address: Address, g: var Generator, dataReg: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      let otherReg = dataReg.getOtherRegUInt32()
      if offset != 0:
        g.output &= &"  LOAD {otherReg}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {otherReg}, {address.label}\p"
      g.output &= &"  SW ({otherReg}), {dataReg}\p"
    of RelativeFP:
      g.output &= &"  SW (FP{offset + address.fpOffset:+}), {dataReg}\p"
    of Expression:
      let otherReg = dataReg.getOtherRegUInt32()
      address.exp.generate(g, otherReg)
      g.output &= &"  SW ({otherReg}{offset:+}), {dataReg}\p"

proc readFromAddrUInt32(address: Address, g: var Generator, target: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      if offset != 0:
        g.output &= &"  LOAD {target}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {target}, {address.label}\p"
      g.output &= &"  LW {target}, ({target})\p"
    of RelativeFP:
      g.output &= &"  LW {target}, (FP{offset + address.fpOffset:+})\p"
    of Expression:
      address.exp.generate(g, target)
      g.output &= &"  LW {target}, ({target}{offset:+})\p"

proc writeToAddrInRegUInt32(g: var Generator, dataReg, addrReg: Register, offset: int = 0) =
  g.output &= &"  SW ({addrReg}{offset:+}), {dataReg}\p"

proc moveRegsUInt32(g: var Generator, dest, src: Register) {.inline.} =
  g.output &= &"  MOV {dest}, {src}\p"

proc generateUInt32(ast: UnaryExprNode, g: var Generator, target: Register) =
  if ast.exp of DereferenceExprNode and ast.operator in ["++", "--"]:
    let otherReg = target.getOtherRegUInt32()
    ast.exp.DereferenceExprNode.exp.generate(g, otherReg)
    g.output &= &"  LW {target}, ({otherReg})\p"
    if ast.operator == "++":
      g.output &= &"  ADDI {target}, 1\p"
    else:
      g.output &= &"  SUBI {target}, 1\p"
    g.writeToAddrInRegUInt32(target, otherReg)
    return
  if ast.operator notin ["++", "--"]:
    ast.exp.generate(g, target)
  case ast.operator:
    of "-": g.output &= &"  SUB {target}, R0, {target}\p"
    of "~": g.output &= &"  XORI {target}, -1\p"
    of "++", "--":
      let otherReg = target.getOtherRegUInt32()
      if ast.exp of VarNode:
        ast.raiseError("Unresolved increment!")
      elif not ast.exp.isLvalue:
        ast.raiseError(if ast.operator == "++": "Cannot increment rvalue!" else: "Cannot decrement rvalue!")
      
      let address = ast.exp.getAddress(g)
      if address.kind == RelativeFP:
        ast.exp.generate(g, target)
        if ast.operator == "++":
          g.output &= &"  ADDI {target}, 1\p"
        else:
          g.output &= &"  SUBI {target}, 1\p"
        address.writeToAddrUInt32(g, target)
      else:
        address.loadAddr(g, otherReg, false)
        g.output &= &"  LW {target}, ({otherReg}{address.offset:+})\p"
        if ast.operator == "++":
          g.output &= &"  ADDI {target}, 1\p"
        else:
          g.output &= &"  SUBI {target}, 1\p"
        g.writeToAddrInRegUInt32(target, otherReg, address.offset)
    else: assert(false)
  
proc generateUInt32(ast: PostfixExprNode, g: var Generator, target: Register) =
  if not ast.exp.isLvalue:
    ast.raiseError(
      if ast.operator == "++": "Cannot increment rvalue!" 
      else: "Cannot decrement rvalue!")

  let address = ast.exp.getAddress(g)
  let otherReg = target.getOtherRegUInt32()
  
  if address.kind == RelativeFP:
    ast.exp.generate(g, target)
    case ast.operator:
      of "++": g.output &= &"  ADDI {otherReg}, {target}, 1\p"
      of "--": g.output &= &"  SUBI {otherReg}, {target}, 1\p"
      else: assert(false)
    address.writeToAddrUInt32(g, otherReg)
  else:
    address.loadAddr(g, otherReg, false)
    g.output &= &"  LW {target}, ({otherReg}{address.offset:+})\p"
    if ast.operator == "++":
      g.output &= &"  ADDI {target}, 1\p"
    else:
      g.output &= &"  SUBI {target}, 1\p"
    g.writeToAddrInRegUInt32(target, otherReg)
    if ast.operator == "++":
      g.output &= &"  SUBI {target}, 1\p"
    else:
      g.output &= &"  ADDI {target}, 1\p"


proc generateUInt32(ast: BinaryExprNode, g: var Generator, target: Register) =
  let otherReg = target.getOtherRegUInt32()
  if g.shouldOptimize and ast.exp2.isOneLevel():
    ast.exp1.generate(g, otherReg)
    ast.exp2.generate(g, target)
  elif g.shouldOptimize and ast.exp1.isOneLevel():
    ast.exp2.generate(g, target)
    ast.exp1.generate(g, otherReg)
  else:
    ast.exp1.generate(g, target)
    g.output &= &"  SW (SP), {target}\p" &
                &"  SUBI SP, 4\p"
    ast.exp2.generate(g, target)
  
    g.output &= &"  ADDI SP, 4\p" &
                &"  LW {otherReg}, (SP)\p"
  # Operands: otherReg <op> target
  case ast.operator:
    of "-": g.output &= &"  SUB {target}, {otherReg}, {target}\p"
    of "+": g.output &= &"  ADD {target}, {otherReg}, {target}\p"
    of "*": g.output &= 
        &"  MLTU {otherReg}, {target}\p" &
        &"  MOV {target}, LO\p"
    of "/": g.output &= 
        &"  DIVU {otherReg}, {target}\p" &
         "  NOP\p".repeat(11) &
        &"  MOV {target}, LO\p"
    of "%": g.output &= 
        &"  DIVU {otherReg}, {target}\p" &
         "  NOP\p".repeat(11) &
        &"  MOV {target}, HI\p"
    of "==": g.output &= 
        &"  CMP {target}, {otherReg}\p" &
        &"  LDI?Z* {target}, 1\p" &
        &"  LDI?NZ* {target}, 0\p"
    of "!=": g.output &= 
        &"  CMP {target}, {otherReg}\p" &
        &"  LDI?Z* {target}, 0\p" &
        &"  LDI?NZ* {target}, 1\p"
    of "<": g.output &= 
        &"  CMP {otherReg}, {target}\p" &
        &"  LDI?C* {target}, 1\p" &
        &"  LDI?NC* {target}, 0\p"
    of ">=": g.output &= 
        &"  CMP {otherReg}, {target}\p" &
        &"  LDI?C* {target}, 0\p" &
        &"  LDI?NC* {target}, 1\p"
    of ">": g.output &= 
        &"  CMP {target}, {otherReg}\p" &
        &"  LDI?C* {target}, 1\p" &
        &"  LDI?NC* {target}, 0\p"
    of "<=": g.output &= 
        &"  CMP {target}, {otherReg}\p" &
        &"  LDI?C* {target}, 0\p" &
        &"  LDI?NC* {target}, 1\p"
    of "<<": g.output &= &"  LSH {target}, {otherReg}, {target}\p"
    of ">>": g.output &=
      &"  SUB {target}, R0, {target}\p" &
      &"  LSH {target}, {otherReg}, {target}\p"
    of "&": g.output &= &"  AND {target}, {otherReg}, {target}\p"
    of "^": g.output &= &"  XOR {target}, {otherReg}, {target}\p"
    of "|": g.output &= &"  OR {target}, {otherReg}, {target}\p"
    else: assert(false)

proc generateUInt32(ast: BinaryRightConstExprNode, g: var Generator, target: Register) =
  let otherReg = target.getOtherRegUInt32()
  ast.exp1.generate(g, target)
  # Operands: target <op> num
  if ast.num == 0:
    case ast.operator:
      of "<<", ">>", "^", "|", "+", "-": discard
      of "*", "&": g.output &= &"  MOV {target}, R0\p"
      of "/": g.output &= 
          &"  LOAD {otherReg}, {ast.num and 0xFFFFFFFF}\p" &
          &"  DIVU {target}, {otherReg}\p" &
           "  NOP\p".repeat(11) &
          &"  MOV {target}, LO\p"
      of "%": g.output &= 
          &"  LOAD {otherReg}, {ast.num and 0xFFFFFFFF}\p" &
          &"  DIVU {target}, {otherReg}\p" &
           "  NOP\p".repeat(11) &
          &"  MOV {target}, HI\p"
      of "==": g.output &= 
          &"  CMP {target}\p" &
          &"  LDI?Z* {target}, 1\p" &
          &"  LDI?NZ* {target}, 0\p"
      of "!=": g.output &= 
          &"  CMP {target}\p" &
          &"  LDI?Z* {target}, 0\p" &
          &"  LDI?NZ* {target}, 1\p"
      of "<": g.output &= 
          &"  CMP {target}\p" &
          &"  LDI?C* {target}, 1\p" &
          &"  LDI?NC* {target}, 0\p"
      of ">=": g.output &= 
          &"  CMP {target}\p" &
          &"  LDI?C* {target}, 0\p" &
          &"  LDI?NC* {target}, 1\p"
      of ">": g.output &= 
          &"  CMP R0, {target}\p" &
          &"  LDI?C* {target}, 1\p" &
          &"  LDI?NC* {target}, 0\p"
      of "<=": g.output &= 
          &"  CMP R0, {target}\p" &
          &"  LDI?C* {target}, 0\p" &
          &"  LDI?NC* {target}, 1\p"
      else: assert(false)
  else:
    case ast.operator:
      of "-": g.output &= &"  SUBI {target}, {ast.num}\p"
      of "+": g.output &= &"  ADDI {target}, {ast.num}\p"
      of "*": g.multiplyByConst(target, ast.num.int)
      of "/": g.output &= 
          &"  LOAD {otherReg}, {ast.num and 0xFFFFFFFF}\p" &
          &"  DIVU {target}, {otherReg}\p" &
          "  NOP\p".repeat(11) &
          &"  MOV {target}, LO\p"
      of "%": g.output &= 
          &"  LOAD {otherReg}, {ast.num and 0xFFFFFFFF}\p" &
          &"  DIVU {target}, {otherReg}\p" &
          "  NOP\p".repeat(11) &
          &"  MOV {target}, HI\p"
      of "==": 
        g.output &= 
          &"  CMP {target}, {ast.num}\p" &
          &"  LDI?Z* {target}, 1\p" &
          &"  LDI?NZ* {target}, 0\p"
      of "!=": g.output &= 
          &"  CMP {target}, {ast.num}\p" &
          &"  LDI?Z* {target}, 0\p" &
          &"  LDI?NZ* {target}, 1\p"
      of "<": g.output &= 
          &"  CMP {target}, {ast.num}\p" &
          &"  LDI?C* {target}, 1\p" &
          &"  LDI?NC* {target}, 0\p"
      of ">=": g.output &= 
          &"  CMP {target}, {ast.num}\p" &
          &"  LDI?C* {target}, 0\p" &
          &"  LDI?NC* {target}, 1\p"
      of ">": g.output &= 
          &"  LOAD {otherReg}, {ast.num and 0xFFFFFFFF}\p" &
          &"  CMP {otherReg}, {target}\p" &
          &"  LDI?C* {target}, 1\p" &
          &"  LDI?NC* {target}, 0\p"
      of "<=": g.output &= 
          &"  LOAD {otherReg}, {ast.num and 0xFFFFFFFF}\p" &
          &"  CMP {otherReg}, {target}\p" &
          &"  LDI?C* {target}, 0\p" &
          &"  LDI?NC* {target}, 1\p"
      of "<<": g.output &= &"  LSHI {target}, {ast.num}\p"
      of ">>": g.output &= &"  LSHI {target}, {-ast.num}\p"
      of "&": g.output &= &"  ANDI {target}, {ast.num}\p"
      of "^": g.output &= &"  XORI {target}, {ast.num}\p"
      of "|": g.output &= &"  ORI {target}, {ast.num}\p"
      else: assert(false)

proc generateUInt32(ast: ConvertExprNode, g: var Generator, target: Register) =
  ast.exp.generate(g, target)
  let t = ast.exp.typeData
  case t.kind:
    of UnknownType: assert(false, "Convert from unknown type!")
    of VoidType: assert(false, "Convert from void type!")
    of FunctionType: assert(false, "Convert from function type!")
    of StructType: assert(false, "Convert from struct type!")
    of ArrayType, ArrayOfUnknownSizeType: assert(false, "Convert from array type!")
    of PointerType: discard
    of SimpleType:
      case t.simpleType:
        of Int8, Int16, Int32,
           UInt8, UInt16, UInt32: discard