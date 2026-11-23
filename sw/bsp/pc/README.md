# GPU PC platform

From the repository root, build one target at a time (`-j1`):

```sh
make -C sw/bsp/pc linux -j1
make -C sw/bsp/pc windows -j1
. ~/.local/opt/edrv32/env.sh
make -C sw/bsp/pc board -j1
```

Products are `build/gpu_pc/gpu_hello`, `gpu_hello.exe`, and `gpu_hello.elf`.
Every build uses C11 and `-Wall -Wextra -Werror`. Windows uses
`~/.local/opt/zig-0.17.0/zig cc -target x86_64-windows-gnu`; the executable
contains its textures and font and needs only Windows system libraries.
The RISC-V ELF links into DDR and is compile-only until hardware is available.

Run the deterministic Linux frontend and replay its GPU capture:

```sh
build/gpu_pc/gpu_hello --frames 300 --dump 1,150,300 --out build/gpu_pc/frames \
    > build/gpu_pc/perf.csv
python3 tools/gpu/emu/pc/replay.py build/gpu_pc/frames
make -C sw/bsp/pc test -j1
```

`frame001.png`, `frame150.png`, and `frame300.png` are 1280×720 RGB PNGs.
The PNG stream uses stored DEFLATE blocks; its CRC and Adler fields are required
by the file format. CSV reports all 16 GPU PERF counters for each frame; cycle
counters remain zero in the functional GPU model. The example resets the GPU
and supplies all GPU state and textures each frame, so the counters describe
one frame and the frame-150 capture can be replayed independently.
That capture contains the entire 64 MiB DDR before the first GPU write,
the ordered GPU register writes, DDR after the GPU finishes, and PERF values.
The replay compares every DDR byte and all PERF counters with the Python model.

Input scripts use one `frame-number key-mask` per line, in increasing frame order;
the state remains active until the next line. Decimal and `0x` masks are accepted.
For example, `1 0x01`, `60 0x08`, `120 0` holds UP, then RIGHT, then releases all
keys. Pass the file with `--input path`.

The coordinator clarified S-0b on 2026-11-23: keep eight controller bits matching
`virtual_input.h`, without X/Y. Masks are UP=1, DOWN=2, LEFT=4, RIGHT=8, A=16,
B=32, SELECT=64, START=128. Windows keys are arrows, Z/X, Esc/Enter; run
`gpu_hello.exe --half` for a 640×360 window instead of 1280×720.
Board GPIO bits 0–3 (next/prev/enter/esc) map to RIGHT/LEFT/A/START.
Board ETH uses the existing controller window at `VIRTUAL_INPUT_BASE`,
MAC `02:45:44:52:56:32`, IP `192.168.1.10`, UDP port 5000, as the existing monitor.

PC compilation puts the replacement MMIO header first in the search path and
force-includes it to establish `EDRV32_MMIO_H` before quote-includes in driver
headers. The board and PC compile the same GPU/AUD/DISP/PLIC driver sources.
DDR allocation returns aligned offsets within a contiguous 64 MiB host image;
the board uses a 64 MiB static DDR pool. Cache operations on PC are no-ops.
Headless time advances 800 stereo samples per display frame; Windows follows
wall time at 48 kHz and uses waveOut. IRQ delivery uses PLIC claim/complete and
the same `plat_irq_register` callback convention on both targets.
