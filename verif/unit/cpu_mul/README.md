# CPU mul unit test

Run from the repository root (create `build/unit` first):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_mul/files.f --Mdir build/unit/cpu_mul > build/unit/cpu_mul-compile.log 2>&1
build/unit/cpu_mul/Vtb
```
