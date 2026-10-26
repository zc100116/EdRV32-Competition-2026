# M-V1 storage subsystem verification

Independent verification of mem-subsys v0.1 / SoC v0.5, testplan sections 2,
3.1–3.4, 4–6. No implementation in `rtl/mem/` or the subsystem RTL top was read.
AD-01 belongs to M-R4. The baseline is `92725ae75c792a0b1b42e41dcd1965edcdb1bc51`.

The current `dut.f` explicitly selects the empty-response compilation stub. The
functional cases must fail with this stub. `run_stub.py` treats only the listed
functional comparisons and bounded non-completion as expected stub outcomes;
ordinary regression entries still fail and never convert those failures to PASS.

## Commands

Run from the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/mem_subsys/run_stub.py
make lint
python3 tools/check/verilog_style.py rtl/
python3 verif/block/mem_subsys/coverage.py build/regress/full/block/mem_subsys
```

The stub acceptance command runs the three component self-tests through
`tools.regress.run_test`, then compiles the common MB entry once with `CASE=0`
and serially executes every registered CASE/SEED. It uses Verilator `-j 1`,
`--output-split 10000 --output-split-cfuncs 100 -CFLAGS -O0`; it runs one simulator
process at a time. Files lists resolve paths relative to each list. The final
coverage command is for a successful real-RTL full run; stub logs have no
functional coverage and cannot meet that target.

Generated evidence: `build/regress/smoke/block/mem_subsys/{model,checker,master}_selftest/`
and `build/mem_mb_stub/{compile.log,<test>/run.log}`. The acceptance summary can be
saved with `python3 verif/block/mem_subsys/run_stub.py > build/mem_stub_acceptance.log`.

For integration, M-I1 replaces only the explicit stub entries in `dut.f` with the
real subsystem file list, then runs `make smoke` / `make full` through the shared
regression driver. A normal MB entry compiles its selected CASE and SEED; CASE=0
is the shared runtime entry (`+CASE=... +SEED=...`). The normal simulation deadline
is 2,500,000 clk_mem edges; stub acceptance uses `+MAX_CYCLES=100000`, or 5,000 for cases blocked by
missing forwarding/PM execution.

## Test mapping

Every directory below has `test.yaml` and `files.f`, with the shared self-checking
`edrv32_mem_subsys_tb.sv` top. S means smoke (also included in full); F means full.

| Test | Directory | CASE | Tier |
|---|---|---:|---|
| GW-01 | `gw_01` | 101 | S |
| GW-02 | `gw_02` | 102 | S |
| GW-03 | `gw_03` | 103 | S |
| GW-04 | `gw_04` | 104 | F |
| GW-05 | `gw_05` | 105 | F |
| MX-01 | `mx_01` | 201 | S |
| MX-02 | `mx_02` | 202 | F |
| MX-03 | `mx_03` | 203 | F |
| MX-04 | `mx_04` | 204 | F |
| MX-05 | `mx_05` | 205 | S |
| MX-06 | `mx_06` | 206 | S |
| MX-07 | `mx_07` | 207 | S |
| MX-08 | `mx_08` | 208 | S |
| MX-09 | `mx_09` | 209 | S |
| MX-10 | `mx_10` | 210 | F |
| MX-11 | `mx_11` | 211 | S |
| MX-12 | `mx_12/seed_01` … `seed_20` | 212 | F |
| PM-01 | `pm_01` | 301 | S |
| PM-02 | `pm_02` | 302 | S |
| PM-03 | `pm_03` | 303 | F |
| PM-04 | `pm_04` | 304 | S |
| PM-05 | `pm_05` | 305 | F |
| PM-06 | `pm_06` | 306 | F |
| PM-07 | `pm_07` | 307 | F |
| P6-01 | `p6_01` | 401 | S |
| TOP-01 | `top_01` | 501 | S |

There are 26 functional items / 45 MB regression entries and three environment
self-test entries:

- `model_selftest`: row hit/miss latency, bank selection, masked byte writes,
  B-ordered reference storage, exact last-write/B delay, queued read/write
  turnaround gap and refresh interruption (53 checked read beats, two writes).
- `checker_selftest`: 18 scenarios including alignment, 4 KiB, all five stalled
  channel payloads, WLAST/RLAST, response IDs/order, EXOKAY rejection, legal stalls
  and error responses, implicit downstream response readiness and continuous W.
- `master_selftest`: 12 queued writes plus 12 reads with independent W delay/gaps,
  random B/R readiness and urgent, checking 192 returned beats; additional P0-only
  and P1-only drivers each complete eight transactions against stalled empty slaves.

## Components and observation

`verif/common/edrv32_axi256_master.sv` exposes queued `enqueue_read`,
`enqueue_write`, and `wait_done` tasks. Independent address/data streams support
multiple outstanding transactions. Test controls select periodic or seeded random
R/B readiness and urgent, plus initial and inter-beat W delays. P0 is read-only,
P1 write-only; ETH uses local ID 1, PERF_MON local ID 0.

`edrv32_axi256_checker.sv` checks SoC 4.2 request shape and handshake stability,
AW/W ordering and counts, response IDs/counts/LAST, legal response codes and
continuous downstream W. Local ID/LEN widths enforce the structural 1-bit / 4-bit
limits. The downstream instance consumes every B/R valid, regardless of interface
READY wires. The separate `edrv32_axi256_reference.sv` stores sparse bytes,
commits complete writes in B order and compares every downstream R beat; local
port scoreboards compare the routed data again under upstream backpressure.
`edrv32_mem_write_scoreboard.sv` separately compares source AW, complete WDATA and
WSTRB against DDR grants/data, including both P6 sources; this prevents a wrong
write payload from becoming its own expected reference value. Address-derived
preloads make read misrouting observable before the first write.
Gateway conversions are compared directly against independently formed AXI256
addresses, WDATA and WSTRB, including every naturally aligned byte position.

`edrv32_mem_schedule_observer.sv` records each DDR AW/AR handshake with port,
direction, beat count and cycle, plus occupancy/peak counters.
`edrv32_mem_schedule_reference.sv` reconstructs ingress heads and complete W
transactions from the seven xbar port handshakes, and calculates the allowed
priority set under outstanding limits, 128-beat read credit, urgent cap,
low-latency P2, token rate, starvation and direction batching. It independently
tracks the statistics used by MX-10, including simultaneous snapshot/clear.
DRR cursor details are intentionally unconstrained as approved by the coordinator;
zero-weight eligibility and long-term beat shares are checked.

Approved module-port observations are `u_dut.u_xbar.pN_*` and
`u_dut.u_perf_mon.axi_*` with `_i`/`_o` direction suffixes. Stub instances provide
these exact paths. PERF_MON latency is measured at its own AR/first-R handshake,
not at the DDR pins. PM-04 uses a calibration run only to choose DDR latency
settings that reach histogram edges; all register expectations come from the
independently observed source-port timestamps. P6 contention is checked at the
P6 xbar ingress, with local-ID routing checked at both response destinations.

## Coverage and agreed clarifications

Each successful MB case prints `COVER` records. `coverage.py` merges only logs
containing `PASS mem_subsys`, reports the union of legal gateway crosses,
naturally aligned SIZE/byte positions, unsupported gateway categories, five
scheduling rules, urgent/token/starvation events, direction changes, every
nonzero port/global cap, exhausted read credit, violations by direction,
PERF_MON mode/address crosses, 16 histogram bins, and snapshot/clear. It returns
a nonzero exit status if any MB target is missing. Saturation uses the RTL authors'
forced-initial-value unit tests as required by MX-10; MB does not force internals.

Coordinator answers incorporated during M-V1:

- AXI256 LEN is 4 bits, so LEN > 15 cannot be injected. The coordinator removed
  that impossible violation class; MX-09 covers crossing 4 KiB and misalignment,
  with both read and write directions. No placeholder test was added.
- LFSR is 32 bits, left shift, feedback `bit31 ^ bit21 ^ bit1 ^ bit0`.
  START loads SEED; use the current state for a transaction, then advance.
  Random block index is `(LFSR[31:16] * (SIZE/512)) >> 16`, not modulo.
  Mixed direction uses `acc += RW_RATIO`, read when `acc >= 16`, then subtract 16.
  MB compares the read/write subsequences separately because xbar may reorder
  the directions; global generation order belongs to the PERF_MON unit test.
- Token buckets reset full (32 beats). MX-02 subtracts those initial 32 beats
  and compares grants per clk with RATE/256 using 2% relative error; MX-04
  compares beat shares using 5 percentage points of absolute error.
- Only priority-1 urgent grants increment the urgent count. Other ports winning
  or urgent going low clear it. At the cap, the port can still compete via
  priorities 2–5 without changing its own urgent count.
- WAIT begins when the transaction is an arbitratable head (W complete for
  writes), including limit/credit stalls, through DDR AW/AR handshake inclusive.
  SNAPSHOT captures counts before that edge's increment; CLEAR sets counts to
  zero and wins over the edge's increment; simultaneous SNAPSHOT/CLEAR captures
  the old values first.

## Acceptance status

The component self-tests, all 45 expected stub failures, and `make lint` are the
M-V1 acceptance checks. All 26 functional items, precise scheduling/WAIT timing,
PERF_MON bandwidth and full coverage still require the M-I1 real-RTL integration
run; an empty-response stub provides no functional DUT pass evidence.


Observed M-V1 results (Verilator, serial; 2026-10-26):

- `run_stub.py`: all three component self-tests PASS; shared CASE=0 compile PASS;
  **45/45 expected functional failures**, acceptance process exit 0.
- Every registered CASE/SEED elaborates with `--lint-only --timing`, zero warnings
  (`build/mem_mb_case_lint.log`).
- `make lint`: exit 0; RTL style reports 47 files / 0 warnings
  (`build/mem_make_lint.log`). The new SV/SVH formatting check reports 24 files /
  0 tab or code-line-width violations; `git diff --check` is clean.
- Coverage merger reports **0/116 MB bins and 0/13 limit peaks** for stub logs,
  returning 1 as expected (`build/mem_mb_coverage.log`). Functional PASS/coverage
  must come from M-I1, including the separately supplied saturation unit evidence.
