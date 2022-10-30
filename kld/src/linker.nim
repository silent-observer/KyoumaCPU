import kelf
import tables
import stew/endians2
import strformat

type
  Relocation = object
    name: string
    isGlobal: bool
    offset: uint32
    relKind: uint8
  SectionData = object
    data: seq[byte]
    offset: uint32
    kind: SpecialSection
    rels: seq[Relocation]
  ElfObjectFileImage = object
    sections: Table[uint32, SectionData]
  SymbolImageData = object
    name: string
    imageId, sectionId: uint32
    value: uint32
  LinkingError = object of Exception

const StartAddress = 0x00010000'u32

proc fillProgBits(imageId: int, f: ElfObjectFile, 
    images: var seq[ElfObjectFileImage], 
    offsets: var array[SpecialSection, uint32]) =
  for sIndex, s in f:
    if s.kind == ProgBits:
      let spec = 
        if s.flags == {Allocate, Executable}: Text
        elif s.flags == {Allocate, Writable}: Data
        elif s.flags == {Allocate}: Rodata
        else: raise newException(LinkingError, "Unknown ProgBits section!")
      let section = SectionData(
          data: s.data,
          kind: spec,
          offset: offsets[spec]
        )
      images[imageId].sections.add(sIndex.uint32, section)
      offsets[spec] += s.data.len.uint32
    elif s.kind == NoBits:
      let section = SectionData(
          data: @[],
          kind: Bss,
          offset: offsets[Bss]
        )
      images[imageId].sections.add(sIndex.uint32, section)
      offsets[Bss] += s.noBitsSize
proc fillRels(imageId: int, f: ElfObjectFile, 
    images: var seq[ElfObjectFileImage], symTab: SymbolTableData) =
  for sIndex, s in f:
    if s.kind == Rel:
      for r in s.rels:
        let rel = 
          if r.index >= symTab.local.len.uint32: Relocation(
            name: symTab.global[r.index - symTab.local.len.uint32].name,
            isGlobal: true,
            offset: r.offset,
            relKind: r.relKind
            )
          else: Relocation(
            name: symTab.local[r.index].name,
            isGlobal: false,
            offset: r.offset,
            relKind: r.relKind
            )
        images[imageId].sections[s.relSectionId].rels.add rel
proc fillSymtabs(imageId: int, f: ElfObjectFile, 
    localSymTab: var Table[(uint32, string), SymbolImageData],
    globalSymTab: var Table[string, SymbolImageData]): SymbolTableData =
  for sIndex, s in f:
    if s.kind == SymbolTable:
      for sym in s.symTable.local:
        let symImgData = SymbolImageData(
          name: sym.name,
          imageId: imageId.uint32,
          sectionId: sym.sectionId,
          value: sym.value,
          )
        let key = (imageId.uint32, sym.name)
        if key in localSymTab:
          raise newException(LinkingError, 
            "Multiple local symbols \"" & sym.name & "\" in the same file!")
        localSymTab.add((imageId.uint32, sym.name), symImgData)
      for sym in s.symTable.global:
        let symImgData = SymbolImageData(
          name: sym.name,
          imageId: imageId.uint32,
          sectionId: sym.sectionId,
          value: sym.value,
          )
        if sym.name in globalSymTab:
          if sym.sectionId == 0:
            discard
          elif globalSymTab[sym.name].sectionId == 0:
            globalSymTab[sym.name] = symImgData
          else:
            raise newException(LinkingError, 
              "Multiple global symbols \"" & sym.name & "\"!")
        else:
          globalSymTab.add(sym.name, symImgData)
      return s.symTable

proc relocateAll(imageId: int, images: var seq[ElfObjectFileImage], 
    localSymTab: Table[(uint32, string), SymbolImageData],
    globalSymTab: Table[string, SymbolImageData],
    offsets: array[SpecialSection, uint32]) =
  for sectionId, s in images[imageId].sections.mpairs:
    for r in s.rels:
      let sym = if r.isGlobal: globalSymTab[r.name]
        else: localSymTab[(imageId.uint32, r.name)]
      if sym.sectionId == 0:
        raise newException(LinkingError, 
          "Undefined symbol \"" & sym.name & "\"!")
      let symSection = images[sym.imageId].sections[sym.sectionId]
      let x = sym.value + symSection.offset + offsets[symSection.kind]
      case r.relKind:
        of 0: # NoRelocation
          discard
        of 1: # HiRelocation
          let v = x shr 18 and 0x3FFF'u32
          let d = uint32.fromBytesLE(s.data[r.offset..^1])
          let newD = d + (v shl 4)
          s.data[r.offset..r.offset+3] = newD.toBytesLE()
        of 2: # LoRelocation
          let v = x and 0xFFFFF'u32
          let d = uint32.fromBytesLE(s.data[r.offset..^1])
          let newD = d + (v shl 4)
          s.data[r.offset..r.offset+3] = newD.toBytesLE()
        of 3: # FullRelocation
          s.data[r.offset..r.offset+3] = x.toBytesLE()
        of 4: # LoRelocationImm
          let v = x and 0x3FFF'u32
          let d = uint32.fromBytesLE(s.data[r.offset..^1])
          let newD = d + (v shl 4)
          s.data[r.offset..r.offset+3] = newD.toBytesLE()
        else:
          raise newException(LinkingError, 
            "Unknown relocation type \"" & $r.relKind & "\"!")

proc findMain(images: seq[ElfObjectFileImage], 
  globalSymTab: Table[string, SymbolImageData],
  offsets: array[SpecialSection, uint32]): uint32 =
  if "main" notin globalSymTab:
    raise newException(LinkingError, "No main function!")
  let sym = globalSymTab["main"]
  let symSection = images[sym.imageId].sections[sym.sectionId]
  sym.value + symSection.offset + offsets[symSection.kind]

proc link*(inputs: seq[ElfObjectFile]): ElfProgramFile =
  var images = newSeq[ElfObjectFileImage](inputs.len)
  var offsets: array[SpecialSection, uint32]
  for img in images.mitems:
    img.sections = initTable[uint32, SectionData]()
  var localSymTab = initTable[(uint32, string), SymbolImageData]()
  var globalSymTab = initTable[string, SymbolImageData]()
  
  for imageId, f in inputs:
    #echo f
    fillProgBits(imageId, f, images, offsets)
    let symTab = fillSymtabs(imageId, f, localSymTab, globalSymTab)
    fillRels(imageId, f, images, symTab)
  var sections: array[SpecialSection, seq[byte]]
  for s in SpecialSection:
    sections[s] = newSeq[byte](offsets[s])

  let bssSize = offsets[Bss]
  offsets[Bss] = offsets[Rodata] + offsets[Text] + offsets[Data] + StartAddress
  offsets[Data] = offsets[Rodata] + offsets[Text] + StartAddress
  offsets[Rodata] = offsets[Text] + StartAddress
  offsets[Text] = StartAddress
  for imageId in 0..<images.len:
    relocateAll(imageId, images, localSymTab, globalSymTab, offsets)
  let entry = findMain(images, globalSymTab, offsets)
  for imageId, img in images:
    for sectionId, s in img.sections:
      sections[s.kind][s.offset..<s.offset + s.data.len.uint32] = s.data
  var reSegment = sections[Text] & sections[Rodata]
  var rwSegment = sections[Data]
  var b = initElfProgBuilder()
  b.addReadExecuteSegment(reSegment, StartAddress)
  b.setEntryPoint(entry)
  echo &"{entry:08X}"
  if rwSegment.len != 0 or bssSize != 0:
    b.addReadWriteSegment(rwSegment, bssSize, offsets[Data])
  b.getProgFile()