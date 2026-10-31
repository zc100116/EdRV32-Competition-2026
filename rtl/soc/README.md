# B2 SoC integration

`edrv32_soc_top` implements the B2 board plan: CPU, system and memory subsystems,
VIN, PIX, GEO, DISP, NPU and ETH. RND is not connected. The external port contract
is SoC specification section 3; `debug_o` is 64 bits (cpu-spec 3.1, 7.2).
DISP remains the B2 single-layer v0.2 implementation with ID `0x0005_0001`;
the subsequent v0.3 two-layer specification belongs to B3.

| Instance / module | mem_xbar | APB slot | PLIC source | Reset | Clock |
|---|---|---|---|---|---|
| `u_cpu` / `edrv32_cpu_subsys` | P2 through sys S6 / DDR gateway | system 5 (CACHE_CTRL) | 6 to PLIC; receives MEIP/MSIP/MTIP | `rst_sys_n` | sys |
| `u_sys` / `edrv32_sys_subsys` | S6 to memory subsystem | system peripherals; exports media decoder | owns 1–7 and synchronizes 8–15 | external `rst_n_i`; produces domain resets | sys; media bridge/decoder in mem; domain clocks to reset_ctrl |
| `u_mem` / `edrv32_mem_subsys` | owns xbar, gateway P2; ETH exclusively owns P6 | media 8 MEM_XBAR; 9 reserved | 15 MEM_XBAR | `rst_sys_n`, `rst_mem_core_n` | sys, mem |
| `u_vin` / `edrv32_vin` | P1 read/write, urgent | media 1 | 8 | `rst_mem_n`, `rst_cam0_n`, `rst_cam1_n` | mem, cam0/1 pclk |
| `u_pix` / `edrv32_pix` | VIN pixel stream, no DDR port | media 2 | 9 | `rst_mem_n` | mem |
| `u_geo` / `edrv32_geo` | P5 read/write | media 3 | 10 | `rst_mem_n` | mem |
| `u_disp` / `edrv32_disp` | P0 read, urgent | media 5 | 12 | `rst_mem_n`, `rst_pix_n` | mem, pix |
| `u_npu` / `edrv32_npu` | P3 read/write, internal X9 bridge | media 6, internal X10 bridge | 13 (npu domain) | `rst_mem_n`, `rst_npu_n` | mem, npu |
| `u_eth` / `edrv32_eth` | P6 directly through memory subsystem | media 7 | 14 | `rst_mem_n`, `rst_eth_rx_n`, `rst_eth_tx_n` | mem, eth RX/TX |
| RND absent | P4 requests valid=0; B/R ready=1 | media 4 reserved | 11=0 | — | — |

P4 payloads are zero. Only P0/P1 have urgent signals in the memory subsystem
interface; all other ports' urgent inputs are zero inside that subsystem.
Reserved media slots 0, 4 and 10–15 return `pready=1`, `pslverr=1`, `prdata=0`.
VIN's `pix_in_*` stream feeds PIX and PIX's `pix_out_*` stream returns to VIN.
GPIO0 bits 12/13 drive cam0 PWDN/RESET_N; bits 14/15 drive cam1 PWDN/RESET_N
(SoC 3.5). The full GPIO vector is also exposed at the SoC boundary.

The NPU reset releases synchronously on `clk_npu_i` from the same request as the
other media resets, and both MEDIA and SOC software resets assert it. The memory
fabric and gateway continue using `rst_mem_core_n`. The annotation on
`rst_mem_n_w` documents the registered X8 reset-status crossing: it is an async
reset to engines and a synchronized status input to reset_ctrl.

MEM_XBAR statistics use separate read/write transaction and beat counters
(mem-subsys-spec v0.4 4.1): `RD_TXN/RD_BEAT` at `0x400/0x404 + 0x20*p` and
`WR_TXN/WR_BEAT` at `0x414/0x418 + 0x20*p`. SNAPSHOT, CLEAR and saturation semantics
are unchanged.

## File list and lint

`rtl/filelists/soc.f` references the nine existing subsystem/engine lists.
As with those lists, paths are relative to their containing file list. Shared
sources must be expanded once, retaining their first appearance, using the same
convention as the PDS import scripts. The coordinator's `tools.regress.expand_files`
provides this expansion without suppressing MODDUP warnings.

From the repository root, after `. ~/.local/opt/edrv32/env.sh`:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
from tools.regress import expand_files
for name in ('soc_top', 'sys_subsys', 'mem_subsys'):
    filename = 'soc' if name == 'soc_top' else name
    subprocess.run(['verilator', '--lint-only', '-Wall', '+define+SIM_MODE',
                    '--top-module', 'edrv32_' + name] +
                   expand_files(Path('rtl/filelists/' + filename + '.f')), check=True)
