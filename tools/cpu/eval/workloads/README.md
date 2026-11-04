# Second workloads

These harnesses run repository C code on Spike without SoC peripherals. They do
not modify software or RTL. Source revision: `dc00c1e8`; measurements and conclusions
are in section 7 of `docs/design/2026-11-04-cpu-fmax-ipc.md`.

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/lvgl
flock -s /tmp/edrv32-sim.lock python3 tools/cpu/eval/workloads/run.py prepare vision
flock -s /tmp/edrv32-sim.lock python3 tools/cpu/eval/workloads/run.py prepare render
flock -s /tmp/edrv32-sim.lock python3 tools/cpu/eval/workloads/run.py measure vision
flock -s /tmp/edrv32-sim.lock python3 tools/cpu/eval/workloads/run.py measure render
```

Run the measurement commands sequentially: each uses at most two model processes.
Each configuration runs once. `build/second-workloads/{vision,render}/` contains
`commands.txt`, compilation logs, ELF/map, `spike.log`, `statistics.json`, and
`results.jsonl`. `coremark.elf` is the existing loader's required filename; the
ELF contains the selected workload. The RAM mapping is Spike-only, 32 MiB at
`0x80000000`. The loader initializes BSS, and the harness establishes SP/GP.

For the common-definition CoreMark statistics (the existing tuned trace must
already be prepared with `run_predictor_eval.py prepare`):

```sh
flock -s /tmp/edrv32-sim.lock python3 - <<'PY'
import sys
sys.path.insert(0, 'tools/cpu/eval/workloads')
import run
out = run.ROOT / 'build/cpu_predictor_eval/tuned'
program, symbols, trace = run.program_and_trace(out)
run.statistics(out, program, symbols, trace)
PY
```

This writes `build/cpu_predictor_eval/tuned/statistics.json` without rerunning
any CoreMark model configuration. Counting all load→conditional branches gives
87,650 pairs (section 6's two selected mnemonics gave 86,690). Counting the union
of dynamic PCs in the two hot short-loop spans gives 340,740 instructions
(section 6's backedge-only lower coverage proxy gave 339,900).

Both use GCC 15.2, RV32IM/Zicsr/Zifencei, ILP32, C11, `-Wall -Wextra -Werror`,
the `TUNED` options from `run_predictor_eval.py`, and freestanding section GC.
All model configurations are the existing `CONFIGS` and `LIMITS` from
`run_fmax_eval.py`, V3s/BTB128/PHT4096/RAS4/PC>>2, all cache hits. Initialization
is traced to warm predictor state, but only retired `start_time` through just
before `stop_time` is measured, as in CoreMark.

`vision.c` invokes showcase's `board/vision/post.c` and `sw/lib/yolo_tables.c`.
There is no `sw/apps/showcase/model/` at this revision. The fixed tensor follows
the sparse-output recipe in `sw/tests/showcase/vision/post_test.c`: 75 active cells
per head, cell `(n*37)%cells`, class `n%5`, logit `threshold+n%16`; other classes
are -128, DFL bin 3 is +32 and the other bins are -32. This is a synthetic fixed
NPU output, not a captured image inference; it exercises full class scanning,
DFL, heapsort, class-aware NMS and display-coordinate conversion.

`render.c` uses locked LVGL 9.6.0 (`80ca777e`), software drawing, builtin memory
and strings, a simple theme, and RGB565 160×120 direct rendering to RAM. It draws
a label, a button, and an eight-row flex list (LVGL's replacement for deprecated
`lv_list`). An initial refresh warms state; one full invalidation and refresh
after a 24-pixel list scroll is measured. Flush only acknowledges the RAM buffer.
This is a small software rendering sample, not the board's 1280×720 GUI or RND.

Statistics count dynamic adjacent register RAW dependencies, including memory
address/store-data uses; these are opportunities, not actual issue pairs.
Load→compare includes any conditional branch. Macro counts retain exactly
`addi→andi` and `srli→or` from section 6; pointer-chain counts retain `lw→lbu`.
Short loops are backward conditional edges spanning at most eight static
instructions; coverage counts the union of PCs in the two hottest such spans.
As in section 6, multiply coverage by global perfect-frontend savings for a
uniform-distribution estimate, not a measured local saving. One-cycle-per-pair
estimates are capped by the corresponding ideal model's global savings.

LVGL exposed a model trace-cursor bug during initialization: an unpredicted JALR
can target PC+4, allowing a trace-matching younger instruction to issue and then
be squashed. Recovery must replay that instruction. `pipe_model.py` now restores
the trace cursor on ordinary redirects too; the new directed regression reproduces
the original mismatch. No RTL changes were needed.

Validation: the initial unchanged model passed 36 tests. After discovery, the
coordinator authorized one additional full regression of the fix: 37 tests passed
with `python3 tools/cpu/eval/test_pipe_model.py`. The coordinator also requested
one additional CoreMark base run; its result is
`build/second-workloads/coremark-base-fixed.json` (unchanged at 1,877,663 cycles).
The equivalent command is:

```sh
flock -s /tmp/edrv32-sim.lock python3 tools/cpu/eval/pipe_model.py \
    build/cpu_predictor_eval/tuned --variant V3s --btb-entries 128 \
    --gshare-entries 4096 --ras-entries 4 --gshare-pc-shift 2
```

Passed vision configurations
were not rerun; the failed LVGL measurement was retried after the fix.
