# V-R2 DISP RTL / unit verification report

## Implementation and source revision

RTL/source revision: `4c1e7dd460c2910ff91c2ce479b22ff0b53d3829`.
Implementation commits:

- `e9fdb7df7d51c596185716164cc711edaa6e205e`: DISP RTL and initial five units.
- `4c1e7dd460c2910ff91c2ce479b22ff0b53d3829`: reset/drain CDC and control unit.

The implementation uses the requested top plus timing, TMDS encoder, reader,
scan, register and control-CDC submodules. `edrv32_dma2d_rd` is instantiated at top level
with OUTSTANDING=4; reader owns line descriptors and frame scheduling.
No files outside the assigned RTL and unit-test directories were changed.

| Files | Purpose |
|---|---|
| `rtl/media/disp/edrv32_disp.v` | APB/P0/TMDS top, DMA, scan FIFO and common CDC instances |
| `rtl/media/disp/edrv32_disp_control.v` | ENABLE/frame-request acknowledgement and reset-drain CDC |
| `rtl/media/disp/edrv32_disp_timing.v` | Fixed continuous 1650x750 raster, 1280x720 active |
| `rtl/media/disp/edrv32_disp_tmds_enc.v` | Legacy three-stage TMDS algorithm, explicit arithmetic widths |
| `rtl/media/disp/edrv32_disp_reader.v` | Queued frames, per-line descriptors, occupancy reservation |
| `rtl/media/disp/edrv32_disp_scan.v` | RGB565 expansion, whole-group black, cross-frame debt |
| `rtl/media/disp/edrv32_disp_regs.v` | Surface handoff, IRQ/ERR, performance and local reset |
| `verif/unit/disp_{timing,tmds_enc,scan,reader,regs,control}/{tb.sv,files.f,test.yaml}` | Six self-checking unit tests |
| `verif/unit/disp_reader/resource.ys` | Reproducible generic LUT4 synthesis with FIFO memory retained |
| `verif/unit/disp_reader/README.md` | This report |

## Verification

Environment: `. ~/.local/opt/edrv32/env.sh`;
Verilator `5.020 2024-01-01 rev (Debian 5.020-1)`.
All Verilator builds use `-j 1`; tests run sequentially.
The added control test's first full build hit its 240-second compilation limit
while other workers were compiling. Its test timeout is now 600 seconds;
the same Verilator flow is used. Initial evidence is retained in
`build/disp_control_compile_timeout.log`.

```sh
python3 tools/check/verilog_style.py rtl/media/disp
verilator --lint-only -Wall --top-module edrv32_disp \
    rtl/media/disp/*.v \
    rtl/common/edrv32_dma2d_rd.v \
    rtl/common/edrv32_async_fifo.v \
    rtl/common/edrv32_cdc_sync_bit.v \
    rtl/common/edrv32_cdc_pulse.v \
    rtl/common/edrv32_cdc_gray_cnt.v \
    rtl/common/edrv32_cdc_handshake.v
for tier in smoke full; do
    for name in timing tmds_enc scan reader regs control; do
        make "$tier" REGRESS_ARGS="-j 1 --path verif/unit/disp_${name}" || exit $?
    done
done
```

Style: 7 files, 0 warnings; top-level `-Wall` lint: exit 0, no warnings.
All six smoke and six full tests passed (12/12 total).
Raw logs: `build/disp_style.log`, `build/disp_lint.log`, and
`build/regress/{smoke,full}/unit/disp_<name>/verilator/{compile,run}.log`.

| Unit | Checked behavior | Smoke | Full |
|---|---|---|---|
| timing | Every cycle of two frames; all sync/active/porch boundaries, coordinates, frame/VBlank pulses and totals | PASS | PASS |
| tmds_enc | All byte values, all control symbols, 20K random symbols, both disparity signs, blanking reset; independent serial encoder updates disparity from emitted symbol popcount | PASS | PASS |
| scan | Pixel order/expansion, all 16 pixels black on miss, late arrival mid-group, simultaneous missing/discard, cross-frame and disabled debt, one underflow event per frame | PASS | PASS |
| reader | Every descriptor of five frames (3600 lines), stride/base latching, 79/80 free threshold, full FIFO, pointer wrap, three queued requests, simultaneous enqueue/start, local count clear | PASS | PASS |
| regs | Defaults, aligned fields, unknown offsets, frame/switch/release, RW1C/set priority, both error codes, PERF counters and deferred reset/baselines | PASS | PASS |
| control | Sixty in-flight disables, 36 short ENABLE pulses, three overlapping stop requests, three clock ratios | PASS | PASS |