PY
python3 tools/check/verilog_style.py rtl/soc rtl/mem
```

## Connection smoke

```sh
python3 tools/regress.py smoke --path verif/soc/soc_connect -j 1
```

The runner builds software with `sw/Makefile`, packs its byte images into the
ROM/SRAM models' 64-bit format, and preloads those models using `ROM_HEX` and
`SRAM_HEX`. The CPU starts at the ROM reset vector and enters the SRAM program.
The DDR port uses `verif/models/ddr3_axi256_model.sv`; the bench asserts memory
readiness and drives idle peripheral inputs.

The software checks all eight connected media IDs; all eight reserved slots must
cause load-access exceptions (`mcause=5`, `mtval=address`, cpu-spec 6). It checks
both DDR aliases with BSP cache maintenance, clears P2 statistics, alternates three
single-beat writes and reads, then checks all four snapshot counters equal three.

A single GEO descriptor with zero-size output rectangle triggers a normal
completion without external stimulus: GEO 2.3 allows the empty rectangle to
complete, 2.6 defines its 64-byte descriptor, and 5.1 sets DONE after completion.
PLIC source 10 must reach the CPU as machine external interrupt (`mcause=0x8000000b`);
the handler claims source 10, checks/clears GEO DONE and completes the PLIC claim.
The main program checks `DONE_COUNT=1` and writes SYSCTRL `SIM_EXIT=0`.
Logs, packed images and the compiled simulator are in `build/soc_connect/`.

## Verilator structure reference

Measured RTL commit: `f084837` (B2 top and reset/statistics changes), using
Verilator 5.020 (Debian 5.020-1), `SIM_MODE`. Reuse the expansion in the lint
command above, replacing `--lint-only` with
`--xml-only --stats --Mdir build/soc_connect/scale`.

The XML contains 9 direct top instances, 154 specialized RTL modules,
589 instance declarations across those specialized modules, and 12,306 variable
declarations. These are elaboration structure counts; FPGA resource utilization
still requires PDS. The statistics report's final MODULE node count is 155;
the XML module-definition count above is reported separately.

Raw data and the exact source command/commit are in:
`build/soc_connect/scale/command.log`, `Vedrv32_soc_top.xml` and
`Vedrv32_soc_top__stats.txt` in the same directory.

## Verification results

All commands use `. ~/.local/opt/edrv32/env.sh` and `-j 1`, with no `--parallel`.
Run each row as `python3 tools/regress.py <tier> --path <directory> -j 1`.
The reset/statistics results cover commits `8c408c7` and `32dec38`; the integrated
SoC and system test connections are in `f084837`; the connection smoke
software/testbench are in `f21ce62`.

| Directory | Tier | Result |
|---|---|---|
| `verif/unit/soc_reset_ctrl` | smoke / full | 2 / 2 PASS |
| `verif/unit/sys_subsys_reset` | smoke / full | 2 / 2 PASS |
| `verif/unit/mem_xbar` | smoke / full | 2 / 3 PASS |
| `verif/block/mem_subsys` | smoke / full | 17 / 49 PASS |
| `verif/soc/soc_connect` | smoke | 1 PASS; simulation 4.460 s |
| `verif/block/sys_subsys` | smoke | 38 PASS |
| `verif/block/sys_cpu` | smoke | 3 PASS |

The table totals 121 passing simulator executions across the requested tiers.

Verilator `--lint-only -Wall` has zero warnings for the SoC, system subsystem
and memory subsystem. The style check over `rtl/soc` and `rtl/mem` reports
12 files, zero warnings. Detailed per-case logs are under `build/regress/`;
the aggregate logs are `build/soc_connect/*verif*.log`, `mem_xbar_full.log` and
`regress.log`. The SoC RTL lint command and output are `build/soc_connect/lint.log`.

## Changed files

RTL and integration documentation:

- `rtl/soc/edrv32_soc_top.v`
- `rtl/soc/edrv32_soc_reset_ctrl.v`
- `rtl/soc/edrv32_sys_subsys.v`
- `rtl/mem/edrv32_mem_xbar.v`
- `rtl/mem/edrv32_mem_xbar_regs.v`
- `rtl/filelists/soc.f`
- `rtl/soc/README.md`

Existing verification updated for this task:

- `verif/unit/soc_reset_ctrl/tb.sv`, `test.yaml`
- `verif/unit/sys_subsys_reset/tb.sv`
- `verif/unit/mem_xbar/tb.sv`
- `verif/block/mem_subsys/edrv32_mem_subsys_tb.sv` (MX-10 only)
- `verif/block/sys_subsys/edrv32_sys_env.sv` (NPU reset ports only, coordinator authorized)
- `verif/block/sys_cpu/edrv32_sys_cpu_tb.sv` (NPU reset ports only, coordinator authorized)

New `verif/soc/soc_connect/` files: `test.yaml`, `files.f`,
`edrv32_soc_connect_tb.sv`, `reset_entry.S`, `boot.c`, `main.c`, `run.py`, `README.md`.

The first cold system smoke hit the existing 180-second runner timeout while
compiling the PLIC and UART groups. The timeout left compiler children running;
subsequent entries used the same build directory and reported missing/invalid
PCH files. The initial output is retained in
`build/soc_connect/first_smoke_verif_block_sys_subsys.log` and `first_pl_*.log`.
Those compilation processes were stopped, and the same unmodified runners and
`-j 1` build settings were used to complete the affected builds before the final
regression invocation:

```sh
python3 verif/block/sys_subsys/run.py 502
python3 verif/block/sys_subsys/run.py 602
python3 verif/block/sys_subsys/run.py 101
```

Their logs are `build/soc_connect/prebuild_sys_<case>.log`; no runner, test timeout
or RTL behavior was changed to resolve the cold-build failure.
