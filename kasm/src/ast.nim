import tables
import strformat
from kelf import SpecialSection
export SpecialSection

type
  OutputFormat* {.pure.} = enum
    Binary
    Elf
  RegisterSet* {.pure.} = enum
    SupervisorSet
    UserSet
    CurrentSet
  Register* = object
    num*: range[0..15]
    registerSet*: RegisterSet
  LabelId* = int
  Address* = uint32
  Label* = object
    text*: string
    id*: LabelId
    address*: Address
    section*: SpecialSection
    isDefined*: bool
    firstUsedLine*, firstUsedPos*, firstUsedIndex*: int
  MacroArgumentKind* {.pure.} = enum
    Register
    ImmediateValue
  ImmediateArgumentKind* {.pure.} = enum
    NumberImmediate
    LabelImmediate
    ReplacedLabelImmediate
  InstructionKind* {.pure.} = enum
    Short
    Immediate
    LoadStore
    Move
    Ldi
    Macro
    Data
    Dummy
    Cnd
    MultDiv
    MoveHi
    MoveLo
  ConditionMain* {.pure.} = enum
    None = 0
    OverflowSet = 1
    ZeroSet = 2
    ZeroClear = 3
    NegativeSet = 4
    NegativeClear = 5
    CarrySet = 6
    CarryClear = 7
  Condition* = object
    main*: ConditionMain
    isFreezed*: bool
  RelocationKind* {.pure.} = enum
    NoRelocation
    HiRelocation
    LoRelocation
    FullRelocation
    LoRelocationImm
  Relocation* = object
    offset*: uint32
    section*: SpecialSection
    label*: LabelId
    kind*: RelocationKind
  ImmediateArgument* = object
    relKind*: RelocationKind
    case kind*: ImmediateArgumentKind:
      of ImmediateArgumentKind.LabelImmediate: 
        labelId*: LabelId
        labelAdd*: uint32
      of ImmediateArgumentKind.NumberImmediate: num*: int
      of ImmediateArgumentKind.ReplacedLabelImmediate:
        address*: uint32
        replacedNum*: int
  ShortInstruction* = object
    src1*, src2*, dest*: Register
    opcode*: range[0..7]
  ImmediateInstruction* = object
    src*, dest*: Register
    opcode*: range[0..7]
    imm*: ImmediateArgument
  LoadStoreInstruction* = object
    register*, address*: Register
    opcode*: range[0..7]
    offset*: ImmediateArgument
  MoveInstruction* = object
    src*, dest*: Register
  MoveHiLoInstruction* = object
    dest*: Register
  LdiInstruction* = object
    dest*: Register
    imm*: ImmediateArgument
  MultDivInstruction* = object
    src1*, src2*: Register
    isDiv*: bool
    isSigned*: bool
  MacroInstructionKind* {.pure.} = enum
    MacroJmp
    MacroJmpl
    MacroLoadConst
    MacroLoadConstShort
  MacroArgument* = object
    case kind*: MacroArgumentKind:
      of MacroArgumentKind.Register: reg*: Register
      of MacroArgumentKind.ImmediateValue: imm*: ImmediateArgument
  MacroInstruction* = object
    kind*: MacroInstructionKind
    args*: seq[MacroArgument]
  Instruction* = object
    line*: int
    address*: Address
    condition*: Condition
    case kind*: InstructionKind:
      of Short: short*: ShortInstruction
      of Immediate: imm*: ImmediateInstruction
      of LoadStore: ls*: LoadStoreInstruction
      of Move: mov*: MoveInstruction
      of Ldi: ldi*: LdiInstruction
      of Macro: macroInstr*: MacroInstruction
      of InstructionKind.Data: data*: seq[uint8]
      of Dummy: nil
      of Cnd: conditions*: array[3, Condition]
      of MultDiv: multDiv*: MultDivInstruction
      of MoveHi, MoveLo: movHiLo*: MoveHiLoInstruction
  LabelTable* = object
    table*: Table[string, LabelId]
    labels*: seq[Label]
  ProgramData* = object
    instrs*: seq[Instruction]
    data*, rodata*: seq[uint8]
    bssSize*: uint32
    labelTable*: LabelTable
    relocations*: seq[Relocation]
    totalTextSize*: uint32

