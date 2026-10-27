# NPU datapath integration (D1-F)

Implements `npu-spec.md` v0.2 §5.4 and design record
`2026-10-27-npu-datapath.md` §4.2.2 without changing any of the 85 frozen ports.
The top captures layer fields and connects unpack/cache/window, resident stores,
MAC/ACC, quantization/LUT, residual prefetch/add and the result ring.
The window owns both command contexts; no extra pipeline stage is added at A5/M1,
R3/R4 prepare, Q12/WB1 or the WB2 RAM write boundary.
Pair first reserves result credit and, with RES_EN, a committed residual pair.
`idle_o` combines every pipeline/buffer owner and input unpack status.
No A–E submodule correction was needed.

## Run

From the repository root, using the tool environment and Python environment in
`docs/guides/env-setup.md`:

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_datapath'
make full REGRESS_ARGS='-j 1 --path verif/unit/npu_datapath'
python3 tools/check/verilog_style.py rtl/npu
verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
    --top-module edrv32_npu_datapath rtl/npu/*.v rtl/tech/edrv32_*npu*.v
python3 verif/unit/npu_datapath/synth.py
```

`test.yaml` uses `run.py`: each case writes a JSON configuration below
`build/npu_datapath/<case>/`, invokes `tools/npu/gen_case.py --config ...`, then
`tools/npu/ref/npu_ref.py`. A format-only adapter extracts descriptor fields,
weights, parameters, LUT, input, residual and reference beats into dense SV memories.
It performs no reference arithmetic. Verilator compiles the committed `files.f`
once with `-Wall -DSIM_MODE -j 1`, then runs cases serially.

The self-checking SV bench drives the exact N-C1 port contract, including row-done,
both residual half-banks (starting from bank 1), plane-contiguous residual scatter,
chunk grants, pipelined result reads and release after all read responses.
Every returned valid plane is compared against the independent reference.
The bench also checks command tags/order, read-done two cycles after A1,
every pair's final A1 acceptance to WB2 write latency, MAC beat totals,
chunk order/length/plane count, stability under backpressure, and empty ownership
after release/cancel.
No AXI transactions, descriptor error handling or non-CONV operators are modeled here.

## Integration evidence

Measured on 2026-10-27, based on `7aa206489c4f1afc064b74b24e5b7944208b2d7f`
plus this task's committed integration/test files. The exact final commit is supplied
in the worker completion and `build/npu_datapath/commit.txt`.
Tools: Verilator 5.020 (Debian 5.020-1), Icarus Verilog 12.0,
Yosys 0.70+219 (`5053d0e26`). All simulation builds and runs are serial (`-j 1`).

| Case / seed | Main coverage | Commands | Pairs | Compared 256-bit beats |
|---|---|---:|---:|---:|
| k1_c16 / 1 | K1 S1, Cin16, K=2/G=4 calendar, cancel then restart | 2 | 8 | 16 |
| k1_c32 / 2 | K1 S1, Cin32/Cout64, LUT, varied unsaturated quantization | 4 | 24 | 48 |
| k1_c48 / 3 | K1 S1, Cin48/Cout96 | 6 | 24 | 48 |
| k3_s1 / 4 | K3 S1 zero padding, width12, Cout80 D2 tail, LUT | 12 | 72 | 120 |
| k3_s2 / 5 | K3 S2, Cin32, odd input height5 | 3 | 9 | 18 |
| c4_full / 6 | C4 K3 S2, Cout32 | 3 | 12 | 24 |
| c4_half / 7 | C4 + HALF_TAIL, Cout16, K remains9, LUT + residual | 3 | 12 | 12 |
| d2_res / 8 | D2 K=1/G=2, Cout16, multi-batch residual, width40 | 2 | 40 | 40 |
| d2_transition / 9 | Cout80, G4→G2→G4 across blocks/rows, LUT + residual | 6 | 24 | 40 |
| backpressure / 10 | Width80, Cout80, result ring wrap, DMA stalled800 cycles | 6 | 240 | 400 |
| k1_s2 / 11 | K1 S2, residual | 1 | 4 | 8 |
| quant_limits / 12 | INT32 bias extrema, mult32767/−32768/0/−1, shift0/47 | 2 | 8 | 16 |
| Total per tier | 12 generated/reference cases | 50 | 477 | 790 |

All 477 pair writes per tier satisfy final A1→WB2 = **29 cycles dual plane /
27 cycles single plane**, including C4 half and residual enabled/disabled.
The 50 commands generate 2,388 valid M1 beats per tier.
`k3_s1` observes 11 overlapping command transitions, including three row transitions;
`d2_transition` observes five transitions including the G2→G4 row boundary.
`backpressure` keeps the head chunk stable for 800 cycles and observes zero free
credit for 879 cycles in total; all 400 beats compare correctly after recovery.
The cancellation case aborts occupied computation, checks immediate local idle,
checks no late output for 35 cycles, then configures and executes the layer again.

Integration logs: `build/regress/{smoke,full}/unit/npu_datapath/verilator/run.log`;
compiler log: `build/npu_datapath/compile.log`.
Style reports `13 files, 0 warnings`; standalone `-Wall -DSIM_MODE -Irtl/include`
lint succeeds with an empty log. Evidence is in
`build/npu_datapath/{style,lint}.log`.

## Existing unit regression

All 14 directories pass smoke and full: **19 simulator runs per tier, 38 total,
0 failures**. Reproduce serially with:

```sh
for module in accum activation_lut axi256_mem datapath input_unpack line_cache \
              mac_array quant_param_store residual_add residual_buffer result_quant \
              weight_store window writeback; do
    make smoke REGRESS_ARGS="-j 1 --path verif/unit/npu_${module}"
    make full REGRESS_ARGS="-j 1 --path verif/unit/npu_${module}"
done
```

| Module | Simulators per tier |
|---|---|
| accum | Verilator |
| axi256_mem | Verilator, zero/latency/bw (unchanged model) |
| activation_lut | Verilator + Icarus |
| datapath | Verilator, 12 cases |
| input_unpack | Verilator |
| line_cache | Verilator |
| mac_array | Verilator |
| quant_param_store | Verilator + Icarus |
| residual_add | Verilator |
| residual_buffer | Verilator |
| result_quant | Verilator |
| weight_store | Verilator + Icarus |
| window | Verilator |
| writeback | Verilator |

Commands and aggregate results are captured in `build/npu_datapath/regression.log`
and `build/npu_datapath/regression_final.log`; individual logs are under `build/regress/{smoke,full}/unit/npu_<module>/`.

## Logic-depth reference

`synth.py` reads the fixed tech wrappers as registered black-box boundaries, renames
them to the existing `tools/synth/netlist_paths.py` `ip_*` convention, flattens the
business RTL, runs generic `abc -lut 6 -dress`, and invokes that analyzer.
The complete generated script and raw logs are under `build/npu_datapath/synth/`.

The measured maximum is **21 generic LUT6 levels** (79 endpoints at that depth),
including a path from ACC's R4 bit0 to accumulated bit31; quantization's wide
rounding/zero-point adders also reach that depth. The proxy contains 39,760 LUTs,
31,505 FFs and 340 registered IP black boxes (288 multiplier and 52 RAM wrappers).
Yosys reports conversion of small pipeline/metadata arrays to registers; these are
not Verilator lint warnings. No vendor carry mapping, placement or routing is included.
**PDS remains the authority for timing, resources and 150 MHz closure.**
Remaining work belongs to the coordinator: independent block integration and the
standalone datapath PDS task; this task does not merge or clean the worktree.
