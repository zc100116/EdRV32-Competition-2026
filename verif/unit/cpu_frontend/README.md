# CPU frontend unit test

Run from the repository root (create `build/unit` first):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE -f verif/unit/cpu_frontend/files.f --Mdir build/unit/cpu_frontend > build/unit/cpu_frontend-compile.log 2>&1
build/unit/cpu_frontend/Vtb
```

Also exercise fixed 32-bit instruction fetch:

```sh
verilator --binary --timing -Wno-fatal --top-module tb -GRVC_EN=0 -DSIM_MODE \
    -f verif/unit/cpu_frontend/files.f --Mdir build/unit/cpu_frontend_no_c \
    > build/unit/cpu_frontend_no_c-compile.log 2>&1
build/unit/cpu_frontend_no_c/Vtb
```
