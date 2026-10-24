# LSU throughput probe (2026-09-22)

The baseline `tb_lsu_throughput.sv` used the cached core with the then-enabled
queued LSU, 256-line I/D caches, and the native AXI test adapter
with `IMEM_LAT=1`, `DMEM_LAT=2`. It executes a 64-instruction straight-line body
twice. The first pass warms the caches; the second pass samples the middle 48
retirements, excluding the loop boundary and pipeline fill/drain. Cases 6 and 7
first warm their data line with a load, then execute partial-overlap sequences.

Run on the project's Linux simulation host:

```sh
make case-compile CASE=cpu/lsu-throughput
vvp sim/build/cases/cpu/lsu-throughput/sim.vvp +CASEID=1
vvp sim/build/cases/cpu/lsu-throughput/sim.vvp +CASEID=6 +TRACE
```

`span` is the number of cycles from the first through last sampled retirement
minus one. `bubbles = span - 47`; the mean retirement interval is `span / 47`.
This is a steady-window measurement, not whole-program CPI. Pair gap is the
retirement-cycle difference between the two instructions of each pair.

| Case | Body | Span / 47 | Bubbles | Pair gap | Accepted lookup gap | Key observations |
|---:|---|---:|---:|---:|---:|---|
| 0 | independent ADDI | 47 / 47 = 1.00 | 0 | — | — | Baseline retires once per cycle. |
| 1 | independent warm LW | 94 / 47 = 2.00 | 47 | — | 92 / 46 = 2.00 | Load Queue full 47 cycles. |
| 2 | independent warm SW | 141 / 47 = 3.00 | 94 | — | 138 / 46 = 3.00 | Store reservation wait 47 cycles; Store Queue full 94; COMMIT wait 47. |
| 3 | LW then dependent ADDI | 95 / 47 = 2.02 | 48 | 72 / 24 = 3.00 | 92 / 23 = 4.00 | Decode dependency wait 47 cycles (23 resident, 24 load); EX wait 0. |
| 4 | SW then unrelated LW | 118 / 47 = 2.51 | 71 | 72 / 24 = 3.00 | 117 / 47 = 2.49 | Lookup wait: 47 in LOOKUP, 23 in STORE_RESERVED; COMMIT wait 71. |
| 5 | SW then fully forwarded LW | 70 / 47 = 1.49 | 23 | 24 / 24 = 1.00 | 69 / 23 = 3.00 | Load avoids D-cache lookup; Store reservation still limits following pairs. |
| 6 | SB then partially overlapping LW | — | — | — | — | **Deadlock**, reproduced even after data-line warmup. |
| 7 | one SB then partially overlapping LW, then ALU stream | 47 / 47 = 1.00 (ALU sample) | 0 (ALU sample) | 5 for the preceding SB/LW pair | — | Isolated partial overlap completes, with four empty retire slots between the pair. |

The sampled intervals of cases 1 and 2 have **zero I-cache and D-cache
misses**. With `+TRACE`, all 47 adjacent retirement gaps are exactly two
cycles for case 1 and exactly three cycles for case 2. Thus these means are
steady hit-path initiation intervals, not averages inflated by occasional
misses. In case 1, D-cache alternates `STATE_LOOKUP` (fast hit valid, new
request not ready) and `STATE_IDLE` (new request accepted). In case 2, the
repeating states are `STATE_STORE_RESERVED` with commit/drain and next lookup
accepted, `STATE_LOOKUP` with fast hit, then `STATE_STORE_RESERVED` waiting for
commit; the next acceptance is three cycles after the prior one.

In case 1, the first cold D-cache load completes 25 cycles after its request
under this AXI/native memory model. A measured warm hit completes one cycle
after its accepted request. These numbers describe this simulation adapter and
must not be substituted for FPGA AXI latency.

## Partial-overlap deadlock

