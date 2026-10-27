# VIN V-R1 RTL and unit verification

Implementation: `rtl/media/vin/edrv32_vin.v`, with `dvp`, `fmt`, `msrc`, `ch`,
`p1_arb`, and `regs` submodules. CH0 uses the external PIX ports; CH1 loops the
same channel pipeline ports back locally. No CH2 RTL is instantiated.

The frontends serialize DATA/EOL/SOF/EOF items through 36-bit async FIFOs.
The formatter retains the configured frame's final word until input EOF, so
late truncation and frontend loss reach the channel's completion metadata.
Each channel holds one pending descriptor in addition to the active DMA.
Soft reset drains DMA traffic before clearing memory-domain state; it does not
reset either side of a frontend FIFO independently.

## Unit verification

All tests are self-checking and belong to both smoke and full:

| Directory | Checks |
|---|---|
| `vin_dvp` | High-byte-first pixels, low-halfword-left packing, half pixels, odd pixel lines, coincident EOL/EOF, clock ratios, FIFO overflow and recovery |
| `vin_fmt` | Disable, discard two frames, zero padding, line/frame truncation, dimension capture, frame IDs, incomplete and invalid-size events, output stalls, 100 random malformed frames |
| `vin_ch` | Byte memory oracle, partial strobes, rings 2/3/4, busy-slot skip, EN capture, pending frame during B stalls, bus error, overflow/slot rollback, memory backpressure, ABORT, all busy masks for rings 2/3/4, first-word overflow after an exactly full frame |
| `vin_p1_arb` | Whole-burst availability, stalled AW stability, round robin, contiguous W ownership, ordered B routing |
| `vin_msrc` | Row/page address oracle, two-line reservation, continuous RREADY under output stalls, START while busy, partial row beats, read error, invalid size, ABORT |
| `vin_regs` | Reset values, write masks, zero PSTRB whole-word writes, read-only completion fields, reserved/CH2 offsets, IRQ/RW1C, PERF and reset |

From the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/media/vin
verilator --lint-only -Wall +define+SIM_MODE -Irtl/include \
    --top-module edrv32_vin rtl/media/vin/*.v \
    rtl/common/edrv32_async_fifo.v rtl/common/edrv32_sync_fifo.v \
    rtl/common/edrv32_dma2d_rd.v rtl/common/edrv32_dma2d_wr.v
for vin_tier in smoke full; do
    for vin_unit in dvp fmt ch p1_arb msrc regs; do
        make "$vin_tier" REGRESS_ARGS="-j 1 --path verif/unit/vin_${vin_unit}"
    done
done
```

Simulator: Verilator 5.020. Results: style/lint zero warnings; six PASS in each
tier. Logs: `build/regress/{smoke,full}/unit/vin_*/verilator/`.

## Storage handoff for V-P1

| Instance | Count | Width | Depth | Required read interface |
|---|---:|---:|---:|---|
| `u_camN.u_items` | 2 | 36 | 16 | Independent clocks, FWFT ready/valid; head stable until accepted |
| `g_channel[N].u_channel.u_write_fifo` | 2 | 288 (256 data + 32 strobe) | 512 | Single clock, FWFT ready/valid; head stable until accepted; one beat per cycle |
| `u_msrc.u_buffer` | 1 | 256 | 256 | Single clock, FWFT ready/valid; head stable until accepted |
| `u_p1.u_owners` | 1 | 1 | 8 | Single clock, FWFT ready/valid; small control FIFO |

FWFT means zero additional latency at the RTL consumer interface. A synchronous
RAM IP can implement its physical one-cycle read behind a prefetched output
stage; that latency must be hidden by the wrapper. Current common FIFOs do not
accept a write when full even if a pop occurs on the same edge. The memory-source
buffer uses a power-of-two depth of 256 because the common FIFO requires it;
this exceeds the specified minimum of 160 beats.

## Suggested `rtl/filelists/vin.f`

Paths are relative to `rtl/filelists/`:

```text
+incdir+../include
../common/edrv32_async_fifo.v
../common/edrv32_sync_fifo.v
../common/edrv32_dma2d_rd.v
../common/edrv32_dma2d_wr.v
../media/vin/edrv32_vin_dvp.v
../media/vin/edrv32_vin_fmt.v
../media/vin/edrv32_vin_msrc.v
../media/vin/edrv32_vin_ch.v
../media/vin/edrv32_vin_p1_arb.v
../media/vin/edrv32_vin_regs.v
../media/vin/edrv32_vin.v
```

## Coordinator clarifications

1. Odd complete pixels cannot form a word and are discarded; the line is
   incomplete. Empty lines use EOL items. FIFO item encoding is internal.
2. SOFT_RST first aborts/drains DMA, then resets memory-domain state and all
   architectural registers. DVP and async FIFO external resets stay unchanged.
3. Overflow drains complete bursts, then aborts and discards uncommitted tails
   shorter than a burst, restoring the allocation pointer.
4. ENABLE clear finishes an already started normalized frame. Formatter output
   uses ready/valid so PIX input stalls are absorbed at the async FIFO.
5. Each source's first output frame ID is zero, including after SOFT_RST.
6. SRC=3 is checked against every source's frame boundary; simultaneous source
   boundaries contribute individually to PERF15.
7. Pending SOF precedes its EOF. Raw frames arriving while an older frame's
   boundaries are still pending are skipped, without overwriting those items.
   Asked as `msg_512448a1c7ce`; no answer within ten minutes, so the task's
   authorized recommended behavior was used. Directed tests cover both a
   pending EOF and a pending SOF/EOF pair across later raw frames.

## Resource measurement

The repository's `tools/synth/yosys_synth.py` CLI currently accepts only its CPU
and system targets. `synth.py` in this directory applies the same hierarchical
`synth -noabc; abc -lut 6 -dress` flow to VIN without changing shared tools or
filelists:

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/unit/vin_ch/synth.py full
python3 verif/unit/vin_ch/synth.py logic
```

`logic` substitutes a blackbox for each FIFO array, preserving real pointer,
full/empty, occupancy and CDC logic. Both modes preserve hierarchy and use the
same VIN RTL; generic LUT6 mapping does not model Pango carry chains or DRM.
Logs, generated Yosys scripts, netlists, tool versions and source commits are
in `build/vin/synth/{full,logic}/`. These are reference estimates, not PDS
utilization or timing results.

Measured RTL/test commit: `0e98fd07ccc5653a0c6b62abde87e8a994451d3b`.
Tool: Yosys 0.70+219, git sha1 5053d0e26, Clang 21.1.8. No device/speed-grade or
clock constraint is modeled by this generic LUT6 flow. The storage-free run is
**7,097 LUT6 and 3,644 FF**, including FIFO control and CDC logic. This exceeds
the specification's 4K LUT development target; resource compliance is not
claimed. DRM replacement, Pango carry-chain mapping and PDS measurement remain
for the subsequent integration/resource work.

The six FIFO instances contain 361,608 storage bits in total
(`2*512*288 + 256*256 + 2*16*36 + 8`). Storage is not reset. The generic full
run maps these behavioral arrays to FFs and muxes rather than to Pango DRM.

| Measurement at the RTL commit above | LUT6 | FF |
|---|---:|---:|
| Full behavioral FIFO storage | 156,102 | 365,252 |
| FIFO arrays blackboxed, real control retained | 7,097 | 3,644 |

Both commands completed successfully. `build/vin/synth/full/summary.txt` and
`build/vin/synth/logic/summary.txt` contain these totals. The FF difference is
exactly the 361,608 modeled storage bits. The full mapped netlist is a generated
build artifact, not a deliverable FPGA memory implementation.
