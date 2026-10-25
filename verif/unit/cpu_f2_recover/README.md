# U-11 F2 stale prediction recovery

Run from the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/unit
verilator --binary --timing -Wno-fatal --top-module tb -DSIM_MODE \
    -f verif/unit/cpu_f2_recover/files.f --Mdir build/unit/cpu_f2_recover \
    > build/unit/cpu_f2_recover-compile.log 2>&1
build/unit/cpu_f2_recover/Vtb
```

Cases cover upper-halfword positions in the same or following group, both length
mismatches, correct compressed and 32-bit predictions, and D/M/E priority over F2.
The checker compares PC, raw bytes, expanded instructions and RAS checkpoints,
including older instructions already queued in IB before recovery.
