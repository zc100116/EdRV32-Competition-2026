# RND independent block verification

This environment implements `rnd-spec.md` v0.2 and `rnd-testplan.md` v0.1 without
reading `rtl/media/rnd/` or `legacy/rtl/vision/render/`. All added files belong to
`verif/block/rnd/`. RN-17 belongs to the later LVGL SoC task.

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
| RN-01 | Both destinations, OPA 0/1/128/254/255, destination alpha 0/1/128/255 | Whole-memory oracle | smoke |
| RN-02 | Partial/outside/negative/empty/single-pixel geometry, every aligned destination byte offset, non-32-byte strides | Whole memory, no W for empty area | smoke |
| RN-03 | Radius 0/1/2/7/4095, dimensions 19x16/1x2/2x1 | Whole memory | smoke |
| RN-04 | Horizontal/vertical gradients, signed fractional steps, both saturation directions, three clipped pieces | Whole memory; generator checks pieces equal one draw | smoke |
| RN-05 | Width 1/7/9/20, radius 7, six selected side masks or all sixteen | Whole memory | smoke/full |
| RN-06 | A8/A4/A2/A1, every intra-byte starting pixel, unaligned base/stride | Whole memory | smoke |
| RN-07 | RGB565/ARGB8888/I8/I4/I2/I1, both destinations, unaligned source offsets/stride | Whole memory | smoke |
| RN-08 | Enlargement 2/3.5, reduction 1.5/4/16, scale zero, all flip combinations, clipped RECT | Whole memory, numbered source grid | smoke |
| RN-09 | Key hits/misses and ignored formats, RC_OPA 0/128/255, modes 0–3, destination alpha 0/255 | Whole memory | smoke |
| RN-10 | Different buffers, identity and four overlapping directions, source byte offset | Whole memory against source snapshot | smoke |
| RN-11 | R 0/1/8/31, corner radius 0/4095, clipped expanded grid | Whole memory except specified temporary bytes | smoke/full |
| RN-12 | R 0/1/8/31, 3x2 area smaller than kernel, both destinations | Whole memory except specified temporary bytes | smoke/full |
| RN-13 | Tile 8/16, four formats, all map flips, MAP_X/Y 7/13, multirow map, tile 0/4095, key hits/misses | Whole memory | smoke |
| RN-14 | Twelve dependent commands, newly written data reused as destination/source | Whole memory, DONE_COUNT and CUR_DESC increments, descriptor reads after B drain | smoke |
| RN-15 | Descriptor/source/target/palette R errors, B error, illegal OP/format/COPY/modes 4–7, ABORT in three phases | Error/IRQ/stop/drain, whole partial memory, explicit successful restart after error clear | smoke/full |
| RN-16 | Reset/RO/ignored registers, address/count masks, busy DOORBELL, empty list, idle/busy SOFT_RST | APB readback, IRQ masking/W1C, exact PERF1 and observed beat PERF2/3, PERF reset | smoke |
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

## Acceptance results

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
