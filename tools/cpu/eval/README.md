# CPU trace evaluations (C-E1 / C-E2 / C-E3)

From the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/coremark
python3 tools/cpu/eval/test_models.py
python3 tools/cpu/eval/run_coremark.py
python3 tools/cpu/eval/analyze.py
```

The builder uses the unchanged P0 CoreMark port, `-O2`, `ilp32`, SRAM placement,
and 10 iterations for all six requested ISA variants. Zicsr is common to all
builds because the port reads cycle CSRs. Each variant has its own object
directory; the full compiler and Spike commands are in `commands.txt`.
The port's printed compiler flags are a fixed P0 string; use `commands.txt` and
`build.log` for the actual flags. The short run does not satisfy CoreMark's
10-second scoring rule and does not produce a CoreMark/MHz measurement.

All generated data live in `build/cpu/eval/`:

| File | Content |
|---|---|
| `versions.txt` | Source commit, dependency and tool versions |
| `<isa>/build.log`, `commands.txt` | Build diagnostics and exact commands |
| `<isa>/coremark.elf`, `coremark.map`, `numeric.dis`, `sections.txt` | Software image, decode and sizes |
| `<isa>/console.log`, `spike.log` | Unabridged output and Spike execution/commit log |
| `<isa>/roi.trace` | Timed-region committed PC and original instruction encoding (hex) |
| `<isa>/branches.csv` | Timed-region PC, type, actual direction/target and call/return hints |
| `isa.csv` | Dynamic instruction, instruction-byte, `.text` and aligned fetch-byte counts |
| `pairing.csv` | Both slot-1 rules, pair counts and exclusive failure counts |
| `predictor.csv` | All six ISAs × 27 BTB/gshare/RAS configurations, counts and rates |

The timed region starts after `start_time` returns and ends before entering
`stop_time`, including the call to `stop_time`. The input is the instruction
sequence only. Fetch bytes count sequentially reused, aligned 8-byte groups;
a straddling 32-bit instruction consumes both groups, and a taken transfer
starts a fresh group access. Wrong-path fetches, cache fills and timing are absent.

The predictor starts cold and queries once at each group entry. A redirect
can re-query the remaining part of the same group. A BTB entry below the entry
PC is ignored. There is one control-transfer entry per group, allocated/replaced
by every committed control transfer, including a not-taken conditional branch.
The direct-mapped index is `(PC >> 3) & (entries - 1)`; the remaining group bits
form its tag, and the entry also retains the branch position. The gshare index
is `((PC >> 1) ^ GHR) & (entries - 1)`; history width is log2(entries), initial
history is zero, counters start at 01, and only resolved conditional branches
update history. With 32/512 entries these are spec 4.4's PC[7:3] and PC[9:1].

Prediction uses the group-entry history; resolution/training occurs immediately
in sequence order. JAL/JALR link hints use x1/x5; different link registers on
JALR cause pop then push. RAS updates at prediction, retains the newest entries
when full, and restores the pre-prediction stack on a redirect before applying
the resolved call/return. An empty RAS leaves the BTB target prediction in use.
This is an architectural trace model: there are no in-flight branches, delayed
training, wrong-path instructions or wrong-path RAS pollution. Saved stacks
represent prediction checkpoints, not a measurement of checkpoint hardware.

Direction errors include taken conditionals on a BTB miss (predicted not taken).
Target errors count a BTB-hit, predicted-taken, actually-taken transfer whose
predicted address differs. BTB misses include a group hit at another position.
These categories overlap: do not add them. `redirects` counts each direction or
target failure once, including cold JAL/JALR misses. Direction percentage uses
conditional branches as its denominator; other rates use all control transfers.

Pairing greedily consumes the oldest one or two instructions. Actual taken
transfers end adjacency. The second rule adds conditional branches only; jumps
remain restricted to slot 0. With two sequential candidates, failure precedence
is RAW > structural (slot 0 CSR/system/FENCE) > unsupported slot-1 type.
Missing sequential candidates count as `only_one`. WAW is allowed and x0 does
not cause RAW. No timing, IB occupancy, load-use or multiplier stalls are modeled;
the reported sequence IPC is instructions divided by greedy issue groups.

The seven model tests exercise operand decoding, WAW/RAW, failure priority,
control boundaries, fetch straddling, cold gshare saturation, BTB position/capacity
conflicts, and RAS overflow plus correction after a cold call.
