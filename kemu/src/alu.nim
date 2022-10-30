import flags

type AluResult* = object
  val*: uint32
  flags*: Flags
  mask*: Flags

proc aluFunction*(f: range[0..7], a, b: uint32): AluResult =
  result.mask = {Zero, Negative}
  case f:
    of 0: # Add
      var c = a.uint64 + b.uint64
      if (c and 0xFFFFFFFF00000000'u64) != 0:
        result.flags.incl Carry
      let aNeg = cast[int32](a) < 0
      let bNeg = cast[int32](b) < 0
      let cNeg = cast[int32](c and 0xFFFFFFFF'u64) < 0
      if (aNeg == bNeg) and (aNeg != cNeg):
        result.flags.incl Overflow
      result.mask = {Zero, Carry, Negative, Overflow}
      result.val = c.uint32
    of 1: # Subtract
      result.val = a - b
      if a < b:
        result.flags.incl Carry
      let aNeg = cast[int32](a) < 0
      let bNeg = cast[int32](b) < 0
      let cNeg = cast[int32](result.val) < 0
      if (aNeg != bNeg) and (aNeg != cNeg):
        result.flags.incl Overflow
      result.mask = {Zero, Carry, Negative, Overflow}
    of 2: # Logical shift
      if b == 0:
        result.val = a
      else:
        let bSigned = cast[int32](b).int
        if bSigned > 0:
          result.val = a shl b
          if (a shl (b - 1'u32) and 0x80000000'u32) != 0:
            result.flags.incl Carry
        else:
          result.val = a shr (-bSigned)
          if (a shr (b - 1'u32) and 0x1'u32) != 0:
            result.flags.incl Carry
      result.mask = {Zero, Carry, Negative}
    of 3: # Arithmetic shift
      if b == 0:
        result.val = a
      else:
        let aSigned = cast[int32](a).int
        let bSigned = cast[int32](b).int
        if bSigned > 0:
          result.val = a shl b
          if (a shl (b - 1'u32) and 0x80000000'u32) != 0:
            result.flags.incl Carry
        else:
          result.val = uint32(aSigned shr (-bSigned))
          if (aSigned shr (-bSigned - 1) and 0x1) != 0:
            result.flags.incl Carry
      result.mask = {Zero, Carry, Negative}
    of 4: # And
      result.val = a and b
    of 5: # Or
      result.val = a or b
    of 6: # Xor
      result.val = a xor b
    of 7: # LDH
      result.val = (a and 0x3FFFF'u32) or (b shl 18)
  if result.val == 0:
    result.flags.incl Zero
  if cast[int32](result.val) < 0:
    result.flags.incl Negative
