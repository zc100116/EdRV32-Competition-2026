# D-R2 DISP v0.3 memory-clock path cuts

Sources: v0.2 `4412a29`; D-R1 `23ed7ad`; D-R2 RTL `5a490f9`.
The D-R1 report below is retained as historical evidence.
The Yosys script, LUT4 mapping options and RAM black boxes are unchanged.

| Structural LUT4 levels | v0.2 | D-R1 | D-R2 |
|---|---:|---:|---:|
| clk_mem FF D/E, excluding common DMA internals | 16 | 50 | **16** |
| clk_mem outputs (excluding TMDS) | 16 | 50 | **15** |
| reader FF D/E | 16 | 25 | **12** |
| L1 row-address data | — | 23 | **10** |
| admission occupancy capture | — | 14 | **11** |
| admission occupancy to scheduler | — | 9 | **8** |
| descriptor FF D/E | 16 | 1 | **3** |
| common dma2d_rd internal FF D/E (authorized exception) | 16 | 29 | **24** |
| clk_mem FF D/E including common DMA | 16 | 50 | **24** |

| Resource, same generic flow | v0.2 | D-R1 | D-R2 | D-R2 minus D-R1 |
|---|---:|---:|---:|---:|
| LUT4 | 2947 | 6260 | **6767** | +507 (+8.10%) |
| FF, both clocks | 1864 | 3391 | **3557** | +166 (+4.90%) |
| Physical scan RAM instances | 1 | 2 | 2 | 0 |
| Physical scan RAM storage bits, excluded above | 131072 | 262144 | 262144 | 0 |

The five longest D-R2 paths, including FF D/E and memory-domain outputs but
excluding DMA-internal FF endpoints, are:

| Levels | Start | Endpoint |
|---:|---|---|
| 16 | `u_read1_cnt.sync_r[8]` | `u_regs.urgent_r[0]` (D) |
| 15 | `u_perf1.sync_r[30]` | `u_regs.perf1_less_r[0]` (D) |
| 15 | `u_regs.perf1_less_r[1]` | `apb_prdata_o[30]` |
| 15 | `u_regs.perf6_equal_r[1]` | `apb_prdata_o[31]` |
| 15 | `u_read1_cnt.sync_r[8]` | `p0_urgent_o[0]` |

## Path composition and implementation

D-R1's 50-level cone starts at the synchronized frame-request toggle. The queue
nonzero/frame-start control shared a long mapped cone with 32-bit queue arithmetic;
BUSY then combined that control with the PERF0 baseline subtraction/comparison,
FIFO drain, scan-live/stop acknowledgement and parameter-handshake state. The same
unregistered BUSY drove both the SOFT_CLEAR decision and APB STATUS. Independent
32-bit counter increments and PERF subtraction/APB cones also exceeded 16 levels.

D-R2 makes these cuts:

- Keep a registered queue-nonzero flag alongside the exact queue count, including
  modulo wrap. Frame requests, frame latching, FRAME IRQ and frame-count updates
  retain their original edge. Split 32-bit count updates into 16-bit increments
  or decrements with carry/borrow conditions from the previous low half.
- Capture low-half address sums/carry and high-half sums before committing row
  addresses. Initial horizontal scroll uses the same stages. SCROLL_Y now needs
  two clocks per addition: 4095 additions take 8190 clocks (65.520 us at
  125 MHz), plus fixed setup cycles, within the 30-line VBlank.
  Descriptor ordering, values, backpressure stability and full-line admission
  remain unchanged.
- Register each byte of the requested-versus-scanned count comparison before the
  final BUSY reduction. Register STATUS.BUSY/IDLE, and use this registered state
  for SOFT_CLEAR. Delay the reset request alongside BUSY so the prior IDLE sample
  cannot skip the stop handshake. The BUSY register's longest D path is 9 levels;
  the SOFT_CLEAR register's D path is 1 level. STATUS has one register after its
  final reduction; frame-completion accounting has one additional prior stage.
- Capture small less/equal comparisons alongside each existing raw PERF sample,
  then form modulo count differences with independent byte arithmetic. At
  SOFT_CLEAR, comparisons use the baseline installed on that same edge. PERF
  read values retain their previous sampling latency, including reset baselines.
- Factor FIFO occupancy subtraction into short arithmetic slices and use direct
  write/read-count equality for empty detection. Urgent thresholds and their
  observation cycles stay unchanged; admission still uses registered occupancy.

No defensive checks, fallback paths, timeouts, IP, register-map or CDC changes
were added. All original frame parameters still latch atomically on frame start.

