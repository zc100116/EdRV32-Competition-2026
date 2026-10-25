# CPU branch unit test

Run from the repository root (create `build/unit` first):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_branch/files.f --Mdir build/unit/cpu_branch > build/unit/cpu_branch-compile.log 2>&1
build/unit/cpu_branch/Vtb
```
