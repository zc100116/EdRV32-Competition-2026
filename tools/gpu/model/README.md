# GPU reference model (gpu-spec v0.2)

Python 3 standard library only. The model implements sections 2–6 with fixed arithmetic
from 2.12; command/record layouts come from `rtl/include/regs/gpu.json`. There are no
numeric study parameters. Historical numeric experiments are reproduced using the commit
and commands in `docs/reports/2026-11-24-model-gpu-numeric.md`.

The verification worker can create input DDR, commands and register writes with `Scene`
(see `../scene/README.md`), then run the same image through the oracle:

```python
import json
from pathlib import Path
from tools.gpu.scene import Memory
from tools.gpu.model import GPU

# scene.export has already written these two input files.
image = Path('build/gpu/scene.hex')
writes = json.loads(Path('build/gpu/writes.json').read_text())
memory = Memory.read_hex(image, base=0x80000000)
gpu = GPU(memory).execute(writes)
gpu.memory.write_hex('build/gpu/expected-ddr.hex')
# gpu.color / gpu.depth: flat row-major array('H'); gpu.stencil: bytearray
# gpu.regs: register names -> integers, e.g. PERF[1], OBJ_HIT_COUNT, ERR_CODE
```

`execute(writes)` accepts ordered `(register name or numeric APB offset, value)` pairs.
`DOORBELL` executes synchronously using `DESC_BASE` and `DESC_COUNT`. Alternatively,
`gpu.run(scene.commands)` executes a list of encoded 32-byte commands directly; `run()`
without an argument reads the command list from DDR. Both return `gpu`.
`Memory.read(address, size)` returns bytes for comparing a Surface, object table or list;
`memory.base` and `memory.data` identify the complete contiguous DDR image. Clone input
memory with `Memory(scene.memory.base, scene.memory.data)` before running if both input
and expected images must remain available in memory. `read_errors` and `write_errors`
are sets of DDR byte addresses used to inject the specified AXI error (ERR_CODE 2).

The viewport comes exclusively from `SET_TARGET.VP_X0/VP_Y0/VP_W/VP_H`. Set these fields
before drawing; the GPU constructor and CLI have no viewport argument. Signed viewport
origins and unsigned dimensions follow the JSON layout. For stripes, keep VP_* constant
and change TGT_X0/TGT_Y0 and SC_*; TGT_X0 must be a multiple of four. Physical storage is
115200 pixels: TGT_CFG=0 selects 640x180, TGT_CFG=1 selects 1280x90. Stripe equivalence
compares color, depth and stencil for 640x360 in two stripes and 1280x720 in eight stripes.
`reference_size=(width,height)` allocates a full-frame oracle for that comparison only;
it does not represent a hardware configuration. RESOLVE addresses are
`BASE + screen_y*STRIDE + 2*screen_x`. AA clamps neighbors at each RESOLVE region boundary.

```sh
python3 tools/gpu/model/selftest.py
python3 -m tools.gpu.model build/gpu/scene.hex build/gpu/writes.json build/gpu/expected \
    --base 0x80000000
```

The CLI exports `color.bin` and `depth.bin` as little-endian u16, `stencil.bin` as u8,
updated `ddr.hex`, and `registers.json`. Binary target buffers use physical row-major target
coordinates; subtract SET_TARGET.TGT_X0/Y0 from screen coordinates to index them.
Rendering is entirely integer: MVP s15.16, clip coordinates 40-bit Q16, q Q30 with a
10-bit midpoint ROM and one Newton step, and Q8 LOD with an 8-bit-index log2 ROM.
Bilinear filtering subtracts half a texel after selecting/scaling each mip level;
trilinear filtering uses that same convention independently at both levels.

`interleave_texture(levels, width, height, format)` converts row-major integer mip texels
to the physical four-bank texture stream; `Scene.texture` calls it automatically. RAM is
192 KiB, two 96 KiB halves; each mip reserves complete 2x2 halfword groups, including
8 bytes for a 1x1 mip. Descriptor bounds use that padded physical size. TEX_LOAD copies
bytes linearly. STEP=0 counts and optionally draws alive objects without simulation,
collision, list writes or table writes; HIT/FREE counts and overflow are zero.

State commands must precede their consumers; clear target contents before relying on them.
Zero-filled host allocation does not define hardware power-on RAM contents. TGT_CFG changes
organization without clearing storage. PERF1–4 count functional events. The model does not
simulate APB/AXI cycles, transactions in flight, mid-command ABORT or timing counters
PERF0/5–8, which remain zero. Only specified GPU errors are converted to ERR_CODE and stop
the list; host/API errors raise exceptions.
