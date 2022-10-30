import registerSet, memory, flags, alu, common
import bitops, strformat, terminal

var logInstruction* = false

const
  ShortMnemonics = ["ADD", "SUB", "LSH", "ASH", "AND", "OR", "XOR", "CND"]
  ImmediateMnemonics = ["ADDI", "SUBI", "LSHI", "ASHI", "ANDI", "ORI", "XORI", "LDH"]
  LoadStoreMnemonics = ["LW", "SW", "SH", "SB", "LHU", "LHS", "LBU", "LBS"]

type 
  KCpu = ref object
    regs: RegisterFile
    mem: Memory
    nextConditions: array[0..2, Condition]
    steps: int64
    isBusyHalted*: bool
    nextHi, nextLo: uint32
    stepsBeforeHiLo: int

proc signExtend(x: uint32, len: int): uint32 {.inline.} =
  let shift = 32 - len
  cast[uint32](x.int32 shl shift shr shift)

proc toReg(x: int): string {.inline.} =
  if x <= 10:
    "R" & $x
  elif x == 11: "SR"
  elif x == 12: "LR"
  elif x == 13: "FP"
  elif x == 14: "SP"
  elif x == 15: "PC"
  else: ""

proc newKCpu*(): KCpu =
  new(result)
  result.regs = initRegisterFile()
  result.stepsBeforeHiLo = -1

proc setMem*(cpu: KCpu, mem: Memory) =
  cpu.mem = mem