## Common DMA exception approved by the coordinator

The coordinator explicitly amended D-R2 acceptance to exclude internal
`dma2d_rd`/`dma2d_wr` paths while requiring every other clk_mem path to be at most
16 LUT4 levels, and required the exception to be listed here. D-R1's internal
DMA path was 29 levels; D-R2's is 24, from `u_dma.line_addr_r[6]` to the D input
of `p0_araddr_o[30]`. The common RTL is unchanged; different surrounding logic
changes generic mapper choices.

The fixed v0.2 width allowed constant folding, while v0.3 variable line widths
expose common DMA address/burst arithmetic. The coordinator retained the common
module because variable-width DMA instances already exist in media, and changing
it would also affect VIN and GEO. The existing
[media r4 PDS report](../../../docs/reports/2026-10-29-timing-media-top-r4.md)
uses 125 MHz constraints and reports clk_mem slow-corner +0.592 ns and 135.0 MHz
Fmax. That is prior media evidence; D-R2 has no PDS timing claim. If the later
R-W1 result makes this DMA path critical, the coordinator will open a separate
common-module task.

## Verification and reproduction

All seven unit smoke and full suites passed. After the final arithmetic
cuts, the reader and regs smoke suites were rerun; the full suites already used
those final unit sources. Original block smoke: **10/12 PASS**, with exactly
D-R1's expected DS-04 first-release IRQ and DS-12 ID assertions.
Authorized four-assertion compatibility copy: **12/12 PASS**.

The only unit-test edit is in `verif/unit/disp_regs/tb.sv`: after lowering the
synthetic BUSY input, sample deferred SOFT_CLEAR after **two** ticks instead of
one, because the drain decision now consumes the registered BUSY sample. Every
assertion and expected value is retained. No other unit sampling was changed.
No `docs/`, `verif/block/`, common/tech/include or unrelated RTL was modified.

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/media/disp
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE \
    -f disp.f --top-module edrv32_disp)
for tier in smoke full; do
    for name in timing tmds_enc scan reader regs control layers; do
        make "$tier" REGRESS_ARGS="-j 1 --path verif/unit/disp_${name}" || exit $?
    done
