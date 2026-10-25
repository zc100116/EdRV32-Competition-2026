# CPU regfile unit test

Run from the repository root (create `build/unit` first):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_regfile/files.f --Mdir build/unit/cpu_regfile > build/unit/cpu_regfile-compile.log 2>&1
build/unit/cpu_regfile/Vtb
```

Icarus cross-check:

```sh
iverilog -g2012 -s tb -o build/unit/cpu_regfile.vvp -f verif/unit/cpu_regfile/files.f
vvp build/unit/cpu_regfile.vvp
```
