import ast

type 
  ReplacementError* = object of Exception
    line: int
  ShiftData = object
    startAddress: uint32
    shift: int

proc reportError*(e: ReplacementError): string =
  "Replacement Error occured at line " & $e.line & ":\n" & e.msg & "\n"

iterator mimmArgs(instr: var Instruction): var ImmediateArgument =
  case instr.kind:
    of LoadStore: yield instr.ls.offset
    of Immediate: yield instr.imm.imm
    of Ldi: yield instr.ldi.imm
    of Macro: discard
    else: discard

proc getSectionAddend(data: var ProgramData, section: SpecialSection): Address =
  case section:
    of Text: 0.Address
    of SpecialSection.Data: data.totalTextSize.Address
    of Rodata: data.totalTextSize.Address + data.data.len.Address
    of Bss: data.totalTextSize.Address + data.data.len.Address + data.rodata.len.Address

proc replaceLabelsInInstr(data: var ProgramData, instr: var Instruction, f: OutputFormat) =
  for imm in instr.mimmArgs():
    if imm.kind == LabelImmediate:
      let address = 
        if f == Elf: imm.labelAdd
        else: 
          let label = data.labelTable.labels[imm.labelId]
          label.address + imm.labelAdd + data.getSectionAddend(label.section)
      let relKind = imm.relKind
      if f == Elf:
        data.relocations.add Relocation(
          offset: instr.address,
          label: imm.labelId,
          kind: relKind
        )
      imm = ImmediateArgument(
        kind: ReplacedLabelImmediate,
        address: address,
        relKind: relKind,
        replacedNum: address.getBits(relKind).int
        )
  if instr.kind == Macro and f != Elf:
    for arg in instr.macroInstr.args.mitems:
      if arg.kind != ImmediateValue: continue
      if arg.imm.kind == LabelImmediate:
        let label = data.labelTable.labels[arg.imm.labelId]
        let address = label.address + arg.imm.labelAdd + data.getSectionAddend(label.section)
        arg.imm = ImmediateArgument(
          kind: ReplacedLabelImmediate,
          address: address,
          relKind: FullRelocation,
          replacedNum: label.address.int
          )

proc replaceMacroJmp(data: var ProgramData, instr: var Instruction, i: int, f: OutputFormat) =
  let imm = instr.macroInstr.args[0].imm
  let address = 
    if f == Elf and imm.kind == LabelImmediate:
      let labelId = imm.labelId
      let label = data.labelTable.labels[labelId]
      if not label.isDefined:
        var e = newException(ReplacementError, "Cannot use undefined labels in relative jumps!")
        e.line = instr.line
        raise e
      label.address.int64 + cast[int32](instr.macroInstr.args[0].imm.labelAdd).int64
    else:
      imm.num.int64
  let currAddress = instr.address.int64
  let jump = address - (currAddress + 4)
  if jump >= 8192 or jump <= -8192:
    let e = newException(ReplacementError, "Short jump cannot be longer than 8192")
    e.line = instr.line
    raise e
  instr = Instruction(
    kind: Immediate,
    address: instr.address,
    condition: instr.condition,
    line: instr.line
    )
  instr.imm.src = Register(num: 15, registerSet: CurrentSet)
  instr.imm.dest = instr.imm.src
  if jump >= 0:
    instr.imm.imm = ImmediateArgument(
      kind: NumberImmediate, 
      num: jump.int, 
      relKind: NoRelocation
      )
    instr.imm.opcode = 0
  else:
    instr.imm.imm = ImmediateArgument(
      kind: NumberImmediate, 
      num: -jump.int, 
      relKind: NoRelocation
      )
    instr.imm.opcode = 1

