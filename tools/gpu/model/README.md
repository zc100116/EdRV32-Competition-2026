# GPU reference model

Implements `gpu-spec.md` v0.1 sections 2–6 plus the resource-closure decision da4c70345 without reading GPU RTL. Layouts come directly
from `rtl/include/regs/gpu.json`; arithmetic proposals and coordinator-confirmed specification
omissions are recorded in `docs/reports/2026-11-24-model-gpu-numeric.md`.
Python 3 standard library only; no extra installation is needed.

```python
from tools.gpu.scene import Memory
from tools.gpu.model import GPU, Numeric

memory = Memory.read_hex('build/gpu/scene.hex', base=0x80000000)
gpu = GPU(memory, viewport=(0, 0, 640, 360))
gpu.execute([['DESC_BASE', command_address], ['DESC_COUNT', command_count], ['DOORBELL', 1]])
# gpu.color / gpu.depth: flat row-major array('H'); gpu.stencil: bytearray
# gpu.memory: updated DDR; gpu.regs: register names (including PERF[1] etc.) -> integers
```

`execute` accepts ordered register writes by name or numeric APB offset. `DOORBELL` executes
synchronously. `run()` uses the current `DESC_BASE/COUNT`; `run([encoded_command, ...])`
executes an explicit command list. State commands must precede their consumers; clear target
contents before relying on them. Construction allocates zero-filled host storage, which does
not define the hardware's power-on RAM contents. `TGT_CFG` changes the physical 115200-pixel
storage organization without clearing it.

The viewport is a model API parameter pending specification completion. For stripe rendering,
use the same full-screen viewport for every stripe and change `SET_TARGET` and `TGT_CFG`.
`reference_size=(1280,720)` allocates the full-screen ideal target used exclusively for the
stripe-equivalence test; this is not a hardware configuration. The physical target is
640x180 or 1280x90, selected by TGT_CFG; 640x360 uses two stripes and 1280x720 uses eight.

```sh
python3 tools/gpu/model/selftest.py
python3 tools/gpu/model/numeric.py --output build/gpu/numeric.json
python3 -m tools.gpu.model build/gpu/scene.hex build/gpu/writes.json build/gpu/expected \
    --base 0x80000000 --viewport 0 0 640 360
```

The CLI exports `color.bin`, `depth.bin` (little-endian u16), `stencil.bin` (u8), updated
`ddr.hex`, and `registers.json`. The target arrays contain physical target coordinates;
`SET_TARGET.TGT_X0/Y0` maps screen coordinates into those arrays. RESOLVE Surface addresses
are `BASE + screen_y*STRIDE + 2*screen_x`; the region is in screen coordinates.

PERF1–4 count functional events; timing counters PERF0/5–8 are not predicted and remain zero.
The model does not simulate APB/AXI cycles, transactions in flight, or mid-command ABORT.
`Memory.read_errors` and `Memory.write_errors` are sets of byte addresses at which accesses
raise the specified AXI error (ERR_CODE 2). Other specified errors set registers and stop the
command list. Host/API errors raise exceptions; there are no recovery paths.

`Numeric` holds the temporary G-N1–G-N3 research configurations. MVP input is encoded s15.16;
`matrix_frac` can reduce its evaluated precision. Reciprocal ROMs and log ROMs are generated
from integer arithmetic, then cached; all rendering arithmetic is integer. The independent
float study uses the exact values of the encoded input matrix/vertices as its ideal input.

Textures use the four-bank parity layout from microarch 7ed45f8e9 section 4.8 in 192 KiB
RAM (two 96 KiB halves). `interleave_texture(levels, width, height, format)` exported from
`tools.gpu.model` converts row-major integer mip texels into the physical byte stream;
`Scene.texture` calls it automatically. Each mip reserves complete 2x2 halfword groups,
including 8 bytes for a 1x1 mip, and descriptor bounds use this padded physical size.
`TEX_LOAD` performs a linear byte copy; it does not convert a row-major image online.

`OBJ_STEP STEP=0` counts and optionally draws the input alive objects, without motion,
live-region tests, collisions, list writes, or table writes. HIT/FREE counts and overflow
are zero for that command; ALIVE_COUNT counts the alive input records. STEP=1 performs
all simulation, collisions and writeback before any drawing. Development clock is 180 MHz;
this functional model produces no cycle estimates.