Case 6's shortest relevant sequence is `sb A; lw A; sb A; lw A`. At cycle 62
the older store drains and unblocks the first word load, but a younger store
prepare is accepted by D-cache on that same edge. At cycle 63 the older load
has a valid D-cache request, while D-cache is looking up that younger store.
At cycle 64 D-cache enters `STATE_STORE_RESERVED` for the younger store. The
older load is stuck at COMMIT waiting for its data; the younger store cannot
reach COMMIT and drain to release the reservation. The case terminates with
`PARTIAL_OVERLAP_DEADLOCK` at cycle 500. See `case_6_trace.log` in the local
simulation build directory for the cycle-by-cycle evidence.

Case 7 is a control: the same warmed-line `sb A; lw A` pair retires with a
five-cycle gap when no younger store can reserve the D-cache ahead of the load.
It establishes that the deadlock needs the younger store, rather than a partial
overlap alone.

This is a functional progress failure, not a CoreMark score observation. The
CoreMark binary passed validation; this directed sequence exercises an ordering
corner it did not encounter. The arbitration between an older blocked load
and a younger store prepare needs a dedicated RTL fix and regression.

## Single-path LSU redesign result

The current RTL has one queued cacheable-memory path: four Load Queue entries,
four speculative Store Queue entries, a two-entry committed Store buffer, a
two-entry D-cache request FIFO, and four ordered Store reservations. The
alternate MEM1/MEM2 Cache issue mode and its build switch have been removed.

The same warm-cache simulation now gives:

| Case | Body | Span / 47 | Bubbles | Data/forwarding result |
|---:|---|---:|---:|---|
| 0 | independent ADDI | 47 / 47 = 1.00 | 0 | pass |
| 1 | independent LW | 47 / 47 = 1.00 | 0 | pass; warm request-to-hit result = 1 cycle |
| 2 | independent SW | 47 / 47 = 1.00 | 0 | retires; write correctness also checked by cases 5 and 6 |
| 3 | LW then dependent ADDI | 95 / 47 = 2.02 | 48 | pass; load-to-use pair gap = 3 |
| 4 | SW then unrelated LW | 47 / 47 = 1.00 | 0 | pass |
| 5 | SW then fully forwarded LW | 47 / 47 = 1.00 | 0 | pass |
| 6 | SB then partially overlapping LW | 119 / 47 = 2.53 | 72 | pass; every LW reads the updated `0x11223355` word |
| 7 | one SB then partially overlapping LW, then ALU stream | 47 / 47 = 1.00 | 0 | pass; isolated pair gap = 4 |

All sampled I-cache and D-cache miss counters are zero. Case 6 now completes
instead of deadlocking: the arbiter retains an older blocked Load's age before
admitting a younger Store preparation. The partial-overlap case intentionally
waits for the older Store to drain; its 2.53 interval is a conflict cost, not
the normal hit throughput.

The separate `lsu-control-load` integration case passes a Load-dependent
taken branch and a Load-dependent JALR. Their retirement gaps are 5 and 4
cycles, respectively. EX captures these control operands locally before
redirect resolution so the warm independent Load/Store II=1 and the ordinary
Load-to-ALU interval remain unchanged. PDS post-route timing on PG2L200H is
WNS `+0.147 ns` at 100 MHz, TNS `0`, estimated maximum `101.49 MHz`; the
full implementation record is in
`docs/optimization/2026-09-22-lsu-single-path-results.zh.md`.

## Historical exploratory load-throughput changes

Two temporary RTL variants were compiled under `sim/build`, without changing
the production RTL. In the first, a successful load fast response can accept
the next lookup on the same edge. The independent warm-LW retirement span
changed only from 94 to 93 cycles for 47 gaps (2.00 to 1.98), because the
two-entry Load Queue remained full on 46 sampled cycles.

The second variant also allowed a full Load Queue to allocate on the same edge
as head retirement, with same-slot replacement ordering. Its warm-LW span fell
to 70 cycles for 47 gaps (1.49), but the load/use case regressed from span 95
to 119 and developed 24 EX wait cycles. These variants are diagnostic only;
neither meets the one-LW-per-cycle target or has undergone full correctness
and FPGA timing verification. They show that the D-cache hit turnover and
Load Queue capacity/flow control must be addressed together.
