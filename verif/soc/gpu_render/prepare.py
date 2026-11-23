#!/usr/bin/env python3
# File: prepare.py
# Spec: gpu-soc-testplan ST-10; gpu-spec v0.3 2.
# Description: Render the software scene through tools/gpu/model for HDMI comparison.
# Clock domain: host reference generation.
from pathlib import Path
import struct
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu.scene import Memory, pack
from tools.gpu.model import GPU


def prepare(out):
    memory = Memory(0, bytes(0x180000))
    matrix = [0] * 16
    matrix[0] = matrix[5] = 655
    matrix[10] = 328
    matrix[15] = 65536
    memory.write(0x10000, struct.pack('<16i', *matrix))
    memory.write(0x10100, b'\xff\xff' * 64)
    for i, (x, y, color) in enumerate([(-80, -60, 0xf800), (80, -60, 0x07e0), (0, 60, 31)]):
        memory.write(0x10200 + i * 16, pack('VERTEX', X=x, Y=y, Z=100, COLOR=color))
    memory.write(0x10300, pack('QUAD', X=20, Y=20, W=40, H=24, ALPHA=255))
    memory.write(0x10400, pack('OBJ', ALIVE=1, PX=500*256, PY=280*256, VX=256,
                               W=20, H=20, ALPHA=255))
    gpu = GPU(memory)
    gpu.execute([('OBJ_LIVE_RECT0', 0), ('OBJ_LIVE_RECT1', 640 | (360 << 16))])
    commands = []
    for stripe in range(2):
        y = stripe * 180
        fields = [
            ('SET_TARGET', dict(TGT_Y0=y, SC_Y0=y, SC_X1=640, SC_Y1=y+180, VP_W=640, VP_H=360)),
            ('CLEAR', dict(COLOR=0x0841, DEPTH=65535, EN_COLOR=1, EN_DEPTH=1, EN_STENCIL=1)),
            ('SET_MATRIX', dict(ADDR=0x10000)),
            ('SET_LIGHT', dict(LZ=16384, AMB_RGB=0xffffff)),
            ('TEX_LOAD', dict(SRC=0x10100, BYTES=128)),
            ('SET_TEX', dict(LOG2_W=3, LOG2_H=3, FORMAT=2, LEVELS=1)),
            ('SET_PIXEL', dict(DEPTH_FUNC=1, COLOR_WRITE=1, ST_FUNC=7,
                               ST_RMASK=255, ST_WMASK=255, BL_FS=1)),
            ('DRAW_TRI', dict(ADDR=0x10200, COUNT=1)),
            ('DRAW_QUAD', dict(ADDR=0x10300, COUNT=1)),
            ('OBJ_STEP', dict(ADDR=0x10400, COUNT=1, STEP=int(stripe == 0), DRAW=1)),
            ('RESOLVE', dict(BASE=0x100000, STRIDE=1280, Y0=y, X1=640, Y1=y+180))]
        # Scene supplies the opcode; use its canonical command constructor.
        from tools.gpu.scene import Scene
        scene = Scene(base=0)
        for name, args in fields:
            scene.command(name, **args)
        commands.extend(scene.commands)
        gpu.run(scene.commands)
    pixels = struct.unpack('<230400H', gpu.memory.read(0x100000, 640*360*2))
    (out / 'surface.hex').write_text(''.join(f'{p:04x}\n' for p in pixels))
    (out / 'commands.bin').write_bytes(b''.join(commands))
    print('PASS ST-10 reference: 2 stripes, 230400 source pixels')


if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