proc `$`*(label: Label): string =
  fmt"Label#{label.id}(""{label.text}"") at {label.address:08X}:{label.section}"

proc `$`*(r: Register): string =
  result = case r.registerSet:
    of SupervisorSet: "s"
    of UserSet: "u"
    of CurrentSet: ""
  let x = case r.num:
    of 0..10: "R" & $r.num
    of 11: "SR"
    of 12: "LR"
    of 13: "FP"
    of 14: "SP"
    of 15: "PC"
  result &= x

proc `$`*(r: Relocation): string {.inline.} =
  &"{r.offset:08X}:{r.section} <- Label#{r.label}({r.kind})"

proc `$`*(a: ImmediateArgument): string =
  case a.kind:
    of ImmediateArgumentKind.LabelImmediate: 
      if a.labelAdd == 0: &"Label#{a.labelId}"
      else: &"Label#{a.labelId} {a.labelAdd.int32:+}"
    of ImmediateArgumentKind.NumberImmediate: $a.num
    of ImmediateArgumentKind.ReplacedLabelImmediate: 
      &"{a.address:08X}[{a.relKind}] = {a.replacedNum}"

proc `$`*(a: MacroArgument): string =
  case a.kind:
    of MacroArgumentKind.Register: $a.reg
    of MacroArgumentKind.ImmediateValue: $a.imm

proc `$`*(instr: Instruction): string =
  result = fmt"{instr.address:08X}: "
  if instr.condition.main != None:
    result &= fmt"if {instr.condition.main} "
  if instr.condition.isFreezed:
    result &= "(freezed) "
  let part2 = case instr.kind:
    of Short: fmt"Short#{instr.short.opcode} {instr.short.dest}, {instr.short.src1}, {instr.short.src2}"
    of Immediate: fmt"Immediate#{instr.imm.opcode} {instr.imm.dest}, {instr.imm.src}, {instr.imm.imm}"
    of LoadStore: 
      let isLoad = instr.ls.opcode == 0 or instr.ls.opcode >= 4
      if isLoad:
        fmt"LoadStore#{instr.ls.opcode} {instr.ls.register}, ({instr.ls.address}, {instr.ls.offset})"
      else:
        fmt"LoadStore#{instr.ls.opcode} ({instr.ls.address}, {instr.ls.offset}), {instr.ls.register}"
    of Ldi:
      fmt"Ldi {instr.ldi.dest}, {instr.ldi.imm}"
    of Move:
      fmt"Mov {instr.mov.dest}, {instr.mov.src}"
    of Macro:
      fmt"Macro({instr.macroInstr.kind}) {instr.macroInstr.args}"
    of InstructionKind.Data:
      fmt"Data {instr.data}"
    of Dummy: "Dummy"
    of Cnd: fmt"Cnd {instr.conditions}"
    of MultDiv:
      let signedString = if instr.multDiv.isSigned: "(signed)" else: "(unsigned)"
      if instr.multDiv.isDiv:
        fmt"Div {signedString} {instr.multDiv.src1}, {instr.multDiv.src2}"
      else:
        fmt"Mult {signedString} {instr.multDiv.src1}, {instr.multDiv.src2}"
    of MoveHi: fmt"Mov {instr.movHiLo.dest}, HI"
    of MoveLo: fmt"Mov {instr.movHiLo.dest}, LO"
  result &= part2

proc toNum*(c: Condition): uint32 {.inline.} = c.main.uint32 or c.isFreezed.uint32 shl 3

proc getBits*(x: uint32, relKind: RelocationKind): uint32 {.inline.} =
  case relKind:
    of NoRelocation: x
    of HiRelocation: x shr 18 and 0x3FFF'u32
    of LoRelocation: x and 0xFFFFF'u32
    of FullRelocation: x
    of LoRelocationImm: x and 0x3FFF'u32