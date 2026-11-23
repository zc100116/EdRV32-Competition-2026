# S-0a C GPU emulator results

Code commit: this report’s `gpu_emu: C reference emulator core` commit;
get its exact ID with `git log -1 --format=%H -- tools/gpu/emu/gpu_emu.c`.
Host: shared KVM x86_64 AMD EPYC 7742; gcc 13.3.0, Zig 0.17.0, Python standard library.
Build flags: `-std=c11 -Wall -Wextra -Werror -O2`; gcc native and Zig Windows GNU: 0 warnings.
Reproduce builds and CLI: commands in [README.md](README.md).
Reproduce comparison/timing: `python3 tools/gpu/emu/compare.py > build/gpu-emu/compare.log`.
Raw outputs: `build/gpu-emu/results.json`, `compare.log`; per-run measurements: [timings.csv](timings.csv).

GT01–25: 125 generated runs, 121 bit-exact passes, 4 skips (GT21: injected AXI responses).
All 12 model selftest groups pass: 43863 native operation comparisons;
2 injected read/write error selftest scenarios skipped; Python assertions still run for those.
Complete DDR, all registers (including PERF/OBJ/ERR_CODE), IRQ and target buffers match.
GT22 executes complete lists: mid-command ABORT is outside both synchronous models.
CLI named/numeric writes and nonzero image base match Python; either --base ordering works.
DDR bounds follow coordinator clarification: command index/address/length on stderr, then abort().
Object writeback regression also preserves original reserved bits across aliased list writes.

GT times below: min–max of per-run five-execution medians, milliseconds; no allocation/compare time.
GT25 preserves the bench’s one-command-per-DOORBELL sequence. Exact sub-run times are in CSV.

| GT | Runs | C median range (ms) |
|---|---:|---:|
| gt01 | 1 | 0.762–0.762 |
| gt02 | 1 | 0.607–0.607 |
| gt03 | 1 | 11.242–11.242 |
| gt04 | 1 | 4.378–4.378 |
| gt05 | 1 | 2.954–2.954 |
| gt06 | 1 | 1.131–1.131 |
| gt07 | 1 | 9.478–9.478 |
| gt08 | 1 | 1.943–1.943 |
| gt09 | 1 | 2.671–2.671 |
| gt10 | 1 | 0.365–0.365 |
| gt11 | 3 | 1.378–1.636 |
| gt12 | 54 | 0.094–0.310 |
| gt13 | 16 | 2.781–3.403 |
| gt14 | 1 | 1.128–1.128 |
| gt15 | 2 | 1.538–5.480 |
| gt16 | 8 | 1.439–1.968 |
| gt17 | 3 | 0.019–0.270 |
| gt18 | 1 | 0.061–0.061 |
| gt19 | 3 | 0.053–0.062 |
| gt20 | 2 | 15.487–16.452 |
| gt21 | 0 | 4 skipped: AXI errors |
| gt22 | 4 | 0.407–126.358 |
| gt23 | 3 | 0.042–0.539 |
| gt24 | 1 | 3.146–3.146 |
| gt25 | 10 | 0.715–23.294 |

Stress: **95.293 ms/frame**, median of 11; **16 ms target not reached**.
640x360, two stripes; per stripe: 1000 16x16 I8 quads, 500 ~200-pixel textured triangles,
2000 STEP=1 objects; SAMPLE=1, quads nearest per spec 2.8 and triangles bilinear.
Phase profile is a separate execution; percentages use the sum of phase times.
setup/load: 0.188 ms (0.2%); clear: 1.167 ms (1.2%); quads: 30.060 ms (31.1%); triangles: 64.580 ms (66.7%); objects: 0.274 ms (0.3%); resolve: 0.499 ms (0.5%).
Only result-preserving optimization: rounded power-of-two shifts avoid general 128-bit division.
No multithreading; performance varies with other workers on this shared host.
Stress wording conflict remains pending: task asks bilinear quads, spec/model force nearest;
coordinator question `msg_ffb7f72ca03c` unanswered after four 10-minute waits and escalation.
