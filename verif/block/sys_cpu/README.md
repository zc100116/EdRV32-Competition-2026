# CPU and system subsystem SC environment

This bench connects the real `edrv32_cpu_subsys` (`RVC_EN=1`) and
`edrv32_sys_subsys` with the production AXI, CACHE_CTRL APB, CLINT time and
interrupt interfaces. The system reset controller generates the CPU reset;
MEM_READY is initially delayed. Unused media APB slots return SLVERR.
UART and both SCCB peers reuse the S-V1 serial models; GPIO bit 0 selects the
ROM preload/download path and bit 1 supplies the SC-03 interrupt edge.

Run from the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/coremark
python3 verif/block/sys_cpu/run.py sc01
python3 verif/block/sys_cpu/run.py sc02
python3 verif/block/sys_cpu/run.py sc03
python3 verif/block/sys_cpu/run.py sc04
python3 verif/block/sys_cpu/run.py sc05
python3 verif/block/sys_cpu/run.py sc06
python3 verif/block/sys_cpu/run.py sc07
python3 verif/block/sys_cpu/run.py sc08
python3 verif/block/sys_cpu/run.py perf
python3 verif/block/sys_cpu/check_style.py
```

Each manifest invokes the same runner. SC-01/02/03/06 and the SC-07 CRC run are
`smoke`; SC-04/05/08 are `full`; the four SC-07 measurement runs are `perf`.
The runner builds through `sw/Makefile` and uses one Verilator binary with
`--timing -Wall +define+SIM_MODE -j 2`; tests run serially. No repository-wide
regression is invoked. Software, build commands, simulation commands and UART
logs are under `build/sys_cpu/`.

The default software ELF byte images are packed into sparse, little-endian
64-bit words for the ROM/SRAM technology wrappers. Only file-backed ELF bytes
are loaded; absent words remain uninitialized, and the application startup owns
BSS initialization. The ROM is the S-W2 bootloader; all applications enter
through its banner, MEM_READY check, UART drain and FENCE.I handoff. SC-01--SC-07
finish when SYSCTRL asserts SIM_EXIT, requiring code zero; SC-08 finishes on its
second menu return as described below. The runner
also checks the ROM UART messages and, for CoreMark, all three algorithm CRCs.

SC-04 runs twice: button-selected download with no SRAM preload, and a preloaded
application that sets SCRATCH0 and requests SOC reset before download. The peer
waits for the readiness message and sends a little-endian length and the actual
`sc04` flat binary at 115200 baud. SC-03 drives GPIO bit 1 only after the
software's SCRATCH1 readiness marker. SC-05 checks eight register writes on
each SCCB peer and continuously checks that the unselected port is released.

SC-01 compares all five ASCII logo rows, the boot title, and every startup field
against the SC hardware configuration: CHIP_ID `0xed320001`, clk_sys 150 MHz,
ROM 16 KiB, SRAM 256 KiB, I$/D$ 8 KiB each, MEM_READY=1, SRAM application mode,
and the actual build commit/compiler. The UART checker uses the S-W2 key contract
in `sw/apps/monitor/README.md`.

SC-08 preloads the production monitor in SRAM. After the first complete menu it
sends `3`; after the next complete menu it sends `1`, waits for the iteration
prompt, and sends `1` followed by LF. It ends after the third complete menu
(initial entry plus two returns), requiring no SIM_EXIT write. System information
is compared field by field, including cache configuration and all sixteen event
codes. CoreMark checks both HPM rounds, all four reference CRC values and PASS
results per round, all sixteen event count fields, numeric/rate formats, score,
IPC and other derived metric fields, compiler version/options, and ISA. It does
not select menu item `2`. SC-01--SC-07 retain their SIM_EXIT completion contract.

The DDR backing reuses the B2 fixed-latency adapter and shared sparse AXI model,
with random stalls disabled and `delay_max=0`. `+DDR_LATENCY=N` sets S6 AR to
first-R handshake latency; the default is 20. Later read beats are consecutive
when ready. Write response behavior is the existing B2 model behavior. Both DDR
windows share physical storage. DDR software uses `sw/bsp/ld/ddr.ld`, with a
small SRAM entry trampoline reached through the ordinary ROM handoff; code,
data and stack then reside in the cacheable DDR window.

`perf` builds SRAM O2, SRAM tuned, DDR O2 with latency 20, and DDR O2 with latency
60. CoreMark source/seeds/MEM_STATIC/ten iterations and optimization flags match
C-I3. `sw/tests/sys_cpu/host.c` supplies real UART/SIM_EXIT transport and configures
HPM3--10 to events 1--8. Actual compiler commands are authoritative; the existing
CoreMark port prints its static O2/SRAM metadata even for other builds. Its
short-run duration warning is retained; algorithm CRCs are checked separately.

Performance windows match B2: retirement of `start_time` through just before
retirement of `stop_time`. All sixteen event increments are accumulated from the
CPU event bus; eight hardware CSR deltas are also printed. `SC_BOOT` records
reset release through application entry retirement, while `SC_TOTAL` includes
the complete ROM/application/UART execution. `SC_FILL` records completed
four-beat source-AXI reads whose request and last response both lie inside the
benchmark window, and sums AR-to-last-R service cycles. `SC_MISSWAIT`
counts the I$/D$ busy debug levels within that window. These overlapping bus
service counts are separate from instruction-retirement and HPM cycle counts.
Raw numerical measurements are written to `build/sys_cpu/coremark.csv`.

Icarus 12.0 was also tried for SC-01. It cannot compile the reused AXI interface
ports in the common memory/checker and B2 adapter, so this environment has no
SC-01 Icarus X-propagation result. Diagnostics are retained in
`build/sys_cpu/icarus-compile.log`; the task coordinator accepted reporting this
simulator limitation.

Strict lint uses the same source list and top as simulation:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
from tools.regress import expand_files
subprocess.run(['verilator', '--lint-only', '--timing', '-Wall',
                '+define+SIM_MODE', '--top-module', 'edrv32_sys_cpu_tb'] +
               expand_files(Path('verif/block/sys_cpu/files.f').resolve()), check=True)
PY
```

