import strutils, strformat
import display

var logWrites* = false
var cpuSpeed* = 0'u8

const 
  Depth = 512
  BytePorts = [0xFFFFFFFF'u32, 0xFFFFFFFE'u32, 0xFFFFFFFD'u32]
type
  Memory* = ref object
    stack, heap, code, rom: array[Depth, uint32]
    lcd: Display

proc readBytePort(m: Memory, address: uint32): uint8 =
  case address:
    of 0xFFFFFFFE'u32: m.lcd.readData()
    of 0xFFFFFFFD'u32: cpuSpeed
    else: 0'u8

proc writeBytePort(m: Memory, address: uint32, val: uint8) =
  case address:
    of 0xFFFFFFFF'u32: m.lcd.writeCtrl(val)
    of 0xFFFFFFFE'u32: m.lcd.writeData(val)
    else: discard

proc `[]`*(m: Memory, address: uint32): uint32 =
  let realAddress = (address and 0x7FF) shr 2
  if address < 0x00000800'u32:
    return m.rom[realAddress]
  elif address >= 0x00010000'u32 and address < 0x00010800'u32:
    return m.code[realAddress]
  elif address >= 0x10000000'u32 and address < 0x10000800'u32:
    return m.heap[realAddress]
  elif address >= 0xDFFFF800'u32 and address <= 0xDFFFFFFF'u32:
    return m.stack[realAddress]
  else:
    return 0

proc write*(m: Memory, address: uint32, val: uint32, mask: uint32) =
  let realAddress = (address and 0x7FF) shr 2
  if address < 0x00000800'u32:
    discard
  elif address >= 0x00010000'u32 and address < 0x00010800'u32:
    m.code[realAddress] = (m.code[realAddress] and not mask) or (val and mask)
  elif address >= 0x10000000'u32 and address < 0x10000800'u32:
    m.heap[realAddress] = (m.heap[realAddress] and not mask) or (val and mask)
  elif address >= 0xDFFFF800'u32 and address <= 0xDFFFFFFF'u32:
    m.stack[realAddress] = (m.stack[realAddress] and not mask) or (val and mask)

proc writeByte*(m: Memory, address: uint32, val: uint8) {.inline.} =
  if logWrites:
    echo &"[{address:08X}] <- {val:02X}"
  if address in BytePorts:
    m.writeBytePort(address, val)
    return
  let mask = case (address and 0x3'u32):
    of 0'u32: 0x000000FF'u32
    of 1'u32: 0x0000FF00'u32
    of 2'u32: 0x00FF0000'u32
    of 3'u32: 0xFF000000'u32
    else: 0
  let valToWrite = case (address and 0x3'u32):
    of 0'u32: val.uint32
    of 1'u32: val.uint32 shl 8
    of 2'u32: val.uint32 shl 16
    of 3'u32: val.uint32 shl 24
    else: 0
  m.write(address, valToWrite, mask)
proc writeHalfWord*(m: Memory, address: uint32, val: uint16) {.inline.} =
  if logWrites:
    echo &"[{address:08X}] <- {val:04X}"
  let mask = case (address and 0x3'u32):
    of 0'u32, 1'u32: 0x0000FFFF'u32
    of 2'u32, 3'u32: 0xFFFF0000'u32
    else: 0
  let valToWrite = case (address and 0x3'u32):
    of 0'u32, 1'u32: val.uint32
    of 2'u32, 3'u32: val.uint32 shl 16
    else: 0
  m.write(address, valToWrite, mask)
proc writeWord*(m: var Memory, address: uint32, val: uint32) {.inline.} =
  if logWrites:
    echo &"[{address:08X}] <- {val:08X}"
  m.write(address, val, 0xFFFFFFFF'u32)

proc readByte*(m: Memory, address: uint32): uint8 {.inline.} =
  if address in BytePorts:
    return m.readBytePort(address)
  let val = m[address]
  let valShifted = case (address and 0x3'u32):
    of 0'u32: val
    of 1'u32: val shr 8
    of 2'u32: val shr 16
    of 3'u32: val shr 24
    else: 0
  uint8(valShifted and 0xFF'u32)
proc readHalfWord*(m: Memory, address: uint32): uint16 {.inline.} =
  let val = m[address]
  let valShifted = case (address and 0x3'u32):
    of 0'u32, 1'u32: val
    of 2'u32, 3'u32: val shr 16
    else: 0
  uint16(valShifted and 0xFFFF'u32)

proc newMem*(memFile: string): Memory =
  new(result)
  var address = 0
  for line in memFile.lines:
    if line.startsWith('@'):
      address = parseHexInt(line[1..^1])
    else:
      result.rom[address] = fromHex[uint32](line)
      address += 1

proc setLcd*(m: Memory, lcd: Display) {.inline.} =
  m.lcd = lcd