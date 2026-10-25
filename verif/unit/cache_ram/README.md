Run from repository root:

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build
verilator --binary --timing --top-module tb -DSIM_MODE -F verif/unit/cache_ram/files.f --Mdir build/cache_ram -o sim
build/cache_ram/sim
```

Self-checking simulation exits on a mismatch and prints PASS on completion.
