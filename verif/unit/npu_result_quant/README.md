# NPU result quantization unit

`tb_npu_result_quant.sv` checks npu-spec v0.2 sections 2.3/5.4/5.5 and
D1-D in the datapath design section 5.2 (TL-01, OP-05, OP-08).
It supplies the frozen two-edge parameter/LUT responses directly, without
requiring the D1-B storage implementations.

The scoreboard implements the specification formula in signed 64-bit arithmetic.
It independently checks parameter request addresses, all sixteen unsigned LUT
indices, residual prefetch addresses, complete output data/tags, and exact valid
cycles. Stimulus includes INT32 accumulator/bias extrema and sums beyond INT32,
low-17-bit sign boundaries, negative/zero/maximum/minimum multipliers, shifts
0/1/7/8/31/47, signed rounding, zero points and saturation, and LUT indices
0/127/128/255. Block-dependent LUT permutations distinguish unsigned indices and
stale block tags. LUT bypass uses the same output calendar.

256 pairs run continuously at four/two cycles per pair, including G4 -> G2 -> G4
transitions, different blocks, tags, output zero points and LUT/residual flags.
Half output is exercised with both d2 values. Cancellation is checked at every
boundary from preparation through the final Q12 cycle, with subsequent reuse.

The first parameter request is sampled at R4 edge `p`; ACC output is presented
before Q0 at `p+2`. Q12 for group `g` is `p+14+g`, so the complete pair appears at
`p+17` (G4) or `p+15` (G2). Each group has exactly twelve cycles from Q0 to Q12.
The last group's residual low/high requests are sampled at its Q10/Q11 edges.

Reproduce from the repository root after loading the tool environment:

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_result_quant'
make full REGRESS_ARGS='-j 1 --path verif/unit/npu_result_quant'
python3 tools/check/verilog_style.py rtl/npu/edrv32_npu_result_quant.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
  --top-module edrv32_npu_result_quant \
  rtl/npu/edrv32_npu_result_quant.v \
  rtl/tech/edrv32_mul_npu_quant_low.v \
  rtl/tech/edrv32_mul_npu_quant_high.v
```

Regression compile/run logs are under
`build/regress/{smoke,full}/unit/npu_result_quant/verilator/`.
The simulation build also uses `-Wall`, with no warning suppressions.
Windows vendor-model equivalence and PDS timing/resource measurements remain
with the integration/IP tasks.

Observed with Verilator 5.020: smoke and full each report `1 PASS, 0 FAIL`;
the self-check completes 274 pairs, 464 LUT groups and 370 residual reads.
All four LUT boundary indices are observed. Style reports `1 files, 0 warnings`,
and the standalone `-Wall -DSIM_MODE -Irtl/include` lint exits successfully with
an empty log. The corresponding style/lint logs are
`build/npu_result_quant/{style,lint}.log`.
