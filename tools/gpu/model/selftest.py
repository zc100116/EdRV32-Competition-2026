#!/usr/bin/env python3
"""selftest.py — gpu-spec 2–6 / gpu-testplan 4 reference-model self-checks.
Host Python tests, no clock domain. Run directly from any working directory.
"""
from array import array
import random
import struct
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.gpu.model import GPU, Numeric, interleave_texture
from tools.gpu.model.layout import mip_layout, texel_address
from tools.gpu.model.arithmetic import d, divide, expand, p565
from tools.gpu.scene import LAYOUTS, Memory, Scene, pack, unpack


def pixel_state(**overrides):
    values = dict(DEPTH_FUNC=1, DEPTH_WRITE=0, COLOR_WRITE=1, CULL=0,
                  ST_FUNC=7, ST_SFAIL=0, ST_ZFAIL=0, ST_ZPASS=0, ST_REF=0,
                  ST_RMASK=255, ST_WMASK=255, BL_FS=1, BL_FD=0, BL_OP=0, BL_CONST_A=0)
    values.update(overrides)
    return unpack('CMD_SET_PIXEL', pack('CMD_SET_PIXEL', **values))


def target(gpu, width=640, height=360, y=0):
    gpu.target = dict(TGT_X0=0, TGT_Y0=y, SC_X0=0, SC_Y0=y,
                      SC_X1=width, SC_Y1=y + height)


def ready(color=0xffff, **kwargs):
    scene = Scene()
    scene.blob(bytes(4096))
    gpu = GPU(scene.memory, **kwargs)
    gpu.pixel_state = pixel_state()
    target(gpu)
    gpu.ram[:128] = struct.pack('<64H', *([color] * 64))
    gpu.command(pack('CMD_SET_TEX', OFFSET=0, LOG2_W=3, LOG2_H=3,
                     FORMAT=2, LEVELS=1, SAMPLE=0))
    return gpu


def quad(x=0, y=0, width=1, height=1, **kwargs):
    return unpack('QUAD', pack('QUAD', X=x, Y=y, W=width, H=height, ALPHA=255, **kwargs))


def screen_vertex(x, y, depth=0):
    return [x, y, depth, 1 << 30, 0, 0, 255 << 16, 255 << 16, 255 << 16]


def test_shared_edges():
    for seed in range(4):
        rng = random.Random(seed)
        gpu = ready(0x0821)
        gpu.pixel_state = pixel_state(BL_FD=1)
        grid = [[(32 + x * 192 + (rng.randrange(-48, 49) if 0 < x < 8 else 0),
                  32 + y * 192 + (rng.randrange(-48, 49) if 0 < y < 8 else 0))
                 for x in range(9)] for y in range(9)]
        for y in range(8):
            for x in range(8):
                a, b, c, e = grid[y][x], grid[y][x + 1], grid[y + 1][x], grid[y + 1][x + 1]
                triangles = ((a, b, e), (a, e, c)) if rng.randrange(2) else ((a, b, c), (b, e, c))
                for points in triangles:
                    if rng.randrange(2):
                        points = points[::-1]
                    gpu.triangle([screen_vertex(*point) for point in points])
        for y in range(104):
            for x in range(104):
                expected = 0x0821 if 2 <= x < 98 and 2 <= y < 98 else 0
                assert gpu.color[y * 640 + x] == expected, (seed, x, y)
        assert gpu.regs['PERF[4]'] == 96 * 96
    # A horizontal/vertical edge passes through pixel centres, including a shared vertex.
    gpu = ready(0x0821)
    gpu.pixel_state = pixel_state(BL_FD=1)
    a, b, c, e = ((8, 8), (168, 8), (8, 168), (168, 168))
    for points in ((a, b, e), (a, e, c)):
        gpu.triangle([screen_vertex(*point) for point in points])
    assert sum(value != 0 for value in gpu.color) == 100
    assert set(gpu.color) == {0, 0x0821}


