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
python3 verif/block/sys_cpu/run.py perf
python3 verif/block/sys_cpu/check_style.py
```

Each manifest invokes the same runner. SC-01/02/03/06 and the SC-07 CRC run are
`smoke`; SC-04/05 are `full`; the four SC-07 measurement runs are `perf`.
The runner builds through `sw/Makefile` and uses one Verilator binary with
`--timing -Wall +define+SIM_MODE -j 2`; tests run serially. No repository-wide
regression is invoked. Software, build commands, simulation commands and UART
logs are under `build/sys_cpu/`.

The default software ELF byte images are packed into sparse, little-endian
64-bit words for the ROM/SRAM technology wrappers. Only file-backed ELF bytes
are loaded; absent words remain uninitialized, and the application startup owns
BSS initialization. The ROM is the S-W1 bootloader; all applications enter
through its banner, MEM_READY check, UART drain and FENCE.I handoff. The bench
finishes only when SYSCTRL asserts SIM_EXIT, requiring code zero. The runner
also checks the ROM UART messages and, for CoreMark, all three algorithm CRCs.

SC-04 runs twice: button-selected download with no SRAM preload, and a preloaded
application that sets SCRATCH0 and requests SOC reset before download. The peer
waits for the readiness message and sends a little-endian length and the actual
`sc04` flat binary at 115200 baud. SC-03 drives GPIO bit 1 only after the
software's SCRATCH1 readiness marker. SC-05 checks eight register writes on
each SCCB peer and continuously checks that the unselected port is released.

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
