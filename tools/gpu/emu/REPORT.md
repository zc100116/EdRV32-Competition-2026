# S-0d GPU emulator performance

Code commit: this report’s `gpu_emu: speed up emulator core` commit; exact ID:
`git log -1 --format=%H -- tools/gpu/emu/gpu_emu.c`. Baseline: `2367f249f`.
Host: shared KVM, AMD EPYC 7742, 3 allowed CPUs; gcc 13.3.0, Zig 0.17.0, C11 -O2.
Builds: gcc native and Zig Windows GNU, `-Wall -Wextra -Werror`, 0 warnings.
Both thread counts: 121 GT bit-exact passes, 4 GT21 AXI-injection skips;
12 model selftest groups, 43863 native comparisons pass, 2 AXI-injection skips.
Complete DDR, registers/PERF/OBJ/errors, IRQ and target buffers match Python.
gpu_hello: 300 frames and frame-150 replay PASS; API header and pc/sw sources unchanged.
Stress median of 11: baseline **95.293 ms**, serial **20.539 ms**,
3 threads **10.961 ms/frame** (16 ms target met, 8.69x baseline).
640x360, two stripes; each: 1000 16x16 I8 nearest quads, 500 bilinear triangles,
2000 STEP=1 objects. Phase times are a separate run; shares use their phase sum.

| Phase | Serial ms (%) | 3 threads ms (%) |
|---|---:|---:|
| setup/load | 0.071 (0.3%) | 0.051 (0.4%) |
| clear | 1.492 (7.4%) | 1.033 (8.1%) |
| quads | 1.453 (7.2%) | 1.837 (14.4%) |
| triangles | 16.634 (82.2%) | 9.309 (72.9%) |
| objects | 0.176 (0.9%) | 0.133 (1.0%) |
| resolve | 0.411 (2.0%) | 0.398 (3.1%) |

| GT (five-run medians, min–max) | Serial ms | 3 threads ms |
|---|---:|---:|
| gt01 | 0.149–0.149 | 0.209–0.209 |
| gt02 | 0.170–0.170 | 0.175–0.175 |
| gt03 | 2.113–2.113 | 2.241–2.241 |
| gt04 | 1.119–1.119 | 0.918–0.918 |
| gt05 | 0.581–0.581 | 0.576–0.576 |
| gt06 | 0.421–0.421 | 0.582–0.582 |
| gt07 | 2.763–2.763 | 2.725–2.725 |
| gt08 | 0.539–0.539 | 0.514–0.514 |
| gt09 | 1.568–1.568 | 1.480–1.480 |
| gt10 | 0.955–0.955 | 0.993–0.993 |
| gt11 | 0.800–0.880 | 0.742–0.889 |
| gt12 | 0.057–12.035 | 0.052–11.948 |
| gt13 | 1.309–1.566 | 1.355–2.537 |
| gt14 | 0.567–0.567 | 0.578–0.578 |
| gt15 | 1.124–4.566 | 1.172–4.572 |
| gt16 | 0.738–1.098 | 0.754–0.922 |
| gt17 | 0.019–0.068 | 0.020–0.056 |
| gt18 | 0.053–0.053 | 0.048–0.048 |
| gt19 | 0.049–0.055 | 0.052–0.071 |
| gt20 | 15.380–15.758 | 16.042–19.749 |
| gt21 | 4 AXI skips | 4 AXI skips |
| gt22 | 0.379–22.377 | 0.342–20.631 |
| gt23 | 0.040–0.129 | 0.041–0.146 |
| gt24 | 1.606–1.606 | 1.561–1.561 |
| gt25 | 0.754–9.708 | 0.850–9.176 |
gprof first: pixel 29.2%, tiled texel reads 19.0%, inlined command/triangle work 33.9%.
Optimizations: exact edge stepping; 64-bit normalized math (spec 2.13 widths);
constant attributes; decoded texture/group cache; opaque quad rows; 3 ordered row sections.
Reproduce: README build/profile commands; `python3 tools/gpu/emu/compare.py --threads 1`
and `--threads 3`; `make -C sw/bsp/pc -j1 linux test windows`;
`build/gpu_pc/gpu_hello --frames 300 --dump 1,150,300 --out build/gpu-emu/s0d/hello`;
`python3 tools/gpu/emu/pc/replay.py build/gpu-emu/s0d/hello`.
Raw: `build/gpu-emu/s0d/`: `compare-{single,multi}.log`, `results-{single,three}.json`,
`before-gprof.txt`, `pc-build.log`, `hello.csv`, `replay.log`; GT data: `timings.csv` (shared host).