def test_hand_computed():
    gpu = ready(0xf800)
    gpu.quad(quad(2, 3, 2, 2))
    assert [gpu.color[y * 640 + x] for y in (3, 4) for x in (2, 3)] == [0xf800] * 4
    assert gpu.regs['PERF[3]'] == 1 and gpu.regs['PERF[4]'] == 4
    gpu = ready()
    gpu.triangle([screen_vertex(0, 0), screen_vertex(64, 0), screen_vertex(0, 64)])
    # Top-left excludes the descending diagonal: rows contain 3,2,1,0 centres.
    assert gpu.regs['PERF[4]'] == 6
    assert [sum(gpu.color[y * 640:y * 640 + 4]) // 65535 for y in range(4)] == [3, 2, 1, 0]
    gpu.pixel_state = pixel_state(COLOR_WRITE=0, ST_ZPASS=3)
    gpu.quad(quad(0, 0, 2, 2))
    gpu.quad(quad(1, 1, 2, 2))
    assert gpu.stencil[0] == 1 and gpu.stencil[641] == 2 and gpu.stencil[1282] == 1
    gpu.pixel_state = pixel_state(DEPTH_FUNC=0, DEPTH_WRITE=1, ST_ZFAIL=2, ST_REF=73)
    gpu.depth[0] = 9
    gpu.pixel(0, 0, 10, (255, 0, 0, 255))
    assert gpu.stencil[0] == 73 and gpu.depth[0] == 9
    before = (gpu.color[0], gpu.depth[0], gpu.stencil[0])
    gpu.pixel(0, 0, 0, (255, 0, 0, 0), transparent=True)
    assert before == (gpu.color[0], gpu.depth[0], gpu.stencil[0])
    # A zero *global* alpha is still a fragment when the texture is opaque.
    gpu.ram[:128] = struct.pack('<64H', *([0xffff] * 64))
    gpu.pixel_state = pixel_state(ST_ZPASS=3)
    before = gpu.stencil[0]
    item = quad()
    item['ALPHA'] = 0
    gpu.quad(item)
    assert gpu.stencil[0] == before + 1
    assert gpu.color[0] == 0xffff


def test_strips():
    for width, height, stripe_height, wide in ((640, 360, 180, 0), (1280, 720, 90, 1)):
        full = ready(viewport=(0, 0, width, height), reference_size=(width, height))
        target(full, width, height)
        pattern = interleave_texture([[0xffff if (x + y) % 2 else 0x8410
                                       for y in range(8) for x in range(8)]], 8, 8, 2)
        full.ram[:128] = pattern
        rectangles = [quad((index * 137) % (width - 50), index * 29 - 13, 49, 63,
                           DEPTH=index * 13) for index in range(25)]
        full.pixel_state = pixel_state(DEPTH_WRITE=1, ST_ZPASS=3)
        for item in rectangles:
            full.quad(item)
        matrix = (256, 0, 0, -65536, 0, -256, 0, 65536, 0, 0, 256, 0, 0, 0, 0, 65536)
        vertices = [dict(X=x, Y=y, Z=index * 64, NX=0, NY=0, NZ=127, U=x * 100,
                         V=y * 100, COLOR=(0xf800, 0x07e0, 0x001f)[index])
                    for index, (x, y) in enumerate(((1, 1), (500, 1), (200, 500)))]
        full.matrix = matrix
        full.light = dict(LX=0, LY=0, LZ=0, AMB_RGB=0xffffff, DIR_RGB=0)
        full.draw_triangle(vertices)
        stitched_color, stitched_depth, stitched_stencil = array('H'), array('H'), bytearray()
        for y in range(0, height, stripe_height):
            strip = ready(viewport=(0, 0, width, height))
            strip.write_register('TGT_CFG', wide)
            strip.ram[:128] = pattern
            target(strip, width, stripe_height, y)
            strip.pixel_state = full.pixel_state
            strip.matrix, strip.light = matrix, full.light
            for item in rectangles:
                strip.quad(item)
            strip.draw_triangle(vertices)
            stitched_color.extend(strip.color)
            stitched_depth.extend(strip.depth)
            stitched_stencil.extend(strip.stencil)
        assert full.color == stitched_color
        assert full.depth == stitched_depth
        assert full.stencil == stitched_stencil


def test_objects():
    scene = Scene()
    objects = [dict(ALIVE=1, PX=10 * 256, PY=10 * 256, VX=256, VY=0, AX=2048,
                    AY=0, LIFE=0, COL_HW=2, COL_HH=2, TGT_MASK=3, W=2, H=2, ALPHA=255),
               dict(ALIVE=1, PX=10 * 256, PY=10 * 256, LIFE=1),
               dict(ALIVE=1, PX=99 * 256, PY=10 * 256, VX=512), dict(ALIVE=0)]
    address = scene.records('OBJ', objects)
    raw = bytearray(scene.memory.read(address, 32))
    raw[0] |= 0x80
    raw[7], raw[11], raw[22], raw[23] = 0xab, 0xcd, 0xef, 0xbe
    scene.memory.write(address, raw)
    hit = scene.reserve(32)
    free = scene.reserve(32)
    gpu = ready()
    gpu.memory = scene.memory
    for name, value in [('OBJ_LIVE_RECT0', 0), ('OBJ_LIVE_RECT1', 100 | (100 << 16)),
                        ('OBJ_HIT_BASE', hit), ('OBJ_HIT_MAX', 1),
                        ('OBJ_FREE_BASE', free), ('OBJ_FREE_MAX', 1),
                        ('OBJ_TGT0[0]', 10 | (8 << 16)), ('OBJ_TGT1[0]', 14 | (14 << 16)),
                        ('OBJ_TGT0[1]', 9 | (9 << 16)), ('OBJ_TGT1[1]', 15 | (15 << 16))]:
        gpu.write_register(name, value)
    gpu.objects(dict(ADDR=address, COUNT=4, STEP=1, DRAW=1))
    result = unpack('OBJ', scene.memory.read(address, 32))
    assert result['VX'] == 384 and result['PX'] == 2944
    updated = scene.memory.read(address, 32)
    assert updated[0] & 0x80
    assert [updated[i] for i in (7, 11, 22, 23)] == [0xab, 0xcd, 0xef, 0xbe]
    assert gpu.regs['OBJ_HIT_COUNT'] == 2 and gpu.regs['OBJ_FREE_COUNT'] == 2
    assert gpu.regs['OBJ_ALIVE_COUNT'] == 1 and gpu.regs['OBJ_STAT'] == 3
    assert scene.memory.read(hit, 4) == struct.pack('<I', 0)
    assert scene.memory.read(free, 4) == struct.pack('<I', 1)
    assert not unpack('OBJ', scene.memory.read(address + 32, 32))['ALIVE']
    assert not unpack('OBJ', scene.memory.read(address + 64, 32))['ALIVE']
    before = bytes(scene.memory.data)
    gpu.objects(dict(ADDR=address, COUNT=4, STEP=0, DRAW=0))
    assert bytes(scene.memory.data) == before
    assert gpu.regs['OBJ_FREE_COUNT'] == 0
    # Edge contact and fractional collision positions use floor-to-pixel coordinates.
    gpu.write_register('OBJ_TGT0[0]', 13 | (8 << 16))
    gpu.write_register('OBJ_TGT1[0]', 16 | (14 << 16))
    gpu.objects(dict(ADDR=address, COUNT=1, STEP=0, DRAW=0))
    assert gpu.regs['OBJ_HIT_COUNT'] == 0  # STEP=0 performs no collision
    stationary = unpack('OBJ', scene.memory.read(address, 32))
    stationary.update(VX=0, AX=0)
    scene.memory.write(address, pack('OBJ', **stationary))
    gpu.objects(dict(ADDR=address, COUNT=1, STEP=1, DRAW=0))
    assert gpu.regs['OBJ_HIT_COUNT'] == 1  # target 0 only touches the collision edge
    gpu.write_register('OBJ_LIVE_RECT1', 1 | (1 << 16))
    before = scene.memory.read(address, 32)
    for _ in range(2):
        gpu.objects(dict(ADDR=address, COUNT=1, STEP=0, DRAW=0))
        assert gpu.regs['OBJ_FREE_COUNT'] == 0 and gpu.regs['OBJ_ALIVE_COUNT'] == 1
        assert scene.memory.read(address, 32) == before


def test_texture():
    gpu = ready()
    texture = gpu.texture
    gpu.ram[:128] = interleave_texture(
        [[0xf800 if index % 2 else 0x001f for index in range(64)]], 8, 8, 2)
    assert texture.sample(0, 0, 0) == (0, 0, 255, 255)
    assert texture.sample(256, 0, 0) == (255, 0, 0, 255)
    assert texture.sample(-256, 0, 0) == (255, 0, 0, 255)
    texture.desc['SAMPLE'] = 1
    assert texture.sample(128, 0, 0) == (128, 0, 128, 255)
    gpu.command(pack('CMD_SET_TEX', LOG2_W=3, LOG2_H=3, FORMAT=2, LEVELS=2, SAMPLE=2))
    gpu.ram[128:160] = struct.pack('<16H', *([0x07e0] * 16))
    assert gpu.texture.sample(0, 0, 128) == (0, 128, 128, 255)
    gpu.ram[:32] = interleave_texture([[1 if x % 2 == 0 else 2
                                          for y in range(8) for x in range(8)]], 8, 8, 0)
    gpu.palettes[3][1] = (15 << 16) | 0xf800
    gpu.palettes[3][2] = 0x07e0
    gpu.command(pack('CMD_SET_TEX', LOG2_W=3, LOG2_H=3, FORMAT=0, LEVELS=1, PAL_GROUP=3))
    assert gpu.texture.sample(0, 0, 0) == (255, 0, 0, 255)
    assert gpu.texture.sample(256, 0, 0) == (0, 255, 0, 0)
    gpu.ram[0] = 1
    gpu.command(pack('CMD_SET_TEX', LOG2_W=3, LOG2_H=3, FORMAT=1, LEVELS=1, PAL_GROUP=3))
    assert gpu.texture.sample(0, 0, 0) == (255, 0, 0, 255)


def test_texture_layout():
    assert interleave_texture([[1, 2, 3, 4]], 2, 2, 0) == struct.pack('<4H', 0x4321, 0, 0, 0)
    assert interleave_texture([[1, 2, 3, 4]], 2, 2, 1) == struct.pack(
        '<4H', 0x0201, 0, 0x0403, 0)
    assert interleave_texture([list(range(16))], 4, 4, 2) == struct.pack(
        '<16H', 0, 1, 4, 5, 2, 3, 6, 7, 8, 9, 12, 13, 10, 11, 14, 15)
    for format, expected in ((0, 43704), (1, 87392), (2, 174768)):
        assert sum(level[3] for level in mip_layout(256, 256, 9, format)) == expected
        assert mip_layout(1, 1, 1, format)[0][3] == 8
        for width, height in ((8, 8), (2, 64), (256, 1), (1, 256)):
            mask = (15, 255, 65535)[format]
            texels = [(index * 7 + 3) & mask for index in range(width * height)]
            data = interleave_texture([texels], width, height, format)
            assert len(data) == mip_layout(width, height, 1, format)[0][3]
            for v in range(height):
                for u in range(width):
                    address, bit = texel_address(u, v, width, height, format, 0)
                    word = int.from_bytes(data[address:address + 2], 'little')
                    assert (word >> bit) & mask == texels[v * width + u]
                    banks = {}
                    for du, dv in ((0, 0), (1, 0), (0, 1), (1, 1)):
                        byte, _ = texel_address(u + du, v + dv, width, height, format, 0)
                        banks.setdefault((byte // 2) & 3, set()).add(byte // 2)
                    assert max(map(len, banks.values())) == 1
    assert len(interleave_texture([[1] * 128], 2, 64, 0)) == 128
    # The final 1x1 mip reserves 8 physical bytes; raw texel size would fit here.
    gpu = ready()
    gpu.run([pack('CMD_SET_TEX', OFFSET=196544, LOG2_W=3, LOG2_H=3,
                  FORMAT=0, LEVELS=6)])
    assert gpu.regs['ERR_CODE'] == 3


def test_command_stream():
    scene = Scene()
    matrix = scene.matrix([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0.5, 0, 0, 0, 1])
    tex, size = scene.texture([[0xffff] * 64], 2, 8, 8)
    palette = scene.records('PAL_ENTRY', [dict(RGB565=0xf800, A4=15)])
    quads = scene.records('QUAD', [dict(X=1, Y=1, W=2, H=2, ALPHA=255)])
    vertices = scene.records('VERTEX', [dict(X=x, Y=y, COLOR=65535)
                                        for x, y in ((-1, 1), (0, 1), (-1, 0))])
    output = scene.reserve(640 * 180 * 2, 4096)
    scene.command('SET_MATRIX', ADDR=matrix)
    scene.command('SET_LIGHT', AMB_RGB=0xffffff)
    scene.command('TEX_LOAD', SRC=tex, DST=0, BYTES=size)
    scene.command('PAL_LOAD', SRC=palette, GROUP=0, ENTRIES=1)
    scene.command('SET_TEX', LOG2_W=3, LOG2_H=3, FORMAT=2, LEVELS=1)
    scene.command('SET_PIXEL', **{k: v for k, v in pixel_state().items() if k != 'OPCODE'})
    scene.command('SET_TARGET', SC_X1=640, SC_Y1=360)
    scene.command('CLEAR', DEPTH=65535, EN_COLOR=1, EN_DEPTH=1, EN_STENCIL=1)
    scene.command('DRAW_QUAD', ADDR=quads, COUNT=1)
    scene.command('DRAW_TRI', ADDR=vertices, COUNT=1)
    scene.command('RESOLVE', BASE=output, STRIDE=1280, X1=640, Y1=180)
    with tempfile.TemporaryDirectory() as directory:
        image, writes = Path(directory) / 'ddr.hex', Path(directory) / 'registers.json'
        register_writes = scene.export(image, writes)
        memory = Memory.read_hex(image, scene.memory.base)
        gpu = GPU(memory).execute(register_writes)
    assert gpu.regs['ERR_CODE'] == 0 and gpu.regs['DONE_COUNT'] == 1
    assert gpu.regs['PERF[1]'] == 3 and gpu.regs['PERF[2]'] == 1
    assert gpu.color[0] == 0xffff
    assert memory.read(output, 2) == b'\xff\xff'
    assert gpu.palettes[0][0] == 0xff800
    # Every specified error stops before a following CLEAR; no silent fallback.
    for data, expected in [(bytes([255]) + bytes(31), 1),
                           (pack('CMD_SET_TEX', OFFSET=196576, LOG2_W=3, LOG2_H=3,
                                 FORMAT=2, LEVELS=1), 3),
                           (pack('CMD_TEX_LOAD', DST=196576, BYTES=64), 4)]:
        gpu = ready(0xf800)
        gpu.run([data, pack('CMD_CLEAR', COLOR=0xffff, EN_COLOR=1)])
        assert gpu.regs['ERR_CODE'] == expected and gpu.color[0] == 0
        assert gpu.regs['DONE_COUNT'] == 0 and not (gpu.regs['IRQ_STAT'] & 1)
    memory.read_errors.add(scene.memory.base)
    gpu = GPU(memory)
    gpu.regs.update(DESC_BASE=scene.memory.base, DESC_COUNT=1)
    gpu.run()
    assert gpu.regs['ERR_CODE'] == 2
    gpu = ready()
    gpu.memory = Memory(0, bytes(64))
    gpu.memory.write_errors.add(0)
    gpu.run([pack('CMD_RESOLVE', BASE=0, STRIDE=32, X1=16, Y1=1)])
    assert gpu.regs['ERR_CODE'] == 2 and gpu.regs['DONE_COUNT'] == 0


def test_stencil_blend_and_aa():
    gpu = ready()
    # Exhaust each stencil operation at saturation and with a nontrivial write mask.
    for old in (0, 19, 255):
        for operation, expected in enumerate((old, 0, 73, min(255, old + 1),
                                               max(0, old - 1), old ^ 255)):
            gpu.stencil[0] = old
            gpu.pixel_state = pixel_state(ST_REF=73, ST_WMASK=0x5a)
            gpu.stencil_op(0, operation)
            assert gpu.stencil[0] == ((old & 0xa5) | (expected & 0x5a))
    for function in range(8):
        for ref in (5, 19, 33):
            gpu.pixel_state = pixel_state(ST_FUNC=function, ST_REF=ref, ST_ZPASS=2,
                                          COLOR_WRITE=0)
            gpu.stencil[0] = 19
            gpu.pixel(0, 0, 0, (255, 255, 255, 255))
            passed = (False, ref < 19, ref == 19, ref <= 19, ref > 19,
                      ref != 19, ref >= 19, True)[function]
            assert gpu.stencil[0] == (ref if passed else 19)
    for fs in range(10):
        for fd in range(10):
            for op in range(5):
                gpu.color[0] = 0x6b4d
                gpu.pixel_state = pixel_state(BL_FS=fs, BL_FD=fd, BL_OP=op, BL_CONST_A=83)
                source, alpha, result = (211, 93, 47), 119, []
                for src, dst in zip(source, expand(0x6b4d)):
                    factors = [0, 255, alpha, 255 - alpha, src, 255 - src,
                               dst, 255 - dst, 83, 172]
                    a, b = divide(src * factors[fs], 255), divide(dst * factors[fd], 255)
                    value = [a + b, a - b, b - a, min(a, b), max(a, b)][op]
                    result.append(min(255, max(0, value)))
                gpu.pixel(0, 0, 0, (*source, alpha))
                assert gpu.color[0] == p565(result)
    gpu = ready()
    gpu.memory = Memory(0, bytes(64))
    gpu.color[0], gpu.color[1] = 0xffff, 0
    gpu.resolve(dict(X0=0, Y0=0, X1=2, Y1=1, BASE=0, STRIDE=32, FXAA=1, FXAA_TH=1))
    # N=S=C on a one-row image; vertical edge uses W and E, clamped at boundaries.
    assert gpu.memory.read(0, 4) == struct.pack('<HH', p565((191, 191, 191)), p565((63, 63, 63)))


def test_clipping_and_arithmetic():
    assert d(65025) == 255 and divide(-3, 2) == -2
    assert Numeric(matrix_frac=12).coefficient(0x7fffffff) == (1 << 27) - 1
    assert Numeric(matrix_frac=12).coefficient(-0x80000000) == -(1 << 27)
    gpu = ready()
    gpu.write_register('DESC_COUNT', 0x12345678)
    assert gpu.regs['DESC_COUNT'] == 0x5678
    gpu.write_register('TGT_CFG', 0xfffffffe)
    assert gpu.regs['TGT_CFG'] == 0 and (gpu.width, gpu.height) == (640, 180)
    gpu.matrix = (65536, 0, 0, 0, 0, 65536, 0, 0, 0, 0, 65536, 0, 0, 0, 0, 65536)
    gpu.light = dict(LX=0, LY=0, LZ=16384, AMB_RGB=0, DIR_RGB=0xffffff)
    v = dict(X=1, Y=2, Z=3, NX=0, NY=0, NZ=127, U=123, V=456, COLOR=65535)
    transformed = gpu.transform(v)
    unit = 1 << gpu.numeric.clip_frac
    assert transformed[:4] == [unit, 2 * unit, 3 * unit, unit]
    assert transformed[4:6] == [123, 456]
    assert transformed[6:] == [253 << 16] * 3
    gpu.light['AMB_RGB'] = 0xffffff
    assert gpu.transform(v)[6:] == [255 << 16] * 3
    f = gpu.numeric.clip_frac
    def vertex(x, y, w):
        return [round(x * (1 << f)), round(y * (1 << f)), 0, round(w * (1 << f)),
                0, 0, 255 << 16, 255 << 16, 255 << 16]
    for polygon in ([vertex(-1, -1, 1), vertex(1, -1, 1), vertex(0, 1, 0)],
                    [vertex(-8, -1, 1), vertex(8, -1, 1), vertex(0, 8, 1)]):
        result = gpu.clip(polygon)
        assert len(result) >= 3
        for v in result:
            assert v[3] >= gpu.numeric.near
            assert abs(v[0]) <= 4 * v[3] + 1 and abs(v[1]) <= 4 * v[3] + 1
    assert not gpu.clip([vertex(0, 0, -1)] * 3)
    before = gpu.regs['PERF[2]']
    gpu.triangle([screen_vertex(0, 0)] * 3)
    assert gpu.regs['PERF[2]'] == before
    for cull, points in [(1, [(0, 0), (64, 0), (0, 64)]),
                         (2, [(0, 0), (0, 64), (64, 0)])]:
        gpu.pixel_state = pixel_state(CULL=cull)
        gpu.triangle([screen_vertex(*p) for p in points])
        assert gpu.regs['PERF[2]'] == before


def main():
    start = time.perf_counter()
    for test in (test_shared_edges, test_hand_computed, test_strips, test_objects,
                 test_texture, test_texture_layout, test_command_stream, test_stencil_blend_and_aa,
                 test_clipping_and_arithmetic):
        test()
        print(f'{test.__name__}: PASS')
    print(f'PASS ({time.perf_counter() - start:.3f} s)')


if __name__ == '__main__':
    main()