Module-level `verif/block/disp` verification belongs to the independent worker
and was not run here.

## Resource reference and storage

```sh
yosys -Q -T -s verif/unit/disp_reader/resource.ys > build/disp_resource.log
```

Yosys `0.70+219 (git sha1 5053d0e26, Release, Clang 21.1.8)`.
Generic 4-input LUT mapping, flattened full DISP including common DMA and CDC;
no Pango device, speed grade or clock constraint is applied.
The FIFO remains one `$mem_v2` cell: its storage is excluded from LUT/FF counts,
while FIFO pointers and synchronizers are included.

| Item | Reference count |
|---|---:|
| Generic LUT4 | 3920 |
| FF (all DFF/DFFE/SDFF variants) | 1519 |
| FIFO memory | 512 x 256 = 131072 bits = 16 KiB |
| Other inferred memories | 0 |

Raw results: `build/disp_resource.log`, `build/disp_resource.json`.
The LUT4 reference exceeds the spec's 2.5K LUT target; it does not establish a
Pango LUT result. PDS mapping/resource and timing measurements remain outstanding.
There is no previous DISP RTL resource baseline in this repository.
The scan FIFO currently uses the authorized common behavioral implementation;
the coordinator will replace its storage implementation in V-P1.

## Suggested `rtl/filelists/disp.f`

Entries below are relative to `rtl/filelists/`, consistent with existing lists.
The coordinator owns creation of this file and must avoid duplicate common
sources when composing subsystem lists.

```text
../common/edrv32_cdc_sync_bit.v
../common/edrv32_cdc_pulse.v
../common/edrv32_cdc_handshake.v
../common/edrv32_cdc_gray_cnt.v
../common/edrv32_async_fifo.v
../common/edrv32_dma2d_rd.v
../media/disp/edrv32_disp_control.v
../media/disp/edrv32_disp_timing.v
../media/disp/edrv32_disp_tmds_enc.v
../media/disp/edrv32_disp_scan.v
../media/disp/edrv32_disp_reader.v
../media/disp/edrv32_disp_regs.v
../media/disp/edrv32_disp.v
```

## Coordinator questions and confirmed interpretations

1. **Scan BUSY crossing:** do not add a scan-active level CDC. PERF0 increments
   at the last visible pixel of each scanned frame. BUSY compares the local
   received-request count against synchronized PERF0 (both adjusted for local
   reset baselines), in addition to reader activity/backlog.
2. **Debt after disabling:** debt repayment continues in blanking and unscanned
   frames; only normal display reads depend on frame enable. Disabled frames
   create no new underflow.
3. **Local SOFT_RST:** stop issuing new frame requests, drain all requested
   frames, then reset memory-domain registers/status. Keep FIFO pointers and
   raw crossed counters intact; clear PERF0-2 via baseline subtraction.
4. **Drain completion:** BUSY also includes FIFO write count unequal to the
   synchronized read count, so IDLE includes final debt/data drainage.
5. **In-flight request during SOFT_RST:** replace the frame-request pulse CDC
   with `edrv32_cdc_handshake` (acknowledgement on the edge receiving/counting
   the request). Synchronize `scan_live = enable_pix || !frame_req_ready` to
   memory with `edrv32_cdc_sync_bit`, and include it in BUSY/reset drainage.
   This supersedes the original frame-request pulse-only boundary; the
   coordinator is updating X6; it provisionally authorized this implementation
   while obtaining the user's final specification confirmation.
6. **Consecutive ENABLE/SOFT_RST before scan_live returns:** Orca question
   `msg_43c520df0325` received no answer within 600000 ms. Following the Task's
   explicit ten-minute fallback, implement the proposed explicit stop handshake:
   every falling memory-domain ENABLE starts a memory-to-pixel handshake;
   pixels acknowledge only with synchronized ENABLE=0 and no outstanding frame
   request handshake. Pending stop state holds BUSY until the round trip returns.
   This also handles rapid ENABLE/ABORT and overlapping disables without a
   software timing precondition. The coordinator must register the stop handshake
   in X5/X6 alongside the previously agreed frame-request/live changes.

Items 1-4 are coordinator-confirmed clarifications; item 5 is provisionally
authorized by the coordinator; item 6 is the explicitly
authorized timeout assumption from the Task. The coordinator owns the
corresponding specification updates. No new RTL error codes or timeout logic were
introduced.
