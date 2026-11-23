# GPU C reference emulator

C11 functional implementation of `gpu-spec.md` v0.3 sections 2–6, using the
Python model's integer algorithms. The library uses only standard C and compiler
`__int128`; it has no operating system or windowing dependency.

`gpu_emu.h` fixes the five entry points: create/destroy, APB offset read/write,
and IRQ level. The caller owns the entire DDR allocation starting at physical
address zero and keeps it alive until destroy. Create returns NULL on allocation
failure. DOORBELL executes the descriptor list synchronously. IRQ is the OR of
IRQ_STAT & IRQ_EN. CTRL soft reset clears model state and counters; DDR survives.
PERF1–4 count functional events; cycle counters and unused PERF entries read zero.
Register masks, reset values and record fields use the generated BSP header.
`codec.h` is regenerated with `python3 tools/gpu/emu/gen_codec.py`.

Out-of-allocation DDR accesses print the zero-based command index, address and
length, then call `abort()`, per the coordinator's clarification of S-0a. They are
host software defects, not an emulated AXI response. Injected AXI responses and
mid-command ABORT/timing are outside this synchronous model, as in Python.

Build from the repository root (one compiler process at a time):

```sh
mkdir -p build/gpu-emu
gcc -std=c11 -Wall -Wextra -Werror -O2 -c tools/gpu/emu/gpu_emu.c \
    -o build/gpu-emu/gpu_emu.o
gcc -std=c11 -Wall -Wextra -Werror -O2 tools/gpu/emu/gpu_emu.c \
    tools/gpu/emu/cli.c -o build/gpu-emu/gpu-emu
~/.local/opt/zig-0.17.0/zig cc -target x86_64-windows-gnu \
    -std=c11 -Wall -Wextra -Werror -O2 tools/gpu/emu/gpu_emu.c \
    tools/gpu/emu/cli.c -o build/gpu-emu/gpu-emu.exe
```

CLI input is the Python CLI's word-per-line DDR hex and JSON ordered register
writes (names or numeric offsets, decimal JSON values). The output directory must
exist. Output is updated `ddr.hex` and all `registers.json`; execution CPU time in
milliseconds is printed. `--base` is the image origin; it does not change the
library's DDR origin zero. For a high image origin the CLI allocates all preceding
DDR too. It does not export Python's optional internal target buffer files.

```sh
mkdir -p build/gpu-emu/result
build/gpu-emu/gpu-emu build/gpu/scene.hex build/gpu/writes.json \
    build/gpu-emu/result --base 0x80000000
python3 tools/gpu/emu/compare.py > build/gpu-emu/compare.log
```

`compare.py` builds with gcc -O2, runs every GT generator with its declared seed,
and compares the complete DDR, every register, IRQ, and color/depth/stencil
buffers. Unit selftests are replayed with private `test_bridge.c` entry points:
explicitly configured internal state is copied before each independent operation,
then outputs are compared. This also permits full-frame oracle buffers used only
by stripe selftests. Client programs link only `gpu_emu.c`, never the test bridge.
No Python model, scene helper or verification source is changed. Test scenes use
origin zero while preserving the same record contents and relative addresses.
GT21 and the two selftest injected AXI-error cases are reported as skipped.
GT22 runs complete command lists for differential functional testing; its RTL
mid-command ABORT trigger is not replayed by either functional model.

Each GT timing is the median of five complete C executions excluding setup,
allocation and comparison; stress uses eleven. Python-to-C register-call overhead
is included. The stress generator renders 640x360 in two stripes, each with 1000
16x16 I8 quads, 500 textured triangles (about 200 pixels each), and 2000 STEP=1
objects. SAMPLE=1 selects bilinear for triangles; quads use the specified nearest
path. Phase times are one additional C execution timed per command, including
adapter overhead. All per-run timings and skip reasons are written to
`build/gpu-emu/results.json`. `--gt-only` or `--selftest-only` selects one test
suite; both also run stress. See `REPORT.md` for the measured result.
