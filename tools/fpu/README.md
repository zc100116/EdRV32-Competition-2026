# Independent RISC-V F/D reference

Implements fpu-spec v0.2 2.1–2.3 and the numeric/bit-vector portion of
fpu-testplan v0.2 FV01–FV09 / FT01. No FPU RTL was read. SoftFloat and TestFloat
are unmodified Release3e source copies; actual upstream commits, import date and
licenses are in their `third_party/berkeley-*/README.md` and `COPYING.txt` files.
The upstream repositories are [SoftFloat](https://github.com/ucb-bar/berkeley-softfloat-3)
and [TestFloat](https://github.com/ucb-bar/berkeley-testfloat-3).

Run from the repository root (Python standard library, GCC, make, Verilator 5):

```sh
python3 tools/fpu/build.py
python3 verif/unit/fpu_ref_check/check.py
python3 tools/fpu/generate.py --tier smoke --format F --output build/fpu/smoke-f
python3 tools/fpu/generate.py --tier smoke --format FD --output build/fpu/smoke-fd
python3 tools/fpu/generate.py --tier full --format F --output build/fpu/full-f
python3 tools/fpu/generate.py --tier full --format FD --output build/fpu/full-fd
python3 tools/regress.py smoke --path verif/unit/fpu_ref_check -j 1
```

Builds use upstream Linux-x86_64-GCC recipes with `SPECIALIZE_TYPE=RISCV`,
`SOFTFLOAT_FAST_INT64`, `SOFTFLOAT_ROUND_ODD`, `INLINE_LEVEL=5`,
`SOFTFLOAT_FAST_DIV32TO16`, `SOFTFLOAT_FAST_DIV64TO32`, PIC and `-O2`.
TestFloat enables `FLOAT64`; wrappers compile C11 with `-Wall -Wextra -Werror`.
All objects, executables, vectors and logs reside under `build/`.
`Reference.evaluate` uses global SoftFloat state and must be called sequentially.

Each opcode/precision/applicable rounding produces one `.vec` file. F has only S;
FD has S and D, with S source/result boxing retained in the vectors. Five rounding
modes are encoded as RISC-V rm 0..4. Non-rounding operations use rm=0. Exact D.S
conversion is also exercised for all five rm values. TestFloat is invoked with
`-tininessafter -exact`; the wrapper explicitly resets flags and selects
`softfloat_tininess_afterRounding` on every call.

Smoke adds all custom boundary cases and 32 samples from each **complete**
TestFloat level1 stream, generator and sampling seed 0. The reservoir sampler
uses SplitMix64 and algorithm R, consuming the entire stream; it does not take a
prefix. FMA variants reuse the same sampled `mulAdd` cases with sign-transformed
inputs, giving each opcode its own instruction and expected result. Identical
TestFloat invocations are reused in memory during one Python process.

Full adds the **untruncated level2 stream**, seed 0, for every supported TestFloat
opcode/precision/rounding class, plus seeds 0..9, each sampled over its complete
level2 stream with that same sampling seed, yielding 10000 extra cases per seed.
The pinned upstream f32 unary level2 stream has 8800 cases; those sampled runs
use `-n 10000` to extend it. The untruncated base stream retains all 8800.
This full mode is intentionally extremely large (ternary level2 can exceed
100 billion rows per invocation); it has no truncation or implicit budget.
RISC-V-only operations use 32 (smoke) or 10000×10 (full) Python raw-bit random
cases in addition to every fixed boundary. Every output directory records actual
per-class directed/random/level2 counts in `counts.txt` and the exact TestFloat
and sampling commands in `commands.txt`. Full generation is provided but the
F05 acceptance run only runs smoke plus a complete unary level2 cross-check.

The RISCV specialization supplies canonical NaNs and signed/unsigned RV32
conversion saturation. `reference.c` supplies minimumNumber/maximumNumber,
signed-zero ordering, quiet/signaling comparison behavior, ten-way FCLASS,
payload-preserving FSGNJ/moves, and NaN-boxing exceptions. Arithmetic including
all four FMA variants uses SoftFloat; expected values never use host `float`.
Load/store vectors model only raw transfer/boxing, not memory ordering or beats.
`store` returns source1 raw low width bits and `int_dest=0` as a bit-model check;
it must not be issued to the arithmetic unit as an architectural writeback.

The hand tests independently assert known values, including the S fused example
`(1+2^-23)(1-2^-23)-1=-2^-46`, its D counterpart and all sign variants,
`0*infinity+qNaN` with NV, integer conversion saturation, ties, flags and boxing.
Generated TestFloat cases additionally compare wrapper results/flags against
TestFloat's original expected fields before writing the vectors.

Architectural illegal instructions/rm/frm, NONE/FS-Off visibility, CSR sequencing,
f0/register dependencies, bus beats and cancellation require the later CPU/unit
DUT tests; this task does not modify F02/F03/F04 testbenches. ISSUE_WIDTH does not
affect this pure numeric reference.

## F05 acceptance evidence (2026-11-28)

`python3 tools/regress.py smoke --path verif/unit/fpu_ref_check -j 1` passed:
301 hand-computed assertions, 144000 complete-unary-level2/ten-seed comparisons,
F and FD smoke generation, Verilator `--lint-only -Wall` with zero warnings, and
self-checking SV reader/compare/EOF simulation. Generation measured F=26.794 s
(78 classes, 52300 vectors), FD=41.957 s (164 classes, 109779 vectors).
A separate fresh-process FD smoke run on the development host measured 34.566 s
with the final bounded sample cache. A later fresh run on the shared simulation
host took 230.045 s with identical counts and no reference mismatch; elapsed
time varies across host load conditions. No local HDL simulation was needed.
A class is one opcode × source precision × applicable rounding mode.

| Configuration / source precision | Classes | Directed per class | Sampled per class |
|---|---:|---:|---:|
| F S binary | 28 | 961 | 32 |
| F S unary | 19 | 31 | 32 |
| F S fused | 20 | 1095 | 32 |
| F S integer source | 11 | 37 | 32 |
| FD S binary | 28 | 1023 | 32 |
| FD S unary | 24 | 62 | 32 |
| FD S fused | 20 | 1188 | 32 |
| FD S integer source | 11 | 68 | 32 |
| FD D binary | 28 | 961 | 32 |
| FD D unary | 23 | 31 | 32 |
| FD D fused | 20 | 1095 | 32 |
| FD D integer source | 10 | 37 | 32 |

Full keeps these same directed counts, adds the actual complete level2 count
for each TestFloat class and 100000 sampled/random cases per class. Complete
full F/FD generation was not run for this acceptance. Detailed counts and
commands are generated alongside each run's vectors. The repository style
checker reports zero warnings (it checks `.v`/`.vh`, so these SV verification
files are checked by Verilator); Python compilation and C warning checks pass.
Imported upstream whitespace is preserved; `git diff --check` is applied to
project-owned integration files, excluding the upstream copies.
