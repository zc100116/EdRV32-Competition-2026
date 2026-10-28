# CPU reference tools (C-V1)

Run from the repository root, after loading the installed xPack GCC 15.2.0 and Spike:

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/build_tests.py
python3 tools/cpu/test_trace_compare.py
```

The first command builds and runs all applicable tests: **64 riscv-tests**
(41 rv32ui, 8 rv32um, 1 rv32uc, 14 rv32mi) and **92 architectural tests**
(39 I, 8 M, 29 C, 1 Zifencei, 15 privilege).
Use `--suite riscv-tests` or `--suite arch-test` to run one suite.
All generated files live in `build/cpu/{riscv-tests,arch-test}/<test>/`:
ELF, compiler diagnostics (`build.log`), `rom.hex`, `sram.hex`, `ddr.hex`,
absolute byte-addressed `mem.hex`, and `spike.log`. Architectural tests also
produce `reference.signature` through Spike's HTIF signature output, using the
ELF's `begin_signature` / `end_signature` symbols and 32-bit words.

`tools/elf2mem.py` creates the three region-relative byte images; the builder
combines those images into `mem.hex` for B1's `+MEM_HEX=` loader.
`verif/block/cpu/env/link.ld` places the reset trampoline at ROM address zero,
test code in DDR (writable for FENCE.I self-modifying tests), and data/tohost in
SRAM. `boot.S` jumps to the upstream test entry. The riscv-tests p environment
is adapted to run every test in M mode, without probing unimplemented S-mode,
PMP, RNMI or delegation CSRs. Sources are copied into `third_party/`, not submodules.

## Reference configuration

```sh
python3 tools/cpu/run_spike.py path/to/program.elf build/cpu/program
python3 tools/cpu/run_spike.py path/to/program.elf build/cpu/program --signature
python3 tools/cpu/run_spike.py path/to/noncompressed.elf build/cpu/program --no-c
```

Spike uses `rv32imc_zicsr_zifencei_zicntr_zihpm`, `--priv=m`,
`--pmpregions=0`, `--no-dm`, `--pc=0`, `--disable-dtb`, `-l --log-commits`.
`--no-c` removes C from the reference ISA; its input ELF must itself run without C.
The upstream architectural suite builder targets the C-enabled configuration;
its alignment macros can emit C instructions even in I-only tests.
Zicntr/Zihpm name the counters already present in cpu-spec section 5; enabling
them was confirmed by the coordinator. Flat memory covers ROM `0:0x4000`,
SRAM `0x10000000:0x10000`, and DDR `0x80000000:0x40000000` (SoC spec 6.1).
This is an instruction reference, not a model of ROM write protection or devices.
`tohost` comes from the ELF symbol, never from a fixed device address.
A nonzero test failure propagates Spike's exit status. Spike polls tohost in
batches; `spike.log` ends at the first nonzero store to the ELF tohost address,
matching the B1 termination point rather than including subsequent polling-loop commits.

## RTL retirement trace

```text
00000000 800002b7 05 80000000
00000004 00028067 00 00000000
trap 0000000b
```

Each retirement is four hexadecimal fields: `PC instr rd value` (no `0x` required).
Fields are taken from cpu-spec 3.4's `trace_pc_w`, `trace_instr_w`, `trace_rd_w`,
and `trace_rd_data_w`, when the corresponding `trace_valid_w` bit is asserted.
A 16-bit compressed instruction retains its original encoding, zero-extended to
32 bits. No GPR writeback means `rd=0 value=0`; x0 writes have the same meaning.
On dual retirement, the producer emits pipeline 0 first and pipeline 1 second.
After the older retirements, trap entry emits `trap mcause` from
`trace_trap_w` / `trace_cause_w`; a trapping instruction does not retire.
There is no cycle field: the file's order is architectural order.

```sh
python3 tools/cpu/trace_compare.py build/cpu/program/rtl.trace build/cpu/program/spike.log
```

The comparator reads Spike's commits, GPR writes and trap/interrupt events,
ignores disassembly and memory/CSR side effects, and compares ordered events.
It reports the first mismatch, printing both PC, instruction, rd and writeback
value (or mcause for a trap), and returns 1. A missing/extra event also fails.
The self-test above converts all applicable real Spike logs to this RTL format, compares
them, flips the first writeback value in the add test and verifies the failure
index and nonzero exit status. It also verifies the counter-value waiver while
keeping counter rd mismatches detectable. Evidence is in `build/cpu/trace-compare/`.

Architectural signatures must also be compared; normal termination alone is
not an architectural-test pass:

```sh
python3 tools/cpu/compare_signatures.py path/to/rtl.signature \
    build/cpu/arch-test/I-add-01/reference.signature