proc replaceMacroJmpl(data: var ProgramData, instr: var Instruction, i: int, f: OutputFormat) =
  let address = 
    if f == Elf: cast[int32](instr.macroInstr.args[0].imm.labelAdd).int64
    else: instr.macroInstr.args[0].imm.num.int64
  let labelId = if f == Elf: instr.macroInstr.args[0].imm.labelId else: 0
  instr = Instruction(
    kind: LoadStore,
    address: instr.address,
    condition: instr.condition,
    line: instr.line
    )
  instr.ls = LoadStoreInstruction(
    offset: ImmediateArgument(kind: NumberImmediate, num: 0),
    register: Register(num: 15, registerSet: CurrentSet),
    address: Register(num: 15, registerSet: CurrentSet),
    opcode: 0
    )
  let relAddr = if instr.condition.main == None:
    instr.ls.offset = ImmediateArgument(kind: NumberImmediate, num: 0)
    data.instrs[i+1] = Instruction(
      kind: InstructionKind.Data,
      address: instr.address + 4,
      condition: Condition(main: None, isFreezed: instr.condition.isFreezed),
      line: instr.line
    )
    data.instrs[i+1].data = @[
      uint8(address and 0xFF),
      uint8(address shr 8 and 0xFF),
      uint8(address shr 16 and 0xFF),
      uint8(address shr 24 and 0xFF)
    ]
    instr.address + 4
  else:
    instr.ls.offset = ImmediateArgument(kind: NumberImmediate, num: 4)
    data.instrs[i+1] = Instruction(
      kind: Immediate,
      address: instr.address + 4,
      condition: Condition(main: None, isFreezed: instr.condition.isFreezed),
      line: instr.line,
      imm: ImmediateInstruction(
        src: Register(num: 15, registerSet: CurrentSet),
        dest: Register(num: 15, registerSet: CurrentSet),
        imm: ImmediateArgument(kind: NumberImmediate, num: 4),
        opcode: 0
      )
    )
    data.instrs[i+2] = Instruction(
      kind: InstructionKind.Data,
      address: instr.address + 8,
      condition: Condition.default,
      line: instr.line
    )
    data.instrs[i+2].data = @[
      uint8(address and 0xFF),
      uint8(address shr 8 and 0xFF),
      uint8(address shr 16 and 0xFF),
      uint8(address shr 24 and 0xFF)
    ]
    instr.address + 8
  if f == Elf:
    data.relocations.add Relocation(
      offset: relAddr,
      label: labelId,
      kind: FullRelocation
    )

proc replaceMacroLoadConstShort(data: var ProgramData, instr: var Instruction, i: int, f: OutputFormat) =
  let reg = instr.macroInstr.args[0].reg
  let imm = instr.macroInstr.args[1].imm
  if imm.kind == LabelImmediate:
    var e = newException(ReplacementError, "Cannot load labels with short loads!")
    e.line = instr.line
    raise e
  instr = Instruction(
    kind: Ldi,
    address: instr.address,
    condition: instr.condition,
    line: instr.line,
    ldi: LdiInstruction(
      dest: reg,
      imm: imm
      )
    )

proc replaceMacroLoadConst(data: var ProgramData, instr: var Instruction, i: int, f: OutputFormat) =
  let reg = instr.macroInstr.args[0].reg
  let imm = instr.macroInstr.args[1].imm
  let cond = instr.condition
  let val = if f == Elf and imm.kind == LabelImmediate: imm.labelAdd
    else: cast[uint32](imm.num)
  echo val
  instr = Instruction(
    kind: Ldi,
    address: instr.address,
    condition: Condition(main: cond.main, isFreezed: true),
    line: instr.line,
    ldi: LdiInstruction(
      dest: reg,
      imm: ImmediateArgument(
        kind: NumberImmediate,
        num: val.getBits(LoRelocation).int
        )
      )
    )
  data.instrs[i+1] = Instruction(
      kind: Immediate,
      address: instr.address + 4,
      condition: cond,
      line: instr.line,
      imm: ImmediateInstruction(
        src: reg,
        dest: reg,
        imm: ImmediateArgument(
          kind: NumberImmediate, 
          num: val.getBits(HiRelocation).int
          ),
        opcode: 7
      )
    )
  if f == Elf and imm.kind == LabelImmediate:
    data.relocations.add Relocation(
      offset: instr.address,
      label: imm.labelId,
      kind: LoRelocation
    )
    data.relocations.add Relocation(
      offset: instr.address + 4,
      label: imm.labelId,
      kind: HiRelocation
    )

proc replaceMacro(data: var ProgramData, instr: var Instruction, i: int, f: OutputFormat) =
  case instr.macroInstr.kind:
    of MacroJmp: replaceMacroJmp(data, instr, i, f)
    of MacroJmpl: replaceMacroJmpl(data, instr, i, f) 
    of MacroLoadConstShort: replaceMacroLoadConstShort(data, instr, i, f) 
    of MacroLoadConst: replaceMacroLoadConst(data, instr, i, f) 

