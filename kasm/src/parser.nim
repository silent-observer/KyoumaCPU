import token, ast
from parseutils import parseUntil
from strutils import spaces, toUpperAscii
import tables

const 
  ShortMnemonics = ["ADD", "SUB", "LSH", "ASH", "AND", "OR", "XOR", "CND"]
  ShortInstructionSize = 2
  ImmediateMnemonics = ["ADDI", "SUBI", "LSHI", "ASHI", "ANDI", "ORI", "XORI", "LDH"]
  LoadStoreMnemonics = ["LW", "SW", "SH", "SB", "LHU", "LHS", "LBU", "LBS"]
  MultDivMnemonics = ["MLTU", "MLTS", "DIVU", "DIVS"]
  NormalInstructionSize = 4


type ParsingError* = object of Exception
  line, pos, index: int

type Parser = object
  input: TokenList
  labels: LabelTable
  index: int
  currentAddress: Address
  instructionsSinceLastCND: int

proc peek(parser: Parser): Token {.inline.} =
  if parser.index >= parser.input.len:
    let t = parser.input[^1]
    Token(kind: Eof, line: t.line, pos: t.pos, index: t.index)
  else:
    parser.input[parser.index]

proc getOne(parser: var Parser): Token {.inline.} =
  result = parser.peek()
  parser.index.inc

proc reportError*(e: ParsingError, input: string): string =
  result = "Parsing Error occured!\n" & e.msg & "\nLine " & $e.line & ":\n"
  let lineStart = e.index - (e.pos - 1)
  var lineString: string
  discard input.parseUntil(lineString, {'\n', '\r'}, lineStart)
  result &= lineString & "\n"
  if e.pos - 1 >= 0:
    result &= spaces(e.pos - 1) & "^\n"

proc raiseError(t: Token, text: string) {.noReturn.} =
  var e = newException(ParsingError, text)
  e.line = t.line
  e.pos = t.pos
  e.index = t.index
  raise e

proc alignAddress(parser: var Parser, alignment: static[int]) =
  const mask = if alignment == 4: 0x3'u32 else: 0x1'u32
  if (parser.currentAddress and mask) != 0:
    let newAddress = (parser.currentAddress + alignment.uint32) and not mask
    # Move all labels at this address too, because otherwise they would point to NOP instruction
    for l in parser.labels.labels.mitems:
      if l.address == parser.currentAddress:
        l.address = newAddress
    
    parser.currentAddress = newAddress

proc alignAddressRuntime(parser: var Parser, alignment: int) =
  while parser.currentAddress mod alignment.uint32 != 0:
    parser.currentAddress += 1

proc parseCondition(parser: var Parser): Condition =
  let t = parser.peek()
  if t.kind == TokenKind.Condition:
    discard parser.getOne()
    result.main = case t.text.toUpperAscii:
      of "Z", "EQ": ZeroSet
      of "NZ", "NE": ZeroClear
      of "V": OverflowSet
      of "LT": NegativeSet
      of "GE": NegativeClear
      of "C": CarrySet
      of "NC": CarryClear
      else: None
  if parser.peek().kind == TokenKind.FreezeFlags:
    discard parser.getOne()
    result.isFreezed = true

proc parseRegister(parser: var Parser, isNonCurrentSetAcceptable: bool = false): Register =
  let t = parser.peek()
  if t.kind != TokenKind.RegisterName:
    t.raiseError("Expected register")
  discard parser.getOne()
  let text = t.text.toUpperAscii()
  result.registerSet = case text[0]:
      of 'S': 
        if text != "SR" and text != "SP": 
          SupervisorSet
        else: 
          CurrentSet
      of 'U': UserSet
      else: CurrentSet
  if not isNonCurrentSetAcceptable and result.registerSet != CurrentSet:
    t.raiseError("Only registers in current register set are allowed!")
  let mainText = if result.registerSet == CurrentSet:
      text
    else:
      text[1..^1]
  result.num = case mainText:
    of "R0": 0
    of "R1": 1
    of "R2": 2
    of "R3": 3
    of "R4": 4
    of "R5": 5
    of "R6": 6
    of "R7": 7
    of "R8": 8
    of "R9": 9
    of "R10": 10
    of "R11", "SR": 11
    of "R12", "LR": 12
    of "R13", "FP": 13
    of "R14", "SP": 14
    of "R15", "PC": 15
    else: 0

