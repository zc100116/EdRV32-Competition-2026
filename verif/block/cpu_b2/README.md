# CPU B2 environment

This bench implements cpu-testplan 2.2 and 3.8 using `edrv32_cpu_subsys`: the real
core, I$, D$ and CACHE_CTRL. The production wrapper contains wiring only; `RVC_EN`
is its only parameter. `irq_o` is the CACHE_CTRL level interrupt for PLIC source 6.
The bench holds APB and the three interrupt inputs inactive and advances `mtime_i`
once per system clock.

Source the installed tools before running from the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/b2_run.py cpu_smoke --rvc 0
python3 tools/cpu/b2_run.py cpu_smoke --rvc 1
python3 tools/cpu/b2_run.py r01
python3 tools/cpu/b2_run.py r02
python3 tools/cpu/b2_run.py r03
python3 tools/cpu/b2_run.py r04
python3 tools/cpu/b2_run.py r05
```

Every entry builds with `sw/Makefile`, `-O2`, C11 and the selected RV32IM[C]+Zicsr
ISA, links code/data in SRAM, and installs an eight-byte reset trampoline in ROM.
R-05 uses the existing `sw/apps/coremark` port and the recorded CoreMark submodule,
with `ITERATIONS=10`. Initialize the dependency with
`git submodule update --init third_party/coremark` before the first R-05 build.
BSP startup is reused; `sw/tests/cpu_perf/host.c` supplies B2 console/exit transport
and programs the eight HPM selectors to events 1–8 before entering `main`.

Logs are `build/cpu_b2/<test>/rvc<0|1>/{compile,run}.log`; software products are in
`build/sw/{cpu_smoke,cpu_b2_r01,...,coremark}/`. Verilator products for each RVC
configuration are reused in `build/cpu_b2/obj_rvc<0|1>/`. Every simulation includes
the existing AXI64 checker on both CPU master ports. A nonzero tohost status,
protocol error, simulation timeout or failed CoreMark CRC returns a nonzero exit.
The script defaults to 100,000,000 simulated cycles; use `--max-cycles` to change it.

## Memory and device transport

Both AXI ports instantiate `verif/common/edrv32_axi64_memory.sv` through a small
R-channel latency adapter. Both access the same sparse byte memory in
`edrv32_axi64_memory_pkg`; DDR and its uncached alias share physical storage.
The I-side write inputs are tied off. The model has random stalls disabled and
`delay_max=0`. `--read-latency N` configures deterministic AR-handshake to first-R
handshake latency (minimum 2, default 2 cycles with a ready receiver). Later burst
beats are consecutive when the receiver is ready. There is no DDR timing model.

The bench accepts byte-wide sparse hex: `+MEM_HEX=<absolute-address image>`, or
`+ROM_HEX=`, `+SRAM_HEX=`, `+DDR_HEX=` with region-relative offsets, respectively
0x00000000, 0x10000000 and 0x80000000. These are the images emitted by `tools/elf2mem.py`.
`@<hex-address>` selects the next byte address; subsequent tokens are byte values.
The standalone runner uses the three region images. To supply a custom full image,
invoke the built simulator directly with `+MEM_HEX=... +TOHOST=<hex symbol address>`
and optionally `+READ_LATENCY=N +TIMEOUT=N`. The image must include reset code at 0.

The test-only device register bank occupies 64 bytes at 0x40007000 in the system
APB device region. The common AXI memory stores its bytes; it is not a model of a
production peripheral. Its first word emits the low byte when the D-side AXI W
transaction is accepted. `b2_console` is a linker-defined symbol at that address.
`tohost` remains a linked SRAM object using `(status << 1) | 1`; the bench observes
its first committed low-word store through the core/cache interface. This observes
exit even when the cache line remains dirty. B2 uses the dedicated console BSP
because a host write to the ordinary BSP's cached `fromhost` is not coherent with
D$. The shared BSP and cache RTL are unchanged by the environment.

## Performance output

The bench hierarchically reads `u_dut.u_core.u_csr.cycle_r`, `instret_r`, the eight
`counter_r` counters and their selectors. `B2_TOTAL` and `window=total` cover reset
release through the committed exit store, including startup and console output.
`B2_WINDOW` reports cycles and retired instructions for the selected benchmark
window. `B2_HPM` reports all sixteen event counts; `B2_CSR_HPM` reports the actual
eight selected CSR counters alongside them. All sixteen event increments are
accumulated from `u_core.event_count_w`, as approved for this performance bench;
these observations do not determine functional PASS/FAIL. The total CSR counts begin
counting their selected events when `__wrap_main` programs each selector, so they
exclude the earlier startup events visible in the parallel total accumulator.

Windows begin at the retirement of `b2_perf_begin` and end just before retirement
of `b2_perf_end`; R-03 additionally uses `b2_perf2_begin/end` for multiplication.
CoreMark uses retirement of the entry PCs of `start_time` and `stop_time`. Thus its
B2 window includes the timing-function entry overhead, and its `Total ticks` value
comes from the port's cycle-CSR snapshots inside those functions. Events and
retirement counts have whole-cycle resolution when a marker retires alongside
another instruction. The CSR deltas and the parallel event accumulator cover the
same cycle boundaries.

| Test | Work inside the window | Interpretation |
|---|---|---|
| R-01 | 256 × 32 independent ALU pairs | IPC = instret/cycles; 16,384 ALU instructions plus loop overhead |
| R-02 | 256 × 64 dependent ALU instructions | Dependency-limited IPC; 16,384 ALU instructions plus loop overhead |
| R-03 window 0 | 256 × 16 load/add pairs | 4,096 load-use pairs; report cycles per pair |
| R-03 window 1 | 256 × 16 dependent mul/add pairs | 4,096 multiplication-use pairs; report cycles per pair |
| R-04 | 256 × 256 taken branches at distinct PCs | 65,536 branches exceed the 32-entry BTB; event 16 records mispredictions |
| R-05 | CoreMark, 10 iterations, SRAM | CRCs, ticks, 10 × 1,000,000 / ticks = CoreMark/MHz |

R-01–R-04 check their software results but do not assert performance thresholds;
formal numeric measurements belong to C-I3 after core integration. Cold cache and
predictor startup remain inside the windows. R-04 avoids a learned alternating
branch pattern: 256 distinct branches, eight bytes apart, continuously replace
each other's direct-mapped BTB entries.

For CoreMark's standard 2,000-byte performance seeds, the script checks the printed
list/matrix/state CRCs against the canonical `e714/1fd7/8e3a` values and emits
`B2_COREMARK iterations=10 CRC=PASS|FAIL cycles=N CoreMark/MHz=X`. The upstream
minimum ten-second reporting check is expected to report a short run with ten
iterations; the requested value is an engineering cycle-normalized measurement.
CRC checking is independent of that duration check. Compiler options printed by
the upstream port's static header describe its default RVC build; the actual
build command in the runner is authoritative for `--rvc 0`.

The YAML runner entries are rooted at this repository and require the optional
`runner` support in `tools/regress.py`: cpu_smoke in both RVC configurations and
R-05 CRC run in smoke; R-01–R-05 run in perf.

## Production file list

The coordinator should add `rtl/filelists/cpu_subsys.f` with:

```text
-f cpu.f
-f cache.f
../soc/edrv32_cpu_subsys.v
```

The B2 `files.f` already composes the existing CPU/cache lists with this wrapper
and the reused verification components, so it does not require the new production
file list to run.

## Acceptance commands

The environment was verified on the integration fixes through upstream `a9420fb`
(cherry-picked locally through `34c3219`) with the commands below. This validation
checks the environment and software entry points; it is not the C-I3 performance
baseline. Tools: Verilator 5.020 (Debian 5.020-1), xPack RISC-V GCC 15.2.0.

```sh
python3 tools/check/verilog_style.py rtl/
verilator --lint-only -Wall +define+SIM_MODE --top-module edrv32_cpu_subsys \
    -GRVC_EN=0 -F rtl/filelists/cpu.f -F rtl/filelists/cache.f rtl/soc/edrv32_cpu_subsys.v
verilator --lint-only -Wall +define+SIM_MODE --top-module edrv32_cpu_subsys \
    -GRVC_EN=1 -F rtl/filelists/cpu.f -F rtl/filelists/cache.f rtl/soc/edrv32_cpu_subsys.v
python3 tools/cpu/b2_run.py cpu_smoke --rvc 0
python3 tools/cpu/b2_run.py cpu_smoke --rvc 1
python3 tools/regress.py perf
make smoke
```

Style: 31 RTL files, zero warnings. Both top-level lint configurations and all
B2 simulator builds have zero warnings. Both cpu_smoke configurations passed;
perf passed all seven cases, including R-01–R-05. `make smoke` passed all 65
simulator runs (55 configurations), with zero failures. Regression logs are
`build/cpu_b2/{perf,smoke}.log` and `build/regress/{perf,smoke}/`; per-program
console/performance logs remain under `build/cpu_b2/<test>/rvc<0|1>/`.
