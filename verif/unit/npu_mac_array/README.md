# NPU MAC array unit test

The self-checking test implements D1-C from design record
`docs/design/2026-10-27-npu-datapath.md` 5.2, covering NPU testplan
OP-01/02/04/07/08 at the MAC boundary. Its reference independently multiplies
signed scalar bytes and sums eight products for every pixel/channel.

Run from the repository root after loading the tool environment:

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_mac_array'
make full REGRESS_ARGS='-j 1 --path verif/unit/npu_mac_array'
python3 tools/check/verilog_style.py rtl/npu/edrv32_npu_mac_array.v
tools/check/lint.sh -DSIM_MODE -Irtl/include --top-module edrv32_npu_mac_array \
    rtl/npu/edrv32_npu_mac_array.v rtl/tech/edrv32_mul_npu_int8_pair.v
```

Coverage includes both signed extrema, mixed signs, each of the eight input
lanes, all 64 outputs, ordinary C8, D2 C16 selection, C4 half without D2,
continuous terms and changing block/row tags, invalid bubbles, cancel at all
five occupied pipeline boundaries, reset while occupied and fresh work after
cancel/reset. The random stream uses seed `0x326ac851`.

The scoreboard checks data, first/last/tag, M1 `mac_beat_o`, and idle on every
cycle. If a term is sampled into M1 at edge e, its R3 result is visible after
edge e+4: five register boundaries, M1/M2/R1/R2/R3. There is no CE or ready.

Logs are under `build/regress/{smoke,full}/unit/npu_mac_array/verilator/`.
These tests use the committed fixed APM behavioral wrapper; vendor SIMD
equivalence and physical timing/resource measurements remain N-IP1/PDS work.
