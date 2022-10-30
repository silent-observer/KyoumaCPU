import strutils, os

proc toByteSeqComp(s: string): seq[byte] {.compileTime.} =
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = c.byte
proc toByteSeq(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  copyMem(addr result[0], unsafeAddr s[0], s.len)

const 
  LoaderStr = staticRead("romloader.bin")
  LoaderData = LoaderStr.toByteSeqComp()

when isMainModule:
  if paramCount() != 1:
    echo "Syntax: elf2mem <input.elf>"
    quit(1)
  let data = paramStr(1).readFile().toByteSeq()
  let totalData = LoaderData & data
  var i = 0
  var s = ""
  while i < totalData.len:
    let v = totalData[i].uint32 or
      totalData[i+1].uint32 shl 8 or
      totalData[i+2].uint32 shl 16 or
      totalData[i+3].uint32 shl 24
    s.add v.int32.toHex(8) & "\p"
    i += 4
  paramStr(1).changeFileExt(".mem").writeFile(s)