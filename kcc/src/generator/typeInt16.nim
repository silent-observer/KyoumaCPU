when not declared(Generator):
  include common

proc getOtherRegInt16(r: Register): Register {.inline.} =
  if r == Register(1): Register(2) else: Register(1)

proc loadConstInt16(g: var Generator, r: Register, num: int64) {.inline.} =
  g.output &= &"  LDI {r}, {num.toSignedHalfWord}\p"

proc pushOnStackInt16(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  SH (SP), {r}\p" &
              &"  SUBI SP, 4\p"

proc popFromStackInt16(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  ADDI SP, 4\p" &
              &"  LHS {r}, (SP)\p"

proc writeToAddrInt16(address: Address, g: var Generator, dataReg: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      let otherReg = dataReg.getOtherRegInt16()
      if offset != 0:
        g.output &= &"  LOAD {otherReg}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {otherReg}, {address.label}\p"
      g.output &= &"  SH ({otherReg}), {dataReg}\p"
    of RelativeFP:
      g.output &= &"  SH (FP{offset + address.fpOffset:+}), {dataReg}\p"
    of Expression:
      let otherReg = dataReg.getOtherRegInt16()
      address.exp.generate(g, otherReg)
      g.output &= &"  SH ({otherReg}{offset:+}), {dataReg}\p"

proc readFromAddrInt16(address: Address, g: var Generator, target: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      if offset != 0:
        g.output &= &"  LOAD {target}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {target}, {address.label}\p"
      g.output &= &"  LHS {target}, ({target})\p"
    of RelativeFP:
      g.output &= &"  LHS {target}, (FP{offset + address.fpOffset:+})\p"
    of Expression:
      address.exp.generate(g, target)
      g.output &= &"  LHS {target}, ({target}{offset:+})\p"

proc writeToAddrInRegInt16(g: var Generator, dataReg, addrReg: Register, offset: int = 0) =
  g.output &= &"  SH ({addrReg}{offset:+}), {dataReg}\p"

proc moveRegsInt16(g: var Generator, dest, src: Register) {.inline.} =
  g.output &= &"  MOV {dest}, {src}\p"

proc generateInt16(ast: ConvertExprNode, g: var Generator, target: Register) =
  ast.exp.generate(g, target)
  let t = ast.exp.typeData
  case t.kind:
    of UnknownType: assert(false, "Convert from unknown type!")
    of VoidType: assert(false, "Convert from void type!")
    of FunctionType: assert(false, "Convert from function type!")
    of StructType: assert(false, "Convert from struct type!")
    of PointerType: ast.raiseError(&"Attempt to cast {t} to short!")
    of ArrayType, ArrayOfUnknownSizeType: assert(false, "Convert from array type!")
    of SimpleType:
      case t.simpleType:
        of Int8, Int16, UInt8, UInt16: discard
        of Int32, UInt32:
          g.output &= &"  ASH {target}, 16\p" &
                      &"  ASH {target}, -16\p"