proc interruptZeroDivision(cpu: KCpu) =
  if cpu.regs.mode == SupervisorMode:
    echo "Zero division error in supervisor mode!"
  cpu.regs.mode = SupervisorMode
  cpu.regs.setStatusRegister(cpu.regs.sr or 0x20'u32)
  if logInstruction:
    echo "Zero division error!"

template writeColor(text: string) =
  when ColorsAvailable:
    stdout.styledWrite fgRed, text, resetStyle
  else:
    echo text

proc execShortInstr(cpu: KCpu, instr: uint32) =
  let shortInstr = 
    if cpu.regs.pc.testBit(1): 
      uint16(instr shr 16) 
    else:
      uint16(instr and 0xFFFF'u32)
  if logInstruction:
    when ColorsAvailable:
      stdout.styledWriteLine(fgBlue, &"{cpu.regs.pc:08X}:", fgGreen, &" {shortInstr:04X}", resetStyle)
    else:
      echo &"{cpu.regs.pc:08X}: {shortInstr:04X}"
  cpu.regs.incPc(2)
  if shortInstr == 0x0000:
    if logInstruction:
      writeColor("  NOP")
      echo ""
    return
  let opcode = (shortInstr shr 12) and 0x7
  if opcode == 7: # CND
    cpu.nextConditions[0] = toCondition(instr.int shr 8 and 0xF)
    cpu.nextConditions[1] = toCondition(instr.int shr 4 and 0xF)
    cpu.nextConditions[2] = toCondition(instr.int and 0xF)
    if logInstruction:
      writeColor "  CND"
      echo &" {cpu.nextConditions}"
  else:
    let isCondTrue = cpu.nextConditions[0].isTrue(cpu.regs.flags)
    if logInstruction:
      if cpu.nextConditions[0].main != None:
        echo &"  ({cpu.nextConditions[0]}) is {isCondTrue}"
    cpu.nextConditions[0] = cpu.nextConditions[1]
    cpu.nextConditions[1] = cpu.nextConditions[2]
    cpu.nextConditions[2] = Condition.default
    if not isCondTrue:
      return
    let 
      destReg = shortInstr.int shr 8 and 0xF
      src1Reg = shortInstr.int shr 4 and 0xF
      src2Reg = shortInstr.int and 0xF
      a = cpu.regs[src1Reg]
      b = cpu.regs[src2Reg]
      aluResult = aluFunction(opcode, a, b)
    if logInstruction:
      writeColor "  " & ShortMnemonics[opcode]
      echo &" {destReg.toReg}, {src1Reg.toReg}, {src2Reg.toReg}"
      echo &"  {src1Reg.toReg} = {a}({a:#010X}), {src2Reg.toReg} = {b}({b:#010X})"
    cpu.regs[destReg] = aluResult.val
    if not cpu.nextConditions[0].freeze:
      cpu.regs.setFlags(aluResult.flags, aluResult.mask)
    if logInstruction:
      when ColorsAvailable:
        stdout.styledWriteLine(
          &"  {destReg.toReg} <- {aluResult.val}({aluResult.val:#010X}), flags <- ",
          fgYellow, &"{aluResult.flags}", resetStyle, " with mask ", 
          fgYellow, &"{aluResult.mask}", resetStyle)
      else:
        echo &"  {destReg.toReg} <- {aluResult.val}({aluResult.val:#010X}), flags <- ",
             &"{aluResult.flags} with mask {aluResult.mask}"

proc execImmediateInstr(cpu: KCpu, instr: uint32) =
  let cond = toCondition(instr.int and 0xF)
  let isCondTrue = cond.isTrue(cpu.regs.flags)
  if logInstruction:
    if cond.main != None:
      echo &"  ({cond}) is {isCondTrue}"
  if not isCondTrue:
    return
  let 
    opcode = instr.int shr 26 and 0x7
    destReg = instr.int shr 22 and 0xF
    srcReg = instr.int shr 18 and 0xF
    imm = instr shr 4 and 0x3FFF
    a = cpu.regs[srcReg]
    b = imm.signExtend(14)
    aluResult = aluFunction(opcode, a, cast[uint32](b))
  if logInstruction:
    writeColor "  " & ImmediateMnemonics[opcode]
    echo &" {destReg.toReg}, {srcReg.toReg}, {b}({cast[uint32](b):#010X})"
    echo &"  {srcReg.toReg} = {a}({a:#010X})"
  cpu.regs[destReg] = aluResult.val
  if not cond.freeze:
    cpu.regs.setFlags(aluResult.flags, aluResult.mask)
  if logInstruction:
    when ColorsAvailable:
      stdout.styledWriteLine(
        &"  {destReg.toReg} <- {aluResult.val}({aluResult.val:#010X}), flags <- ",
        fgYellow, &"{aluResult.flags}", resetStyle, " with mask ", 
        fgYellow, &"{aluResult.mask}", resetStyle)
    else:
      echo &"  {destReg.toReg} <- {aluResult.val}({aluResult.val:#010X}), flags <- ", 
           &"{aluResult.flags} with mask {aluResult.mask}"
proc execLoadStoreInstr(cpu: KCpu, instr: uint32) =
  let cond = toCondition(instr.int and 0xF)
  let isCondTrue = cond.isTrue(cpu.regs.flags)
  if logInstruction:
    if cond.main != None:
      echo &"  ({cond}) is {isCondTrue}"
  if not isCondTrue:
    return
  let
    opcode = instr.int shr 27 and 0x7
    reg = instr.int shr 23 and 0xF
    addressReg = instr.int shr 19 and 0xF
    offsetVal = instr shr 4 and 0x7FFF
    offset = offsetVal.signExtend(15)
    offsetSigned = cast[int32](offset)
    address = cpu.regs[addressReg] + offset
    isLoad = opcode == 0 or opcode >= 4
  if logInstruction:
    writeColor "  " & LoadStoreMnemonics[opcode]
    if isLoad:
      if addressReg == 0:
        echo &" {reg.toReg}, ({offset:08X})"
      else:
        echo &" {reg.toReg}, ({addressReg.toReg}{offsetSigned:+})"
    else:
      if addressReg == 0:
        echo &" ({offset:08X}): {reg.toReg}"
      else:
        echo &" ({addressReg.toReg}{offsetSigned:+}), {reg.toReg}"
  case opcode:
    of 0:
      let v = cpu.mem[address]
      cpu.regs[reg] = v
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(&"  {reg.toReg} <- {v}({v:#010X}) <- ", 
            fgBlue, &"[{address:08X}]", resetStyle)
        else:
          echo &"  {reg.toReg} <- {v}({v:#010X}) <- [{address:08X}]"
    of 1:
      let v = cpu.regs[reg]
      cpu.mem.writeWord(address, v)
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(fgBlue, &"[{address:08X}]", 
            resetStyle, &" <- {v}({v:#010X}) <- {reg.toReg}")
        else:
          echo &"  [{address:08X}] <- {v}({v:#010X}) <- {reg.toReg}"
    of 2:
      let v = uint16(cpu.regs[reg] and 0xFFFF'u16)
      cpu.mem.writeHalfWord(address, v)
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(fgBlue, &"[{address:08X}]", 
            resetStyle, &" <- {v}({v:#06X}) <- {reg.toReg}")
        else:
          echo &"  [{address:08X}] <- {v}({v:#06X}) <- {reg.toReg}"
    of 3:
      let v = uint8(cpu.regs[reg] and 0xFF'u8)
      cpu.mem.writeByte(address, v)
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(fgBlue, &"[{address:08X}]", 
            resetStyle, &" <- {v}({v:#04X}) <- {reg.toReg}")
        else:
          echo &"  [{address:08X}] <- {v}({v:#04X}) <- {reg.toReg}"
    of 4:
      let v = cpu.mem.readHalfWord(address).uint32
      cpu.regs[reg] = v
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(&"  {reg.toReg} <- {v}({v:#06X}) <- ", 
            fgBlue, &"[{address:08X}]", resetStyle)
        else:
          echo &"  {reg.toReg} <- {v}({v:#06X}) <- [{address:08X}]"
    of 5:
      let v = cpu.mem.readHalfWord(address).uint32.signExtend(16)
      cpu.regs[reg] = v
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(&"  {reg.toReg} <- {v}({v:#06X}) <- ", 
            fgBlue, &"[{address:08X}]", resetStyle)
        else:
          echo &"  {reg.toReg} <- {v}({v:#06X}) <- [{address:08X}]"
    of 6:
      let v = cpu.mem.readByte(address).uint32
      cpu.regs[reg] = v
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(&"  {reg.toReg} <- {v}({v:#04X}) <- ", 
            fgBlue, &"[{address:08X}]", resetStyle)
        else:
          echo &"  {reg.toReg} <- {v}({v:#04X}) <- [{address:08X}]"
    of 7:
      let v = cpu.mem.readByte(address).uint32.signExtend(8)
      cpu.regs[reg] = v
      if logInstruction:
        when ColorsAvailable:
          stdout.styledWriteLine(&"  {reg.toReg} <- {v}({v:#04X}) <- ", 
            fgBlue, &"[{address:08X}]", resetStyle)
        else:
          echo &"  {reg.toReg} <- {v}({v:#04X}) <- [{address:08X}]"
    else: discard

proc execLdiInstr(cpu: KCpu, instr: uint32) =
  let cond = toCondition(instr.int and 0xF)
  let isCondTrue = cond.isTrue(cpu.regs.flags)
  if logInstruction:
    if cond.main != None:
      echo &"  ({cond}) is {isCondTrue}"
  if not isCondTrue:
    return
  let
    destReg = instr.int shr 24 and 0xF
    immValue = instr shr 4 and 0xFFFFF
    imm = immValue.signExtend(20)
  if logInstruction:
    writeColor "  LDI"
    echo &" {destReg.toReg}, {imm}({(imm):#010X})"
  cpu.regs[destReg] = imm

proc execMoveInstr(cpu: KCpu, instr: uint32) =
  let cond = toCondition(instr.int and 0xF)
  let isCondTrue = cond.isTrue(cpu.regs.flags)
  if logInstruction:
    if cond.main != None:
      echo &"  ({cond}) is {isCondTrue}"
  if not isCondTrue:
    return
  if cpu.regs.mode != SupervisorMode:
    if logInstruction:
      echo &"  Mode is not Supervisor"
    return
  let 
    isUS = (instr and 0x02000000'u32) != 0
    destReg = instr.int shr 21 and 0xF
    srcReg = instr.int shr 17 and 0xF
    srcMode = if isUS: SupervisorMode else: UserMode
    destMode = if isUS: UserMode else: SupervisorMode
    a = cpu.regs.getRegSet(srcMode)[srcReg]
  if logInstruction:
    writeColor "  MOV"
    if isUS:
      echo &" u{destReg.toReg}, s{srcReg.toReg}"
      echo &"  s{srcReg.toReg} = {a}({a:#010X})"
    else:
      echo &" s{destReg.toReg}, u{srcReg.toReg}"
      echo &"  u{srcReg.toReg} = {a}({a:#010X})"
  cpu.regs.getRegSet(destMode)[destReg] = a

proc execMultDivInstr(cpu: KCpu, instr: uint32) =
  let cond = toCondition(instr.int and 0xF)
  let isCondTrue = cond.isTrue(cpu.regs.flags)
  if logInstruction:
    if cond.main != None:
      echo &"  ({cond}) is {isCondTrue}"
  if not isCondTrue:
    return
  let 
    isDiv = (instr and 0x04000000'u32) != 0
    isSigned = (instr and 0x04000000'u32) != 0
    src1Reg = instr.int shr 21 and 0xF
    src2Reg = instr.int shr 17 and 0xF
    a = cpu.regs[src1Reg]
    b = cpu.regs[src2Reg]
  if logInstruction:
    let signedString = if isSigned: "(signed)" else: "(unsigned)"
    if isDiv:
      writeColor "  DIV"
      echo &" {signedString} {src1Reg.toReg}, {src2Reg.toReg}"
    else:
      writeColor "  MULT"
      echo &" {signedString} {src1Reg.toReg}, {src2Reg.toReg}"
    echo &"  {src1Reg.toReg} = {a}({a:#010X}), {src2Reg.toReg} = {b}({b:#010X})"
  if isDiv:
    if b == 0:
      cpu.interruptZeroDivision()
      return
    if isSigned:
      cpu.nextHi = cast[uint32](cast[int32](a) mod cast[int32](b))
      cpu.nextLo = cast[uint32](cast[int32](a) div cast[int32](b))
    else:
      cpu.nextHi = a mod b
      cpu.nextLo = a div b
    cpu.stepsBeforeHiLo = 11;
    if logInstruction:
      echo &"  (after 11 cycles) HI <- {cpu.nextHi}({cpu.nextHi:#010X}), LO <- {cpu.nextLo}({cpu.nextLo:#010X})"
  else:
    if isSigned:
      let 
        aSigned = cast[int32](a).int64
        bSigned = cast[int32](b).int64
        cSigned = aSigned * bSigned
      cpu.regs.hi = uint32(cSigned shr 32 and 0xFFFFFFFF'i64)
      cpu.regs.lo = uint32(cSigned and 0xFFFFFFFF'i64)
    else:
      cpu.regs.hi = uint32((a.uint64 * b.uint64) shr 32)
      cpu.regs.lo = uint32((a.uint64 * b.uint64) and 0xFFFFFFFF'u64)
    if logInstruction:
      echo &"  HI <- {cpu.regs.hi}({cpu.regs.hi:#010X}), LO <- {cpu.regs.lo}({cpu.regs.lo:#010X})"

proc execMoveHiLoInstr(cpu: KCpu, instr: uint32) =
  let cond = toCondition(instr.int and 0xF)
  let isCondTrue = cond.isTrue(cpu.regs.flags)
  if logInstruction:
    if cond.main != None:
      echo &"  ({cond}) is {isCondTrue}"
  if not isCondTrue:
    return
  let 
    isLo = (instr and 0x02000000'u32) != 0
    destReg = instr.int shr 21 and 0xF
    a = if isLo: cpu.regs.lo else: cpu.regs.hi
  if logInstruction:
    writeColor "  MOV"
    if isLo:
      echo &" {destReg.toReg}, LO"
      echo &"  LO = {a}({a:#010X})"
    else:
      echo &" {destReg.toReg}, HI"
      echo &"  HI = {a}({a:#010X})"
  cpu.regs[destReg] = a

proc execLongInstr(cpu: KCpu, instr: uint32) =
  cpu.nextConditions[0] = cpu.nextConditions[1]
  cpu.nextConditions[1] = cpu.nextConditions[2]
  cpu.nextConditions[2] = Condition.default
  if instr == 0x87FC0040'u32 or instr == 0x83FFFFC0'u32:
    cpu.isBusyHalted = true
    return
  if logInstruction:
    when ColorsAvailable:
      stdout.styledWriteLine(fgBlue, &"{cpu.regs.pc:08X}:", fgGreen, &" {instr:08X}", resetStyle)
    else:
      echo &"{cpu.regs.pc:08X}: {instr:08X}"
  cpu.regs.incPc(4)
  if (instr and 0xE0000000'u32) == 0x80000000'u32:
    cpu.execImmediateInstr(instr)
  elif (instr and 0xC0000000'u32) == 0xC0000000'u32:
    cpu.execLoadStoreInstr(instr)
  elif (instr and 0xF0000000'u32) == 0xA0000000'u32:
    cpu.execLdiInstr(instr)
  elif (instr and 0xF8000000'u32) == 0xB0000000'u32:
    cpu.execMultDivInstr(instr)
  elif (instr and 0xFC000000'u32) == 0xB8000000'u32:
    cpu.execMoveInstr(instr)
  elif (instr and 0xFC000000'u32) == 0xBC000000'u32:
    cpu.execMoveHiLoInstr(instr)

proc step*(cpu: KCpu, breakpoints: seq[uint32]): bool =
  if cpu.isBusyHalted:
    cpu.steps += 1
    return true
  if cpu.regs.pc in breakpoints:
    result = true
  let instr = cpu.mem[cpu.regs.pc]
  if instr.testBit(31):
    execLongInstr(cpu, instr)
  else:
    execShortInstr(cpu, instr)
  cpu.steps += 1
  if cpu.stepsBeforeHiLo > 0:
    cpu.stepsBeforeHiLo -= 1
  elif cpu.stepsBeforeHiLo == 0:
    cpu.regs.hi = cpu.nextHi
    cpu.regs.lo = cpu.nextLo
    cpu.stepsBeforeHiLo = -1
    if logInstruction:
      echo &"  (DIV executed!) HI <- {cpu.regs.hi}({cpu.regs.hi:#010X}), LO <- {cpu.regs.lo}({cpu.regs.lo:#010X})"

proc `$`*(cpu: KCpu): string {.inline.} = "Registers:\p" & $cpu.regs
proc sp*(cpu: KCpu): uint32 {.inline.} = cpu.regs.sp
proc fp*(cpu: KCpu): uint32 {.inline.} = cpu.regs.fp
proc r1*(cpu: KCpu): uint32 {.inline.} = cpu.regs[1]