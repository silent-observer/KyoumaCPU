type
  Register* = distinct range[0..15]

proc `$`*(reg: Register): string {.inline.} = "R" & $reg.int
proc `==`*(a, b: Register): bool {.inline.} = a.int == b.int