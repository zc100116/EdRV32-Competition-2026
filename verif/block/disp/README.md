# DISP v0.3 independent module verification

The DUT is compiled through `rtl/filelists/disp.f`. Neither testbench reads or
forces DUT hierarchy. The frozen APB/AXI/TMDS ports, common protocol checker and
TMDS receiver are the only DUT connections. No DISP RTL source was read while
implementing these tests.

After `. ~/.local/opt/edrv32/env.sh`, run serially:

```sh
python3 verif/block/disp/blend_ref.py
python3 tools/regress.py smoke -j 1 --path verif/block/disp
python3 tools/regress.py full -j 1 --path verif/block/disp
```

Both YAML entries use `group: verif/block/disp`, since both runners share
`build/disp/`. D-I1 measured DS-01 at 64 seconds and DS-03 at 65 seconds before
retiering. Six-frame reference generation/comparison also reached 106 seconds.
Under CLAUDE.md 9.1 and Task D-I1, smoke runs the existing Python reference
self-test; full runs the Python/SV frame comparison and all DS-01–19
(75 complete raster instances), including
all former smoke cases. No frames, seeds, variants or pixel checks are removed.
The regression tool also selects the reference smoke entry for full.
All tops build with `--timing -Wall -j 1`.
All simulations run one at a time. Logs and generated references stay in
`build/disp/`; standard summaries stay in `build/regress/{smoke,full}/block/disp/`.
The runner prints separate build, reference and individual-case wall times.

| Item | Implementation | Stimulus and direct checks |
|---|---|---|
| DS-01 | `tb.sv`, `display_monitor`, case 1 | Two full timing frames, HS/VS/DE positions and polarity |
| DS-02 | `tb.sv`, case 2; `tmds_ref.py` | Python TMDS symbols, including blanking and disparity |
| DS-03 | `tb.sv`, both monitors, case 3 | Reset L0 configuration; stride 2560/4096; all pixels and AR addresses |
| DS-04 | `tb.sv`, case 4 | Mid-frame/VBlank base updates, repeats, FRAME/SWITCH/CUR/REL/count |
| DS-05 | `tb.sv`, case 5 | Black before enable, first scan, complete requested scan on disable |
| DS-06 | `tb_layers.sv`, both memory processes, case 6 | Both layers full screen; random AR/R gaps; RREADY; layer order and FIFO reservation bounds including in-flight beats |
| DS-07 | `tb_layers.sv`, `display_monitor`, case 7 | Separate L1-only, L0-only and both-layer stalls across the frame boundary; exact PERF1/2/5/6, ERR_CODE 3/1, per-layer recovery |
| DS-08 | `tb.sv`, case 8 | Pending request, previous read completion, PERF4 |
| DS-09 | `tb_layers.sv`, `memory_monitor`, case 9 | L1-only, L0-only, both layers; low/high watermarks and L1 outside rectangle; exact PERF3 |
| DS-10 | `tb.sv`, case 10, `boundary_stop_test` | ABORT during reads and at -8/-2/+4 pixel phases around VBlank |
| DS-11 | `tb.sv`, case 11 | SLVERR code/IRQ/RW1C with unchanged pixel data |
| DS-12 | `tb.sv`, register tasks/case 12; `tb_layers.sv`, case 12 | New ID/reset/alignment fields, drain/baseline reset and stop phases; SWITCH1 RW1C and populated L1 underflow counters cleared by SOFT_RST |
| DS-13 | `tb_layers.sv`, case 13 | Ten seeds, six requested frames; bases/enables/scroll/rectangle/OPA, stop intervals, enable changes, clock phase and ratio |
| DS-14 | `tb_layers.sv`, case 14 | SCROLL_X 0–15, 16, 31, 48; SCROLL_Y=3; 80/81 beats per row |
| DS-15 | `tb_layers.sv`, case 15; `blend_ref.py` | Six full frames with OPA 0/1/128/255/73/219; alpha endpoints/intermediates and pseudorandom values; every Python/SV/RGB pixel |
| DS-16 | `tb_layers.sv`, case 16 | Three rectangles: origin 8×1, bottom-right 8×1, right/bottom-aligned large rectangle; no extra L1 descriptors |
| DS-17 | `tb_layers.sv`, case 17 | First enable, independent base replacement, L1 disable/re-enable, scroll/position/size/OPA-only changes; exact SWITCH bits and release bases |
| DS-18 | `tb_layers.sv`, case 18 | Eighteen instances: every frame-latched register written just before/after FRAME; current/next frame AR and scan parameters |
| DS-19 | `tb_layers.sv`, case 19 | ENABLE with both layers off still gives FRAME/count and black without AR; subsequent L1-only frame |