done
make smoke REGRESS_ARGS="-j 1 --path verif/block/disp"
# Create the already-authorized copy using the recipe in the D-R1 report below.
python3 build/disp_v02_compat/run.py smoke
yosys -Q -T -l build/disp_dr2_iter7.log -s verif/unit/disp_reader/resource.ys
python3 verif/unit/disp_reader/resource_path.py
```

All commands use the versions listed in D-R1 below; simulations run serially
with one build job. The analyzer now reports the common DMA group separately
by FF source filename, the five longest remaining paths, and declared bit offsets.
The Yosys synthesis flow itself is unchanged. Reproduce D-R1 with the v0.2 archive
recipe below, substituting `23ed7ad` for the revision and `dr1` for output names.

Raw evidence: `build/disp_dr2_{style,lint}.log`,
`build/disp_dr2_<unit>_{smoke,full}.log`,
`build/disp_dr2_block_{original,compat}_smoke.log`,
`build/disp_dr2_iter7.{log,stdout}`, `build/disp_resource_{v02,dr1,dr2}.json`,
`build/disp_path_{v02,dr1,dr2}.log`, and `build/disp_v02_compat/tb.diff`.

Modified files: `rtl/media/disp/edrv32_disp{,_reader,_regs}.v`,
`verif/unit/disp_reader/{README.md,resource_path.py}`,
`verif/unit/disp_regs/tb.sv`.

---

# D-R1 DISP v0.3 RTL and unit verification

Baseline: `4412a299b4e8c054ed73ab335226c8760470f5d9` (v0.2 RTL).
Specification clarifications: coordinator commits `e6ff241` and `b230b95` confirm
that disabled layers retain their last actually read CUR_BASE, first activation
has no release SWITCH, and the L0 urgent threshold is fixed at 81 beats even when
p=0 (v0.2 used 80). Along with the explicit ID version update, these are the
intentional v0.2 compatibility changes. No `docs/` files were modified by this worker.
RTL source: `e0f07bd` (`disp: implement two-layer scanout and frame parameters`).
Register description/header: `a62702c` (`regs: describe DISP v0.3 layers and counters`).
Verification sources and this report are committed together in the `verif:` commit.
The task was rebased onto coordinator register-metadata commit `24e5523`; ID fields
are TYPE/VERSION and public reset values are explicit. RTL/common/DISP filelist
inputs stayed unchanged across this rebase; only JSON/header metadata was merged.
The regenerated header was rebuilt with `regs_check` after the rebase.

## Implementation

| Spec | Change |
|---|---|
| 2.4 | Atomically sample all frame registers at reader start; send the 56-bit scan parameter bundle with `edrv32_cdc_handshake`; apply the most recently received bundle at the first pixel of row 0 |
| 2.5 | Process rows 0..719, L0 before the applicable L1 rectangle row; hold the descriptor's layer through DONE and route all its DMA data to that FIFO |
| 2.5 | Form L0 base plus horizontal offset once, add STRIDE SCROLL_Y times during prefetch, then once per screen row; advance L1 address once per applicable row; no address multipliers |
| 2.5 | Admit a full line against its own occupancy; serialize descriptors through DONE, so there are no unreturned reservations when evaluating the next admission |
| 2.6 | Two independent 512x256 external-RAM FIFOs using `edrv32_async_fifo_ram` and two instances of the existing `edrv32_ram_disp_scan` wrapper; per-layer read-count gray CDC; specified urgent thresholds |
| 2.7 | L0 pixel lane `(x+p) mod 16`, with a fresh beat at x=0 and each lane wrap; discard the unused tail at the next row; L1 rectangular eight-pixel groups |
| 2.7, 6 | Independent missing-beat debts, transparent L1 misses, black L0 misses, repayment during blanking and unscanned frames; L1 event/pixel counts via common CDC primitives |
| 2.7 | Non-premultiplied ARGB8888 and per-frame OPA; alpha product and channel sums use the exact specified `d(x)` including both additions and the final shift |
| 2.8, 4.1 | BUSY includes parameter-handshake completion and both FIFO occupancies; existing stop/frame-request handshakes remain in force |
| 4.1-4.3 | ID version 2, SWITCH1/L1_REL_BASE, frame-latched new registers, PERF5/6 reset baselines; JSON register table and regenerated C header |

No range checks, new errors, timeouts, watchdogs or IP were added.
`rtl/filelists/disp.f` remains unchanged because no RTL files were added or removed.

## Verification commands

Environment: `. ~/.local/opt/edrv32/env.sh`.
Verilator 5.020; Yosys 0.70+219 (`5053d0e26`); xPack GCC 15.2.0.
All simulation invocations use one build job and run directories sequentially.

```sh
python3 tools/check/verilog_style.py rtl/media/disp
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE \
    -f disp.f --top-module edrv32_disp)
for tier in smoke full; do
    for name in timing tmds_enc scan reader regs control layers; do
        make "$tier" REGRESS_ARGS="-j 1 --path verif/unit/disp_${name}" || exit $?
    done
done
make smoke REGRESS_ARGS="-j 1 --path verif/block/disp"
make -C sw PROGRAM=regs_check
```

| Unit | Checked behavior |
|---|---|
| reader | Every descriptor of five baseline frames, all 16 scroll offsets with nonzero SCROLL_Y, L0/L1 ordering, L1 Y/height/stride/width, both independent FIFO admission boundaries, urgent thresholds, backpressure stability, queued requests, modulo counter wraps and two disabled layers |
| scan | Original RGB565/debt regression including late arrivals, simultaneous miss/discard, cross-frame and disabled repayment |
| layers | Two-clock parameter handshake and mid-frame receipt isolation, 16 scroll offsets over two rows, every alpha/OPA pair (65,536), varying channels and RGB565 colors, eight-pixel rectangle at the right/bottom boundary, L0-off, L1-off and independent debts |
| regs | New reset values and masks, first-frame/no-release, per-layer base changes and disabling, simultaneous release, IRQ9 and ERR_CODE3, PERF5/6 and SOFT_RST baselines; existing APB/IRQ/reset regression |
| timing, tmds_enc, control | Existing complete raster, symbol and stop/request-handshake regressions |

Validation results:

| Check | Result |
|---|---|
| RTL style | 7 files, 0 warnings |
| Complete DISP filelist, Verilator `--lint-only -Wall` | PASS, 0 warnings |
| All seven units, smoke | 7/7 PASS |
| All seven units, full | 7/7 PASS |
| `sw/tests/regs_check` build after metadata rebase | PASS |
| Original v0.2 block smoke | 10/12 PASS; two expected version assertions |
| Authorized copy, four assertion updates only | 12/12 PASS |

The reader results include explicit 80/81 L0 urgency checks; the layers results
include a requested frame with both layers disabled, no FIFO consumption or errors,
and correct PERF0 completion. All 65,536 alpha/OPA pairs passed the independent
integer-division reference.

Raw logs are in `build/disp_<unit>_{smoke,full}.log` and
`build/regress/{smoke,full}/unit/disp_<unit>/verilator/{compile,run}.log`.

## Resource and memory-clock path reference

```sh
yosys -Q -T -l build/disp_resource_v03.log -s verif/unit/disp_reader/resource.ys
python3 verif/unit/disp_reader/resource_path.py
```

The v0.2 baseline can be reproduced with:

```sh
mkdir -p build/disp_v02
git archive 4412a299b4e8c054ed73ab335226c8760470f5d9 rtl/media/disp | \
    tar -x -C build/disp_v02
