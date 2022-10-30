type
  Flag* {.pure.} = enum
    Zero
    Carry
    Negative
    Overflow
  Flags* = set[Flag]
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
    freeze*: bool

proc toInt*(flags: Flags): int {.inline.} = cast[int](flags)
proc toFlags*(x: int): Flags {.inline.} = cast[Flags](x)

proc toInt*(cond: Condition): int {.inline.} = cond.main.int or (cond.freeze.int shl 3)
proc toCondition*(x: int): Condition {.inline.} =
  result.main = ConditionMain(x and 0x7)
  result.freeze = (x and 0x8) != 0

proc `$`*(f: Flags): string =
  result &= (if Overflow in f: "V" else: "-")
  result &= (if Negative in f: "N" else: "-")
  result &= (if Carry in f: "C" else: "-")
  result &= (if Zero in f: "Z" else: "-")

proc `$`*(c: Condition): string =
  case c.main:
    of None: "None"
    of OverflowSet: "Overflow"
    of ZeroSet: "Zero"
    of ZeroClear: "not Zero"
    of NegativeSet: "Negative"
    of NegativeClear: "not Negative"
    of CarrySet: "Carry"
    of CarryClear: "not Carry"

proc isTrue*(cond: Condition, flags: Flags): bool =
  case cond.main:
    of None: true
    of OverflowSet: Overflow in flags
    of ZeroSet: Zero in flags
    of ZeroClear: Zero notin flags
    of NegativeSet: Negative in flags
    of NegativeClear: Negative notin flags
    of CarrySet: Carry in flags
    of CarryClear: Carry notin flags