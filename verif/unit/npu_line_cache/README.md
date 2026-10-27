# NPU line cache unit test

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_line_cache'
make full REGRESS_ARGS='-j 1 --path verif/unit/npu_line_cache'
verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
  --top-module edrv32_npu_line_cache rtl/npu/edrv32_npu_line_cache.v \
  rtl/tech/edrv32_ram_npu_line.v
```

The test uses the fixed `edrv32_ram_npu_line` wrappers. It writes and reads every
address in both banks, including the five 204-item slots (0 through 1019) and
the two 512-item slots (0 through 1023) of CP-02. An independent read-first memory
model checks every returned 256-bit word, independent enables, held outputs,
back-to-back reads and overlapping reads/writes. A request sampled on edge e has
its output register updated on e+1: two registered read stages.

The RAM module has no reset or cancellation port. Logs are under
`build/regress/{smoke,full}/unit/npu_line_cache/verilator/`.