```

Dump RTL memory from `begin_signature` inclusive to `end_signature` exclusive,
one 32-bit hexadecimal word per line in increasing address order. The comparator
stops on the first word difference or length difference and exits nonzero.

## Upstream applicability

The coordinator approved these scope decisions:

| Suite | Selection / exclusion |
|---|---|
| riscv-tests | All rv32ui/um/uc/mi `.S` files, p environment, except the two below |
| rv32ui-p-ma_data | Excluded: requires successful misaligned accesses; cpu-spec 4.7/6 requires mcause 4/6 |
| rv32mi-p-ma_fetch | Runs on Spike; RTL uses upstream tohost self-check only, no commit comparison (misa.C probing) |
| rv32mi-p-breakpoint | Excluded by coordinator: requires debug triggers absent from cpu-spec 2.1; C-01 verifies illegal trigger-CSR access |
| rv32mi-p-pmpaddr | Excluded: specifically tests PMP, which cpu-spec does not implement |
| arch-test | Signature-based upstream release 3.10.0; rv32i_m I/M/C/Zifencei/privilege |
| C directory Zcb/Zbb tests | Not applicable: require extensions outside cpu-spec 2.1; retained as upstream source |
| Zicsr | No standalone instruction suite in release 3.10.0; covered by riscv-tests CSR tests and C-V4 C-01, per coordinator |

The misaligned exception tests in rv32mi remain enabled. All architectural
privilege tests in this selected release run in M mode; no S/U/PMP tests are selected.
Upstream CSR probes are not a substitute for cpu-spec's CSR reset/value tests:
Spike's writable misa and instruction-based counters differ from this RTL's
read-only misa and cycle timing. The coordinator approved a precise counter waiver: for CSR instructions reading
`mcycle/minstret/mhpmcounter3–10` and high halves (`B00`, `B02–B0A`, `B80`,
`B82–B8A`), or `cycle/time/instret/hpmcounter3–10` and high halves
(`C00–C0A`, `C80–C8A`), compare PC, instruction and rd, and omit only the
writeback-value comparison. The explicit CSR set is in `trace_compare.py`.
All other writeback values remain compared. `rv32mi-p-ma_fetch` uses tohost
self-check only on RTL. Interrupt timing tests use B1 self-checking programs
per testplan 3.5.

## Random instruction streams (C-V3 / P-09)

```sh
. ~/.local/opt/edrv32/env.sh
# Generate assembly only, without C (default), or with explicit C instructions.
python3 tools/cpu/randgen.py generate high-dep 17
python3 tools/cpu/randgen.py generate high-dep 17 --c
# Generate, build B1 images, and run Spike; seed upper bound is exclusive.
python3 tools/cpu/randgen.py batch high-dep 0 50
python3 tools/cpu/randgen.py batch high-dep 0 50 --c
# Full generator acceptance: four configurations, 50 seeds, both ISA variants.
for config in high-dep low-dep memory branch; do
    python3 tools/cpu/randgen.py batch "$config" 0 50
    python3 tools/cpu/randgen.py batch "$config" 0 50 --c
