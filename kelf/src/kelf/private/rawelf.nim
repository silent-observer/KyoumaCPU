import strformat
import stew/endians2

type 
  ElfSectionType* {.pure.} = enum
    NullSection = 0
    ProgBits = 1
    SymbolTable = 2
    StringTable = 3
    RelA = 4
    NoBits = 8
    Rel = 9
  ElfSectionFlag* {.pure, size: sizeof(uint32).} = enum
    Writable
    Allocate
    Executable
  ElfSectionFlags* = set[ElfSectionFlag]
  ElfSectionHeader* = object
    nameIndex*: uint32
    sectionType*: ElfSectionType
    flags*: ElfSectionFlags
    address*: uint32
    offset*: uint32
    size*: uint32
    link*: uint32
    info*: uint32
    addrAlign*: uint32
    entrySize*: uint32

type 
  ElfProgramType* {.pure.} = enum
    NullProgram = 0
    Load = 1
  ElfProgramFlag* {.pure, size: sizeof(uint32).} = enum
    ProgX
    ProgW
    ProgR
  ElfProgramFlags* = set[ElfProgramFlag]
  ElfProgramHeader* = object
    programType*: ElfProgramType
    offset*: uint32
    address*: uint32
    physicalAddress*: uint32
    fileSize*: uint32
    memSize*: uint32
    flags*: ElfProgramFlags
    align*: uint32

type
  ElfKind* {.pure.} = enum
    ObjectFile
    ExecutableFile
  RawElfFile* = object
    case kind*: ElfKind:
      of ObjectFile: 
        sections*: seq[ElfSectionHeader]
        strTableIndex*: uint16
      of ExecutableFile:
        segments*: seq[ElfProgramHeader]
    data*: seq[byte]
  ElfError* = object of Exception

