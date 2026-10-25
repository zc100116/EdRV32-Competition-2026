# Active RTL tree

This is the clean RTL tree for the 2026-09-01 CPU rewrite.

The active CPU is a scalar, in-order, eight-stage RV32IMC core.  It implements
Zicsr, Zifencei, Zicntr, and machine mode.  It contains no F/D-extension
configuration, no dual-issue lanes, and no unused interfaces reserved for
either feature.

Directory ownership:

- `cpu/frontend/`: IF1, IF2, ALIGN, instruction buffering, decompression, prediction
- `cpu/decode/`: DECODE-stage decode and immediate generation
- `cpu/execute/`: EX-stage integer ALU and control-flow resolution
- `cpu/lsu/`: MEM1/MEM2 address classification and load/store sequencing
- `cpu/mdu/`: decoupled integer multiply/divide engine
- `cpu/csr/`: machine CSRs, counters, and trap state
- `cpu/control/`: redirect arbitration, hazards, and the MDU-only scoreboard
- `cpu/datapath/`: integer register file and small reusable datapath blocks
- `cpu/cache/`: instruction/data cache controllers and arrays
- `cpu/core/`: integration tops; no stage implementation belongs here
- `include/`: active shared contracts and encodings
- `com/`, `soc/`: verified platform RTL reused from the archived tree
- `competition/`: active synthesis file lists

The architecture contract is
`docs/architecture/edrv32-8stage-architecture.zh.md`. RTL that violates its
registered-boundary, side-effect, or redirect rules must not be merged merely
to make a test pass.

For a textbook-style walkthrough from the classic five-stage model to the
current pipeline, memory, cache, exception, redirect, and MDU behavior, see
`docs/architecture/cpu-architecture-guide.zh.md`.

## RTL style contract

The active hand-maintained RTL follows these conventions:

- Pipeline stages are named `if1`, `if2`, `align`, `decode`, `ex`, `mem1`,
  `mem2`, and `commit`.
- CPU rewrite port direction is expressed only by the `_i` or `_o` suffix. Do
  not add a redundant `in_` or `out_` prefix. Prefixes identify an interface,
  pipeline stage, or semantic owner, such as `dmem_req_valid_o`. Reused
  platform clock/reset names and board pins retain their established names for
  compatibility with existing constraints and IP integration.
- Preserve a signal's semantic stem across module boundaries. For example,
  branch-prediction metadata is always `predicted_taken` and
  `predicted_target`; an owner prefix such as `block_`, `window_`, or
  `candidate_` may be added, but the stem must not be shortened to `pred_*`.
- Use `mem1` and `mem2` for the two official memory stages. `req`, `resp`, and
  `addr` remain valid protocol-field abbreviations in interfaces such as
  `dmem_req_*`; `pc`, `instr`, `rs`, `rd`, and `imm` remain the standard ISA
  abbreviations.
- Internal combinational signals use `_w`; state elements use `_r`.
- Declare one signal per line and place one named instance connection per line.
- Group ports by interface and owner, and introduce each internal functional
  block where that responsibility begins. Comments should explain ownership,
  timing, or intent naturally instead of restating the following statement.
- Mirror those interface groups at every module instance. Separate clock/reset,
  upstream packets, downstream packets, and sideband or control interfaces with
  blank lines; introduce each long port group with a short purpose comment.
- Keep handshake state (`valid`) separate from payload state when they have
  different enable or flush semantics.
- Keep non-comment source lines within 100 columns.

Run `python scripts/check/verilog_style.py` before regression to check the
mechanically enforceable rules above.
