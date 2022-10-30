
proc f(x: static[int]) =
  for l in and @[1, 2, 3].items:
    discard

f(4)