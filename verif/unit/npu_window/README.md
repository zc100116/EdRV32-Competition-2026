# NPU D1-A window verification

This unit uses the frozen datapath design 4.2.4 ports, the real two-bank line
cache and fixed line RAM wrappers. A contract-driven two-stage weight source
supplies distinguishable bytes for every weight row. No other D1 worker module
is required.

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_window'
make full REGRESS_ARGS='-j 1 --path verif/unit/npu_window'
python3 tools/check/verilog_style.py \
  rtl/npu/edrv32_npu_input_unpack.v rtl/npu/edrv32_npu_line_cache.v \
  rtl/npu/edrv32_npu_window.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
  --top-module edrv32_npu_window rtl/npu/edrv32_npu_window.v
```

The mathematical reference enumerates pair, ky, kx, C16 and C8 loops from accepted
commands. It compares both bank enables, enabled bank addresses, weight row,
first/last, all 49 tag bits, all four activation replicas and every weight byte.
It never reads DUT internals. Reservation slot/address inputs change on every
cycle, checking that a pair retains only its first-edge reservation.

The schedule checker also predicts the earliest legal A1 edge. It checks every
term, including bubbles, rather than only comparing valid payloads. It applies
`T+K_new-1 >= L+G_previous` at pair entry and checks uninterrupted later terms,
even while pair credit and issue enable are withdrawn. Thus it checks command
preparation, advance submission and the absence of fixed block/row drain waits.

Coverage:

- 1x1/3x3, S1/S2, non-power-of-two width 12, top/bottom/left/right zero padding,
  shared-beat S1 and opposite-bank S2 reads, multiple C16 planes.
- Ordinary K=2 to D2 K=1 to ordinary K=2 across blocks and rows, exercising the
  previous pair's four/two-group quantization calendar.
- D2 full-C16 activation and C4 low-C4 activation, with/without HALF_TAIL;
  C4 HALF_TAIL retains K=9 and clears the d2 tag bit.
- CP-02 five 204-item row slots and two 512-item slots; overlapping old/new
  command contexts without waiting for A5 to drain.
- Pair-entry stalls and cancellation, followed by reuse of unchanged RAM data.

The cycle scoreboard requires command `read_done` at A1+2 and A5 term output at
A1+4, including the command row/block labels. The standalone cache checks its
array/output register stages independently; the unpack test checks C16/C4 write
and row completion timing.

Logs are under `build/regress/{smoke,full}/unit/npu_window/verilator/`.
PDS resource/timing and full datapath integration remain with the coordinator's
later tasks; these unit tests make no FPGA timing or resource claim.

## Recorded unit results

Verilator 5.020 (Debian 5.020-1), 2026-10-27, SIM_MODE; all builds and
regressions ran serially with `-j 1`. Results refer to the implementation commit
containing this file; the completion message provides its full Git commit ID.

| Module | smoke | full | Observed checks |
|---|---|---|---|
| input_unpack | 1 PASS, 0 FAIL | 1 PASS, 0 FAIL | 120 writes, 14 row completions; C16 II=1, C4 acceptance II=4 |
| line_cache | 1 PASS, 0 FAIL | 1 PASS, 0 FAIL | 2454 returned/held-word comparisons, both banks and all 1024 addresses |
| window | 1 PASS, 0 FAIL | 1 PASS, 0 FAIL | 22079 A1 terms, 1007 pair reservations, 83 completed commands; A3=A1+2, A5=A1+4 |

The [unpack commands](../npu_input_unpack/README.md) and
[cache commands](../npu_line_cache/README.md) give their exact smoke/full/lint
invocations. All six regression compile logs contain zero warnings with `-Wall`,
without warning suppressions. The three-RTL style check prints
`Style: 3 files, 0 warnings` in `build/npu_d1_a/style.log`; standalone
`--lint-only -Wall -DSIM_MODE -Irtl/include` for each top exits 0 with empty
`build/npu_d1_a/lint-{input_unpack,line_cache,window}.log` files.

Changes are limited to the three `rtl/npu/edrv32_npu_{input_unpack,line_cache,window}.v`
files and the three corresponding unit directories. Each unit directory contains
`README.md`, `files.f`, `test.yaml` and its `tb_npu_<module>.sv`. A5 retains four
256-bit activation register copies using the existing PDS `syn_preserve` /
`syn_keep` convention and registers weights in 32 independent 64-bit channel slices.

No D1-A implementation items remain. Datapath integration, scheduler/DMA integration
and PDS resource/timing measurements are outside this task and remain with the
coordinator's subsequent work.
