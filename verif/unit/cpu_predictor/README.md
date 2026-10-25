# CPU predictor unit test

Run from the repository root (create `build/unit` first):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_predictor/files.f --Mdir build/unit/cpu_predictor > build/unit/cpu_predictor-compile.log 2>&1
build/unit/cpu_predictor/Vtb
```
