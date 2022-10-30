when not declared(Generator):
  include common

proc getOtherRegUInt16(r: Register): Register {.inline.} =
  if r == Register(1): Register(2) else: Register(1)

proc loadConstUInt16(g: var Generator, r: Register, num: int64) {.inline.} =
  g.output &= &"  LDI {r}, {num and 0xFFFF}\p"

proc pushOnStackUInt16(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  SH (SP), {r}\p" &
              &"  SUBI SP, 4\p"

proc popFromStackUInt16(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  ADDI SP, 4\p" &
              &"  LHU {r}, (SP)\p"

proc writeToAddrUInt16(address: Address, g: var Generator, dataReg: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      let otherReg = dataReg.getOtherRegUInt16()
      if offset != 0:
        g.output &= &"  LOAD {otherReg}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {otherReg}, {address.label}\p"
      g.output &= &"  SH ({otherReg}), {dataReg}\p"
    of RelativeFP:
      g.output &= &"  SH (FP{offset + address.fpOffset:+}), {dataReg}\p"
    of Expression:
      let otherReg = dataReg.getOtherRegUInt16()
      address.exp.generate(g, otherReg)
      g.output &= &"  SH ({otherReg}{offset:+}), {dataReg}\p"

proc readFromAddrUInt16(address: Address, g: var Generator, target: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      if offset != 0:
        g.output &= &"  LOAD {target}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {target}, {address.label}\p"
      g.output &= &"  LHU {target}, ({target})\p"
    of RelativeFP:
      g.output &= &"  LHU {target}, (FP{offset + address.fpOffset:+})\p"
    of Expression:
      address.exp.generate(g, target)
      g.output &= &"  LHU {target}, ({target}{offset:+})\p"

proc writeToAddrInRegUInt16(g: var Generator, dataReg, addrReg: Register, offset: int = 0) =
  g.output &= &"  SH ({addrReg}{offset:+}), {dataReg}\p"

proc moveRegsUInt16(g: var Generator, dest, src: Register) {.inline.} =
  g.output &= &"  MOV {dest}, {src}\p"

proc generateUInt16(ast: ConvertExprNode, g: var Generator, target: Register) =
  ast.exp.generate(g, target)
  let t = ast.exp.typeData
  case t.kind:
    of UnknownType: assert(false, "Convert from unknown type!")
    of VoidType: assert(false, "Convert from void type!")
    of FunctionType: assert(false, "Convert from function type!")
    of StructType: assert(false, "Convert from struct type!")
    of ArrayType, ArrayOfUnknownSizeType: assert(false, "Convert from array type!")
    of PointerType: ast.raiseError(&"Attempt to cast {t} to unsigned short!")
    of SimpleType:
      case t.simpleType:
        of Int8, UInt8, UInt16: discard
        of Int16, Int32, UInt32:
          g.output &= &"  LSH {target}, 16\p" &
                      &"  LSH {target}, -16\p"