import strutils, os

const WordCount = 1024
type MemoryImage = array[WordCount, uint32]

proc readMem(filename: string): MemoryImage =
  var address = 0
  for line in filename.lines:
    if line.startsWith('@'):
      address = parseHexInt(line[1..^1])
    else:
      result[address] = fromHex[uint32](line)
      address += 1

proc writeMif(filename: string, img: MemoryImage) =
  var s = 
    """-- begin_signature
    -- ROM
    -- end_signature
    WIDTH=32;
    DEPTH=1024;
    
    ADDRESS_RADIX=UNS;
    DATA_RADIX=HEX;
    
    CONTENT BEGIN
    """.unindent
  for i, x in img:
    s &= $i & ": " & x.int64.toHex(8) & ";\p"
  s &= "END;"
  filename.writeFile(s)

when isMainModule:
  if paramCount() != 1:
    echo "Syntax: mem2mif <input.mem>"
    quit(1)
  let inFile = paramStr(1)
  "ROMContents.mem".writeFile(inFile.readFile())
  let img = inFile.readMem()
  "simulation/modelsim/kcpu.ram0_rom_16bd8.hdl.mif".writeMif(img)
  "db/KCPU.ram0_ROM_16bd8.hdl.mif".writeMif(img)