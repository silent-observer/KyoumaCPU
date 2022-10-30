import elf
import tables

type 
  SpecialSection* {.pure.} = enum
    Text
    Rodata
    Data
    Bss
  ElfObjBuilder* = object
    obj: ElfObjectFile
    specStrIndex: array[SpecialSection, uint32]
    specId: array[SpecialSection, uint32]
    symbolTable: Table[string, (int, bool)]

proc initElfObjBuilder*(): ElfObjBuilder =
  result.obj = @[
    ElfSection(kind: NullSection),
    ElfSection(
      name: ".strtab",
      nameIndex: 1,
      kind: StringTable,
      strTable: "\0.strtab\0.symtab\0"
    ),
    ElfSection(
      name: ".symtab",
      nameIndex: 9,
      kind: SymbolTable,
      symTable: SymbolTableData()
    ),
  ]
  result.symbolTable = initTable[string, (int, bool)]()

proc addRelocationSection(builder: var ElfObjBuilder, nameStr: string, sect: SpecialSection) =
  let index = builder.specStrIndex[sect] - 4
  builder.obj.add ElfSection(
    kind: Rel,
    name: ".rel" & nameStr,
    nameIndex: index,
    address: 0,
    flags: {},
    rels: @[],
    relSectionId: builder.obj.len.uint32 - 1
  )

template strTableSection(x: untyped): untyped = x.obj[1]

template addProgBitsSection(flagsVal: ElfSectionFlags, nameStr: string, sect: SpecialSection): untyped =
  let index = if builder.specStrIndex[sect] == 0:
      strTableSection(builder).strTable.len.uint32 + 4
    else: builder.specStrIndex[sect]
  builder.specId[sect] = builder.obj.len.uint32
  builder.obj.add ElfSection(
    kind: ProgBits,
    name: nameStr,
    nameIndex: index,
    address: address,
    flags: flagsVal,
    data: data
  )
  if builder.specStrIndex[sect] == 0:
    builder.specStrIndex[sect] = index
    strTableSection(builder).strTable &= ".rel" & nameStr & "\0"
  addRelocationSection(builder, nameStr, sect)

proc addTextSection*(builder: var ElfObjBuilder, data: seq[byte], address: uint32) =
  addProgBitsSection({Allocate, Executable}, ".text", Text)
proc addDataSection*(builder: var ElfObjBuilder, data: seq[byte], address: uint32) =
  addProgBitsSection({Allocate, Writable}, ".data", Data)
proc addRodataSection*(builder: var ElfObjBuilder, data: seq[byte], address: uint32) =
  addProgBitsSection({Allocate}, ".rodata", Rodata)

proc addBssSection*(builder: var ElfObjBuilder, size: uint32, address: uint32) =
  let index = if builder.specStrIndex[Bss] == 0:
      builder.strTableSection.strTable.len.uint32
    else: builder.specStrIndex[Bss]
  builder.specId[Bss] = builder.obj.len.uint32
  builder.obj.add ElfSection(
    kind: NoBits,
    name: ".bss",
    nameIndex: index,
    address: address,
    flags: {Allocate, Writable},
    noBitsSize: size
  )
  if builder.specStrIndex[Bss] == 0:
    builder.specStrIndex[Bss] = index
    builder.strTableSection.strTable &= ".bss\0"

proc addSymbol(builder: var ElfObjBuilder, name: string, 
    value: uint32, size: uint32, kind: SymbolKind, isGlobal: bool, sectionId: uint16) =
  let symbol = SymbolData(
    name: name,
    nameIndex: builder.strTableSection.strTable.len.uint32,
    value: value,
    size: size,
    kind: kind,
    sectionId: sectionId
    )
  builder.strTableSection.strTable &= name & "\0"
  if isGlobal:
    builder.symbolTable.add(name, (builder.obj[2].symTable.global.len, true))
    builder.obj[2].symTable.global.add symbol
  else:
    builder.symbolTable.add(name, (builder.obj[2].symTable.local.len, false))
    builder.obj[2].symTable.local.add symbol

proc addSymbolToSpec*(builder: var ElfObjBuilder, name: string, 
    value: uint32, size: uint32, kind: SymbolKind, 
    isGlobal: bool, spec: SpecialSection) {.inline.} =
  builder.addSymbol(name, value, size, kind, isGlobal, builder.specId[spec].uint16)

proc addSymbolToLast*(builder: var ElfObjBuilder, name: string, 
    value: uint32, size: uint32, kind: SymbolKind, isGlobal: bool) {.inline.} =
  builder.addSymbol(name, value, size, kind, isGlobal, builder.obj.len.uint16 - 2)

proc addUndefinedSymbol*(builder: var ElfObjBuilder, name: string, 
    value: uint32, size: uint32, kind: SymbolKind, isGlobal: bool) {.inline.} =
  builder.addSymbol(name, value, size, kind, isGlobal, 0)

proc addRelocation*(builder: var ElfObjBuilder, name: string, 
    address: uint32, relKind: uint8, section: SpecialSection) =
  let (index, isGlobal) = builder.symbolTable[name]
  let symbolIndex = 
    if isGlobal: builder.obj[2].symTable.local.len + index
    else: index
  let rel = ElfRelocation(
    index: symbolIndex.uint32,
    offset: address,
    relKind: relKind
    )
  builder.obj[builder.specId[section] + 1].rels.add rel

proc getObjFile*(builder: var ElfObjBuilder): ElfObjectFile {.inline.} =
  builder.obj