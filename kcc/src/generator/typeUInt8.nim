when not declared(Generator):
  include common

proc getOtherRegUInt8(r: Register): Register {.inline.} =
  if r == Register(1): Register(2) else: Register(1)

proc loadConstUInt8(g: var Generator, r: Register, num: int64) {.inline.} =
  g.output &= &"  LDI {r}, {num and 0xFF}\p"

proc pushOnStackUInt8(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  SB (SP), {r}\p" &
              &"  SUBI SP, 4\p"

proc popFromStackUInt8(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  ADDI SP, 4\p" &
              &"  LBU {r}, (SP)\p"

proc writeToAddrUInt8(address: Address, g: var Generator, dataReg: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      let otherReg = dataReg.getOtherRegUInt8()
      if offset != 0:
        g.output &= &"  LOAD {otherReg}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {otherReg}, {address.label}\p"
      g.output &= &"  SB ({otherReg}), {dataReg}\p"
    of RelativeFP:
      g.output &= &"  SB (FP{offset + address.fpOffset:+}), {dataReg}\p"
    of Expression:
      let otherReg = dataReg.getOtherRegUInt8()
      address.exp.generate(g, otherReg)
      g.output &= &"  SB ({otherReg}{offset:+}), {dataReg}\p"

proc readFromAddrUInt8(address: Address, g: var Generator, target: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      if offset != 0:
        g.output &= &"  LOAD {target}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {target}, {address.label}\p"
      g.output &= &"  LBU {target}, ({target})\p"
    of RelativeFP:
      g.output &= &"  LBU {target}, (FP{offset + address.fpOffset:+})\p"
    of Expression:
      address.exp.generate(g, target)
      g.output &= &"  LBU {target}, ({target}{offset:+})\p"

proc writeToAddrInRegUInt8(g: var Generator, dataReg, addrReg: Register, offset: int = 0) =
  g.output &= &"  SB ({addrReg}{offset:+}), {dataReg}\p"

proc moveRegsUInt8(g: var Generator, dest, src: Register) {.inline.} =
  g.output &= &"  MOV {dest}, {src}\p"

proc generateUInt8(ast: ConvertExprNode, g: var Generator, target: Register) =
  ast.exp.generate(g, target)
  let t = ast.exp.typeData
  case t.kind:
    of UnknownType: assert(false, "Convert from unknown type!")
    of VoidType: assert(false, "Convert from void type!")
    of FunctionType: assert(false, "Convert from function type!")
    of StructType: assert(false, "Convert from struct type!")
    of ArrayType, ArrayOfUnknownSizeType: assert(false, "Convert from array type!")
    of PointerType: ast.raiseError(&"Attempt to cast {t} to char!")
    of SimpleType:
      case t.simpleType:
        of UInt8: discard
        of Int8, Int16, Int32, UInt16, UInt32:
          g.output &= &"  ANDI {target}, 0xFF\p"