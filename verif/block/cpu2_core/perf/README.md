# A00 hot structural microbenchmarks

`kernels.S` selects 38 fixed streams through `CASE`; each stream repeats its payload 64 times.
One call warms the same kernel and data before the measured call. Separate jumps warm the
marker and tail lines, including speculative instruction fetches. `start_time` and `stop_time`
measure retirement of the call through its return. Both markers are outside the repeated body.
The original CoreMark runner in this directory remains unchanged.

Run from a frozen repository snapshot on the simulation host with GCC 15.2, Spike 1.1.1-dev
and Verilator 5.051:

```sh
/usr/bin/python3 tools/cpu/run_model_conformance.py build
/usr/bin/python3 tools/cpu/run_model_conformance.py run
/usr/bin/python3 tools/cpu/run_model_conformance.py lint
```

`--names load_stream load_use` selects individual streams. Generated files stay under
`build/cpu2-conformance/`: each case has the ELF, Spike log, numeric disassembly, model JSON,
three RTL logs/traces, and two cycle CSV probes. `cycles.json` contains the measured table.
CSV `cycle` is decimal; every other field is hexadecimal. `probe_tb.sv` only observes signals.
Expected register results and instruction order come from Spike, never DUT internal signals.
The run fails immediately on any cycle-run or architectural trace mismatch.

All three RTL runs consume the same ELF-derived memory image. The RTL image adds a reset
trampoline at address zero; Spike starts at the ELF entry in DDR, since the installed Spike's
debug module occupies address zero. Architectural comparisons begin at the identical ELF entry.
The timed region and complete warm-up kernel are identical. The reference checks PC, encoding,
rd and integer result through the tohost store. The three store kernels also check final
cached store values in software after stop_time.

Model W1 uses `BASES['small']`; W2 uses `BASES['full']` plus `EXPERIMENTS['combo4-zba']`,
including the fresh RAM TAGE predictor. Both preserve `IcacheProbe(1)`, the registered frontend
margin and C07's operand-dependent DIV schedule. Primary columns use original defaults
`completion_entries=0`, as confirmed by the coordinator; extra N4 columns diagnose the frozen
four-entry completion window. Existing model files and defaults are never edited by this runner.
N4 is a diagnostic approximation and is not expected to match every RTL retirement edge.

The old RTL is the unchanged `verif/block/cpu/b1` competition core with its normal zero-miss
cache interface models. CPU v2 uses its real caches plus the existing shared AXI64 BFM. Thus
warm steady-state comparisons isolate structure, while short entry/return differences remain
visible. Both v2 widths must report zero timed I$/D$ miss-state cycles for a hot-cache result.
No frequency, FPGA resource or PDS timing result is inferred from these simulations.

The build/lint commands waive only Verilator 5.051's new `PROCASSINIT` warning for declaration
initializers in the existing verification harnesses; `-Wall` remains fatal for all other warnings.
