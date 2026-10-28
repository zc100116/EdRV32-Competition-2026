# SRAM UART monitor

Implements SoC specification v0.5 section 7.5: ROM startup information followed
by a persistent SRAM menu. UART is 115200 8N1, with its fractional divisor
calculated from SYSCTRL `CLK_SYS_HZ`. The monitor does not write `SIM_EXIT`.

## Build and size

From the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/coremark
make -C sw PROGRAM=bootloader
make -C sw PROGRAM=monitor MEMORY=sram
riscv-none-elf-size build/sw/bootloader/bootloader.elf build/sw/monitor/monitor.elf
python3 sw/apps/monitor/run_spike.py
```

Outputs are `build/sw/{bootloader,monitor}/` ELF, disassembly, map, raw `.bin` and
`rom.hex`/`sram.hex`/`ddr.hex`.
Load bootloader ROM and monitor SRAM images together. UART download accepts the
raw application image described in `../../boot/README.md`.

Measured with xPack GCC 15.2.0, `-O2`, `rv32im_zicsr_zifencei/ilp32`:

| Image | text | data | bss | Section total | Capacity |
|---|---:|---:|---:|---:|---:|
| bootloader | 4584 | 0 | 0 | 4584 | 16384 ROM bytes |
| monitor | 19492 | 8 | 2116 | 21616 | 65536 SRAM bytes |

B1 verification source commit: **`9a4c485`**. The monitor's aligned SRAM extent
is `0x10000000..0x10005484` (21636 bytes), with stack top `0x10010000`.
Build logs are `build/board_b1/bootloader.log` and `build/board_b1/monitor.log`.
The 19500-byte monitor binary fits below the bootloader's final 4 KiB stack area
(61440-byte download limit), and its BSS ends 43900 bytes below stack top.

Sizes are bytes, with constants included in text. The SRAM linker includes
alignment between sections; stack top is at SRAM end. Build metadata records the commit, compiler and CFLAGS, excluding host include
paths; changing these strings can change text size. `Build commit` and `Compiler version` are Makefile string macros.
`Compiler flags` is the exact CFLAGS string used for authored C and the shared
port, including `-march` (also printed separately as `ISA`). The pre-existing
coordinator exception removes `-Werror` only from unmodified third-party C;
GCC's upstream `core_list_join.c` maybe-uninitialized warning remains visible.
Only upstream `core_main.c` gets `-Dmain=coremark_main` so the monitor can reuse
`iterate()` without retaining the upstream standalone entry point.

## Menu and input protocol

Every completed operation returns to this exact line:

```text
Menu: 1=CoreMark 2=Peripheral tests 3=System info
```

Send one menu character, without an Enter:

| Character | Operation |
|---|---|
| `1` | CoreMark; then send decimal iterations and CR or LF, or only CR/LF for default 10 |
| `2` | GPIO walk/button observation, CLINT interrupt, then I2C scans of both ports |
| `3` | System information, cache configuration and HPM event encoding table |

CoreMark accepts decimal 1..4294967295. Malformed, zero or overflowing input
prints `Input error` and returns to the menu. CR/LF between menu commands is
ignored. An Enter immediately after menu command `1` chooses the default;
therefore send the numeric response after receiving `Iterations input`.
For SC-08: send byte `3`, await the next `Menu`, then send bytes `1`, `1`, `\n`
(hex `31 31 0a`); await the next `Menu` after `CoreMark result`.

`Boot mode` reads the coordinator-confirmed scratch convention: bootloader sets
SYSCTRL `SCRATCH1=0` for SRAM preload, `1` for UART download before jumping.
SCRATCH0 retains its existing request/consume protocol. Direct SRAM execution
without a bootloader does not establish a new boot-mode handoff.
ROM/SRAM sizes come from generated `soc_map.h`; cache sizes (8 KiB each),
2 ways, 32-byte lines and D-cache write-back/write-allocate come from cache-spec
2.1, explicitly reported as constants rather than register discovery.

## CoreMark, CRC and HPM

All algorithms and `iterate()` are compiled directly from pinned
`third_party/coremark`; the timing functions, volatile seeds and initialization
port are reused from `../coremark/`. The monitor initializes the three algorithm
blocks (2000 total bytes, 666 bytes per algorithm) before each measured run.
The performance seeds are `(0,0,0x66)`.

The upstream known-id 3 reference CRCs are seed `e9f5`, list `e714`,
matrix `1fd7`, state `8e3a`. Each field is compared separately and contributes
to `CRC result`; `CoreMark result` combines both rounds. Per coordinator
correction to the task, `CRC final` is recorded without PASS/FAIL: it depends
on the iteration count and upstream supplies no fixed reference. Observed
Spike final CRCs are `e714` at 1 iteration and `fcaf` at 10 iterations.

There are 8 hardware HPM counters (3..10), so there are **two complete runs**
at the selected iteration count: events 1..8, then 9..16. Each run starts with
freshly initialized algorithm data and explicitly programs `mhpmevent3..10`.
`mcountinhibit` freezes CY, IR and HPM together while clearing/reading counters;
the shared CoreMark timing port reads cycle CSR snapshots while frozen.
Only the `iterate()` window and start/stop call overhead are counted, excluding
initialization, UART printing, CRC validation and metric arithmetic.
HPM remains inhibited outside the measured window, while CY/IR resume.
The monitor owns these counters and resets CY/IR at each measurement.
No cache maintenance is added between runs; their cache warmness can differ.

All ratios are fractions (not percentages), printed with three decimal places,
truncated. A zero denominator prints `N/A (denominator=0)`, not a fabricated
numeric rate. Let C1/C2 be the measured cycles in each round, I1 be round-1
retired instructions, and E[n] be the HPM count for event code n:

| Key | Formula |
|---|---|
| `Iterations/Sec` | iterations × SYSCTRL CLK_SYS_HZ / C1 |
| `CoreMark/MHz` | iterations × 1000000 / C1 |
| `IPC` | I1 / C1 |
| `Dual retire ratio` | E[1] / C1 |
| `Load-use stall ratio` | E[9] / C2 |
| `Divide stall ratio` | E[10] / C2 |
| `Device wait ratio` | E[11] / C2 |
| `Frontend empty ratio` | E[12] / C2 |
| `Branch mispredict rate` | E[16] / E[4] |
| `I-cache MPKI` | E[13] × 1000 / I1 |
| `D-cache MPKI` | E[14] × 1000 / I1 |

Event 1 measures dual **retirement**, so `Dual retire ratio` is the retirement
side indicator for dual-issue effectiveness, not a direct issue-stage rate.
Mispredict rate and MPKI combine equivalent workloads from different rounds;
they are not counts from one simultaneous 16-event window. Event 4 includes
branches **and jumps**, matching the denominator for event 16.
`Score status` explicitly identifies runs shorter than 10 seconds as diagnostic
runs, following upstream's duration requirement for published scores.

## Peripheral development values (pending user confirmation)

GPIO initializes all pins as inputs at boot. The test drives bits **1..4**
(`0x001e`) as a walking LED pattern, each for **100 ms** measured by CLINT;
bit **0** is the active-low button (same convention as bootloader). Each step
prints input levels and pressed state, then outputs are cleared and GPIO returns
to inputs. LED/button verification is observational, so the test prints
`GPIO result: OBSERVE...` rather than claiming an automatic board-level PASS.
Board GPIO mapping remains unassigned in sys-subsys-spec 2.7.

CLINT sets `mtimecmp=mtime+4096` cycles, enables MTIE and MIE, checks
`mcause=0x80000007`, records interrupt arrival time, disarms `mtimecmp` to all
ones and restores the previous trap vector/interrupt enables. It prints delay,
elapsed time, lateness and interrupt count. An unexpected trap prints its cause
and FAIL, then stops; no timeout or alternate interrupt path is added.

I2C scans **both ports**, at **100 kHz**, legal 7-bit unicast addresses
**0x08..0x77** (reserved ranges omitted). Each transaction sends only the
write-direction address byte with START and STOP; no device register data is
written. Print every ACK address and per-port device count. Zero devices is an
observation; no expected board device inventory is assumed.

## Complete UART key contract

Each structured field has exactly one `Key: Value` line terminated by CRLF.
Integers are unsigned decimal, hex values have `0x` and 8 lowercase hex digits,
and rates have 3 decimal places. ASCII logo and existing boot download/handoff
messages remain unstructured. Keys are case-sensitive and contain no padding
before `:`. The following are **all production keys**:

Boot and monitor system information:

```text
CHIP_ID
CLK_SYS_HZ
ROM bytes
SRAM bytes
I-cache bytes
D-cache bytes
MEM_READY
Boot mode
Build commit
Compiler version
```

Menu, system configuration and input:

```text
Monitor
Menu
Iterations default
Iterations input
Input error
Cache ways
Cache line bytes
D-cache policy
Cache configuration source
Compiler flags
ISA
HPM event 00
HPM events 17-31
System info result
```

CoreMark and per-round reporting (the CRC and round keys repeat twice):

```text
Iterations
HPM rounds
HPM round
HPM first event
HPM last event
HPM round cycles
HPM round instructions
CRC seed
CRC list
CRC matrix
CRC state
CRC final
CRC seed result
CRC list result
CRC matrix result
CRC state result
CRC result
Cycles
Instructions
Iterations/Sec
CoreMark/MHz
Score status
IPC
Dual retire ratio
Load-use stall ratio
Divide stall ratio
Device wait ratio
Frontend empty ratio
Branch mispredict rate
I-cache MPKI
D-cache MPKI
CoreMark result
```

All 16 HPM keys, ordered by event code. System information uses these same keys
to print event **codes**; CoreMark uses them to print 64-bit event **counts**:

```text
HPM 01 dual retire
HPM 02 single retire
HPM 03 zero retire
HPM 04 branches
HPM 05 pair RAW
HPM 06 pair structural
HPM 07 pair slot1 type
HPM 08 pair missing slot1
HPM 09 load-use stall
HPM 10 divide stall
HPM 11 device wait
HPM 12 frontend empty
HPM 13 I-cache miss
HPM 14 D-cache miss
HPM 15 dirty writeback
HPM 16 branch mispredict
```

Peripheral fields (LED fields repeat per step, address fields per ACK, device
counts per port; `Trap cause` appears only for an unexpected trap):

```text
GPIO LED mask
GPIO button bit
GPIO LED output
GPIO input
GPIO button pressed
GPIO result
Timer requested cycles
Timer elapsed cycles
Timer lateness cycles
Timer mcause
Timer interrupts
Timer result
Trap cause
I2C SCL Hz
I2C first address
I2C last address
I2C port
I2C ACK address
I2C devices
I2C result
```

The software-only Spike harness additionally prints `Spike iterations`,
`Spike ticks`, `Zero denominator`, `Wide count`, `Spike formula result`; these
are not production monitor fields.

## Verification and limits

`run_spike.py` builds a separate ELF under `build/sw/monitor-spike/`, using
the existing SRAM/HTIF Spike flow, then executes the real upstream algorithms
at 1 and 10 iterations and compares all four reference CRCs. It also checks
the exact UART strings for score normalization and every derived metric against
hand-computed values, including fractional rounding, zero denominator and a
counter above 32 bits. A nonzero `tohost` status fails the command.
Its logs are `build/sw/monitor-spike/{build,console}.log`.

On source commit `ca52144`, both build commands above passed; authored sources
produced zero warnings under `-Werror`, and the unchanged upstream source
produced the single documented warning. The standalone CoreMark target also
built successfully after the port change (`make -C sw PROGRAM=coremark MEMORY=sram`,
log `build/sw/monitor-spike/standalone-build.log`). Spike CRC checks passed for
both iteration counts; recorded ticks were 288206 and 2882012 respectively
(Spike instruction-model observations, not SoC timing). All score/metric string
checks passed (`Spike formula result: PASS`). Source whitespace/100-column
checks, `git diff --check`, and a comparison of all 92 production keys against
this README passed.

No fake peripheral or HPM implementation is used by this check. Actual boot,
UART menu, HPM event semantics and external devices require SC/board testing;
SC-01 and SC-08 are assigned to S-I3, outside this task. No Verilator or full
repository regression is run here. Authored C retains C11 and
`-Wall -Wextra -Werror`; the existing Verilog-only style/lint tool has no RTL
changes to inspect. The coordinator has explicitly authorized existing driver
APIs until the separate register generator task supplies generated offsets.
This task adds no driver/BSP register definitions or register addresses.
