# DISP GPU variant verification

Scope: gpu-soc-spec v0.2 §8.2 on the DISP v0.4 implementation.
The visual project's RTL and tests remain unchanged.

| Item | Tier | Evidence |
|---|---|---|
| ST-04 | full | All 75 original DS-01–19 instances and Python/SV blend reference retained |
| ST-05 | smoke/full | Case 20: nonzero SCROLL (32,3), 640×360 source window, every 1280×720 received pixel, all 720 row addresses and 28,800 read beats |
| ST-06 | full | Case 21: X2 → native → X2 frame latching, L1 rectangle/OPA blending, both-layer underflow and disabled-frame debt repayment, recovered frame alignment |
| ST-07 | full | `tb_urgent`: exact occupancy 39/40 and native 80/81, shadow mode change, paired source rows, exact 40-beat FIFO admission |

The TMDS receiver and APB/AXI scoreboards are copied from `verif/block/disp/`.
X2 expected source coordinates are `(SCROLL_X+x/2, SCROLL_Y+y/2)`.
Underflow patterns separate L0 red and L1 blue so missing beats can be inferred
from received pixels and checked independently. The scan unit also runs its
complete directed debt schedules with both 16- and 32-output-pixel groups.
Only the register readback expectation changes for the newly implemented bit 2.

Run on the simulation host after sourcing the project environment:

```sh
python3 tools/regress.py smoke -j 1 --path verif/block/disp_gpu
python3 tools/regress.py full -j 1 --path verif/block/disp_gpu
python3 tools/regress.py full -j 1 --path verif/unit/disp_reader_gpu
python3 tools/regress.py full -j 1 --path verif/unit/disp_regs_gpu
python3 tools/regress.py full -j 1 --path verif/unit/disp_scan_gpu
python3 tools/regress.py full -j 1 --path verif/unit/disp_layers_gpu
```

`run.py x2full` runs only ST-06/07; `run.py full` includes all ST-04–07.
Builds and case logs use `build/disp_gpu/`; regression summaries use
`build/regress/`. Builds use one job; full runs six independent cases concurrently, leaving host capacity
for other workers. `run.py full --parallel 1` selects serial case execution.
Results, lint commands and original-to-variant diff counts are in `results.md`.

The copied Python TMDS model uses binary-string population counts so the same
reference algorithm runs with the supplied host's Python. Test builds retain the
original BLKSEQ/UNUSEDSIGNAL/SYNCASYNCNET behavioral waivers and additionally waive
PROCASSINIT/ZERODLY diagnostics emitted by the host compiler for the original
initialized test signals and variable clock delays. RTL top lint has no waivers.
