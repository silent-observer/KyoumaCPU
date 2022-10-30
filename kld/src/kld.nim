import linker, os, kelf

when isMainModule:
  if paramCount() == 0:
    echo "Syntax: kld <input.kobj>*"
    quit(1)
  var objFiles: seq[ElfObjectFile]
  for i in 1..paramCount():
    let f = paramStr(i).open()
    defer: f.close()
    var buffer = newSeq[byte](f.getFileSize())
    discard f.readBytes(buffer, 0, buffer.len)
    objFiles.add buffer.readObjFile()
  let progFile = objFiles.link()
  #echo progFile.segments.len
  let bytes = progFile.writeProgFile()
  block:
    let f = "out.elf".open(fmWrite)
    defer: f.close()
    discard f.writeBytes(bytes, 0, bytes.len)

