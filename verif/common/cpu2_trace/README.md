# CPU v2 retirement comparator (V01)

`edrv32_cpu2_trace_check.sv` is a simulation-only checker. It never reads CPU RTL, RFs,
cache arrays, or implementation expressions. Connect every `trace_*_i` to the corresponding
CPU top-level internal `trace_*_w` wire; [the self-test bench](../../unit/cpu2_trace_check/tb.sv)
provides a complete named-port example. Only `ISSUE_WIDTH=1/2` and
`FPU_FORMAT="NONE"/"F"/"FD"` select configurations. Tag width is 2/3/4 respectively.
The physical source ports are source0..4, with unused ports tied to zero; the active
source counts are NONE 2/4, F 3/5, FD 2/4 for single/dual issue.

Drive reset before the first sampling edge. Trace is sampled at the retirement rising edge,
**before** the registered WB outputs update. WB/RF writes one edge later must not move
this observation point. Low packed fields are the older slot. The checker consumes each
retirement and then any younger trap in that order, compares the final fflags/frm/FS once
per cycle, and does not consume a retirement record for a faulting instruction. The
expected state is held across idle cycles; actual architectural payloads are ignored
when neither retirement nor trap is valid. Pulse `finish_i` after the final event and all
BFM observations; the checker checks exhausted streams/queues and prints PASS. The caller
then ends simulation. Any mismatch prints field, expected/actual, retirement count and time,
and calls `$fatal(1)`.

Purpose-domain encoding is 0=no write, 1=integer, 2=FP. Integer x0 is no write; FP f0 is
a real write. Integer and F-format values have zero high 32 bits; FD values retain all
64 bits, including NaN boxing. Memory addresses retain their original byte address;
data is low aligned, zero padded, before sign extension/boxing, with size mask 1/3/F/FF.

The coordinator confirmed these scope clarifications while V01 was implemented; the
updated fpu-testplan section 4 records the Spike limitations:

- Spike supplies PC/instruction, rd/domain/raw result, explicit CSR writes, accumulated
  fflags/frm and FS transitions, traps, memory addresses and store data. `fcsr` explicit
  writes are reconstructed from Spike's constituent c1_fflags/c2_frm writes. FS starts
  Off, becomes Dirty on logged FP writes/flags writes or explicit FP CSR writes, and
  follows explicit mstatus writes. A load's raw low bytes come from its logged rd value.
- Per-instruction FP flags cannot be recovered from accumulated sticky flags. They remain
  a SoftFloat/TestFloat unit-test obligation. All trace flags ports remain connected;
  NONE additionally checks that the field is zero. No synthetic per-instruction oracle
  is invented. fcsr accumulation is checked through both fflags and frm.
- Implementation tags are not Spike architectural state. Source ports check configured
  availability, known tag bits of the correct width, and NONE's integer domain. F2 checks
  stage=1/tag=0/cause=1 or 3. EX/MEM checks stage=2 or 3 and cause=1..3. Only a redirect
  **in the same cycle and with the same PC as a retired control instruction** compares its
  target to Spike's next PC. Cross-cycle association and canceled instances belong to
  V02's age environment; no retirement tag or cancel input exists in this trace contract.
- MISA writes and counter CSR reads explicitly fail conversion and require the CV10
  dedicated CSR tests. Spike can change MISA, and its cycle/time/retirement/HPM read values
  differ from the CPU's timing. No CSR comparison is silently skipped. Missing required
  destination/CSR/memory/trap data fails explicitly, including load-to-x0 whose raw data
  is absent. Programs for this Spike comparator must avoid those unsupported observations.

Device/uncached actual store beats are compared, in order, against an independent AXI BFM
via `bfm_valid_i`, `bfm_addr_i[31:0]`, `bfm_data_i[31:0]`, `bfm_mask_i[3:0]`.
The BFM supplies actual memory effects, including a low FSD beat that remains written when
the high beat fails. It must not derive its values from trace or read internal write-buffer
events. AXI AW/W may arrive independently: assemble them in the BFM, unshift the AXI64
byte lanes using original address[2:0], and emit low-aligned data/mask. Emit an effect only
when the memory model actually changes bytes; the failed high beat emits none. BFM and
trace can arrive on different cycles. No tag association is required or invented.

