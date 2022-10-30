import elf

type
  ElfProgBuilder* = object
    prog: ElfProgramFile

proc initElfProgBuilder*(): ElfProgBuilder {.inline.} =
  result.prog = ElfProgramFile(
    segments: @[]
  )

proc setEntryPoint*(builder: var ElfProgBuilder, entry: uint32) {.inline.} =
  builder.prog.entry = entry

proc addLoadSegment(builder: var ElfProgBuilder, 
    data: seq[byte], emptyBytes: uint32, address: uint32, flags: ElfProgramFlags) {.inline.} =
  builder.prog.segments.add ElfSegment(
    flags: flags,
    address: address,
    memSize: data.len.uint32 + emptyBytes,
    data: data
  )
proc addReadExecuteSegment*(builder: var ElfProgBuilder, 
    data: seq[byte], address: uint32) {.inline.} =
  builder.addLoadSegment(data, 0, address, {ProgR, ProgX})
proc addReadWriteSegment*(builder: var ElfProgBuilder, 
    data: seq[byte], emptyBytes: uint32, address: uint32) {.inline.} =
  builder.addLoadSegment(data, emptyBytes, address, {ProgR, ProgW})

proc getProgFile*(builder: ElfProgBuilder): ElfProgramFile {.inline.} =
  builder.prog