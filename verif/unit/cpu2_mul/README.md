# CPU v2 MUL CV06

Run `python3 tools/regress.py smoke --path verif/unit/cpu2_mul -j 1` from the repository root.
The six configurations cover ISSUE_WIDTH=1/2 and FPU_FORMAT=NONE/F/FD.
The independent signed/unsigned reference checks four product forms, boundary operands,
800 deterministic random operations per configuration, latency 4, four consecutive requests,
backpressure, cancellation in every stage and at E0, completion cancellation, tag wrap and reuse.
The test drives only public ports. Timing/PDS evidence is separate from functional simulation.