proc replaceCND(data: var ProgramData, instr: var Instruction, i: int) =
  if instr.condition.main == None and not instr.condition.isFreezed: return
  if i == 0: return
  if data.instrs[i-1].kind != Dummy:
    let e = newException(ReplacementError, "No Place for CND!")
    e.line = instr.line
    raise e
  data.instrs[i-1] = Instruction(
    kind: Cnd,
    address: instr.address,
    condition: Condition.default,
    line: instr.line
    )
  instr.address += 2
  template cnd: untyped = data.instrs[i-1]
  template instr1: untyped = data.instrs[i+1]
  template instr2: untyped = data.instrs[i+2]
  cnd.conditions[0] = instr.condition
  if i+1 < data.instrs.len and instr1.kind == Short:
    cnd.conditions[1] = instr1.condition
    if i+2 < data.instrs.len and instr2.kind == Short:
      cnd.conditions[2] = instr2.condition
    else:
      cnd.conditions[2] = Condition.default
  else:
    cnd.conditions[2] = Condition.default

proc collectShifts(data: var ProgramData, f: OutputFormat): seq[ShiftData] =
  for instr in data.instrs.mitems:
    if instr.kind != Macro or instr.macroInstr.kind != MacroLoadConst:
      continue
    let arg = instr.macroInstr.args[1].imm
    
    let isContracted = case arg.kind:
      of NumberImmediate: arg.num < 524288 and arg.num >= -524288
      of ReplacedLabelImmediate: 
        arg.replacedNum < 524284 and arg.replacedNum >= -524288
      of LabelImmediate: 
        if f == Binary:
          let e = newException(ReplacementError, "Label immediate in updating addresses")
          e.line = instr.line
          raise e
        else: false
    if isContracted:
      instr.macroInstr.kind = MacroLoadConstShort
      result.add ShiftData(startAddress: instr.address + 8, shift: -4)

proc shiftAddress(shifts: seq[ShiftData], address: Address): Address =
  var i = 0
  var shift = 0
  while i < shifts.len and address >= shifts[i].startAddress:
    shift += shifts[i].shift
    i.inc
  Address(address.int64 + shift.int64)

proc shiftInstr(instr: var Instruction, shifts: seq[ShiftData], shift: int) =
  instr.address = cast[Address](instr.address.int32 + shift.int32)
  for arg in instr.mimmArgs():
    if arg.kind == ReplacedLabelImmediate:
      let newAddress = shifts.shiftAddress(arg.address)
      arg.replacedNum = newAddress.getBits(arg.relKind).int
  if instr.kind == Macro:
      for arg in instr.macroInstr.args.mitems:
          if arg.kind != ImmediateValue: continue
          if arg.imm.kind == ReplacedLabelImmediate:
            let newAddress = shifts.shiftAddress(arg.imm.address)
            arg.imm.replacedNum = newAddress.getBits(arg.imm.relKind).int

proc replaceLabels(data: var ProgramData, f: OutputFormat) =
  for instr in data.instrs.mitems:
    data.replaceLabelsInInstr(instr, f)

proc updateAddresses(data: var ProgramData, f: OutputFormat) =
  while true:
    var shifts = data.collectShifts(f)
    if shifts.len != 0:
      var shift = 0
      var i = 0
      for instr in data.instrs.mitems:
        let address = instr.address
        while i < shifts.len and address >= shifts[i].startAddress:
          shift += shifts[i].shift
          i.inc
        instr.shiftInstr(shifts, shift)
      data.totalTextSize = cast[uint32](data.totalTextSize.int32 + shift.int32)

      for label in data.labelTable.labels.mitems:
        label.address = shifts.shiftAddress(label.address)
    else: return

proc replaceImmediatesToNumbers(data: var ProgramData, f: OutputFormat) =
  for instr in data.instrs.mitems:
    for arg in instr.mimmArgs():
      if arg.kind == ReplacedLabelImmediate:
        arg = ImmediateArgument(kind: NumberImmediate, num: arg.replacedNum)
    if instr.kind == Macro:
      for arg in instr.macroInstr.args.mitems:
          if arg.kind != ImmediateValue: continue
          if arg.imm.kind == ReplacedLabelImmediate:
            arg.imm = ImmediateArgument(kind: NumberImmediate, num: arg.imm.replacedNum)

proc replaceMacrosAndCND(data: var ProgramData, f: OutputFormat) =
  for i, instr in data.instrs.mpairs:
    if instr.kind == Macro:
      data.replaceMacro(instr, i, f)
    if instr.kind == Short:
      data.replaceCND(instr, i)

proc replaceAll*(data: var ProgramData, f: OutputFormat) =
  data.replaceLabels(f)
  data.updateAddresses(f)
  data.replaceImmediatesToNumbers(f)
  data.replaceMacrosAndCND(f)