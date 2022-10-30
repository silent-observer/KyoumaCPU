# Kyouma OS Specification

Kyouma OS is an OS specifically written for Kyouma CPU and supporting devices. Currently non existent.

## Kyouma Executable and Linkable Format

Executables and object files in Kyouma OS have ELF format.
Specifically LSB 32-bit ELF format.

### Relocations
Kyouma CPU architecture uses only `Elf32_Rel` relocation entries, addend is stored in relocation field

- `S` - value of the symbol.
- `A` - value at relocation field
Value of relocation `V` is always calculated as `S + A`

####Relocation types:
|       Name        | Value | Field  | Relocation place | Calculation |
|-------------------|-------|--------|------------------|-------------|
| `NoRelocation`    | `0`   | none   | none             | none        |
| `HiRelocation`    | `1`   | word32 | `instr[17..4]`   | `V[31..18]` |
| `LoRelocation`    | `2`   | word32 | `instr[23..4]`   | `V[19..0]`  |
| `FullRelocation`  | `3`   | word32 | `instr[31..0]`   | `V[31..0]`  |
| `LoRelocationImm` | `4`   | word32 | `instr[17..4]`   | `V[12..0]`  |