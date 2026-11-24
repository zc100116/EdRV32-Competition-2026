# GPU C reference emulator

C11 functional implementation of `gpu-spec.md` v0.3 sections 2–6, using the
Python model's integer algorithms. Arithmetic uses standard C and compiler
`__int128`. Large draw batches use three horizontal sections, with Win32 threads
on Windows and pthreads on Linux. `-DGPU_EMU_THREADS=1` removes the platform
thread code and keeps the serial library. Public entry points are unchanged.

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
gcc -std=c11 -Wall -Wextra -Werror -O3 -pthread -c tools/gpu/emu/gpu_emu.c \
    -o build/gpu-emu/gpu_emu.o
gcc -std=c11 -Wall -Wextra -Werror -O3 -pthread tools/gpu/emu/gpu_emu.c \
    tools/gpu/emu/cli.c -o build/gpu-emu/gpu-emu
~/.local/opt/zig-0.17.0/zig cc -target x86_64-windows-gnu \
    -std=c11 -Wall -Wextra -Werror -O3 tools/gpu/emu/gpu_emu.c \
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

`compare.py` builds with gcc -O3, runs every GT generator with its declared seed,
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

Use `compare.py --threads 1` for the serial comparison/timing and `--threads 3`
for the default threaded build. Every draw command completes before the next command;
sections share only disjoint target rows, keep local counters/texture caches and
preserve primitive order. Two persistent workers and the caller own the three
sections; worker jobs and texture storage survive soft reset and are released
on destroy. Batches below 128 triangles or 2048 quads stay serial to avoid
wakeup and state-copy overhead. OBJ_STEP remains serial to preserve DDR
object/list aliasing and writeback order.

For P-1 acceptance, run `python3 tools/gpu/emu/bench_stress.py` by itself.
It times exactly three complete stress frames with three threads, reports their
median and `uptime` load, and saves `build/gpu-emu/stress-acceptance.json`.

Reproduce the gprof stress profile from the repository root:

```sh
python3 - <<'PY'
import struct, sys
sys.path[:0] = ['tools/gpu/emu', 'verif/block/gpu', '.']
import compare
from tools.gpu.scene import Scene
original = Scene.__init__
Scene.__init__ = lambda self, base=0: original(self, base)
from stress import scene
s = scene()
writes = s.finish()
compare.BUILD.mkdir(parents=True, exist_ok=True)
(compare.BUILD/'stress.bin').write_bytes(s.memory.data)
(compare.BUILD/'writes.bin').write_bytes(b''.join(
    struct.pack('<II', compare.REGS[r], v) for r, v in writes))
PY
gcc -std=c11 -O2 -Wall -Wextra -Werror -pg -DGPU_EMU_THREADS=1 \
    tools/gpu/emu/gpu_emu.c tools/gpu/emu/profile.c -o build/gpu-emu/profile
GMON_OUT_PREFIX=build/gpu-emu/gmon build/gpu-emu/profile \
    build/gpu-emu/stress.bin build/gpu-emu/writes.bin
gprof build/gpu-emu/profile build/gpu-emu/gmon.* > build/gpu-emu/gprof.txt
```

The profile driver resets DDR and the emulator before each of 100 executions;
wall-clock timings in `compare.py` exclude setup/allocation and profiling overhead.

Profile the Ember Isles coast replay (phase wall times in ms/frame and frame
mean/p50/p95/max; a separate gprof run includes instrumentation overhead):

```sh
python3 tools/gpu/emu/pc/profile_ember.py
python3 tools/gpu/emu/pc/profile_ember.py --gprof
```

Outputs live in `build/ember-perf/profile/`. Phase IDs: 0 simulation, 1 gfx
preparation, 2 audio including mixing/IRQ, 3 DISP composition, 4 platform wait;
GPU IDs are 16 + opcode (32 CLEAR, 48 DRAW_TRI, 49 DRAW_QUAD, 50 OBJ_STEP,
64 TEX_LOAD, 65 PAL_LOAD, 80 RESOLVE, 17–21 state setup). The Linux headless
frontend has no display-device or GDI calls, and its platform wait is immediate.
Indexed texture caches retain indices across per-quad palette-group changes;
alpha blending still rounds source and destination products separately.
Use `--revision <commit>` for the same instrumentation on historical C sources;
its output directory is `build/ember-perf/profile-<commit>/`.
