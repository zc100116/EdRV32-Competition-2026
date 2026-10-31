# S-R2 interrupt, system-control and reset tests

The four smoke manifests cover sys-subsys-testplan CL-01–CL-05, PL-01–PL-05,
and SY-01–SY-07. Each runs on Verilator and Icarus through `tools/regress.py`.

| Directory | Checks |
|---|---|
| `periph_clint` | Cycle reference for mtime, half writes and carry, registered MTIP boundary, MSIP, rejected SIZE/burst/alignment, AXI response stalls and IDs |
| `periph_plic` | Priority and tie break, threshold and enable, claim at AR acceptance, held-level suppression, incorrect completion, re-pending, 12 allocated sources, asynchronous sources at two clock ratios, reserved inputs tied low |
| `periph_sysctrl` | IDs and generated frequency, synchronized MEM_READY, both scratch registers, APB request timing, one-cycle software/SIM_EXIT pulses, arbitrary SIM_EXIT code |
| `soc_reset_ctrl` | Delayed MEM_READY, asynchronous assertion and synchronous release on all nine resets, sixteen-cycle software hold followed by exactly two clocks in each media domain, preserved memory core and scratch, ordered system release |

Run from the repository root after `. ~/.local/opt/edrv32/env.sh`:

```sh
python3 tools/gen/soc_map.py
make smoke REGRESS_ARGS='-j 1 --path verif/unit/periph_clint'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/periph_plic'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/periph_sysctrl'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/soc_reset_ctrl'
make lint
python3 tools/check/verilog_style.py rtl/
verilator --lint-only -Wall -Irtl/include --top-module edrv32_periph_clint \
    rtl/periph/edrv32_periph_clint.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_periph_plic \
    rtl/periph/edrv32_periph_plic.v rtl/common/edrv32_cdc_sync_bit.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_periph_sysctrl \
    rtl/periph/edrv32_periph_sysctrl.v rtl/common/edrv32_cdc_sync_bit.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_soc_reset_ctrl \
    rtl/soc/edrv32_soc_reset_ctrl.v rtl/common/edrv32_cdc_sync_bit.v \
    rtl/common/edrv32_reset_sync.v rtl/common/edrv32_reset_copy.v
```

The coordinator revised acceptance during execution because simultaneous full
regressions exhausted host memory: workers run only their own test directories,
and the coordinator runs `make smoke`/`make full` serially at integration.
This task stopped both its full-smoke attempts and cleaned up its compiler
processes. The initial failures were C++ compilation timeouts and one invalid
precompiled header after a compiler optimization change; they did not execute
failing RTL simulations. Task acceptance uses the default Verilator invocation
above, without an optimization override.

The PLIC manifest allows 300 seconds for its larger Verilator C++ build.

Logs are in `build/regress/smoke/{unit,block}/<test>/<simulator>/`.

## Integration handoff

The coordinator owns system file lists. Add these entries to the system RTL
file list (paths relative to `rtl/filelists/`):

```text
+incdir+../include
../common/edrv32_cdc_sync_bit.v
../common/edrv32_reset_sync.v
../periph/edrv32_periph_clint.v
../periph/edrv32_periph_plic.v
../periph/edrv32_periph_sysctrl.v
../soc/edrv32_soc_reset_ctrl.v
```

Include each common primitive once when combining lists. SYSCTRL `rst_n_i`
connects to reset_ctrl `rst_sys_por_n_o`; the other system devices use
`rst_sys_n_o`. `rst_mem_core_n_o` is for the memory fabric and DDR gateway;
`rst_mem_n_o` is for memory-clock engines. Reset controller clock ports are
`clk_sys_i`, `clk_mem_i`, `clk_pix_i`, `clk_cam0_i`, `clk_cam1_i`,
`clk_eth_rx_i`, and `clk_eth_tx_i`. Its software request inputs are
`soft_reset_media_i` and `soft_reset_soc_i`. Tie PLIC sources 3, 4 and 7 low at
the integration boundary. CLINT/PLIC legal writes select the full 32-bit half
by address bit 2 and ignore WSTRB, as confirmed by the coordinator.

`clk_sys_hz: 100000000` in `rtl/include/soc_address_map.json` generates the
same `EDRV32_CLK_SYS_HZ` value in Verilog and C. The separately committed
regression-tool fix translates command-file include/define syntax to the
Icarus command-line equivalents; Verilator arguments are unchanged.

## Verified results (2026-10-25)

Implementation commit: `ce8aac5b14f7024523d6b8a42e70c2861f9f6a4a`; regression-tool commit: `ec4b8c9`.
Base: `7822d70` (confirmed system subsystem specification).
Reported tools: Verilator 5.020 and Icarus Verilog 12.0 on Linux.

- The directory-filtered Python command above: **8 PASS, 0 FAIL** using the
  default Verilator compilation, recorded in `build/sr2-unit-tests.log`.
- The Icarus smoke subset, selected by the existing manifests: **12 PASS,
  0 FAIL** (seven common primitive tests, example, and these four unit tests).
- `make lint`: **0 warnings**; explicit lint for the four new modules using
  the commands above: **0 warnings**.
- `python3 tools/check/verilog_style.py rtl/`: **21 files, 0 warnings**.
- `git diff --check`: clean. Full smoke/full remains the coordinator's
  integration check under the revised acceptance instruction. This checkout
  has no CPU test manifests, so these results do not claim CPU regression
  coverage.

New files (17):

```text
rtl/periph/edrv32_periph_clint.v
rtl/periph/edrv32_periph_plic.v
rtl/periph/edrv32_periph_sysctrl.v
rtl/soc/edrv32_soc_reset_ctrl.v
verif/unit/periph_clint/files.f
verif/unit/periph_clint/tb.sv
verif/unit/periph_clint/test.yaml
verif/unit/periph_plic/files.f
verif/unit/periph_plic/tb.sv
verif/unit/periph_plic/test.yaml
verif/unit/periph_sysctrl/files.f
verif/unit/periph_sysctrl/tb.sv
verif/unit/periph_sysctrl/test.yaml
verif/unit/soc_reset_ctrl/files.f
verif/unit/soc_reset_ctrl/tb.sv
verif/unit/soc_reset_ctrl/test.yaml
verif/unit/soc_reset_ctrl/README.md
```

## SY-07 reset copies (2026-10-31)

The default manifest uses clk_mem/clk_sys periods 14/10; `fast_mem` uses 6/10.
Both run SY-03/04/05 and check two memory reset copies, one-clock release delay,
asynchronous assertion between memory edges, and copy-before-system ordering
for both power-on sequences and SOC software reset. The CDC input is checked
against the external copies, so sampling the raw memory reset fails this test.

```sh
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke -j 1 --path verif/unit/soc_reset_ctrl
```
