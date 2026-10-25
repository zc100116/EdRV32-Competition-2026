# CPU div unit test

Run from the repository root (create `build/unit` first):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_div/files.f --Mdir build/unit/cpu_div > build/unit/cpu_div-compile.log 2>&1
build/unit/cpu_div/Vtb
```
