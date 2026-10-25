# CPU decode unit test

Run from the repository root (create `build/unit` first):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_decode/files.f --Mdir build/unit/cpu_decode > build/unit/cpu_decode-compile.log 2>&1
build/unit/cpu_decode/Vtb
```
