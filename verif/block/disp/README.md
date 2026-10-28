# DISP black-box module verification

The DUT is compiled through `rtl/filelists/disp.f`. The testbench uses only the
specified top-level ports and APB registers; it does not inspect or force DUT
hierarchy. The common AXI256 checker and APB interface are reused unchanged.

Run after `. ~/.local/opt/edrv32/env.sh`:

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/tmds_rx_model'
make smoke REGRESS_ARGS='-j 1 --path verif/block/disp'
make full REGRESS_ARGS='-j 1 --path verif/block/disp'
```

`run.py` builds with Verilator `--timing -j 1 -Wall` and executes one simulation
at a time. The full make target runs the full-only cases and all smoke cases.
Raw case logs, compile output and the generated TMDS frame are in `build/disp/`;
the standard regression summaries are under `build/regress/{smoke,full}/block/disp/`.
Individual cases can be reproduced with
`build/disp/obj/sim +CASE=7 +SEED=1 +STRIDE=4096` after building. DS-02 additionally
requires `+REF=build/disp/tmds.hex`.

The memory BFM constructs a distinct nonblack RGB565 pattern for every surface,
row and column and checks all AR addresses against the latched base/stride.
AXI frame starts may precede the visible TMDS blanking edge by encoder latency;
the request accounting check settles at the following active-coordinate line start.
Each accepted burst is queued and returned in order with pseudorandom ARREADY
and RVALID gaps. Directed stops cover late data across a frame boundary and a
single SLVERR response. Responses remain outstanding through stalls.

`tmds_ref.py` produces all 1,237,500 symbols of a frame, with a separate running
disparity per channel and a reset at every control interval. It follows
[DDWG DVI 1.0 Figure 3-5](https://glenwing.github.io/docs/DVI-1.0.pdf), independently
of the RTL and of the receiver's inverse decode equations. DS-02 checks every
symbol, including blanking, rather than comparing only decoded pixels.

The pixel monitor uses active coordinates with the first DE pixel at (0, 0).
Per the coordinator's timing clarification, the vertical line boundary is the HS
rising edge: VS rises at active coordinates (1390, 724), stays high for five
whole lines and falls at (1390, 729). Vertical blank starts at (1390, 719).

For underflow, the source pattern cannot be black. A complete black group is
therefore observable without internal FIFO access. The monitor accounts every
requested group and every returned AXI beat, checks that data cannot appear
before it was returned, checks the first black group against the externally available data bound,
tracks the possible debt repayment window until nonblack data resumes, and compares every subsequent nonblack pixel against its original
position. PERF0/1/2 are checked against completed scans/black frames/black groups.
The coordinator approved this black-box method and external FIFO occupancy
bounds: row reservation and urgent are checked outside the CDC/encoder boundary
window, with an eight-beat row margin and sixteen-beat urgent margin; precise internal
boundary checks
remain in the RTL unit tests. PERF3 is counted on every memory clock with no
approximation.

| Test | Implementation in `tb.sv` | Stimulus and checks |
|---|---|---|
| DS-01 | `display_monitor`, scenario 1 | Two complete frames; all HS/VS/DE symbols, polarity and periods |
| DS-02 | `display_monitor`, scenario 2; `tmds_ref.py` | Full frame symbol comparison including disparity and controls |
| DS-03 | `memory_monitor`, `display_monitor`, scenario 3 | Both 2560 and 4096 strides; every pixel and every burst address |
| DS-04 | Scenario 4 and both monitors | Active/VBlank base updates, repeats, FRAME/SWITCH/REL_BASE/CUR_BASE/count |
| DS-05 | Scenario 5 and `display_monitor` | Disabled black, first enabled frame, stop after requested scan, IDLE |
| DS-06 | `memory_drive`, `memory_monitor`, scenario 6 | Random AR/R gaps, permanent RREADY, row capacity bound, four outstanding |
| DS-07 | Scenario 7, `display_monitor`, `check_perf` | Cross-frame stop, debt repayment in an unscanned frame, recovery, PERF1/2 |
| DS-08 | Scenario 8 and `memory_monitor` | Pending request, prior frame completion before next frame, PERF4 |
| DS-09 | Scenario 9 and `memory_monitor` | Known high/low occupancy regions, exact PERF3 clock count |
| DS-10 | Scenario 10 and `wait_idle` | ABORT during read and at three VBlank phases; complete scan, no post-IDLE AR |
| DS-11 | Scenario 11, `memory_drive`, `display_monitor` | Injected SLVERR, ERR_CODE 2/IRQ/RW1C, unchanged pixel stream |
| DS-12 | `register_reset_checks`, scenario 12 | Reset fields/RW1C/START, SOFT_RST drain/baselines and three VBlank phases |
| DS-13 | Scenario 13 and both monitors | Ten seeds, six frame intervals, random switches/stalls/enable, clock phase/ratio |

The coordinator also approved phase sweeps for spec 2.8 in DS-10 and DS-12.
Separate fresh simulations write ABORT or SOFT_RST at -8, -2 and +4 pixel clocks
relative to the visible VBlank start. Because ENABLE synchronizer latency is not
specified, the boundary reference permits zero or one critical request, adopts
that request from the first AR, and then compares the entire resulting scan.
After the first APB observation of IDLE, every ARVALID must remain zero through
another complete frame, and soft-reset registers must retain their reset values.
The ordinary mid-frame ABORT/SOFT_RST cases remain separate runs.

Lint enables `-Wall` and waives only behavioral/environment categories:
`BLKSEQ` for ordered BFM/model/scoreboard sampling, `UNUSEDSIGNAL` for unused APB
slots and fixed-width field slicing, and `SYNCASYNCNET` because testbench
monitors sample reset while DUT reset pins are asynchronous. `--timescale
1ns/1ps` supplies the default for RTL modules without a timescale. Width,
connectivity, latch and functional warnings remain enabled.
