# NPU input normalization unit test

`test.yaml` runs a self-checking SystemVerilog test with Verilator `-Wall`.

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_input_unpack'
make full REGRESS_ARGS='-j 1 --path verif/unit/npu_input_unpack'
verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
  --top-module edrv32_npu_input_unpack rtl/npu/edrv32_npu_input_unpack.v
```

The scoreboard schedules cache writes from DMA handshakes, independently of the
unpack state. C16 writes occur at acceptance edge e. C4 writes occur at e+1 through
e+4 with bank/address `(0,a),(1,a),(0,a+1),(1,a+1)`, preserving the low four bytes
of each pixel and zeroing the upper twelve. Every byte is compared.

Coverage includes continuous C16 traffic, continuous C4 beats with eight distinct
pixels, multiple beats per row, row completion while the next row is accepted,
and cancellation of an accepted C4 beat followed by a new row. Row completion
is checked immediately after the actual final cache write edge, never at C4 input
acceptance. `line_wr_idle_o` is checked after expansion and cancellation.

Logs are under `build/regress/{smoke,full}/unit/npu_input_unpack/verilator/`.
