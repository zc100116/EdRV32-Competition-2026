# NPU accumulator unit test

The self-checking test implements D1-C from design record
`docs/design/2026-10-27-npu-datapath.md` 5.2, covering NPU testplan
OP-01/02/07/08 at the R3 boundary. The reference accumulates complete pair sums
from independently driven signed physical-channel terms.

Run from the repository root after loading the tool environment:

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_accum'
make full REGRESS_ARGS='-j 1 --path verif/unit/npu_accum'
python3 tools/check/verilog_style.py rtl/npu/edrv32_npu_accum.v
tools/check/lint.sh -DSIM_MODE -Irtl/include --top-module edrv32_npu_accum \
    rtl/npu/edrv32_npu_accum.v
```

Coverage includes 19-bit signed input extremes reachable from eight INT8
products, positive/negative and mixed D2 halves, different pixel results,
long reductions, first replacing old data, first/last together, last-only
output, invalid first/last bubbles, continuously changing block/row tags,
ordinary → D2 → C4 half transitions, cancellation and reset while occupied.
All 64 INT32 values and all tag bits are compared. The random stream uses
seed `0x1accc602`.

Ordinary terms sign-extend through R4; D2 merges c/c+16 to 20 bits and fills
the high 16 output channels with zero. Both modes have the same two register
boundaries, R4/ACC. With R3 inputs stable before edge e, prepare/tag are already
present combinationally and sampled with R4 at e; the last item's final
accumulated vector is visible after ACC at e+1. The test checks prepare before
any clock edge and also samples it like the parameter RAM, then checks the
corresponding final vector exactly one boundary later.

Logs are under `build/regress/{smoke,full}/unit/npu_accum/verilator/`.
Whole-datapath Q0 parameter alignment and 29/27-cycle tails remain D1-F
integration work; this unit test checks the frozen R3/R4/ACC contract.
