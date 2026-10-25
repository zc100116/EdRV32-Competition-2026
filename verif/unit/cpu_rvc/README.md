# CPU rvc unit test

Run from the repository root (create `build/unit` first):

```sh
python3 verif/unit/cpu_rvc/vectors.py
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_rvc/files.f --Mdir build/unit/cpu_rvc > build/unit/cpu_rvc-compile.log 2>&1
build/unit/cpu_rvc/Vtb
```