`tb.sv` retains its original L0-only DS-06/07/09/13 scenarios for direct baseline
diagnosis. The tier runners select the two-layer versions of those items.
Reproduce an individual case after a build:

```sh
build/disp/obj/sim +CASE=3 +SEED=1 +STRIDE=4096
build/disp/obj_layers/sim +CASE=14 +SEED=1 +VARIANT=15
build/disp/obj_layers/sim +CASE=7 +SEED=1 +VARIANT=2
build/disp/obj_layers/sim +CASE=15 +SEED=1 +BLEND_REF=build/disp/blend.hex
```

`blend_ref.py` uses only the standard library. `Frame.descriptors()` independently
implements spec 2.5 ordering/addresses/widths; `Frame.pixel()` implements L0
windowing, L1 placement, disabled/missing layers and spec 2.7 blending. `LayerDebt`
models ordered arrivals, missed demands and repayment during disabled frames.
Self-test checks d(x) against integer division for all 65,026 inputs, blend cases,
scroll descriptors, rectangle edges and independent cross-frame debts. The separate `tb_blend_ref` top compares all six Python/SV expected frames even
when the installed DUT predates v0.3; the pixel monitor repeats this comparison
while checking the live output. The six DS-15 expected frames exercise the complete Python frame model, with the same
specified d(x) formula implemented separately in SV. Surface patterns use
explicit 32-bit arithmetic, so Python and SV agree on overflow.

The layer scoreboard snapshots software parameters at the public FRAME interrupt
(with only FRAME enabled), then verifies active-layer CUR_BASE values over APB.
It validates every AXI burst against the next layer/row descriptor. The physical
source layouts stay at 4096/5120 bytes per row; changing STRIDE changes the view
of those fixed memory contents, including in DS-18. Responses
carry their layer/frame ownership through the BFM queue; FIFO space bounds
subtract both returned and in-flight reserved beats.

For DS-07/12/13, L0 contributes nonzero red and zero blue; L1 contributes only
nonzero blue with alpha 255. OPA remains between 32 and 223 in randomized
underflow tests. Thus L0 absence and L1 absence are independently observable.
Each inferred missing beat holds across its entire visible pixel group; every
channel is compared with the blend formula and the original surface coordinates.
Missing beats/frames are counted separately and compared exactly with PERF.
Late responses during a disabled frame must repay the old debt; the next scanned
frame must be fully correct. This is an external observation of debt and alignment,
not a direct measurement of internal empty signals or exact repayment cycles.
Row reservation uses the existing eight-beat CDC/encoder boundary margin; urgent
uses sixteen-beat margins. DS-09 classifies L1 only when the observable AR row
through AR row + 8 lies wholly inside or outside its rectangle; the 512-beat
FIFO and at least 80 L0 beats per row bound descriptor lookahead (the L1-only
phase uses 160 beats per row). The mixed phase uses 32 L1 beats per row to
exercise a different W/8 watermark. PERF3 is counted exactly at every memory edge.

The timing monitor's origin is the first active pixel. CEA vertical line
boundaries occur at the HS rising edge: VBlank starts at (1390,719), and VS rises
at (1390,724), remaining high for five complete lines. Stop-phase tests permit
zero or one in-flight critical request; any accepted request must drain and scan
completely, with no AR after the first IDLE or soft-reset counter rebound.

Lint uses the existing behavioral waivers `BLKSEQ`, `UNUSEDSIGNAL` and
`SYNCASYNCNET`; width, latch and connectivity warnings remain enabled. Supply
`--timescale 1ns/1ps` for RTL without an explicit timescale. Both top names must
be linted with the expanded `files.f` list. Results and exact commands are in
`results.md`.
