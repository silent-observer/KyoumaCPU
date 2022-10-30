# Package

version       = "0.1.0"
author        = "silent-observer"
description   = "KyoumaCPU linker"
license       = "MIT"
srcDir        = "src"
bin           = @["kld"]



# Dependencies

requires "nim >= 0.20.2", "kelf"
requires "stew#43bbe48e5f8181b7ca8923e6edf78dec635e8aea"
