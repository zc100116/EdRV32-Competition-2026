Run from repository root:

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build
verilator --binary --timing --top-module tb -DSIM_MODE -F verif/unit/cache_pma/files.f --Mdir build/cache_pma -o sim
build/cache_pma/sim
```

Self-checking simulation exits on a mismatch and prints PASS on completion.
