import ast, kelf

type 
  MachineCode* = seq[uint32]
  GenerationError* = object of Exception
    line: int

proc reportError*(e: GenerationError): string =
  "Generation Error occured at line " & $e.line & ":\n" & e.msg & "\n"

proc writeWord(code: var MachineCode, address: uint32, val: uint32) =
  code[address div 4] = val
proc writeHalfWord(code: var MachineCode, address: uint32, val: uint16) =
  template word: untyped = code[address div 4]
  if (address and 0x2) == 0:
    word = (word and 0xFFFF0000'u32) or val.uint32
  else:
    word = (word and 0x0000FFFF'u32) or (val.uint32 shl 16)
proc writeByte(code: var MachineCode, address: uint32, val: uint8) =
  template word: untyped = code[address div 4]
  case address and 0x3:
    of 0: word = (word and 0xFFFFFF00'u32) or (val.uint32)
    of 1: word = (word and 0xFFFF00FF'u32) or (val.uint32 shl 8)
    of 2: word = (word and 0xFF00FFFF'u32) or (val.uint32 shl 16)
    of 3: word = (word and 0x00FFFFFF'u32) or (val.uint32 shl 24)
    else: discard

proc generateShortInstr(instr: Instruction, result: var MachineCode) =
  var val = 0x0000'u16
  val = val or (instr.short.opcode.uint16 shl 12)
  val = val or (instr.short.dest.num.uint16 shl 8)
  val = val or (instr.short.src1.num.uint16 shl 4)
  val = val or (instr.short.src2.num.uint16)
  result.writeHalfWord(instr.address, val)

proc generateImmediateInstr(instr: Instruction, result: var MachineCode) =
  var val = 0x80000000'u32
  val = val or (instr.imm.opcode.uint32 shl 26)
  val = val or (instr.imm.dest.num.uint32 shl 22)
  val = val or (instr.imm.src.num.uint32 shl 18)
  var n = instr.imm.imm.num
  if n >= 8192:
    n -= 16384
  if n >= 8192 or n < -8192:
    var e = newException(GenerationError, "Immediate value in immediate instruction should be between -8192 and 8191")
    e.line = instr.line
    raise e
  let imm = cast[uint32](n) and 0x3FFF
  val = val or (imm shl 4)
  val = val or instr.condition.toNum
  result.writeWord(instr.address, val)

proc generateLoadStoreInstr(instr: Instruction, result: var MachineCode) =
  var val = 0xC0000000'u32
  val = val or (instr.ls.opcode.uint32 shl 27)
  val = val or (instr.ls.register.num.uint32 shl 23)
  val = val or (instr.ls.address.num.uint32 shl 19)
  var n = instr.ls.offset.num
  if n >= 16384:
    n -= 32768
  if n >= 16384 or n < -16384:
    var e = newException(GenerationError, "Offset in load/store instruction should be between -16384 and 16383")
    e.line = instr.line
    raise e
  let imm = cast[uint32](n) and 0x7FFF
  val = val or (imm.uint32 shl 4)
  val = val or instr.condition.toNum
  result.writeWord(instr.address, val)

proc generateMoveInstr(instr: Instruction, result: var MachineCode) =
  var val = 0xB8000000'u32
  if instr.kind == MoveHi:
    val = 0xBC000000'u32
    val = val or (instr.movHiLo.dest.num.uint32 shl 21)
  elif instr.kind == MoveLo:
    val = 0xBE000000'u32
    val = val or (instr.movHiLo.dest.num.uint32 shl 21)
  else:
    if instr.mov.dest.registerSet == UserSet:
      val = 0xBA000000'u32
    val = val or (instr.mov.dest.num.uint32 shl 21)
    val = val or (instr.mov.src.num.uint32 shl 17)
  val = val or instr.condition.toNum
  result.writeWord(instr.address, val)

proc generateLdiInstr(instr: Instruction, result: var MachineCode) =
  var val = 0xA0000000'u32
  val = val or (instr.ldi.dest.num.uint32 shl 24)
  var n = instr.ldi.imm.num
  if n >= 524288:
    n -= 1048576
  if n >= 524288 or n < -524288:
    var e = newException(GenerationError, "Immediate value in LDI instruction should be between -524288 and 524287")
    e.line = instr.line
    raise e
  let imm = cast[uint32](n) and 0xFFFFF
  val = val or (imm.uint32 shl 4)
  val = val or instr.condition.toNum
  result.writeWord(instr.address, val)

proc generateData(instr: Instruction, result: var MachineCode) =
  var address = instr.address
  for x in instr.data:
    result.writeByte(address, x)
    address += 1

proc generateCndInstr(instr: Instruction, result: var MachineCode) =
  var val = 0x7000'u16
  val = val or (instr.conditions[0].toNum.uint16 shl 8)
  val = val or (instr.conditions[1].toNum.uint16 shl 4)
  val = val or (instr.conditions[2].toNum.uint16)
  result.writeHalfWord(instr.address, val)

proc generateMultDivInstr(instr: Instruction, result: var MachineCode) =
  var val = 0xB0000000'u32
  val = val or (instr.multDiv.isDiv.uint32 shl 26)
  val = val or (instr.multDiv.isSigned.uint32 shl 25)
  val = val or (instr.multDiv.src1.num.uint32 shl 21)
  val = val or (instr.multDiv.src2.num.uint32 shl 17)
  val = val or instr.condition.toNum
  result.writeWord(instr.address, val)

proc generateInstr(instr: Instruction, result: var MachineCode) =
  case instr.kind:
    of Short: instr.generateShortInstr(result)
    of Immediate: instr.generateImmediateInstr(result)
    of LoadStore: instr.generateLoadStoreInstr(result)
    of Move, MoveHi, MoveLo: instr.generateMoveInstr(result)
    of Ldi: instr.generateLdiInstr(result)
    of InstructionKind.Data: instr.generateData(result)
    of Cnd: instr.generateCndInstr(result)
    of MultDiv: instr.generateMultDivInstr(result)
    of Macro, Dummy: discard

proc generateRaw(data: ProgramData): seq[byte] =
  let size = data.totalTextSize + 
             data.data.len.uint32 + 
             data.rodata.len.uint32 + 
             data.bssSize
  var requiredSize = size div 4
  if size mod 4 != 0:
    requiredSize += 1
  var d = newSeq[uint32](requiredSize)
  for i in data.instrs:
    i.generateInstr(d)
  result = newSeqOfCap[byte](d.len * 4)
  for x in d:
    result.add byte(x and 0xFF)
    result.add byte(x shr 8 and 0xFF)
    result.add byte(x shr 16 and 0xFF)
    result.add byte(x shr 24 and 0xFF)

proc generateElf*(data: ProgramData): seq[byte] =
  let s = data.generateRaw()
  var b = initElfObjBuilder()
  b.addTextSection(s, 0x00010000'u32)
  if data.data.len > 0:
    b.addDataSection(data.data, 0x00010000'u32 + 
                                data.totalTextSize)
  if data.rodata.len > 0:
    b.addRodataSection(data.rodata, 0x00010000'u32 + 
                                    data.totalTextSize +
                                    data.data.len.uint32)
  if data.bssSize > 0'u32:
    b.addBssSection(data.bssSize, 0x00010000'u32 + 
                                  data.totalTextSize +
                                  data.data.len.uint32 +
                                  data.rodata.len.uint32)
  for l in data.labelTable.labels:
    let isGlobal = l.text[0] != '_'
    if l.isDefined:
      b.addSymbolToSpec(l.text, l.address, 0, Function, isGlobal, l.section)
    else:
      b.addUndefinedSymbol(l.text, l.address, 0, Function, isGlobal)
  for r in data.relocations:
    let label = data.labelTable.labels[r.label]
    b.addRelocation(label.text, r.offset, r.kind.uint8, r.section)
  b.getObjFile().writeObjFile()

proc generate*(data: ProgramData, f: OutputFormat): seq[byte] {.inline.} =
  case f:
    of Binary: data.generateRaw()
    of Elf: data.generateElf()