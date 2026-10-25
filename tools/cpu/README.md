# CPU reference tools (C-V1)

Run from the repository root, after loading the installed xPack GCC 15.2.0 and Spike:

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/build_tests.py
python3 tools/cpu/test_trace_compare.py
```

The first command builds and runs all applicable tests: **65 riscv-tests**
(41 rv32ui, 8 rv32um, 1 rv32uc, 15 rv32mi) and **92 architectural tests**
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
SRAM `0x10000000:0x40000`, and DDR `0x80000000:0x40000000` (SoC spec 6.1).
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
The self-test above converts all 65 real Spike logs to this RTL format, compares
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
