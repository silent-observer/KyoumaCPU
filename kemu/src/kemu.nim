# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.
import kcpu, memory, display, common
import strutils, os, strformat, terminal, parseopt

const
  AvailableCommands = ["help", "load", "r", "read", "run", 
    "st", "stack", "state", "s", "step", "quit", "log", "lei", "bp", "lcd"]
  HelpMessage = 
    """Available commands:
       - help: prints this message
       - bp [add|remove|view] <address>: manage breakpoints
       - lcd: view LCD display
       - load <input.mem>: loads memory from .mem file
       - log [enable|disable] <something>: enables/disables printing some logs. To see details run "log enable help"
       - lei: shortcut for log enable instruction
       - read <address> [<address>]: read memory contents
       - run <x>, r <x>: runs KCPU for <x> cycles
       - stack: prints stack contents
       - state, st: prints KCPU state
       - step, s: runs KCPU for 1 cycle
       - quit: quit the emulator
       """.unindent()

when isMainModule:
  var cpu = newKCpu()
  var lcd = newDisplay()
  var isMemInitialized = false
  var logState = false
  var mem: Memory
  var breakpoints: seq[uint32]

  var p = initOptParser()
  var fileToLoad = ""
  var testCycles = 0
  for kind, key, val in p.getopt():
    case kind:
      of cmdArgument: fileToLoad = key
      of cmdShortOption:
        if key == "t": testCycles = val.parseInt
        else: 
          echo "Unknown option -", key, "!"
          quit(1)
      of cmdLongOption:
        echo "Unknown option --", key, "!"
        quit(1)
      of cmdEnd: discard
  
  if testCycles != 0 and fileToLoad != "":
    try:
      mem = newMem(fileToLoad)
      cpu.setMem(mem)
      mem.setLcd(lcd)
      isMemInitialized = true
      for i in 0..<testCycles:
        if cpu.step(breakpoints):
          echo cpu.r1.int64.toHex(8)
          quit(0)
      echo "Error: Endless loop!"
    except:
      echo "Couldn't load file " & fileToLoad & "!"
    quit(0)

  echo "The almighty KyoumaCPU Emulator was successfully booted!"
  if fileToLoad != "":
    try:
      mem = newMem(fileToLoad)
      cpu.setMem(mem)
      mem.setLcd(lcd)
      isMemInitialized = true
      echo "Successfully loaded memory image!"
    except:
      echo "Couldn't load file " & paramStr(1) & "!"
  
  while true:
    when ColorsAvailable:
      stdout.styledWrite(fgGreen, "> ", resetStyle)
    else:
      stdout.write("> ")
    stdout.flushFile()
    let command = stdin.readLine().split()
    if command[0] notin AvailableCommands:
      echo "Unknown command! Run \"help\" to print all available commands"
    else:
      if not isMemInitialized:
        case command[0]:
          of "help": echo HelpMessage
          of "load":
            if command.len < 2:
              when ColorsAvailable:
                stdout.styledWriteLine(fgRed, "Syntax: ", resetStyle, "load <input.mem>")
              else:
                echo "Syntax: load <input.mem>"
            else:
              try:
                mem = newMem(command[1])
                cpu.setMem(mem)
                mem.setLcd(lcd)
                isMemInitialized = true
                echo "Successfully loaded memory image!"
              except:
                when ColorsAvailable:
                  stdout.styledWriteLine("Couldn't load file ", fgRed, command[1], resetStyle, "!")
                else:
                  echo "Couldn't load file " & command[1] & "!"
          of "quit": quit()
          else: 
            echo "Cannot execute this command without loading memory first!"
            when ColorsAvailable:
              stdout.styledWriteLine("Please run command ", fgRed, "load <input.mem>", 
                resetStyle, " to load memory!")
            else:
              echo "Please run command \"load <input.mem>\" to load memory!"
      else:
        case command[0]:
          of "help": echo HelpMessage
          of "bp": 
            if command.len == 2 and command[1] == "view":
              for i, a in breakpoints:
                echo &"{i}: {a:08X}"
            elif command.len == 3 and command[1] == "add":
              try:
                let a = fromHex[uint32](command[2])
                if a in breakpoints:
                  echo "Already added!"
                else:
                  breakpoints.add a
              except ValueError:
                echo "Invalid address argument!"
            elif command.len == 3 and command[1] == "remove":
              try:
                let a = fromHex[uint32](command[2])
                if a notin breakpoints:
                  echo "Not in breakpoints!"
                else:
                  breakpoints.delete breakpoints.find(a)
              except ValueError:
                echo "Invalid address argument!"
          of "lcd":
            lcd.print()
          of "load":
            if command.len < 2:
              when ColorsAvailable:
                stdout.styledWriteLine(fgRed, "Syntax: ", resetStyle, "load <input.mem>")
              else:
                echo "Syntax: load <input.mem>"
            else:
              try:
                mem = newMem(command[1])
                cpu.setMem(mem)
                mem.setLcd(lcd)
                echo "Successfully loaded memory image!"
              except:
                when ColorsAvailable:
                  stdout.styledWriteLine("Couldn't load file ", fgRed, command[1], resetStyle, "!")
                else:
                  echo "Couldn't load file " & command[1] & "!"
          of "log":
            if command.len != 3 or (command[1] != "enable" and command[1] != "disable"):
              when ColorsAvailable:
                stdout.styledWriteLine(fgRed, "Syntax: ", resetStyle, "log (enable|disable) <something>")
              else:
                echo "Syntax: log (enable|disable) <something>"
            else:
              if command[2] == "write":
                logWrites = command[1] == "enable"
              elif command[2] == "state":
                logState = command[1] == "enable"
              elif command[2] == "instruction":
                logInstruction = command[1] == "enable"
              else:
                echo """Available things to log:
                        - write: memory writes
                        - state: command "state" output after every step
                        - instruction: details about instruction executed""".unindent()
          of "lei": logInstruction = true
          of "read":
            if command.len < 2:
              when ColorsAvailable:
                stdout.styledWriteLine(fgRed, "Syntax: ", resetStyle, "read <address> [<address>]")
              else:
                echo "Syntax: read <address> [<address>]"
            else:
              let a = fromHex[uint32](command[1])
              if command.len == 3:
                let b = fromHex[uint32](command[2])
                if (a and 0xFFFFFFFC'u32) <= (b and 0xFFFFFFFC'u32):
                  var counter = 0
                  for i in countup(a and 0xFFFFFFFC'u32, b and 0xFFFFFFFC'u32, 4):
                    when ColorsAvailable:
                      stdout.styledWriteLine(fgBlue, &"{i:08X}: ", resetStyle, &"{mem[i]:08X}")
                    else:
                      echo &"{i:08X}: {mem[i]:08X}"
                    counter += 1
                    if counter > 100:
                      echo "..."
                      break
              else:
                when ColorsAvailable:
                  stdout.styledWriteLine(fgBlue, &"{a:08X}: ", resetStyle, &"{mem[a]:08X}")
                else:
                  echo &"{a:08X}: {mem[a]:08X}"
          of "run", "r":
            if command.len < 2:
              when ColorsAvailable:
                stdout.styledWriteLine(fgRed, "Syntax: ", resetStyle, "run <x>")
              else:
                echo "Syntax: run <x>"
            else:
              try:
                let count = command[1].parseInt()
                for i in 0..<count:
                  if cpu.step(breakpoints):
                    if cpu.isBusyHalted:
                      echo "Busy halt!"
                    else:
                      echo "Breakpoint!"
                    if logState: echo $cpu
                    break
                  if logState: echo $cpu
              except ValueError:
                when ColorsAvailable:
                  stdout.styledWriteLine(fgRed, "Syntax: ", resetStyle, "run <x> (x is a number)")
                else:
                  echo "Syntax: run <x> (x is a number)"
          of "stack":
            for i in countup(max(cpu.sp and 0xFFFFFFFC'u32, 0xDFFFFF00'u32), 0xDFFFFFFC'u32, 4):
              let spStr = 
                if i == cpu.sp: " sp ->"
                elif i.int64 - cpu.sp.int64 <= 20: &"+{i - cpu.sp:2} ->"
                else: "      "
              let fpStr = 
                if i == cpu.fp: "<- fp"
                elif abs(i.int64 - cpu.fp.int64) <= 20: &"<- fp{i.int64 - cpu.fp.int64:+} "
                else: ""
              when ColorsAvailable:
                stdout.styledWriteLine(fgYellow, spStr, 
                  fgBlue, &" {i:08X}: ", resetStyle, &"{mem[i]:08X} ", fgYellow, fpStr, resetStyle)
              else:
                echo &"{spStr} {i:08X}: {mem[i]:08X} {fpStr}"
          of "state", "st": echo $cpu
          of "step", "s": 
            discard cpu.step(breakpoints)
            if cpu.isBusyHalted:
              echo "Busy halt!"
            if logState: echo $cpu
          of "quit": quit()
          else: 
            echo "Unknown command! Run \"help\" to print all available commands"