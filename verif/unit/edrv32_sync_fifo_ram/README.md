# V-P2 RAM FIFO implementation and verification

`edrv32_sync_fifo_ram` and `edrv32_async_fifo_ram` keep their storage behind
external one-cycle enabled-read RAM ports. A held head and the RAM output form
two elastic prefetch slots. Consumption pointers determine capacity, so the
advertised DEPTH includes prefetched items. Fetch pointers advance independently;
reads only target already-written, locally visible entries. The asynchronous
controller synchronizes only registered Gray write and consumption pointers.
No payload or RAM reset, collision-result dependency, or RTL protocol checks
were added. Interface and reset constraints are in `rtl/common/README.md`.

VIN's two 512x288 write FIFOs and memory-source buffer use
`edrv32_ram_vin_wfifo`. The memory-source buffer is now 512 entries, with zero
in the upper 32 bits. The small camera-item and burst-owner behavioral FIFOs
remain. DISP's 512x256 scan FIFO uses `edrv32_ram_disp_scan`.
VIN channel and memory-source stop completion use their existing occupancy
counters to include entries whose initial RAM prefetch has not finished;
consumer valid alone no longer means the complete FIFO is empty.

## Reproduce verification

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py \
    rtl/common/edrv32_sync_fifo_ram.v rtl/common/edrv32_async_fifo_ram.v \
    rtl/media/vin rtl/media/disp
verilator --lint-only -Wall -DSIM_MODE rtl/common/edrv32_sync_fifo_ram.v
verilator --lint-only -Wall -DSIM_MODE rtl/common/edrv32_async_fifo_ram.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include --top-module edrv32_vin \
    rtl/media/vin/*.v rtl/common/edrv32_async_fifo.v rtl/common/edrv32_sync_fifo.v \
    rtl/common/edrv32_sync_fifo_ram.v rtl/common/edrv32_dma2d_rd.v \
    rtl/common/edrv32_dma2d_wr.v rtl/tech/edrv32_ram_vin_wfifo.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include --top-module edrv32_disp \
    rtl/media/disp/*.v rtl/common/edrv32_async_fifo_ram.v \
    rtl/common/edrv32_dma2d_rd.v rtl/common/edrv32_cdc_sync_bit.v \
    rtl/common/edrv32_cdc_pulse.v rtl/common/edrv32_cdc_gray_cnt.v \
    rtl/common/edrv32_cdc_handshake.v rtl/tech/edrv32_ram_disp_scan.v
for tier in smoke full; do
    for unit in edrv32_sync_fifo_ram edrv32_async_fifo_ram \
        vin_ch vin_dvp vin_fmt vin_msrc vin_p1_arb vin_regs \
        disp_control disp_reader disp_regs disp_scan disp_timing disp_tmds_enc; do
        make "$tier" REGRESS_ARGS="-j 1 --path verif/unit/$unit" || exit $?
    done
done
```

The new tests use uninitialized, unreset behavioral RAMs with enabled
one-cycle reads. Each accepted output is compared against its sequential input
item number. They check empty/full boundaries, writes held against full,
head stability during stalls, pointer wrap, reset with prefetched data,
consecutive read throughput from a full backlog, and 2048-cycle simultaneous
producer/consumer throughput where the producer is at least as fast and DEPTH
is at least 16. Each case also transfers 12000 items under randomized valid
and ready. Depths 2, 16 and 512 are covered. The asynchronous test uses random
initial clock phases and write/read frequency ratios 0.3, 0.5, 1, 2 and 3.
Both new tests run on Verilator and Icarus. Existing media testbench sources
are unchanged; only the two VIN dependency filelists require updates.

Measured 2026-10-28: style checked 16 RTL files with 0 warnings; both new
controllers and both media tops passed SIM_MODE `-Wall` RTL lint with 0 warnings.
All 14 unit directories passed smoke and full: 16 simulator runs in each tier,
32/32 PASS in total (12 existing Verilator media units and 4 new FIFO runs per
tier). Verilator is 5.020; Icarus is 12.0. VIN channel/memory-source smoke was
repeated after the occupancy-based stop change and passed.

Raw logs: `build/regress/{smoke,full}/unit/<unit>/<simulator>/`;
top-level lint logs: `build/v-p2/{vin,disp}-lint.log`.

## Resource reference

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/unit/edrv32_sync_fifo_ram/synth.py
```

Yosys 0.70+219, git sha1 5053d0e26, Clang 21.1.8. RAM wrappers are blackboxes
through `read_verilog -lib`. VIN follows V-R1's hierarchical
`synth -noabc; abc -lut 6 -dress` flow. DISP follows V-R2's flattened
`synth -flatten -lut 4 -run begin:fine; techmap; opt; abc -lut 4` flow.
These are generic logic references, without a Pango device, speed grade,
physical constraints or DRM implementation; PDS resource/timing results remain
outstanding. Generated scripts, source commit, tool version, netlists, logs
and totals are in `build/v-p2/{vin,disp}/`.

| Measurement | Baseline LUT | Current LUT | Baseline FF | Current FF |
|---|---:|---:|---:|---:|
| VIN hierarchical LUT6 | 7097 | 8829 | 3644 | 5651 |
| DISP flattened LUT4 | 3920 | 3947 | 1519 | 1786 |

VIN has three RAM blackboxes; DISP has one. VIN's V-R1 reference blackboxed
**all** FIFO arrays, including the two 36x16 camera FIFOs and 1x8 owner FIFO;
the current measurement keeps those 1160 storage bits in logic. Its FF increase
therefore includes those bits, 832 bits of prefetched head data, and 15 control
bits. VIN LUT6 increases by 1732, FF by 2007. DISP LUT4 increases by 27, FF by
267 (256 head-data bits and 11 control bits). DISP's V-R2 reference retained
its FIFO as an unmapped memory, so storage was already excluded from FF/LUT
counts. Baseline sources: `verif/unit/vin_ch/README.md` and
`verif/unit/disp_reader/README.md`; the coordinator supplied these locations
in response to the first V-P2 ask. A second ask approved using the existing
VIN occupancy counters for stop completion instead of consumer valid.

## Coordinator filelist additions

Only the coordinator modifies shared `rtl/filelists` files. Add paths relative
to `rtl/filelists/`:

```text
# vin.f: retain existing behavioral FIFO entries for the small FIFOs.
+incdir+../include
../common/edrv32_sync_fifo_ram.v
../tech/edrv32_ram_vin_wfifo.v

# disp.f: add RAM controller and storage dependencies.
+incdir+../include
../common/edrv32_async_fifo_ram.v
../tech/edrv32_ram_disp_scan.v
```
