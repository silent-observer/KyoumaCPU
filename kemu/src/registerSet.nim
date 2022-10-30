import flags
import bitops, strformat

type
  RegisterSet* = object
    r: array[0..15, uint32]
  CpuMode* = enum
    SupervisorMode
    UserMode
  RegisterFile* = object
    r: array[CpuMode, RegisterSet]
    mode*: CpuMode
    hi*, lo*: uint32

const
  StatusRegisterIndex = 11
  LinkRegisterIndex = 12
  FramePointerIndex = 13
  StackPointerIndex = 14
  ProgramCounterIndex = 15
  CpuModeBit = 4
  ZeroDivisionBit = 5

proc initRegisterSet*(mode: CpuMode): RegisterSet =
  result.r[StatusRegisterIndex] = mode.uint32 shl CpuModeBit
proc initRegisterFile*(): RegisterFile =
  result.r[SupervisorMode] = initRegisterSet(SupervisorMode)
  result.r[UserMode] = initRegisterSet(UserMode)
  result.mode = SupervisorMode

proc setStatusRegister*(rs: var RegisterSet, val: uint32) {.inline.} =
  rs.r[StatusRegisterIndex] = rs.r[StatusRegisterIndex] or (val and 0x0000002F'u32)
proc setOtherStatusRegister*(rs: var RegisterSet, val: uint32) {.inline.} =
  rs.r[StatusRegisterIndex] = rs.r[StatusRegisterIndex] or (val and 0x00000020'u32)
proc setStatusRegister*(rf: var RegisterFile, val: uint32) =
  let newMode = val.testBit(CpuModeBit).int.CpuMode
  if newMode != rf.mode:
    rf.mode = newMode
  else:
    let otherMode = if rf.mode == SupervisorMode: UserMode else: SupervisorMode
    rf.r[rf.mode].setStatusRegister(val)
    rf.r[otherMode].setOtherStatusRegister(val)

proc `[]`*(rs: RegisterSet, index: range[0..15]): uint32 {.inline.} =
  if index == 0: 0'u32
  else: rs.r[index]
proc `[]`*(rf: RegisterFile, index: range[0..15]): uint32 {.inline.} =
  if index == 0: 0'u32
  else: rf.r[rf.mode][index]

proc `[]=`*(rs: var RegisterSet, index: range[0..15], val: uint32) {.inline.} =
  if index == 0: discard
  elif index == StatusRegisterIndex:
    rs.setStatusRegister(val)
  else:
    rs.r[index] = val
proc `[]=`*(rf: var RegisterFile, index: range[0..15], val: uint32) {.inline.} =
  if index == 0: discard
  elif (index and 0xF) == StatusRegisterIndex:
    rf.setStatusRegister(val)
  else:
    rf.r[rf.mode][index] = val

proc sr*(rs: RegisterSet): uint32 {.inline.} = rs.r[StatusRegisterIndex]
proc lr*(rs: RegisterSet): uint32 {.inline.} = rs.r[LinkRegisterIndex]
proc fp*(rs: RegisterSet): uint32 {.inline.} = rs.r[FramePointerIndex]
proc sp*(rs: RegisterSet): uint32 {.inline.} = rs.r[StackPointerIndex]
proc pc*(rs: RegisterSet): uint32 {.inline.} = rs.r[ProgramCounterIndex]

proc sr*(rf: RegisterFile): uint32 {.inline.} = rf.r[rf.mode].sr
proc lr*(rf: RegisterFile): uint32 {.inline.} = rf.r[rf.mode].lr
proc fp*(rf: RegisterFile): uint32 {.inline.} = rf.r[rf.mode].fp
proc sp*(rf: RegisterFile): uint32 {.inline.} = rf.r[rf.mode].sp
proc pc*(rf: RegisterFile): uint32 {.inline.} = rf.r[rf.mode].pc

proc incPc*(rs: var RegisterSet, val: uint32) {.inline.} = 
  rs.r[ProgramCounterIndex] += val
proc incPc*(rf: var RegisterFile, val: uint32) {.inline.} = 
  rf.r[rf.mode].incPc(val)

proc flags*(rs: RegisterSet): Flags {.inline.} = 
  toFlags(rs.r[StatusRegisterIndex].int and 0xF)
proc flags*(rf: RegisterFile): Flags {.inline.} = rf.r[rf.mode].flags
proc setFlags*(rs: var RegisterSet, f: Flags, mask: Flags) {.inline.} = 
  template sr: untyped = rs.r[StatusRegisterIndex]
  sr = (sr and 0xFFFFFFF0'u32) or (f.toInt().uint32 and mask.toInt().uint32)
proc setFlags*(rf: var RegisterFile, val: Flags, mask: Flags) {.inline.} = rf.r[rf.mode].setFlags(val, mask)
proc getRegSet*(rf: var RegisterFile, mode: CpuMode): var RegisterSet {.inline.} = rf.r[mode]

proc `$`*(rf: RegisterFile): string =
  for i in 0..9:
    result &= &"R{i}:  {rf.r[rf.mode][i]:08X}\p"
  result &= &"R10: {rf.r[rf.mode][10]:08X}\p"
  result &= &"LR:  {rf.lr:08X}\p"
  result &= &"FP:  {rf.fp:08X}\p"
  result &= &"SP:  {rf.sp:08X}\p"
  result &= &"PC:  {rf.pc:08X}\p"
  result &= "Mode: "
  result &= (case rf.mode:
    of SupervisorMode: "Supervisor\p"
    of UserMode: "User\p")
  result &= &"Flags: {rf.flags}\p"
  if rf.sr.testBit(ZeroDivisionBit):
    result &= "Zero division flag is set!\p"