proc addLabelToTheTable(parser: var Parser, label: Token): LabelId =
  if label.text in parser.labels.table:
    return parser.labels.table[label.text]
  result = parser.labels.labels.len
  parser.labels.table[label.text] = result
  parser.labels.labels.add Label(
    text: label.text, 
    id: result, 
    address: 0,
    isDefined: false,
    firstUsedLine: label.line,
    firstUsedPos: label.pos,
    firstUsedIndex: label.index
    )

proc parseLabelAddend(parser: var Parser): uint32 =
  if parser.peek().kind != LeftBracket:
    return 0
  discard parser.getOne()
  var sign = 1
  if parser.peek().kind == Minus:
    sign = -1;
    discard parser.getOne()
  let num = parser.getOne()
  if num.kind != Number:
    num.raiseError("Expected number as label addend!")
  if parser.getOne().kind != RightBracket:
    num.raiseError("Expected closing bracket!")
  return cast[uint32](num.num * sign)

proc parseImmediateVal(parser: var Parser): ImmediateArgument =
  var immVal = parser.getOne()

  if immVal.kind == TokenKind.Label:
    return ImmediateArgument(
      kind: ImmediateArgumentKind.LabelImmediate,
      labelId: parser.addLabelToTheTable(immVal),
      labelAdd: parser.parseLabelAddend(),
      relKind: FullRelocation
    )
  
  var sign = 1
  if immVal.kind == TokenKind.Minus:
    sign = -1
    immVal = parser.getOne()

  if immVal.kind == TokenKind.Number:
    return ImmediateArgument(
      kind: ImmediateArgumentKind.NumberImmediate,
      num: immVal.num * sign,
      relKind: NoRelocation
    )
  immVal.raiseError("Expected immediate value!")

proc parseComma(parser: var Parser): bool =
  let t = parser.peek()
  if t.kind == Comma:
    discard parser.getOne()
    return true
  elif t.kind == Newline:
    return false
  else:
    t.raiseError("Expected comma")
proc parseToken(parser: var Parser, token: TokenKind, errorMsg: string) =
  let t = parser.getOne()
  if t.kind != token:
    t.raiseError(errorMsg)

proc parseAddressArgument(parser: var Parser, instr: var LoadStoreInstruction) =
  parser.parseToken(LeftParen, "Expected left paren")
  let regToken = parser.peek()
  if regToken.kind == RegisterName:
    instr.address = parser.parseRegister()
  else:
    instr.address = Register(num: 0, registerSet: CurrentSet)
  
  let sign = parser.peek()
  case sign.kind:
    of RightParen: 
      discard parser.getOne()
      instr.offset = ImmediateArgument(
        kind: NumberImmediate,
        num: 0,
        relKind: NoRelocation)
    of Plus, Minus, Number: 
      if sign.kind == Number and instr.address.num != 0:
        sign.raiseError("Expected plus or minus!")
      if sign.kind != Number:
        discard parser.getOne()
      instr.offset = parser.parseImmediateVal()
      if instr.offset.kind == NumberImmediate:
        if sign.kind == Minus:
          instr.offset.num *= -1
      parser.parseToken(RightParen, "Expected right paren")
    else: sign.raiseError("Expected right paren or offset")

proc parseInstrShort(parser: var Parser, t: Token, index: int, instr: var Instruction): int =
  parser.currentAddress += ShortInstructionSize
  instr = Instruction(kind: Short)
  instr.short.opcode = index
  result = 0
  if index == 7:
    parser.instructionsSinceLastCND = 0
  else:
    parser.instructionsSinceLastCND += 1
  instr.condition = parser.parseCondition()
  if (instr.condition.main != None or instr.condition.isFreezed) and parser.instructionsSinceLastCND > 3:
    result = 1
    parser.instructionsSinceLastCND = 1
    parser.currentAddress += ShortInstructionSize
  instr.short.dest = parser.parseRegister()
  if not parser.parseComma():
    t.raiseError("Short instructions cannot have 1 argument!")
  instr.short.src1 = parser.parseRegister()
  if parser.parseComma():
    instr.short.src2 = parser.parseRegister()
    if parser.parseComma():
      t.raiseError("Instructions cannot have more than 3 arguments!")
  else:
    instr.short.src2 = instr.short.src1
    instr.short.src1 = instr.short.dest