## S-I3 UART transcript

Software input is `c4256d5` (S-W2); this commit adds the SC-01/08 checks.
SC-08 uses the unmodified production monitor and bootloader. Below are the first
20 lines of system information and CoreMark output from
`build/sys_cpu/sc08/run.log`; the complete log contains all sixteen HPM counts,
two complete CRC rounds, `CoreMark result: PASS`, and the final menu.

System information:

```text
CHIP_ID: 0xed320001
CLK_SYS_HZ: 150000000
ROM bytes: 16384
SRAM bytes: 262144
I-cache bytes: 8192
D-cache bytes: 8192
MEM_READY: 1
Boot mode: SRAM app
Build commit: c4256d5
Compiler version: GCC 15.2.0
Cache ways: 2
Cache line bytes: 32
D-cache policy: write-back, write-allocate
Cache configuration source: cache-spec 2.1 constants
Compiler flags: -march=rv32imc_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -I/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-sys-integ/sw/bsp/include -I/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-sys-integ/sw/drivers/include -I/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-sys-integ/sw/boot -I/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-sys-integ/sw/apps/coremark -I/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-sys-integ/third_party/coremark -DITERATIONS=10
ISA: rv32imc_zicsr_zifencei
HPM event 00: disabled
HPM 01 dual retire: 1
HPM 02 single retire: 2
HPM 03 zero retire: 3
```

CoreMark (starting after the iteration-input prompt):

```text
Iterations: 1
HPM rounds: 2
HPM round: 1
HPM first event: 1
HPM last event: 8
HPM round cycles: 281763
HPM round instructions: 288202
CRC seed: 0x0000e9f5
CRC list: 0x0000e714
CRC matrix: 0x00001fd7
CRC state: 0x00008e3a
CRC final: 0x0000e714
CRC seed result: PASS
CRC list result: PASS
CRC matrix result: PASS
CRC state result: PASS
CRC result: PASS
HPM round: 2
HPM first event: 9
HPM last event: 16
```

## S-I3 validation results

On 2026-10-25, the commands above passed SC-01--SC-08: **8/8 PASS, 0 FAIL**,
including both SC-04 download paths. The four `perf` configurations also passed:
**4/4 PASS, 0 FAIL**. SC-08 verified both reference-CRC rounds and all sixteen HPM
fields, returning to the menu after system information and after CoreMark.
The final strict `--lint-only --timing -Wall` check and SC style check each
reported **0 warnings**. No software, shared UART model or RTL changes were needed.

Per-command summaries are `build/sys_cpu/s-i3-sc01.log` through
`s-i3-sc08.log` and `s-i3-perf.log`; detailed UART transcripts remain at the
per-case `run.log` paths. Strict lint/style logs are `s-i3-lint.log` and
`s-i3-style.log`. Each software and simulation log starts with its actual command.
The performance runner's `coremark.csv` records these results (`cycles` is the
software `Total ticks`, separately from the retirement-boundary window):

| Configuration | Total ticks | CoreMark/MHz |
| --- | ---: | ---: |
| coremark_sram_o2 | 2811669 | 3.556606 |
| coremark_sram_tuned | 2309196 | 4.330512 |
| coremark_ddr_o2_l20 | 2814600 | 3.552903 |
| coremark_ddr_o2_l60 | 2820760 | 3.545144 |