sed -e 's@rtl/media/disp/@build/disp_v02/rtl/media/disp/@g' \
    -e 's@build/disp_resource.json@build/disp_resource_v02.json@' \
    verif/unit/disp_reader/resource.ys > build/disp_resource_v02.ys
yosys -Q -T -l build/disp_resource_v02.log -s build/disp_resource_v02.ys
python3 verif/unit/disp_reader/resource_path.py build/disp_resource_v02.json
```

Both revisions use the same generic LUT4 mapping command and black-box the physical
scan RAM wrapper. This comparison excludes RAM contents from LUT/FF totals and counts
the FIFO controller/prefetch registers. It is a Yosys reference, not Pango area or timing.

The new address datapath has one 32-bit stride addition per clock, followed by an
independent registered descriptor selection stage. The full-line admission path is
write count minus synchronized read count into registered occupancies, then comparison
with a **latched** capacity-minus-line limit into the descriptor-valid state register.
S_PICK separates previous DONE from S_WAIT, ensuring the prior final write is included
before this staged occupancy can admit a descriptor. Its result never controls P0
RREADY: DMA data-ready remains tied high. There is no address multiplier or chained
row multiplication on clk_mem. SCROLL_Y initialization takes at most 4095 additions
(32.76 us at 125 MHz), within the approximately 667 us VBlank prefetch interval.

PDS timing and actual LUT/FF/DRM/APM measurements remain for the coordinator's later
board task; no PDS result is claimed by this Linux work.

## Compatibility test adjustment authorized by coordinator

The original v0.2 `verif/block/disp` test has four assertions whose expected values
changed explicitly in v0.3. Coordinator reply to `msg_ff656bbeabf9` authorizes a
build-only copy that changes exactly these assertions:

| Original tb.sv line | Change |
|---|---|
| 502 | ID `0x00050001` to `0x00050002` |
| 527 | ID after ignored RO write: same version update |
| 616 | DS-04 first activation IRQ_STAT `0x104` to `0x004` (no previous Surface release) |
| 736 | ID after SOFT_RST: same version update |

The urgent threshold change is also an expected compatibility difference;
the old smoke cases do not assert its exact 80/81 boundary. The reader unit checks
urgent=0 at occupancy 81 and urgent=1 at occupancy 80, including the reset L0-only
configuration. This threshold follows spec 2.6, independent of p.

The original test is run first without changes. The compatibility copy is
`build/disp_v02_compat/tb.sv`; its complete diff is
`build/disp_v02_compat/tb.diff`. The copied runner uses the same sources, compiler
flags, single build job and 12 smoke case/stride/phase combinations, with only
its root/output locations and testbench path redirected into build.

```sh
make smoke REGRESS_ARGS="-j 1 --path verif/block/disp"
python3 build/disp_v02_compat/run.py smoke
```

To reproduce the authorized build-only copy from a clean checkout, run this before
its runner command:

```sh
python3 - <<'PYTHON'
from pathlib import Path
root = Path.cwd()
out = root / 'build/disp_v02_compat'
out.mkdir(parents=True, exist_ok=True)
tb = (root / 'verif/block/disp/tb.sv').read_text()
tb = tb.replace("rd_check(12'h010, 32'h104);", "rd_check(12'h010, 32'h004);", 1)
tb = tb.replace("32'h00050001", "32'h00050002")
(out / 'tb.sv').write_text(tb)
runner = (root / 'verif/block/disp/run.py').read_text()
runner = runner.replace('ROOT = Path(__file__).resolve().parents[3]',
                        f'ROOT = Path({str(root)!r})')
runner = runner.replace('from tmds_ref import generate',
    "sys.path.insert(0, str(ROOT / 'verif/block/disp'))\nfrom tmds_ref import generate")
