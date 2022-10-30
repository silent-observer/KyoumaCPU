# Kyouma CPU Specification

Kyouma CPU is a simple 32-bit processor made just for fun (and maybe some learning). 
Here you can find a full specification for its architecture.

## General info

First of all, it's mostly **32-bit**. This means that all the registers are 32-bit, all operations are 32-bit and most of the opcodes are 32-bit.
Still, there are short 16-bit opcodes, but they can come only in pairs (so if they don't, NOP should be inserted).

Second, it is **little-endian** (because that's conventional, I guess?)

Third, it uses **predication**. I found it in [zipcpu](https://github.com/ZipCPU/zipcpu) and then in ARM, and it seems to be a very good idea for fully accessible uniform register sets. So every instruction can be executed conditionally. In 16-bit opcodes there are no space for condition specifier, so I desided to use ARM's technique and add an instruction (`CND`) to specify condition codes for 3 successive instructions.


## Register set
Because I really liked [zipcpu](https://github.com/ZipCPU/zipcpu)'s concept about two modes of operation, I'm going to implement it here as well.

So, KCPU has two modes, user (for user code) and supervisor (for kernel-level code). Each mode has it's own set of registers and can freely switch between them. 
It is similar to the context switch in normal CPUs, but because we are changing a single flag inside the CPU, it can be much faster.
Also KCPU in supervisor mode can access user registers (for implementing system calls) while KCPU in user mode can access only its own registers.

There are 16 registers (only 15 of which can store data) in each set and access to all of them is possible (because FREEDOM!)
They are:
+ `R0` - always reads 0, writes are ignored
+ `R1`-`R10` - general purpose
+ `R11` or `SR` - status register
+ `R12` or `LR` - link register (stores return address of the last subroutine call)
+ `R13` or `FP` - frame pointer
+ `R14` or `SP` - stack pointer
+ `R15` or `PC` - program counter
They can be referred to with their respective numbers from 0 to 15. 

There are also `HI` and `LO` registers for multiplication and division results. They are shared between both modes.
`HI` and `LO` registers can only be read with special instructions.

## Flags

- **Bit 0** - Zero flag. Set if last operation resulted in 0
- **Bit 1** - Carry flag
- **Bit 2** - Negative flag. Set if last operation resulted in negative number
- **Bit 3** - Overflow flag
- **Bit 4** - Mode flag. `0` if supervisor mode, `1` if user mode
- **Bit 4** - Zero division error flag
- **Bit 5** - Illegal opcode flag
- **Bit 6** - Wait for interrupt flag
- **Bit 7** - Step flag
- **Bit 8** - Hardware interrupt flag. Set if interrupt was hardware and not software.
- **Bit 9** - NULL reference flag

- **Bits 10-31** - Unused, always `0`

## Conditions

Each condition specifier is 4 bits long. 

- Bit 3 is a _freeze bit_. If it's set, then CPU will freeze flag register, so instruction result won't change it.
  In assembly it is set like this: `ADD* R1, R2, R3`
- Bits 0-2 is _condition_ itself. It may be as follows:
  | Condition | Assembly symbol | Meaning
  |-----------|-----------------|---------
  | `000`     | -               | No condition. Instruction is always executed
  | `001`     | `?V`            | Execute if overflow flag is set
  | `010`     | `?Z` or `?EQ`   | Execute if zero flag is set
  | `011`     | `?NZ` or `?NE`  | Execute if zero flag is not set
  | `100`     | `?LT`           | Execute if negative flag is set
  | `101`     | `?GE`           | Execute if negative flag is not set
  | `110`     | `?C`            | Execute if carry flag is set
  | `111`     | `?NC`           | Execute if carry flag is not set
  In assembly it combines with freeze bit like this: `ADD?NC* R1, R2, R3`

## Instruction set

There are multiple types of instructions:

- Short (16-bit). It can use only values in registers
  |`15`|`14..12`|  `11..8`  | `7..4` | `3..0` |
  |----|--------|-----------|--------|--------|
  |`0` | Opcode |Destination|Source 1|Source 2|

  |Opcode|Instruction mnemonic| Description                                            | Action
  |------|--------------------|--------------------------------------------------------|--------
  |`000` | `ADD`              | Add two integers                                       | `{D} <- {S1} + {S2}`
  |`001` | `SUB`              | Subtract two integers                                  | `{D} <- {S1} - {S2}`
  |`010` | `LSH`              | Logical shift (left if positive, right if negative)    | `{D} <- {S1} <</>> {S2}`
  |`011` | `ASH`              | Arithmetic shift (left if positive, right if negative) | `{D} <- {S1} <</>> {S2} (signed)`
  |`100` | `AND`              | Logical AND                                            | `{D} <- {S1} & {S2}`
  |`101` | `OR`               | Logical OR                                             | `{D} <- {S1} | {S2}`
  |`110` | `XOR`              | Logical XOR                                            | `{D} <- {S1} ^ {S2}`
  |`111` | `CND`              | Conditions (see below)                                 | -

  The `CND` instruction has the following format:
  |`15..12`|    `11..8`    |    `7..4`     |    `3..0`     |
  |--------|---------------|---------------|---------------|
  | `0111` | 1st condition | 2nd condition | 3rd condition |
  It sets conditions for the following 3 instructions

  Also, there is `NOP` instruction. It's code is `0x0000`, so it is `ADD R0, R0, R0`. 
  Usually it would change flags but it is an exception so it doesn't.

  There is one more thing: if second instruction in the pair (short instructions come in pairs, right?)
  is a `NOP` instruction, then it's skipped altogether. 
  
  As such, beware that if you do something like
  ```
  ADD R1, PC, R0
  NOP
  ```

  then value in `R1` register would be the address of instruction **after** `NOP`, not `NOP` itself

- Immediate (32-bit)
  |`31..29`|`28..26`|   `25..22`    |`21..18`|     `17..4`     |  `3..0`   |
  |--------|--------|---------------|--------|-----------------|-----------|
  | `100`  | Opcode |  Destination  | Source | Immediate value | Condition |

  |Opcode|Instruction mnemonic| Description                                            | Action
  |------|--------------------|--------------------------------------------------------|--------
  |`000` | `ADDI`             | Add two integers                                       | `{D} <- {S} + I`
  |`001` | `SUBI`             | Subtract two integers                                  | `{D} <- {S} - I`
  |`010` | `LSHI`             | Logical shift (left if positive, right if negative)    | `{D} <- {S} <</>> I`
  |`011` | `ASHI`             | Arithmetic shift (left if positive, right if negative) | `{D} <- {S} <</>> I (signed)`
  |`100` | `ANDI`             | Logical AND                                            | `{D} <- {S} & I`
  |`101` | `ORI`              | Logical OR                                             | `{D} <- {S} | I`
  |`110` | `XORI`             | Logical XOR                                            | `{D} <- {S} ^ I`
  |`111` | `LDH`              | Move immediate to high 14 bits and source to the rest  | `{D} <- {I, {S}[17..0]}`
  _Immediate value is sign extended to 32 bits._
  _If `LDH` is passed label as an argument, immediate value is high 13 bits of address_

- Load/store (32-bit)
  |`31..30`|`29..27`|       `26..23`       | `22..19` |     `18..4`     |  `3..0`   |
  |--------|--------|----------------------|----------|-----------------|-----------|
  |  `11`  | Opcode |  Source/Destination  | Address  | Immediate value | Condition |

  |Opcode|Instruction mnemonic| Description            | Action
  |------|--------------------|------------------------|--------
  |`000` | `LW`               | Load 32 bits           | `{S/D} <- ({A} + I)` (32-bits)
  |`001` | `SW`               | Store 32 bits          | `({A} + I) <- {S/D}` (32-bits)
  |`010` | `SH`               | Store 16 bits          | `({A} + I) <- {S/D}` (16-bits)
  |`011` | `SB`               | Store 8 bits           | `({A} + I) <- {S/D}` (8-bits)
  |`100` | `LHU`              | Load 16 bits unsigned  | `{S/D} <- ({A} + I)` (16-bits unsigned)
  |`101` | `LHS`              | Load 16 bits signed    | `{S/D} <- ({A} + I)` (16-bits signed)
  |`110` | `LBU`              | Load 8 bits unsigned   | `{S/D} <- ({A} + I)` (8-bits unsigned)
  |`111` | `LBS`              | Load 8 bits signed     | `{S/D} <- ({A} + I)` (8-bits signed)

- Misc (32-bit)
  + `LDI` - loads 20-bit signed immedate value in register
    |`31..28`|  `27..24`   |     `23..4`     |  `3..0`   |
    |--------|-------------|-----------------|-----------|
    | `1010` | Destination | Immediate value | Condition |
    _If passed label as an argument, immediate value is low 19 bits of address_
  + `MLTU` - multiplies two unsigned 32-bit integers. Result is in `HI..LO` pair
    | `31..25`  | `24..21` | `20..17` | `16..4`   |  `3..0`   |
    |-----------|----------|----------|-----------|-----------|
    | `1011000` | Source 1 | Source 2 | Unused?.. | Condition |
  + `MLTS` - multiplies two signed 32-bit integers. Result is in `HI..LO` pair
    | `31..25`  | `24..21` | `20..17` | `16..4`   |  `3..0`   |
    |-----------|----------|----------|-----------|-----------|
    | `1011001` | Source 1 | Source 2 | Unused?.. | Condition |
  + `DIVU` - divides two unsigned 32-bit integers. Quotient is in `LO` register, remainder is in `HI` register
    | `31..25`  | `24..21` | `20..17` | `16..4`   |  `3..0`   |
    |-----------|----------|----------|-----------|-----------|
    | `1011010` | Source 1 | Source 2 | Unused?.. | Condition |
  + `DIVS` - divides two signed 32-bit integers. Quotient is in `LO` register, remainder is in `HI` register
    | `31..25`  | `24..21` | `20..17` | `16..4`   |  `3..0`   |
    |-----------|----------|----------|-----------|-----------|
    | `1011011` | Source 1 | Source 2 | Unused?.. | Condition |
    _Division takes 11 cycles, so for the next 11 instructions you should not expect results in `HI..LO` registers._
    _You still can perform multiplication at that time though, just don't do it right at the 11th instruction after `DIV`_
  + `MVSU` - moves value from user register to supervisor register
    | `31..25`  |  `24..21`   | `20..17` | `16..4`   |  `3..0`   |
    |-----------|-------------|----------|-----------|-----------|
    | `1011100` | Destination |  Source  | Unused?.. | Condition |
    _Name because in assembly its written like `MVSU sR1, uR2` and moves value from user `R2` to supervisor `R1`_
  + `MVUS` - moves value from supervisor register to user register
    | `31..25`  |  `24..21`   | `20..17` | `16..4`   |  `3..0`   |
    |-----------|-------------|----------|-----------|-----------|
    | `1011101` | Destination |  Source  | Unused?.. | Condition |
    _Name because in assembly its written like `MVUS uR1, sR2` and moves value from supervisor `R2` to user `R1`_
  + `MVHI` - moves value from `HI` register to some other register
    | `31..25`  |  `24..21`   | `20..4`   |  `3..0`   |
    |-----------|-------------|-----------|-----------|
    | `1011110` | Destination | Unused?.. | Condition |
  + `MVLO` - moves value from `LO` register to some other register
    | `31..25`  |  `24..21`   | `20..4`   |  `3..0`   |
    |-----------|-------------|-----------|-----------|
    | `1011111` | Destination | Unused?.. | Condition |

## Memory map

There is no definite memory map, but for convenience:

- `0x00000000` - Inaccessible (if accessed in user mode sets corresponding flag and switches to supervisor mode. If in supervisor mode, halt the CPU)
- `0x00000001..0x0000FFFF` - ROM for loader amd supervisor routines. Could be user programs on ROM too
- `0x00010000` - Usual code position
- `0x10000000` - Heap start
- `0xDFFFFFFF` - User Stack bottom. Stack grows downwards
- `0xEFFFFFFF` - Supervisor Stack bottom. Stack grows downwards
- `0xFFFF0000` - Ports

### Ports
_Caution: 1 byte ports only work if writing to them with specifically, not together with other ports_
- `0xFFFFFFFF` (1 byte) - LCD control signals (`LCD_CTRL`)
  * Bit 0 is `LCD_RS`
  * Bit 1 is `LCD_RW`
  * Bit 2 is `LCD_E`
- `0xFFFFFFFE` (1 byte) - LCD data signals (`LCD_DATA`)
- `0xFFFFFFFD` (1 byte) - CPU speed (`CPU_SPEED`)
  * `0` means manual speed (like button-press slow), (`CPU_SPEED_MANUAL`)
  * `1` means slow speed (like 50 Hz), (`CPU_SPEED_SLOW`)
  * `2` means max speed (full 50 MHz), , (`CPU_SPEED_MAX`)

## Calling convention

KCPU should use usual C calling convention with slight modification: return address is in `LR`, and not on stack.
If needed, `LR` is saved on stack or somewhere else by caller. Also, no registers are saved except `SP` and `FP`
### Caller
- If needed, pushes `LR` on stack
- Pushes arguments on stack (in reverse order)
- Sets `LR` to return address
- Jumps to callee
- Cleans up arguments
- If needed, gets `LR` from stack
### Callee
- Pushes `FP` on stack
- Saves current stack position in `FP`
- Executes its code, using `(FP+8)`, `(FP+12)` etc. as arguments and
  allocating local variables at `(FP+0)`, `(FP-4)`, `(FP-8)` etc.
- Stores return value in `R1`
- Restores stack position
- Gets `FP` from stack
- Jumps to position specified by `LR`