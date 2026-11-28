# FPU vector interchange

Every line contains nine whitespace-separated hexadecimal fields, without header
or comments:

```
instr rm src1 src2 src3 int_src expected_data expected_flags int_dest
```

Widths: 32, 3, 64, 64, 64, 32, 64, 5, 1 bits respectively. Integer results are
zero-extended RV32 bit patterns; FP S results are zero-extended for F and boxed
for FD. Flags are RISC-V NV/DZ/OF/UF/NX in bits 4..0. rm is already resolved;
`instr` is an actual RISC-V encoding, with f0/x0 destination and f1/f2/f3 inputs.
Register indices are stimulus labels only; reference results include an x0 result
value before architectural suppression. Files are divided by operation, source
precision and rounding. FCVT.S.D uses source precision 64; FCVT.D.S uses 32.

Compile `edrv32_fpu_vectors_pkg.sv` before the consuming testbench, import
`edrv32_fpu_vectors_pkg::*`, then call `open_vectors`, `read_vector` and
`compare_response`. Close the descriptor with `$fclose` after `available=0`.
The comparison reports operation encoding, raw inputs, rm, expected/actual data,
flags and destination domain, then stops on failure.

The FPU top contract checks all 64 FD bits. Arithmetic unit tests for S should
adapt FD boxed vectors to the unit boundary by selecting the low 32 input bits
and clearing expected upper 32 bits after top-level boxing validation. Invalid
boxing is a top-level semantic test; do not drop its upper bits before that
validation. The pure reader test under `verif/unit/fpu_ref_check` exercises file
round-trip, comparison and EOF without any RTL implementation.