runner = runner.replace("out = ROOT / 'build/disp'", "out = ROOT / 'build/disp_v02_compat'")
runner = runner.replace("sources = expand_files(ROOT / 'verif/block/disp/files.f')",
    "sources = expand_files(ROOT / 'verif/block/disp/files.f')\n"
    "    sources = [str(ROOT / 'build/disp_v02_compat/tb.sv') if p == "
    "str(ROOT / 'verif/block/disp/tb.sv') else p for p in sources]")
(out / 'run.py').write_text(runner)
PYTHON
```

Original result: **10/12 PASS**, with exactly the two expected failures:
DS-04 IRQ_STAT expected `0x104`, actual `0x004`; DS-12 ID expected `0x00050001`,
actual `0x00050002`. The three phase-swept DS-12 cases passed unchanged.
Original logs: `build/disp_block_v02_original_smoke.log`,
`build/regress/smoke/block/disp/verilator/run.log`, and `build/disp/DS-*.log`.

Authorized compatibility copy: **12/12 PASS**, including DS-04 full Surface
handoff/repeat behavior, DS-12 SOFT_RST and all three phase variants.
Copy logs: `build/disp_block_v02_compat_smoke.log` and
`build/disp_v02_compat/{compile,DS-*}.log`. The copy compiled with `-Wall`
without warnings and ran every selected scenario serially.

No `verif/block/` file is modified or committed. The independent v0.3 block tests
and their integration remain D-T1/D-I1 work, as assigned.

## Modified files

| Files | Purpose |
|---|---|
| `rtl/media/disp/edrv32_disp.v` | Second FIFO/RAM, new CDC instances, frame parameter bundle and BUSY integration |
| `rtl/media/disp/edrv32_disp_reader.v` | Ordered layer descriptors, accumulated addresses, staged per-layer admission and urgency |
| `rtl/media/disp/edrv32_disp_scan.v` | Frame parameters, scrolled L0, rectangular L1, exact blend, independent debts/counters |
| `rtl/media/disp/edrv32_disp_regs.v` | Shadow registers, layer release, CUR retention, IRQ/ERR and PERF5/6 |
| `rtl/include/regs/disp.json` | v0.3 register description |
| `sw/bsp/include/regs/disp_regs.h` | Generated C constants |
| `verif/unit/disp_reader/tb.sv` | Two-layer DMA and admission unit |
| `verif/unit/disp_scan/tb.sv` | Existing debt regression with explicit new interface connections |
| `verif/unit/disp_regs/tb.sv` | v0.3 register and release unit |
| `verif/unit/disp_layers/{tb.sv,files.f,test.yaml}` | New scan/blend/parameter-CDC unit |
| `verif/unit/disp_reader/{resource.ys,resource_path.py,README.md}` | Reproducible resource/path measurement and this report |

## Final Yosys reference (RTL e0f07bd)

| Same flow / physical RAM black boxes | v0.2 (4412a29) | v0.3 (e0f07bd) | Delta |
|---|---:|---:|---:|
| Generic LUT4 | 2947 | 6260 | +3313 |
| FF | 1864 | 3391 | +1527 |
| Scan RAM instances | 1 | 2 | +1 |
| Scan RAM storage bits (excluded from LUT/FF) | 131072 | 262144 | +131072 |

This generic flow implements the blend multipliers in LUTs; Pango APM mapping is
not measured. The generic LUT4 count is above the specification's provisional 4K
Pango-LUT budget, so that budget still needs evaluation in PDS.

Raw logs/netlists: `build/disp_resource_v0{2,3}.{log,json}` and
`build/disp_path_v0{2,3}.log`. `resource_path.py` reports **structural LUT4 levels**,
including D and enable inputs of memory-clock FFs, with FF boundaries as path stops.
It does not model Pango carry chains, cell delays, placement or routing.

The added admission comparator path is 9 generic LUT4 levels, from the registered
L1 occupancy to scheduler state; the prior occupancy capture is 14 levels including
the synchronized Gray-count decode and subtraction. Descriptor payload registers
separate row-address addition from the DMA input. The longest descriptor-register
enable path is 1 LUT4 level in this mapping. The L1 address data path is a single
32-bit registered stride accumulation plus selection; its longest generic path is
23 LUT4 levels, including the frame-load control/selection cone.

The complete memory-clock mapping has a longest structural path of 50 LUT4 levels,
from the synchronized frame-request signal through BUSY/drain control to SOFT_CLEAR
(and APB STATUS), compared with 16 levels in the baseline mapping. No nanosecond
slack or timing closure is inferred from those generic levels; the tight clk_mem
margin must be checked by PDS after integration.