proc parseInstrImm(parser: var Parser, t: Token, index: int, result: var Instruction) =
  parser.currentAddress += NormalInstructionSize
  result = Instruction(kind: Immediate)
  result.imm.opcode = index
  result.condition = parser.parseCondition()
  result.imm.dest = parser.parseRegister()
  if not parser.parseComma():
    t.raiseError("Immediate instructions cannot have 1 argument!")
  let srcReg = parser.peek()
  if srcReg.kind == RegisterName:
    result.imm.src = parser.parseRegister()
    if not parser.parseComma():
      return
  else:
    result.imm.src = result.imm.dest
  
  result.imm.imm = parser.parseImmediateVal()
  if result.imm.imm.kind == LabelImmediate:
    result.imm.imm.relKind = if index == 7: HiRelocation else: LoRelocationImm

proc parseInstrLS(parser: var Parser, t: Token, index: int, result: var Instruction) =
  parser.currentAddress += NormalInstructionSize
  result = Instruction(kind: LoadStore)
  result.ls.opcode = index
  result.condition = parser.parseCondition()
  let isLoad = index == 0 or index >= 4

  if isLoad:
    result.ls.register = parser.parseRegister()
  else:
    parser.parseAddressArgument(result.ls)
  if not parser.parseComma():
    t.raiseError("Load/store instructions have 2 arguments!")
  if not isLoad:
    result.ls.register = parser.parseRegister()
  else:
    parser.parseAddressArgument(result.ls)

proc parseInstrMD(parser: var Parser, t: Token, index: int, result: var Instruction) =
  parser.currentAddress += NormalInstructionSize
  result = Instruction(kind: MultDiv)
  result.multDiv.isDiv = index >= 2
  result.multDiv.isSigned = (index == 1 or index == 3)
  result.condition = parser.parseCondition()
  result.multDiv.src1 = parser.parseRegister()
  if not parser.parseComma():
    t.raiseError("Mult/div instructions have 2 arguments!")
  result.multDiv.src2 = parser.parseRegister()

proc parseInstrLdi(parser: var Parser, t: Token, result: var Instruction) =
  parser.currentAddress += NormalInstructionSize
  result = Instruction(kind: Ldi)
  result.condition = parser.parseCondition()
  result.ldi.dest = parser.parseRegister()
  if not parser.parseComma():
    t.raiseError("LDI instruction has 2 arguments!")

  result.ldi.imm = parser.parseImmediateVal()
  if result.ldi.imm.kind == LabelImmediate:
    result.ldi.imm.relKind = LoRelocation

proc parseInstrMov(parser: var Parser, t: Token, instr: var Instruction): int =
  let cond = parser.parseCondition()
  let r1 = parser.parseRegister(true)
  if not parser.parseComma():
    t.raiseError("MOV instruction has 2 arguments!")
  
  let r2Token = parser.peek()
  if r2Token.kind != TokenKind.RegisterName:
    r2Token.raiseError("Expected register")
  
  if r2Token.text.toUpperAscii() == "HI":
    parser.currentAddress += NormalInstructionSize
    instr = Instruction(kind: MoveHi)
    instr.movHiLo.dest = r1
    discard parser.getOne()
  elif r2Token.text.toUpperAscii() == "LO":
    parser.currentAddress += NormalInstructionSize
    instr = Instruction(kind: MoveLo)
    instr.movHiLo.dest = r1
    discard parser.getOne()
  else:
    let r2 = parser.parseRegister(true)
    if r1.registerSet == CurrentSet and r2.registerSet == CurrentSet:
      result = 1
      parser.currentAddress += ShortInstructionSize
      instr = Instruction(kind: Short)
      instr.short.opcode = 0
      instr.short.dest = r1
      instr.short.src1 = r2
      instr.short.src2 = Register(num: 0, registerSet: CurrentSet)
    elif r1.registerSet != UserSet and r2.registerSet == UserSet or
        r1.registerSet == UserSet and r2.registerSet != UserSet:
      parser.currentAddress += NormalInstructionSize
      instr = Instruction(kind: Move)
      instr.mov.dest = r1
      instr.mov.src = r2
    else:
      t.raiseError("Cannot MOV between registers of the same set directly!")
  instr.condition = cond

