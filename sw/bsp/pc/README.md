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

Ember Isles E3 has a separate game input interface; the legacy `plat_keys()`
controller bitmap and existing frontend callbacks retain their values.
`plat_game_keys()` returns W/A/S/D/J/K/L/U/Q/F/Space/Esc/Enter at bits 0..12.
`plat_pointer()` returns 640x360 logical menu coordinates with left/right/middle
button bits 0/1/2. PC frontends publish both through
`pc_soc_game_input(uint16_t keys, struct plat_pointer_state pointer)`.
The Ember Isles Windows frontend supports WASD and arrow aliases, J/K/L/U/Q/F,
Space, Esc and Enter, and scales pointer coordinates for either window size.
On focus loss it releases keyboard/mouse state; the game layer consumes the
pointer only in menus, outside the deterministic replay input stream.

Board virtual input retains its eight-byte wire frame: keys16 little endian,
x/y signed16 little endian (1280x720), mouse L/R/M at byte 6, cumulative wheel
at byte 7. `active` is receiver state, not a ninth wire byte. Existing VI bits
0..11 are unchanged; L/U/Q/F occupy bits 12..15. Board game keys map VI_UP,
LEFT, DOWN, RIGHT, A, B to W/A/S/D/J/K; VI_SELECT to Space, VI_ESC to Esc,
VI_ENTER to Enter, and the four new bits directly to L/U/Q/F. VI_START/NEXT/PREV
are not game keys. `plat_pointer()` divides wire coordinates by two. GPIO
RIGHT/LEFT/A/START maps to game D/A/J/Enter. The debug-tool sender exposes the
new keys; Space replaces its former U physical shortcut for VI_SELECT.

`make -C sw/bsp/pc test -j1` also checks this input contract. The Windows Ember
frontend prints frame mean/p95/max, actual FPS, texture end offset and object
peaks every 600 frames and on shutdown. `game_gdi_ms` excludes platform wait,
DISP composition and audio service; `frame_ms` includes the entire iteration.
Windows QPC pacing keeps absolute 60 Hz deadlines so Sleep rounding does not
accumulate. Actual GDI/waveOut timing requires a Windows runtime measurement.
