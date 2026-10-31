# RND independent block verification

This environment implements `rnd-spec.md` v0.3 and `rnd-testplan.md` v0.2 without
reading `rtl/media/rnd/` or `legacy/rtl/vision/render/`. All added files belong to
`verif/block/rnd/`. RN-17 follows the LVGL software verification plan.

## Run

Source the repository environment before running Verilator:

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/rnd/rnd_ref.py --selftest
python3 verif/block/rnd/check.py
python3 tools/regress.py full --path verif/block/rnd/selftest -j 1
```

The independent acceptance manifest is in full because its two cold serial
compiles exceed the smoke time budget. The last command runs hand-calculated
command examples, arithmetic sweeps, all
smoke/full vector-generation checks, public-port stub compilation and the AXI
memory model selftest. The stub does not implement a renderer; its PASS only means
that the complete harness compiled and elaborated against the specified ports.

RN-18 uses no-wait memory for specification thresholds and reruns all four scenes
with fixed read latency 40 to record numbers without threshold checks (coordinator
clarification `e6ff241`). The limits are 375000 cycles for ARGB fill, 187500 cycles
for RGB565 fill and at least 1.5 pixels/cycle for BLIT.

After the independent RTL is ready, the integration task runs:

```sh
python3 tools/regress.py full --path verif/block/rnd -j 1
python3 tools/regress.py perf --path verif/block/rnd/perf -j 1
```

Each command has one directory argument and runs one simulation at a time. All
manifests use group `verif/block/rnd`. The full invocation includes the root directed
manifest, the full supplement and the independent selftest. The root manifest
covers the RN-01–16 subset originally called smoke; its 531 serial cases exceed
the sixty-second budget, so coordinator clarification `7dcb7ed` assigns it to full.
RND smoke coverage is provided by `verif/unit/rnd_*`. The real-DUT file list
uses `rtl/filelists/rnd.f`; the declaration stub is confined to `selftest/files.f`.
Builds, generated binary images, configuration files and logs live in `build/rnd/`
and `build/regress/<tier>/block/rnd/`.

## Files and test mapping

| Test | Stimulus in `vectors.py` | Checks in `edrv32_rnd_tb.sv` | Tier |
|---|---|---|---|
| RN-01 | Both destinations, OPA 0/1/128/254/255, destination alpha 0/1/128/255 | Whole-memory oracle | full |
| RN-02 | Partial/outside/negative/empty/single-pixel geometry, every aligned destination byte offset, non-32-byte strides | Whole memory, no W for empty area | full |
| RN-03 | Radius 0/1/2/7/4095, dimensions 19x16/1x2/2x1 | Whole memory | full |
| RN-04 | Horizontal/vertical gradients, signed fractional steps, both saturation directions, three clipped pieces | Whole memory; generator checks pieces equal one draw | full |
| RN-05 | Width 1/7/9/20, radius 7, six selected side masks or all sixteen | Whole memory | full |
| RN-06 | A8/A4/A2/A1, every intra-byte starting pixel, unaligned base/stride | Whole memory | full |
| RN-07 | RGB565/ARGB8888/I8/I4/I2/I1, both destinations, unaligned source offsets/stride | Whole memory | full |
| RN-08 | Enlargement 2/3.5, reduction 1.5/4/16, scale zero, all flip combinations, clipped RECT | Whole memory, numbered source grid | full |
| RN-09 | Key hits/misses and ignored formats, RC_OPA 0/128/255, modes 0–3, destination alpha 0/255 | Whole memory | full |
| RN-10 | Different buffers, identity and four overlapping directions, source byte offset | Whole memory against source snapshot | full |
| RN-11 | R 0/1/8/31, corner radius 0/4095, clipped expanded grid | Whole memory except specified temporary bytes | full |
| RN-12 | R 0/1/8/31, 3x2 area smaller than kernel, both destinations | Whole memory except specified temporary bytes | full |
| RN-13 | Tile 8/16, four formats, all map flips, MAP_X/Y 7/13, multirow map, tile 0/4095, key hits/misses | Whole memory | full |
| RN-14 | Twelve dependent commands, newly written data reused as destination/source | Whole memory, DONE_COUNT and CUR_DESC increments, descriptor reads after B drain | full |
| RN-15 | Descriptor/source/target/palette R errors, B error, illegal OP/format/COPY/modes 4–7, ABORT in three phases | Error/IRQ/stop/drain, whole partial memory, explicit successful restart after error clear | full |
| RN-16 | Reset/RO/ignored registers, address/count masks, busy DOORBELL, empty list, idle/busy SOFT_RST | APB readback, IRQ masking/W1C, exact PERF1 and observed beat PERF2/3, PERF reset | full |
| RN-18 | 1280x720 fills, 1024x512 BLIT, 1000 16x20 A4 glyphs | Whole memory; PERF0 ms, PERF1/PERF0, average cycles/glyph; no-wait thresholds and latency-40 recording | perf |
| RN-19 | Ten seeds, fifty legal random commands each, all eight operations, randomized geometry/format/fields/delays | Whole memory, protocol checker | full |

`rnd_ref.py` provides the oracle and descriptor encoding functions for every row.
`edrv32_rnd_memory.sv` provides ordered AXI256 read/write queues, random address and
W readiness, random R gaps and B delay, configurable fixed first-read latency, and
one-shot transaction SLVERR selection. The common AXI checker checks stable payloads,
burst alignment, lengths, 4 KiB boundaries and response ordering. The harness checks
all queues have drained at IDLE and that no AR is accepted after ABORT.

Every test compares the complete initialized memory image: destination, row padding,
random outer region, command list, sources, map, tiles and palette. Only temporary
regions specified for BOX_SHADOW/BLUR are excluded. Error and ABORT cases compare
written bytes with the first-command oracle and all unwritten bytes with the initial
image; the subsequent command's destination must remain unchanged. Recovery reloads
initial data and repairs an illegal descriptor explicitly, then starts without a DUT
reset. Mismatch reports include RN number, command index, coordinate, byte address,
expected/actual byte and simulation time.

## Reference model and specification clauses

| Clause | Implementation |
|---|---|
| 2.1 | `BPP`, `raw_pixel`, `source_pixel`, `argb`, `pack_argb`: little-endian words, MSB-first subbyte extraction, palette lookups and straight alpha |
| 2.2 | `d`, `mix`, `e565`, `p565`, exact integer `Q`, `over`: source-alpha zero preserves bytes, nonpremultiplied output, four blend modes |
| 2.3 | `coverage`: radius clamp, integer square root and Q4 horizontal coverage, zero outside RECT |
| 2.4 | `blur_line`, `blur_grid`: exact integer multiplier/rounding after each separable pass, zero or nearest boundary extension |
| 2.5 | `Command.encode/decode`, `area`: sixteen little-endian words, signed RECT, inclusive intersection, ignored bits and empty areas |
| 2.6 FILL | `fill`, `execute_command`: 32-bit signed steps in units of 2^-16; RECT-relative gradient origin, saturation and nested alpha rounding |
| 2.6 BORDER | `border`, `execute_command`: selected-side inset, unselected-side expansion, inner/outer rounded coverage |
| 2.6 GLYPH | `glyph`, `execute_command`: SRC_X/Y and subbyte alpha expansion |
| 2.6 BLIT | `blit`, `execute_command`: full-precision unsigned scale products, flips, palette, RGB565-only key, recolor then blend then over |
| 2.6 COPY | `copy`, `execute_command`: raw same-format source snapshot before destination writes, including alpha |
| 2.6 BOX_SHADOW | `box_shadow`, `execute_command`: RECT-expanded coverage grid, zero-extension blur, clip only after blur |
| 2.6 BLUR | `blur`, `execute_command`: snapshot of clipped area, nearest-edge blur, all straight-alpha channels, RGB565 unpack/repack |
| 2.6 TILEMAP | `tilemap`, `execute_command`: map coordinate and entry decoding, tile number/flip, packed tile storage, palette/key |
| 6 | `Command.illegal`, `execute`: only the listed invalid OP/source-format/COPY-format/BLIT-mode conditions; stop with error 3 before stores |

The standalone model accepts a binary initial memory image and a packed descriptor
file and emits an expected binary memory image:

```sh
python3 verif/block/rnd/rnd_ref.py --input initial.bin \
    --commands commands.bin --output expected.bin
