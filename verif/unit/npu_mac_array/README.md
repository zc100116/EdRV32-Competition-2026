# NPU MAC array unit test

The self-checking test implements D1-C from design record
`docs/design/2026-10-27-npu-datapath.md` 5.2, covering NPU testplan
OP-01/02/04/07/08 at the MAC boundary. Its reference independently multiplies
signed scalar bytes and sums eight products for every pixel/channel.

Run from the repository root after loading the tool environment:

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/npu_mac_array -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/unit/npu_mac_array -j 1
python3 tools/check/verilog_style.py rtl/npu/edrv32_npu_mac_array.v
tools/check/lint.sh -DSIM_MODE -Irtl/include --top-module edrv32_npu_mac_array \
    rtl/npu/edrv32_npu_mac_array.v rtl/tech/edrv32_mac_npu_int8_chain.v
```

Coverage includes both signed extrema, mixed signs, each of the eight input
lanes, all 64 outputs, ordinary C8, D2 C16 selection, C4 half without D2,
continuous terms and changing block/row tags, invalid bubbles, cancel at all
ten occupied pipeline boundaries, reset while occupied and fresh work after
cancel/reset. The random stream uses seed `0x326ac851`.

The scoreboard checks data, first/last/tag, M1 `mac_beat_o`, and idle on every
cycle. If a term is sampled into M1 at edge e, its C8 result is visible after
edge e+9: ten register boundaries, M1/M2/C1–C8. There is no CE or ready.

Logs are under `build/regress/{smoke,full}/unit/npu_mac_array/verilator/`.
Weights are driven with item k delayed k edges, matching the resident-bank contract.
Vendor cycle equivalence is covered by `verif/unit/npu_mac_chain`; physical timing
remains PDS work.