For cacheable stores, compare trace effects against Spike's successful architectural store
records, splitting D into low then high 32-bit beats. SoC 6.1's cacheable regions are SRAM
0x10000000..0x1000ffff and DDR 0x80000000..0xbfffffff. Independent queues permit effects
before retirement. Final external cache memory/writeback correctness belongs to CV11's
byte memory model, not a one-to-one comparison between an instruction store and a cache
line writeback. Device FSD partial writes never require a fabricated retirement record.

The expected text file is selected by `+TRACE_EXPECT=path`. All tokens are hexadecimal,
with no header/comments. Each line is one event:

| Kind | Following fields in order |
|---|---|
| 1: retirement | pc instr rd rd_domain rd_data csr_valid csr_addr csr_data mem_valid mem_store mem_addr mem_data mem_mask fflags frm fs next_pc |
| 2: trap | cause trap_pc tval fflags frm fs |

Invalid retirement payloads are ignored according to their valid/domain bits. Extra or
missing architectural events and missing/extra effects fail at the next conflicting event
or at `finish_i`. This checker adds no internal watchdog.

Spike version used: **1.1.1-dev, upstream revision 520a5f1**. Its log grammar comes from
[processor.cc](https://github.com/riscv-software-src/riscv-isa-sim/blob/520a5f1/riscv/processor.cc)
and [trap.h](https://github.com/riscv-software-src/riscv-isa-sim/blob/520a5f1/riscv/trap.h).
Both `-l` and `--log-commits` are necessary for trap and retirement records. Trap tval
appears on a separate line; interrupt names are `interrupt #3/#7/#11`.

| ISSUE_WIDTH | FPU_FORMAT | Spike --isa |
|---|---|---|
| 1 | NONE | rv32im_zicsr_zicntr_zifencei_zba |
| 2 | NONE | rv32im_zicsr_zicntr_zifencei_zba |
| 1 | F | rv32imf_zicsr_zicntr_zifencei_zba |
| 2 | F | rv32imf_zicsr_zicntr_zifencei_zba |
| 1 | FD | rv32imfd_zicsr_zicntr_zifencei_zba |
| 2 | FD | rv32imfd_zicsr_zicntr_zifencei_zba |

Run the **same ELF and initial memory** used by the DUT. For a bare-metal image linked in
DDR, a bounded run is, for example:

```sh
spike --isa=rv32imfd_zicsr_zicntr_zifencei_zba --priv=m --pmpregions=0 \
  -m0x80000000:0x2000000 --pc=0x80000000 --disable-dtb --instructions=17 \
  -l --log-commits --log=build/spike.log build/program.elf
python3 tools/cpu/cpu2_spike_trace.py build/spike.log build/expected.txt --format FD
# simulation arguments: +TRACE_EXPECT=build/expected.txt
```

For real programs stop at their test exit, after collecting a successor for any last
control instruction. The instruction budget above is specific to the checked-in probe;
it is not a general test timeout. No `--no-dm` option is used: revision 520a5f1 does not
support that option.

Reproduce the checked-in real Spike fixture with GCC 15.2.0 and the Spike command above:

```sh
riscv-none-elf-gcc -march=rv32imfd_zicsr_zba -mabi=ilp32d -nostdlib \
  -T verif/unit/cpu2_trace_check/probe.ld verif/unit/cpu2_trace_check/probe.S \
  -o build/program.elf
```

Run the comparator self-tests on the simulation host:

```sh
python3 tools/regress.py smoke --path verif/unit/cpu2_trace_check --parallel 3 -j 1
```

Seven test entries run the converter fixture and the six fixed configurations. Each HDL
configuration invokes `tools/check/lint.sh` (`--lint-only -Wall --timing`), compiles once,
runs the known-good stream once, then runs each deliberate mutation once. Each negative
must exit nonzero and name its intended field; expected failures remain in their individual
build logs and do not turn into regression failures.

Coverage includes dual retirement, the younger slot's PC/rd, older retirement with a
same-cycle younger trap, integer high-half zero, FP f0 and FD high result bits, accumulated
fflags/frm/FS, CSR valid/address/value, load raw bytes before sign extension, store original
address/data/size mask, cached low/high D beats, device effects on different cycles, and
FSD low-beat success followed by high-beat fault with no FSD retirement. Every compared
payload family has negative mutations; missing/extra retirement/effects, F2 tag/cause/stage,
same-cycle retired redirect target, and source-port/domain legality are also exercised.
The Python tests additionally cover sticky flags, fcsr aliases, two-line tval, interrupts,
F/FD result width, signed-load raw bytes, D store size, and explicit unsupported/missing
log-field failures. Synthetic stimuli are checker inputs, not an ISA execution model.