done
```

`randgen.py` contains the complete configuration table: instruction category
weights, source dependency distance weights, data offset range, branch/jump
distances, stream length, compressed ALU fraction, and WAW probability. Only the
configuration name, seed (or batch seed range), and C selection are exposed.
`high-dep` favors adjacent producers; `low-dep` selects sources at least four
instructions after their producer; `memory` favors loads/stores; `branch` favors
conditional branches, JAL and JALR. The same configuration, seed, and C selection
produce identical assembly independently of Python's process hash seed.

Each stream has 1,024 generation slots. A JALR slot uses two additional explicit
address instructions, so emitted instruction counts and category proportions
include that overhead. Normal instructions remain 32-bit; `--c` additionally
generates explicit 16-bit C.ADD, C.MV, C.ADDI and C.LI, mixing instruction lengths
and halfword positions without assembler-selected compression. Register sources
are initialized, x8 is the immutable data base, and x31 holds only generated
JALR targets. All byte/halfword/word memory operands lie within initialized
`rand_data` and have natural alignment. All control-flow targets move forward
to generation-slot labels, bounding execution even when branches are taken.
CSR operations use only writable `mscratch`; FENCE/FENCE.I do not modify code.
Division by zero is legal RV32M behavior. No exception-generating system
instruction, interrupt enable, counter-dependent value, or arbitrary indirect
target is emitted. The program ends by writing 1 to the ELF's `tohost` symbol.

Artifacts are under `build/cpu/rand/<config>/{c,no-c}/seed-<seed>/`:
`program.S`, `program.elf`, `program.dis`, `build.log`, the three region images,
absolute-addressed `mem.hex` for B1 `+MEM_HEX=`, and `spike.log`. Programs link
against the same `verif/block/cpu/env/{boot.S,link.ld}` as C-V1. Nonzero tool
exits and unexpected Spike traps fail the batch immediately. B1 can compare
its retirement trace with `spike.log` using `trace_compare.py`; randomized cache
misses/backpressure and cycle-level pairing/bypass/stall coverage belong to B1
and the integration regression.

Each batch writes `statistics-<first>-<stop>.txt` in its ISA directory. It reports
both the generated static body and the body instructions actually retired by
Spike, excluding startup and tohost handling. Categories count instructions;
RAW distances count source operand occurrences in mutable GPRs (x1–x30 except
the fixed x8 base), including implicit C read-modify-write operands. Distances
1/2/3 mean that many body instructions since the last write; `4-8` and `9+`
are buckets; `entry` means the last write preceded the body. x0 and reserved
address registers are excluded from dependency statistics. Forward jumps can
change dynamic producer distances by skipping static producers or intervening
instructions, so both distributions are shown. No CPU cycle timing is inferred
from Spike.

Acceptance run: seeds 0–49 in each configuration and each C mode, **400/400
normal Spike terminations**, Python 3.12.3, xPack GCC 15.2.0, Spike 1.1.1-dev.
The table shows dynamic proportions (ranges span C disabled/enabled); full
category and distance counts are in the eight `statistics-0-50.txt` files.

| Configuration | ALU | Load + store | Branch/jump | RAW distance 1 | RAW distance 9+ |
|---|---|---|---|---|---|
| high-dep | 55.35–55.65% | 19.70–19.78% | 4.73–5.04% | 69.16–69.75% | 3.90–4.12% |
| low-dep | 78.00–78.13% | 8.97–9.10% | 4.01–4.03% | 0.02% | 85.79–86.01% |
| memory | 18.38–18.57% | 67.56–67.57% | 3.92–4.09% | 32.19–32.50% | 17.74–17.88% |
| branch | 41.38–42.01% | 12.43–12.87% | 35.17–35.56% | 26.93–27.29% | 31.24–31.27% |

The low-dep static body has no RAW distances 1–3. Forward jumps occasionally
shorten dynamic distances, accounting for the small dynamic distance-1 fraction.

## Real-core integration regression (C-I1/C-I2)

`python3 tools/cpu/generate_regress.py` materializes 746 B1 descriptors under
`verif/block/cpu/`: 127 riscv-tests configurations, 155 arch-test configurations,
64 directed configurations, and 400 random streams. Run `make smoke` then
`make full` with the installed tool environment loaded. The only upstream RV32UC
source is `rvc.S`; smoke uses the coordinator-approved minimum of three or
the number of applicable sources, running that single C source and three from
each other ISA class.

Both RVC settings run all applicable non-C programs; C programs run with RVC
only. The no-C arch build uses build-local macro copies to remove temporary
RVC alignment padding, without changing upstream test sources. E-01 no-C also
checks an illegal C encoding and misaligned jump target (I-03).

The runner builds and reuses one real-core Verilator binary per RVC setting,
resolves ELF symbols into model plusargs, and compares successful tohost runs
through the architectural tohost-store endpoint. Architectural signatures are
also compared word for word. The Spike extension `spike_config.cc` configures
implementation-ID CSRs to zero through Spike's CSR API; it implements no
instructions. Spike runs with triggers disabled. No GPR comparison waivers were
added; the existing counter-read waiver and ma_fetch exception remain explicit.

As approved by the coordinator, 17 directed test IDs use the same ELF for strict
retirement comparison (34 RVC configurations). The 14 existing `spike=smoke`
IDs use complete B1 software self-checks plus independent observers, with
separately built `SPIKE_SMOKE` reference sanity runs (28 configurations).
Two additional M-04 configurations inject an interrupt during FENCE.I clean,
checking delayed interrupt entry and the modified code's result. Output labels
these 30 configurations `mode=b1-selfcheck`; they are not counted as Spike
retirement comparisons. Random streams always compare with Spike, and use
randomized I/D misses and ready backpressure with the program seed.

Per-program ELF/images, RTL traces, signatures, simulator logs, obligation tables,
predictor snapshots and real coverage live under `build/cpu/`; regression status
logs live under `build/regress/{smoke,full}/`. Artificial coverage self-test files
under `build/cpu-coverage-selftest/` must never be merged into real CPU coverage.
