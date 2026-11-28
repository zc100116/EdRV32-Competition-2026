# CPU v2 DIV CV06

Run `python3 tools/regress.py smoke --path verif/unit/cpu2_div -j 1` from the repository root.
The six configurations cover ISSUE_WIDTH=1/2 and FPU_FORMAT=NONE/F/FD.
The independent 64-bit reference checks all four instructions, all input-sign pairs,
bit lengths 0..32, zero divisors, overflow, 1600 deterministic random operations per configuration,
normal latency 3+n, special latency 2, normal II=L, backpressure, wrap, cancellation and tag reuse.
Cancellation covers E0, preparation, each iteration, correction, special completion and held results.

For a generic LUT6 reference (carry chains are expanded into LUTs):

```sh
yosys -Q -T -p 'read_verilog rtl/cpu2/edrv32_cpu2_div.v; synth -top edrv32_cpu2_div -noabc; abc -lut 6; write_json build/cpu2_i03/div-lut6.json; ltp -noff'
python3 verif/unit/cpu2_div/levels.py build/cpu2_i03/div-lut6.json
```

E0 captures raw sources and magnitudes in parallel; E1 registers the leading-position difference
and 3x divisor; E2 forms n and aligns; E3 begins iteration; E(3+n) corrects and captures the result.
This internal split was approved by the coordinator without changing C07's public L/II.
The public input's preceding issue selection and PDS carry mapping require integrated timing evidence.
