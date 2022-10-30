import strutils, strformat, bitops, terminal
import common

type
  Display* = ref object
    rows: array[4, string]
    data: uint8
    address: uint8
    cursorIncrement: int

proc newDisplay*(): Display =
  new(result)
  for r in result.rows.mitems:
    r = repeat(" ", 20)
  result.cursorIncrement = 1

proc readData*(d: Display): uint8 {.inline.} = d.data
proc writeData*(d: Display, v: uint8) {.inline.} = d.data = v

proc writeCtrl*(d: Display, v: uint8) =
  let
    rs = v.testBit(0)
    rw = v.testBit(1)
    e = v.testBit(2)
  if not e: return
  if rw:
    if rs:
      case d.address:
        of 0x00..0x13: d.data = d.rows[0][d.address].byte
        of 0x40..0x53: d.data = d.rows[1][d.address].byte
        of 0x14..0x27: d.data = d.rows[2][d.address].byte
        of 0x54..0x67: d.data = d.rows[3][d.address].byte
        else: d.data = 0
    else:
      d.data = d.address
  else:
    if rs:
      case d.address:
        of 0x00..0x13: d.rows[0][d.address] = d.data.char
        of 0x40..0x53: d.rows[1][d.address] = d.data.char
        of 0x14..0x27: d.rows[2][d.address] = d.data.char
        of 0x54..0x67: d.rows[3][d.address] = d.data.char
        else: discard
      if d.cursorIncrement == 1:
        d.address += 1
      else:
        d.address -= 1
      if d.address == 0x80:
        d.address = 0x00
      elif d.address == 0xFF:
        d.address = 0x7F
    else:
      if d.data.testBit(7): # Set DD RAM address
        d.address = d.data and 0x7F
      elif d.data.testBit(6): # Set CG RAM address
        discard
      elif d.data.testBit(5): # Function set
        discard
      elif d.data.testBit(4): # Cursor/display shift
        if d.data.testBit(3): # Shift display
          discard
        else: # Shift cursor
          if d.data.testBit(2): # Shift right
            d.address -= 1
          else:
            d.address += 1
          if d.address == 0x80:
            d.address = 0x00
          elif d.address == 0xFF:
            d.address = 0x7F
      elif d.data.testBit(3): # Display on/off
        discard
      elif d.data.testBit(2): # Entry mode
        d.cursorIncrement = if d.data.testBit(0): 1 else: -1
      elif d.data.testBit(1): # Return home
        d.address = 0
      elif d.data.testBit(1): # Clear
        d.address = 0
        for r in d.rows.mitems:
          r = repeat(" ", 20)

proc `$`*(d: Display): string =
  result = "+--------------------+\p"
  for i in 0..3:
    result &= "|" & d.rows[i] & "|\p"
  result &= "+--------------------+"

proc print*(d: Display) =
  when ColorsAvailable:
    stdout.styledWriteLine(bgGreen, fgBlack, "+--------------------+", resetStyle)
    for i in 0..3:
      stdout.styledWriteLine(bgGreen, fgBlack, "|", d.rows[i], "|", resetStyle)
    stdout.styledWriteLine(bgGreen, fgBlack, "+--------------------+", resetStyle)
  else:
    echo d