const
  ElfIdentifier* : array[16, byte] = 
    [0x7F'u8, 0x45, 0x4C, 0x46, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  ElfHeaderSize* = 0x34
  ElfSectionHeaderSize* = 0x28
  ElfProgramHeaderSize* = 0x20
  ET_REL = 1'u16
  ET_EXEC = 2'u16

proc toElfSectionFlags(n: uint32): ElfSectionFlags {.inline.} = cast[ElfSectionFlags](n)
proc toNum(f: ElfSectionFlags): uint32 {.inline.} = cast[uint32](f)
proc toElfProgramFlags(n: uint32): ElfProgramFlags {.inline.} = cast[ElfProgramFlags](n)
proc toNum(f: ElfProgramFlags): uint32 {.inline.} = cast[uint32](f)

proc readSectionTableEntries(elf: var RawElfFile, offset: uint32, num: uint16) =
  var off = offset
  template data32(s: uint32): untyped =
    uint32.fromBytesLE(elf.data[off + s..^1])
  for i in 0'u32..<num:
    var header: ElfSectionHeader
    header.nameIndex = data32(0x0)
    header.sectionType = data32(0x4).ElfSectionType
    header.flags = data32(0x8).toElfSectionFlags()
    header.address = data32(0xC)
    header.offset = data32(0x10)
    header.size = data32(0x14)
    header.link = data32(0x18)
    header.info = data32(0x1C)
    header.addrAlign = data32(0x20)
    header.entrySize = data32(0x24)
    off += ElfSectionHeaderSize
    elf.sections.add header

proc readProgramTableEntries(elf: var RawElfFile, offset: uint32, num: uint16) =
  var off = offset
  template data32(s: uint32): untyped =
    uint32.fromBytesLE(elf.data[off + s..^1])
  for i in 0'u32..<num:
    var header: ElfProgramHeader
    header.programType = data32(0x0).ElfProgramType
    header.offset = data32(0x4)
    header.address = data32(0x8)
    header.physicalAddress = data32(0xC)
    header.fileSize = data32(0x10)
    header.memSize = data32(0x14)
    header.flags = data32(0x18).toElfProgramFlags()
    header.align = data32(0x1C)
    off += ElfProgramHeaderSize
    elf.segments.add header

proc readElf*(data: seq[byte]): RawElfFile =
  if data[0..15] != ElfIdentifier:
    raise newException(ElfError, "File is not valid KELF file!")
  let typeInt = uint16.fromBytesLE(data[0x10..^1])
  let isNoIS = uint16.fromBytesLE(data[0x12..^1]) == 0
  let isVer1 = uint32.fromBytesLE(data[0x14..^1]) == 1
  let isSizeValid = uint16.fromBytesLE(data[0x28..^1]) == 0x34
  if not (isNoIS and isVer1 and isSizeValid):
    raise newException(ElfError, "File is not valid KELF file!")
  
  let programHeaderTableOffset = uint32.fromBytesLE(data[0x1C..^1])
  let sectionHeaderTableOffset = uint32.fromBytesLE(data[0x20..^1])
  let programHeaderSize = uint16.fromBytesLE(data[0x2A..^1])
  let programHeaderNum = uint16.fromBytesLE(data[0x2C..^1])
  let sectionHeaderSize = uint16.fromBytesLE(data[0x2E..^1])
  let sectionHeaderNum = uint16.fromBytesLE(data[0x30..^1])
  let strTableIndex = uint16.fromBytesLE(data[0x32..^1])

  if typeInt == ET_REL:
    if sectionHeaderSize != ElfSectionHeaderSize:
      raise newException(ElfError, "File is not valid KELF object file!")
    result = RawElfFile(
      kind: ObjectFile, 
      data: data, 
      strTableIndex: strTableIndex
      )
    result.readSectionTableEntries(sectionHeaderTableOffset, sectionHeaderNum)
  elif typeInt == ET_EXEC:
    if programHeaderSize != ElfProgramHeaderSize:
      raise newException(ElfError, "File is not valid KELF object file!")
    result = RawElfFile(
      kind: ExecutableFile, 
      data: data
      )
    result.readProgramTableEntries(programHeaderTableOffset, programHeaderNum)
  else:
    raise newException(ElfError, fmt"ELF type {typeInt:02X} is not supported!")

proc writeSectionTableEntries*(
    sections: seq[ElfSectionHeader]): seq[byte] =
  var off = 0'u32
  result = newSeq[byte](sections.len * ElfSectionHeaderSize)
  template data32(s, v: uint32) =
    result[off+s..off+s+3] = v.toBytes()
  for header in sections:
    data32(0x0, header.nameIndex)
    data32(0x4, header.sectionType.uint32)
    data32(0x8, header.flags.toNum())
    data32(0xC, header.address)
    data32(0x10, header.offset)
    data32(0x14, header.size)
    data32(0x18, header.link)
    data32(0x1C, header.info)
    data32(0x20, header.addrAlign)
    data32(0x24, header.entrySize)
    off += ElfSectionHeaderSize

proc writeProgramTableEntries*(
    segments: seq[ElfProgramHeader]): seq[byte] =
  var off = 0'u32
  result = newSeq[byte](segments.len * ElfProgramHeaderSize)
  template data32(s, v: uint32) =
    result[off+s..off+s+3] = v.toBytes()
  for header in segments:
    data32(0x0, header.programType.uint32)
    data32(0x4, header.offset)
    data32(0x8, header.address)
    data32(0xC, header.physicalAddress)
    data32(0x10, header.fileSize)
    data32(0x14, header.memSize)
    data32(0x18, header.flags.toNum())
    data32(0x1C, header.align)
    off += ElfProgramHeaderSize

proc writeObjElfHeader*(data: var seq[byte], offset: uint32, num: uint16, strTableIndex: uint16) =
  data[0..15] = ElfIdentifier
  data[0x10..0x11] = ET_REL.uint16.toBytesLE()
  data[0x12..0x13] = 0'u16.toBytesLE()
  data[0x14..0x17] = 1'u32.toBytesLE()
  data[0x18..0x1B] = 0'u32.toBytesLE()
  data[0x1C..0x1F] = 0'u32.toBytesLE()
  data[0x20..0x23] = offset.uint32.toBytesLE()
  data[0x24..0x27] = 0'u32.toBytesLE()
  data[0x28..0x29] = 0x34'u16.toBytesLE()
  data[0x2A..0x2B] = ElfProgramHeaderSize.uint16.toBytesLE()
  data[0x2C..0x2D] = 0'u16.toBytesLE()
  data[0x2E..0x2F] = ElfSectionHeaderSize.uint16.toBytesLE()
  data[0x30..0x31] = num.uint16.toBytesLE()
  data[0x32..0x33] = strTableIndex.uint16.toBytesLE()

proc writeProgElfHeader*(data: var seq[byte], num: uint16, entry: uint32) =
  data[0..15] = ElfIdentifier
  data[0x10..0x11] = ET_EXEC.uint16.toBytesLE()
  data[0x12..0x13] = 0'u16.toBytesLE()
  data[0x14..0x17] = 1'u32.toBytesLE()
  data[0x18..0x1B] = entry.toBytesLE()
  data[0x1C..0x1F] = 0x34'u32.toBytesLE()
  data[0x20..0x23] = 0'u32.toBytesLE()
  data[0x24..0x27] = 0'u32.toBytesLE()
  data[0x28..0x29] = 0x34'u16.toBytesLE()
  data[0x2A..0x2B] = ElfProgramHeaderSize.uint16.toBytesLE()
  data[0x2C..0x2D] = num.uint16.toBytesLE()
  data[0x2E..0x2F] = ElfSectionHeaderSize.uint16.toBytesLE()
  data[0x30..0x31] = 0'u16.toBytesLE()
  data[0x32..0x33] = 0'u16.toBytesLE()