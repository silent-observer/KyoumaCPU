when not declared(Generator):
  include common

proc getOtherRegInt8(r: Register): Register {.inline.} =
  if r == Register(1): Register(2) else: Register(1)

proc loadConstInt8(g: var Generator, r: Register, num: int64) {.inline.} =
  g.output &= &"  LDI {r}, {num.toSignedByte}\p"

proc pushOnStackInt8(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  SB (SP), {r}\p" &
              &"  SUBI SP, 4\p"

proc popFromStackInt8(g: var Generator, r: Register) {.inline.} =
  g.output &= &"  ADDI SP, 4\p" &
              &"  LBS {r}, (SP)\p"

proc writeToAddrInRegInt8(g: var Generator, dataReg, addrReg: Register, offset: int = 0) =
  g.output &= &"  SB ({addrReg}{offset:+}), {dataReg}\p"

proc writeToAddrInt8(address: Address, g: var Generator, dataReg: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      let otherReg = dataReg.getOtherRegInt8()
      if offset != 0:
        g.output &= &"  LOAD {otherReg}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {otherReg}, {address.label}\p"
      g.output &= &"  SB ({otherReg}), {dataReg}\p"
    of RelativeFP:
      g.output &= &"  SB (FP{offset + address.fpOffset:+}), {dataReg}\p"
    of Expression:
      let otherReg = dataReg.getOtherRegInt8()
      address.exp.generate(g, otherReg)
      g.output &= &"  SB ({otherReg}{offset:+}), {dataReg}\p"

proc readFromAddrInt8(address: Address, g: var Generator, target: Register) =
  let offset = address.offset
  case address.kind:
    of Label:
      if offset != 0:
        g.output &= &"  LOAD {target}, {address.label}[{offset}]\p"
      else:
        g.output &= &"  LOAD {target}, {address.label}\p"
      g.output &= &"  LBS {target}, ({target})\p"
    of RelativeFP:
      g.output &= &"  LBS {target}, (FP{offset + address.fpOffset:+})\p"
    of Expression:
      address.exp.generate(g, target)
      g.output &= &"  LBS {target}, ({target}{offset:+})\p"

proc moveRegsInt8(g: var Generator, dest, src: Register) {.inline.} =
  g.output &= &"  MOV {dest}, {src}\p"

proc generateInt8(ast: ConvertExprNode, g: var Generator, target: Register) =
  ast.exp.generate(g, target)
  let t = ast.exp.typeData
  case t.kind:
    of UnknownType: assert(false, "Convert from unknown type!")
    of VoidType: assert(false, "Convert from void type!")
    of FunctionType: assert(false, "Convert from function type!")
    of StructType: assert(false, "Convert from struct type!")
    of PointerType: ast.raiseError(&"Attempt to cast {t} to signed char!")
    of ArrayType, ArrayOfUnknownSizeType: assert(false, "Convert from array type!")
    of SimpleType:
      case t.simpleType:
        of Int8, UInt8: discard
        of Int16, Int32, UInt16, UInt32:
          g.output &= &"  ASH {target}, 24\p" &
                      &"  ASH {target}, -24\p"