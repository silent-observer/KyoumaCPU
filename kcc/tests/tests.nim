import unittest, os, osproc, strutils
import ../src/kcc

suite "Just compile":
  template compileFile(name: string) =
    if not compile("tests" / "c" / "compile" / name & ".c", 
            "tests" / "kasm" / "compile" / name & ".kasm", false):
      fail()
  test "funcTest":
    compileFile("funcTest")
  test "stringTest":
    compileFile("stringTest")

suite "Standard library tests":
  template compileLinkAndRun(name: string, requiredLibs: openArray[string], cycles: int, expected: string) =
    var libNames: seq[string]
    let opt = {poStdErrToStdOut, poUsePath}
    for lib in requiredLibs:
      let cName = "tests" / "c" / "std" / lib & ".c"
      let kasmName = "tests" / "kasm" / "std" / lib & ".kasm"
      let objName = "tests" / "obj" / "std" / lib & ".obj"
      discard execProcess("rm", args = [kasmName, objName], options = opt)
      if not compile(cName, kasmName, false):
        fail()
      discard execProcess("kasm", args = [kasmName], options = opt)
      discard execProcess("mv", args = [kasmName.changeFileExt(".obj"), objName], options = opt)
      libNames.add objName

    let cName = "tests" / "c" / "stdtest" / name & ".c"
    let kasmName = "tests" / "kasm" / "stdtest" / name & ".kasm"
    let objName = "tests" / "obj" / "stdtest" / name & ".obj"
    let elfName = "tests" / "elf" / "stdtest" / name & ".elf"
    let memName = "tests" / "mem" / "stdtest" / name & ".mem"
    discard execProcess("rm", args = [kasmName, objName, elfName, memName], options = opt)

    if not compile(cName, kasmName, false):
      fail()
    discard execProcess("kasm", args = [kasmName], options = opt)
    discard execProcess("mv", args = [kasmName.changeFileExt(".obj"), objName], options = opt)
    discard execProcess("kld", args = @[objName] & libNames, options = opt)
    discard execProcess("mv", args = ["out.elf", elfName], options = opt)
    discard execProcess("elf2mem", args = [elfName], options = opt)
    discard execProcess("mv", args = [elfName.changeFileExt(".mem"), memName], options = opt)
    let result = execProcess("kemu", args = ["-t:" & $cycles, memName], options = opt)
    if (result != expected & "\n"):
      echo result
    check result == expected & "\n"
  
  test "mallocTest":
    compileLinkAndRun("mallocTest", ["malloc"], 10000, "00000000")

suite "Compile, link and run":
  template compileLinkAndRun(name: string, cycles: int, expected: string) =
    let cName = "tests" / "c" / "execute" / name & ".c"
    let kasmName = "tests" / "kasm" / "execute" / name & ".kasm"
    let objName = "tests" / "obj" / "execute" / name & ".obj"
    let elfName = "tests" / "elf" / "execute" / name & ".elf"
    let memName = "tests" / "mem" / "execute" / name & ".mem"
    let opt = {poStdErrToStdOut, poUsePath}
    discard execProcess("rm", args = [kasmName, objName, elfName, memName], options = opt)

    if not compile(cName, kasmName, false):
      fail()
    discard execProcess("kasm", args = [kasmName], options = opt)
    discard execProcess("mv", args = [kasmName.changeFileExt(".obj"), objName], options = opt)
    discard execProcess("kld", args = [objName], options = opt)
    discard execProcess("mv", args = ["out.elf", elfName], options = opt)
    discard execProcess("elf2mem", args = [elfName], options = opt)
    discard execProcess("mv", args = [elfName.changeFileExt(".mem"), memName], options = opt)
    let result = execProcess("kemu", args = ["-t:" & $cycles, memName], options = opt)
    if (result != expected & "\n"):
      echo result
    check result == expected & "\n"
  
  test "arrayTest":
    compileLinkAndRun("arrayTest", 10000, "00000000")
  test "binaryTest":
    compileLinkAndRun("binaryTest", 1000, "FFFFFFFE")
  test "funcTest":
    compileLinkAndRun("funcTest", 1000, "00000006")
  test "loopsTest":
    compileLinkAndRun("loopsTest", 10000, "000000FA")
  test "ptrTest":
    compileLinkAndRun("ptrTest", 1000, "00000096")
  test "typesTest":
    compileLinkAndRun("typesTest", 1000, "0000003C")
  test "structTest":
    compileLinkAndRun("structTest", 1000, "0000000E")
  test "linkedListTest":
    compileLinkAndRun("linkedListTest", 10000, "00000004")