proc parseInstrJmp(parser: var Parser, t: Token, instr: var Instruction): int =
  result = 0
  instr = Instruction(kind: Macro)
  instr.condition = parser.parseCondition()
  case t.text.toUpperAscii:
    of "JMP": 
      parser.currentAddress += NormalInstructionSize
    of "JMPL": 
      parser.currentAddress += NormalInstructionSize * 2
      result = 1
      if instr.condition.main != None:
        parser.currentAddress += NormalInstructionSize
        result = 2
    else: discard
  instr.macroInstr.kind = case t.text.toUpperAscii:
    of "JMP": MacroJmp
    of "JMPL": MacroJmpl
    else: t.raiseError("Strange JMP error!")
  let t = parser.getOne()
  if t.kind != TokenKind.Label:
    t.raiseError("Jump instruction must have label argument!")
  let labelId = parser.addLabelToTheTable(t)
  let labelAdd = parser.parseLabelAddend()
  let arg = MacroArgument(
    kind: ImmediateValue,
    imm: ImmediateArgument(
      kind: LabelImmediate,
      labelId: labelId, 
      labelAdd: labelAdd
      )
    )
  instr.macroInstr.args = @[arg]

proc parseInstrHalt(parser: var Parser, t: Token, result: var Instruction) =
  parser.currentAddress += NormalInstructionSize
  result = Instruction(kind: Immediate)
  result.imm.opcode = 1
  result.imm.dest = Register(num: 15, registerSet: CurrentSet)
  result.imm.src = Register(num: 15, registerSet: CurrentSet)
  result.imm.imm = ImmediateArgument(
    kind: NumberImmediate, 
    num: NormalInstructionSize,
    relKind: NoRelocation
    )
  result.condition = Condition(main: None, isFreezed: false)

proc parseInstrNop(parser: var Parser, t: Token, result: var Instruction) =
  parser.currentAddress += ShortInstructionSize
  result = Instruction(kind: Short)
  result.short.opcode = 0
  result.short.src1 = Register(num: 0, registerSet: CurrentSet)
  result.short.src2 = result.short.src1
  result.short.dest = result.short.src1
  result.condition = Condition(main: None, isFreezed: false)

proc parseInstrLoad(parser: var Parser, t: Token, instr: var Instruction): int =
  parser.currentAddress += NormalInstructionSize * 2
  instr = Instruction(
    kind: Macro,
    macroInstr: MacroInstruction(
      kind: MacroLoadConst
    )
  )
  instr.condition = parser.parseCondition()
  let r = parser.parseRegister()
  if not parser.parseComma():
    t.raiseError("LOAD macro instruction has 2 arguments!")
  let imm = parser.parseImmediateVal()
  result = 1
  instr.macroInstr.args = @[
    MacroArgument(kind: MacroArgumentKind.Register, reg: r),
    MacroArgument(kind: MacroArgumentKind.ImmediateValue, imm: imm)
  ]

proc parseInstrCmp(parser: var Parser, t: Token, result: var Instruction) =
  let cond = parser.parseCondition()
  let reg1 = parser.parseRegister()
  if not parser.parseComma():
    parser.currentAddress += ShortInstructionSize
    result = Instruction(
      kind: Short,
      condition: cond,
      short: ShortInstruction(
        src1: reg1,
        src2: Register(num: 0, registerSet: CurrentSet),
        dest: Register(num: 0, registerSet: CurrentSet),
        opcode: 0
        )
      )
  elif parser.peek().kind == RegisterName:
    let reg2 = parser.parseRegister()
    parser.currentAddress += ShortInstructionSize
    result = Instruction(
      kind: Short,
      condition: cond,
      short: ShortInstruction(
        src1: reg1,
        src2: reg2,
        dest: Register(num: 0, registerSet: CurrentSet),
        opcode: 1
        )
      )
  else:
    let imm = parser.parseImmediateVal()
    parser.currentAddress += NormalInstructionSize
    result = Instruction(
      kind: Immediate,
      condition: cond,
      imm: ImmediateInstruction(
        src: reg1,
        imm: imm,
        dest: Register(num: 0, registerSet: CurrentSet),
        opcode: 1
        )
      )