```

BLUR temporary size follows v0.2: four bytes per pixel for both destination formats.
No temporary storage contents are assumed. Python computes intermediates in memory and
`temp_region` identifies only the bytes whose final contents the specification leaves
unspecified. All Python code uses the standard library.

## Independent acceptance results (R-T1)

Tested source commit: `ab6527b`, based on coordinator clarification commit `e6ff241`.
Date: 2026-10-29. Tools: Verilator 5.020 (Debian 5.020-1), Python 3.12.3.

| Check | Command / evidence | Result |
|---|---|---|
| Style and complete public-port harness lint | `python3 verif/block/rnd/check.py` | Four SV files plus Python sources, 0 style warnings; Verilator `--lint-only --timing -Wall`, 0 warnings |
| Independent acceptance | `python3 tools/regress.py full --path verif/block/rnd/selftest -j 1` | 1 PASS, 0 FAIL; final warm run 25 seconds |
| Arithmetic/reference selftest | `rnd_ref.selftest`, called by the acceptance runner | d: all 65026 inputs; RGB565: all 65536 words; over: all 65536 sa/Da pairs; Q: all 255 entries; blur: every possible sum for R=0–31 and both edge policies; 32768 legality combinations; PASS |
| Hand-calculated command examples | `rnd_ref.selftest` and `selftest.command_examples`, same runner | All eight operations, signed32 gradient steps, COPY overlap, subbyte alpha, blend modes, radius coverage, shadow R=1, BLUR nearest edges, RGB565 intermediate precision and temporary size; PASS |
| Directed/random vector construction | `selftest.vector_selftest`, same runner | 531 smoke variants + 105 full variants = 636 cases; ten seeds x fifty commands; all eight operations and ten formats; PASS |
| Public-port stub | `run.py stub`, same runner; `build/rnd/stub_obj/compile.log` | Verilator `--binary --timing -Wall -j 1` compile and stub elaboration PASS |
| Memory model | `selftest/edrv32_rnd_memory_tb.sv`, same runner; `build/rnd/memory_obj/compile.log` | Strobes, bursts up to sixteen beats, held R/B payloads, random stalls, exact forty-cycle first-read latency and SLVERR kinds 1–5; PASS |
| RN-18 reference images | `vectors.generate` for `selections('perf')`; `build/rnd/perf_vectors/summary.txt` | All eight no-wait/latency-40 scenes generated and rendered successfully |

The final acceptance transcript is
`build/regress/full/block/rnd/selftest/verilator/run.log`; the lint transcript is
`build/rnd/lint/lint.log`. The no-wait/latency-40 reference images are in
`build/rnd/perf_vectors/{argb,rgb565,blit,glyph}_lat{0,40}/`. Their expected target
pixel counts are 921600 for either fill, 524288 for BLIT and 320000 for the glyph list.
These are reference-model counts, not measured DUT performance.

The two cold serial compiles exceeded sixty seconds under the shared build load;
the independent acceptance manifest is therefore full. Real-DUT image correctness,
RN-01–16 smoke duration and RN-18 cycle/throughput measurements require the separate
RTL integration task. No RND RTL was read or executed in this task.


## Real-RTL integration results (R-I1)

Tested source: `15cf7e1`, unchanged RND RTL from `5bb8e38`.
`python3 tools/regress.py full --path verif/block/rnd -j 1` reports 3 PASS, 0 FAIL:
531 directed real-DUT cases, 105 supplemental cases (including ten seeds of fifty
commands), and the independent environment selftest. The respective directory
runtimes are 274, 1428 and 461 seconds, including any required compilation.
`python3 tools/regress.py perf --path verif/block/rnd -j 1` reports 1 PASS, 0 FAIL:
all eight no-wait/latency-40 scenes pass whole-memory comparison; the three no-wait
performance thresholds pass. The four arithmetic/address unit smoke tests pass.
Style and both top-level/verification lint report zero warnings.

Integration fixes affect only tier assignment, simulator optimization, existing
time budgets and formatted diagnostics; stimulus, oracle and checking conditions
are unchanged. No RND RTL changes were required. See the
[measurement report](../../../docs/reports/2026-10-29-perf-rnd.md) for commands,
cycle counts and specification comparisons, and the
[debug record](../../../docs/debug/2026-10-29-rnd-regression-timeouts.md) for timeout
reproduction and classification.

## T-RND2V independent v2 verification

- Base RTL: `ffb308aa`; verification commit: the commit containing this section.
- Environment: 用户提供的仿真主机（环境不记录）; formula/stub checks also run locally.
- Scope: no RTL read or edit; RN-17, new-RTL integration/resource/board lint remain V2-INTEG.
- Smoke: 42 vectors = unchanged 26 + 16 RN-21–28 representatives.
- Full: 545 directed + 1,249 supplement = 1,794 vectors; RN-19 is 10 seeds × 50 commands,
  covering all 13 OP and random legal parameter blocks; no full DUT integration run here.
- Perf: unchanged 8 RN-18 + 25 RN-29 scenes (G1 AA; NN/bilinear identity/rotation/skew/scale,
  RGB565/ARGB8888/I4). Output PERF0–3, parameter/source beats and raw-format read amplification.
- RN-29 black-box limits approved by coordinator: G1 AA ≥0.45 pixel/cycle;
  bilinear identity ≥0.7 pixel/cycle; other transforms record numbers without threshold.
- Formula checks: 1,200 Cartesian circle points, 192 exact fractional edges, 64 shared-edge
  samples, MASK alpha 0/1/128/255, 48 bilinear f/g/alpha cases, signed48, empty parameters,
  ROUND_CLIP and CUTOUT hand examples; all 1,794 functional vectors generate successfully.
- RN-28: target tile tails, >32 source blocks, unaligned/4KiB reads, same-list source rewrite,
  parameter/source errors and ABORT; restart changes source bytes to expose stale windows.
- Whole-memory comparisons include descriptors/parameters/source/target/frame; only specified
  temporary bytes are excluded; failures identify RN/descriptor/parameter address/pixel/values/time.
- PASS: final selftest (1,794 vectors, parameter SLVERR included), style/lint 0 warnings;
  old smoke 26/26 and perf 8/8 pass before/after; OP 09/0A/0B/0C/0D each rejects with ERROR=3.
- RN-18 PERF0 before=after (ARGB fill/RGB565 fill/BLIT/glyph): no-wait
  125297/64097/269217/502001; latency40 125336/64136/269334/1911001 (zero regression).
- Local summaries: `build/rnd-v2-final-selftest.log`, `build/rnd-v2-baseline-summary.txt`.
- Style uses existing `check.py` SV adapter per coordinator approval; direct RTL-only checker
  is inapplicable to permitted testbench SV syntax; shared tools are unchanged.

Reproduce (local Verilator commands require `. ~/.local/opt/edrv32/env.sh`):

```sh
flock /tmp/edrv32-sim.lock python3 verif/block/rnd/selftest.py
flock /tmp/edrv32-sim.lock python3 verif/block/rnd/check.py
flock /tmp/edrv32-sim.lock python3 verif/block/rnd/baseline.py smoke
flock /tmp/edrv32-sim.lock python3 verif/block/rnd/baseline.py perf
flock /tmp/edrv32-sim.lock python3 verif/block/rnd/baseline.py new
# Integration: run.py smoke / full / perf (same flock prefix locally).
```
