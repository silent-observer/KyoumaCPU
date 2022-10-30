# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.
import kelf

var builder = initElfObjBuilder()
const data = @[1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

builder.addTextSection(data, 0x00000001'u32)
builder.addSymbolToLast("test1", 3, 1, Object, false)
builder.addSymbolToLast("test2", 4, 1, Object, false)
builder.addSymbolToLast("Test3", 5, 4, Object, true)
builder.addSymbolToLast("test4", 9, 1, Object, false)
builder.addRelocation("test4", 10, 1'u8, Text)
let obj = builder.getObjFile()
let binary = obj.writeObjFile()
let f = open("../out.kobj", fmWrite)
discard f.writeBytes(binary, 0, binary.len)
f.close()