proc parseDataToSeq(parser: var Parser, t: Token): seq[uint8] =
  var args: seq[int]
  let arg1 = parser.parseImmediateVal()
  if arg1.kind == LabelImmediate:
    t.raiseError("Data with labels is not yet supported!")
  args.add arg1.num
  while parser.parseComma():
    let arg = parser.parseImmediateVal()
    if arg.kind == LabelImmediate:
      t.raiseError("Data with labels is not yet supported!")
    args.add arg.num
  case t.text.toUpperAscii:
    of "DB": 
      for a in args: 
        result.add uint8(a and 0xFF)
    of "DH": 
      for a in args: 
        result.add uint8(a and 0xFF)
        result.add uint8(a shr 8 and 0xFF)
    of "DW": 
      for a in args: 
        result.add uint8(a and 0xFF)
        result.add uint8(a shr 8 and 0xFF)
        result.add uint8(a shr 16 and 0xFF)
        result.add uint8(a shr 24 and 0xFF)
    else: discard

proc alignData(address: Address, alignment: static[int]): seq[uint8] =
  when alignment == 1:
    return @[]
  elif alignment == 2:
    if (address mod 2) == 0:
      return @[]
    else:
      return @[0'u8]
  elif alignment == 4:
    case address mod 4:
      of 0: return @[]
      of 1: return @[0'u8, 0'u8, 0'u8]
      of 2: return @[0'u8, 0'u8]
      of 3: return @[0'u8]
      else: assert(false)

proc alignDataRuntime(address: Address, alignment: int): seq[uint8] =
  var x = address
  while address mod alignment.uint32 != 0:
    result.add 0'u8
    x += 1

proc parseDataInstr(parser: var Parser, t: Token, result: var Instruction) =
  let data = parser.parseDataToSeq(t)
  parser.currentAddress += data.len.Address
  result = Instruction(
    kind: InstructionKind.Data,
    data: data
  )

type InstrResult = tuple[dummyBefore: int, instr: Instruction, dummyAfter: int]

proc parseInstr(parser: var Parser, t: Token): InstrResult =
  let text = t.text.toUpperAscii
  let indexShort = ShortMnemonics.find(text)
  let indexImm = ImmediateMnemonics.find(text)
  let indexLS = LoadStoreMnemonics.find(text)
  let indexMD = MultDivMnemonics.find(text)
  if text == "DB":
    parser.instructionsSinceLastCND = 4
  elif indexShort != -1 or text == "NOP":
    parser.alignAddress(2)
    discard
  else:
    parser.alignAddress(4)
    parser.instructionsSinceLastCND = 4
  let address = parser.currentAddress
  result[0] = 0
  result[2] = 0
  if indexShort != -1:
    result[0] = parser.parseInstrShort(t, indexShort, result[1])
  elif indexImm != -1:
    parser.parseInstrImm(t, indexImm, result[1])
  elif indexLS != -1:
    parser.parseInstrLS(t, indexLS, result[1])
  elif indexMD != -1:
    parser.parseInstrMD(t, indexMD, result[1])
  elif text == "LDI":
    parser.parseInstrLdi(t, result[1])
  elif text == "MOV":
    result[0] = parser.parseInstrMov(t, result[1])
  elif text == "JMP" or text == "JMPL":
    result[2] = parser.parseInstrJmp(t, result[1])
  elif text == "HALT":
    parser.parseInstrHalt(t, result[1])
  elif text == "NOP":
    parser.parseInstrNop(t, result[1])
  elif text == "LOAD":
    result[2] = parser.parseInstrLoad(t, result[1])
  elif text == "CMP":
    parser.parseInstrCmp(t, result[1])
  elif text == "DB" or text == "DH" or text == "DW":
    parser.parseDataInstr(t, result[1])
  else:
    t.raiseError("Unsupported instruction!")
  result[1].address = address
  result[1].line = t.line
  parser.parseToken(Newline, "Expected end of line!")


proc parseLabel(parser: var Parser, t: Token, section: SpecialSection, address: Address) =
  let id = parser.addLabelToTheTable(t)
  template label: untyped = parser.labels.labels[id]
  if label.isDefined:
    t.raiseError("Label with that name is already defined!")
  label.isDefined = true
  label.address = address
  label.section = section

proc parseData(parser: var Parser, data: var seq[uint8], section: SpecialSection) =
  while true:
    let address = data.len.Address
    let t = parser.peek()
    if t.kind != Directive:
      discard parser.getOne()
    case t.kind
      of Eof: break
      of Newline: continue
      of Mnemonic:
        case t.text.toUpperAscii():
          of "DB": discard
          of "DH": data.add address.alignData(2)
          of "DW": data.add address.alignData(4)
          else: t.raiseError("Could only have data in data section!")
        data.add parser.parseDataToSeq(t)
      of LabelDef: parser.parseLabel(t, section, address)
      of Directive: 
        if t.text.toUpperAscii() in ["TEXT", "DATA", "RODATA", "BSS"]:
          break
        elif t.text.toUpperAscii == "ALIGN":
          discard parser.getOne()
          let t = parser.getOne()
          data.add address.alignDataRuntime(t.num)
        else:
          t.raiseError("Unexpected directive!")
      else:
        t.raiseError("Expected data or label!")
  data.add data.len.Address.alignData(4)

proc parseBss(parser: var Parser, bssSize: var uint32) =
  while true:
    let t = parser.peek()
    if t.kind != Directive:
      discard parser.getOne()
    case t.kind
      of Eof: break
      of Newline: continue
      of Mnemonic:
        case t.text.toUpperAscii():
          of "DB": discard
          of "DH": bssSize += bssSize.alignData(2).len.uint32
          of "DW": bssSize += bssSize.alignData(4).len.uint32
          else: t.raiseError("Could only have data in data section!")
        let d = parser.parseDataToSeq(t)
        for x in d:
          if x != 0:
            t.raiseError("Could only have 0 initialized data in bss!")
        bssSize += d.len.uint32
      of LabelDef: parser.parseLabel(t, Bss, bssSize)
      of Directive: 
        if t.text.toUpperAscii() in ["TEXT", "DATA", "RODATA", "BSS"]:
          break
        elif t.text.toUpperAscii == "ALIGN":
          discard parser.getOne()
          let t = parser.getOne()
          bssSize += bssSize.alignDataRuntime(t.num).len.uint32
        else:
          t.raiseError("Unexpected directive!")
      else:
        t.raiseError("Expected data or label!")
  bssSize += bssSize.alignData(4).len.uint32

proc parse*(tokens: TokenList, f: OutputFormat): ProgramData =
  var parser = Parser(input: tokens, index: 0, currentAddress: 4, instructionsSinceLastCND: 4)
  if f == Elf:
    parser.currentAddress = 0
  else:
    result.instrs = @[Instruction(
      kind: InstructionKind.Data,
      address: 0,
      data: @[0x00'u8, 0x00, 0x00, 0x00]
      )]
  while true:
    let t = parser.getOne()
    case t.kind:
      of Eof: break
      of Newline: continue
      of Mnemonic:
        let (dummyCountBefore, instr, dummyCountAfter) = parser.parseInstr(t)
        for i in 0..<dummyCountBefore:
          result.instrs.add Instruction(kind: Dummy, address: parser.currentAddress)
        result.instrs.add instr
        for i in 0..<dummyCountAfter:
          result.instrs.add Instruction(kind: Dummy, address: parser.currentAddress)
      of LabelDef: parser.parseLabel(t, Text, parser.currentAddress)
      of Directive:
        let text = t.text.toUpperAscii()
        case text:
          of "TEXT": parser.alignAddress(4)
          of "DATA": parser.parseData(result.data, SpecialSection.Data)
          of "RODATA": parser.parseData(result.rodata, SpecialSection.Rodata)
          of "BSS": parser.parseBss(result.bssSize)
          of "ALIGN":
            discard parser.getOne()
            let t = parser.getOne()
            parser.alignAddressRuntime(t.num)
      else: t.raiseError("Expected instruction or label!")
  parser.alignAddress(4)
  result.labelTable = parser.labels
  result.totalTextSize = parser.currentAddress

  for label in result.labelTable.labels:
    let isGlobal = label.text[0] != '_'
    let shouldReportUndefined = case f:
      of Binary: true
      of Elf: not isGlobal
    if not label.isDefined and shouldReportUndefined:
      var e = newException(ParsingError, "Label is not defined!")
      e.line = label.firstUsedLine
      e.pos = label.firstUsedPos
      e.index = label.firstUsedIndex
      raise e