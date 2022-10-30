import rawelf
import stew/endians2

export ElfSectionFlags, ElfSectionFlag, ElfSectionType
export ElfProgramFlags, ElfProgramFlag

type
  SymbolKind* {.pure, size: 1.} = enum
    NoSymbol = 0
    Object = 1
    Function = 2
  SymbolData* = object
    name*: string
    nameIndex*: uint32
    value*: uint32
    size*: uint32
    kind*: SymbolKind
    sectionId*: uint16
  SymbolTableData* = object
    local*, global*: seq[SymbolData]
  ElfRelocation* = object
    offset*: uint32
    index*: uint32
    relKind*: uint8
  ElfSection* = object
    name*: string
    nameIndex*: uint32
    flags*: ElfSectionFlags
    address*: uint32
    case kind*: ElfSectionType:
      of NullSection: nil
      of NoBits: noBitsSize*: uint32
      of ProgBits: data*: seq[byte]
      of SymbolTable: symTable*: SymbolTableData
      of StringTable: strTable*: string
      of RelA: nil 
      of Rel: 
        rels*: seq[ElfRelocation]
        relSectionId*: uint32
  ElfSegment* = object
    flags*: ElfProgramFlags
    address*: uint32
    memSize*: uint32
    data*: seq[byte]
  ElfObjectFile* = seq[ElfSection]
  ElfProgramFile* = object
    segments*: seq[ElfSegment]
    entry*: uint32

proc readSymbolTable(elf: RawElfFile, offset: uint32, num: uint16, strTable: string): SymbolTableData =
  var off = offset
  template data32(s: uint32): untyped =
    uint32.fromBytesLE(elf.data[off + s..^1])
  template data16(s: uint32): untyped =
    uint16.fromBytesLE(elf.data[off + s..^1])
  template data8(s: uint32): untyped =
    elf.data[off + s]
  for i in 0'u16..<num:
    var symData: SymbolData
    symData.nameIndex = data32(0)
    symData.name = $strTable[symData.nameIndex..^1].cstring
    symData.value = data32(4)
    symData.size = data32(8)
    let info = data8(12)
    symData.kind = SymbolKind(info and 0xF'u8)
    let isGlobal = (info and 0x10) != 0
    symData.sectionId = data16(14)
    if isGlobal:
      result.global.add symData
    else:
      result.local.add symData
    off += 16

proc readRelocations(elf: RawElfFile, offset: uint32, num: uint16): seq[ElfRelocation] =
  var off = offset
  template data32(s: uint32): untyped =
    uint32.fromBytesLE(elf.data[off + s..^1])
  for i in 0'u16..<num:
    var r: ElfRelocation
    r.offset = data32(0)
    let info = data32(4)
    r.index = info shr 8
    r.relKind = uint8(info and 0xFF)
    result.add r
    off += 8

proc convertToObjFile(raw: RawElfFile): ElfObjectFile =
  if raw.kind != ObjectFile:
    raise newException(ElfError, "File is not object file!")
  let strTableHeader = raw.sections[raw.strTableIndex]
  let strTableSeq = raw.data[strTableHeader.offset..<
      strTableHeader.offset + strTableHeader.size]
  let strTable = cast[string](strTableSeq)
  for header in raw.sections:
    var section = ElfSection(kind: header.sectionType)
    section.name = $strTable[header.nameIndex..^1].cstring
    section.nameIndex = header.nameIndex
    section.flags = header.flags
    section.address = header.address
    case section.kind
      of ProgBits:
        section.data = raw.data[header.offset..<header.offset + header.size]
      of StringTable:
        section.strTable = strTable
      of SymbolTable:
        let num = header.size div 0x10
        section.symTable = raw.readSymbolTable(header.offset, num.uint16, strTable)
      of NoBits:
        section.noBitsSize = header.size
      of Rel:
        let num = header.size div 0x8
        section.rels = raw.readRelocations(header.offset, num.uint16)
        section.relSectionId = header.info
      else: discard
    result.add section

proc readObjFile*(data: seq[byte]): ElfObjectFile {.inline.} =
  data.readElf().convertToObjFile()

proc writeRelocation(result: var seq[byte], r: ElfRelocation) =
  result.add r.offset.toBytesLE()
  result.add toBytesLE(r.index shl 8 or r.relKind.uint32)

proc writeSymbol(result: var seq[byte], s: SymbolData, isGlobal: bool) =
  result.add s.nameIndex.toBytesLE()
  result.add s.value.toBytesLE()
  result.add s.size.toBytesLE()
  result.add isGlobal.byte shl 4 or s.kind.byte
  result.add 0
  result.add s.sectionId.toBytesLE()

proc writeObjFile*(elf: ElfObjectFile): seq[byte] =
  var headers = newSeq[ElfSectionHeader](elf.len)
  result = newSeq[byte](ElfHeaderSize)
  var strTableIndex = 0
  for i, s in elf:
    if i == 0:
      continue
    headers[i].sectionType = s.kind
    headers[i].offset = result.len.uint32
    headers[i].flags = s.flags
    headers[i].address = s.address
    headers[i].nameIndex = s.nameIndex
    headers[i].link = 0
    headers[i].info = 0
    headers[i].addrAlign = 4
    headers[i].entrySize = case s.kind:
      of SymbolTable: 0x10
      of Rel: 0x8
      of Rela: 0xC
      else: 0
    case s.kind:
      of ProgBits:
        result.add s.data
      of StringTable:
        result.add cast[seq[byte]](s.strTable)
        strTableIndex = i
      of SymbolTable:
        for sym in s.symTable.local:
          result.writeSymbol(sym, false)
        for sym in s.symTable.global:
          result.writeSymbol(sym, true)
        headers[i].link = 1
        headers[i].info = s.symTable.local.len.uint32
      of Rel:
        for r in s.rels:
          result.writeRelocation(r)
        headers[i].link = 2
        headers[i].info = s.relSectionId
      else: discard
    if s.kind == NoBits:
      headers[i].size = s.noBitsSize
    else:
      headers[i].size = result.len.uint32 - headers[i].offset
    while result.len mod 4 != 0:
      result.add 0
  result.writeObjElfHeader(result.len.uint32, elf.len.uint16, strTableIndex.uint16)
  result.add headers.writeSectionTableEntries()

proc writeProgFile*(elf: ElfProgramFile): seq[byte] =
  var headers = newSeq[ElfProgramHeader](elf.segments.len)
  result = newSeq[byte](ElfHeaderSize)
  var offset = elf.segments.len.uint32 * ElfProgramHeaderSize + ElfHeaderSize
  for i, s in elf.segments:
    headers[i].programType = Load
    headers[i].offset = offset
    headers[i].flags = s.flags
    headers[i].address = s.address
    headers[i].physicalAddress = 0
    headers[i].fileSize = s.data.len.uint32
    headers[i].memSize = s.memSize
    headers[i].align = 4
    offset += s.data.len.uint32
    if offset mod 4 != 0:
      offset += 4'u32 - offset mod 4
  result.writeProgElfHeader(elf.segments.len.uint16, elf.entry)
  result.add headers.writeProgramTableEntries()
  for s in elf.segments:
    result.add s.data
    while result.len mod 4 != 0:
      result.add 0