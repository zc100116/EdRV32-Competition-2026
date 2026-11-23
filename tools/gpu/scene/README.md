# Scene construction API

`Scene` constructs the DDR image and ordered register writes for both the model and a GPU
verification testbench. Integer record fields are in encoded fixed-point units: e.g. object
`PX=10*256`, vertex `U=3*256`, matrix entries via `Scene.matrix` in real units.
All names and widths are read from the canonical GPU register JSON. Omitted record/command
fields are encoded as zero; `Scene.command` supplies the opcode. Byte addresses, texture
byte offsets, strides, and byte counts are passed in bytes, including their low zero bits.
Negative signed values are encoded in two's complement. No range or alignment checks are
added beyond the specification's model-side errors.

```python
from tools.gpu.scene import Scene
from tools.gpu.model import GPU

scene = Scene(base=0x80000000)
texture, texture_bytes = scene.texture([[0xf800] * 64], format=2, width=8, height=8)
quads = scene.records('QUAD', [dict(X=7, Y=9, W=16, H=16, ALPHA=255)])
surface = scene.reserve(640 * 360 * 2, alignment=4096)
scene.command('TEX_LOAD', SRC=texture, DST=0, BYTES=texture_bytes)
scene.command('SET_TEX', OFFSET=0, LOG2_W=3, LOG2_H=3, FORMAT=2, LEVELS=1)
scene.command('SET_PIXEL', DEPTH_FUNC=1, COLOR_WRITE=1, ST_FUNC=7,
              ST_RMASK=255, ST_WMASK=255, BL_FS=1)
scene.command('SET_TARGET', SC_X1=640, SC_Y1=360)
scene.command('CLEAR', COLOR=0, DEPTH=65535, EN_COLOR=1, EN_DEPTH=1, EN_STENCIL=1)
scene.command('DRAW_QUAD', ADDR=quads, COUNT=1)
scene.command('RESOLVE', BASE=surface, STRIDE=1280, X1=640, Y1=180)
# Create build/gpu first; export writes no directories or metadata implicitly.
writes = scene.export('build/gpu/scene.hex', 'build/gpu/writes.json')
gpu = GPU(scene.memory).execute(writes)
assert gpu.color[9 * 640 + 7] == 0xf800
```

- `blob(bytes, alignment=32)` and `reserve(size, alignment=32)` return DDR byte addresses.
- `records('VERTEX'|'QUAD'|'OBJ'|'PAL_ENTRY', dictionaries)` packs a table, 32 B aligned.
- `matrix(16_floats)` allocates row-major s15.16 words (nearest-even on scene input).
- `texture([level0_texels, level1_texels, ...], format, width, height)` returns `(address, padded_bytes)`;
  input levels are row-major; output is four-bank parity interleaved with complete 2x2
  halfword groups per mip, followed by final DMA padding to 32 B. This includes 8 B per
  1x1 mip. RAM capacity is 192 KiB. `TEX_LOAD` copies these bytes without rearranging.
- `reg(name, value)` appends setup writes, e.g. `TGT_CFG`, `OBJ_TGT0[3]`, `OBJ_HIT_BASE`.
- `finish()` allocates a 64 B aligned command stream and returns setup writes followed by
  `DESC_BASE`, `DESC_COUNT`, `DOORBELL`. Call it once after building the scene.
- `export(hex_path, register_path)` calls `finish`, exports the DDR and JSON write list.
- `Memory.read_hex(path, base)` imports the same format. Each line is a numeric 32-bit
  little-endian memory word; e.g. bytes `01 02 03 04` produce line `04030201`. The starting
  DDR byte address is explicitly passed as `base`, not embedded as an extra hex directive.
- `pack(layout, **fields)` and `unpack(layout, bytes)` expose the same record codec directly.
