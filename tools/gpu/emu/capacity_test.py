#!/usr/bin/env python3
"""capacity_test.py — tech 5a: default 192 KiB bounds and PC 256 KiB rendering.
Host C11 emulator through its public API; Python standard library only.
"""
import ctypes as C
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu.scene import Scene, SCHEMA

BUILD = ROOT / 'build/gpu-emu/capacity'
REGS = {r['name']: int(r['offset'], 0) for r in SCHEMA['registers']}


class Usage(C.Structure):
    _fields_ = [('texture_bytes', C.c_uint32), ('object_slots', C.c_uint32),
                ('objects_alive', C.c_uint32)]


def run(lib, scene):
    writes = scene.finish()
    data = (C.c_uint8 * len(scene.memory.data)).from_buffer_copy(scene.memory.data)
    emu = lib.gpu_emu_create(data, len(data))
    for name, value in writes:
        lib.gpu_emu_write(emu, REGS[name], value)
    return emu, data


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    for capacity in (192 * 1024, 256 * 1024):
        binary = BUILD / f'capacity-{capacity}.so'
        subprocess.run(['gcc', '-std=c11', '-O3', '-Wall', '-Wextra', '-Werror',
                        '-DGPU_EMU_THREADS=1', f'-DGPU_EMU_TEXTURE_BYTES={capacity}',
                        '-shared', '-fPIC', str(ROOT / 'tools/gpu/emu/gpu_emu.c'),
                        '-o', str(binary)], check=True)
        lib = C.CDLL(str(binary))
        lib.gpu_emu_create.argtypes = [C.c_void_p, C.c_uint32]
        lib.gpu_emu_create.restype = C.c_void_p
        lib.gpu_emu_write.argtypes = [C.c_void_p, C.c_uint32, C.c_uint32]
        lib.gpu_emu_read.argtypes = [C.c_void_p, C.c_uint32]
        lib.gpu_emu_read.restype = C.c_uint32
        lib.gpu_emu_destroy.argtypes = [C.c_void_p]
        lib.gpu_emu_usage.argtypes = [C.c_void_p]
        lib.gpu_emu_usage.restype = Usage
        # Texture at byte 196608 lies just outside hardware RAM and inside PC RAM.
        scene = Scene(0)
        source = scene.blob(struct.pack('<64H', *([0xf800] * 64)))
        quads = scene.records('QUAD', [dict(W=8, H=8, ALPHA=255)])
        output = scene.reserve(8 * 8 * 2, 4096)
        scene.command('TEX_LOAD', SRC=source, DST=192 * 1024, BYTES=128)
        scene.command('SET_TEX', OFFSET=192 * 1024, LOG2_W=3, LOG2_H=3, FORMAT=2, LEVELS=1)
        scene.command('SET_TARGET', SC_X1=8, SC_Y1=8)
        scene.command('SET_PIXEL', DEPTH_FUNC=1, ST_FUNC=7, COLOR_WRITE=1, BL_FS=1)
        scene.command('DRAW_QUAD', ADDR=quads, COUNT=1)
        scene.command('RESOLVE', BASE=output, STRIDE=32, X1=8, Y1=4)
        # Stride is 32-byte aligned; reserve enough DDR for all resolved rows.
        emu, data = run(lib, scene)
        error = lib.gpu_emu_read(emu, REGS['ERR_CODE'])
        assert error == (4 if capacity == 192 * 1024 else 0), (capacity, error)
        if not error:
            for y in range(4):
                assert bytes(data[output + y * 32:output + y * 32 + 16]) == b'\x00\xf8' * 8
            usage = lib.gpu_emu_usage(emu)
            assert usage.texture_bytes == 192 * 1024 + 128
            reset_bit = next(f['lsb'] for r in SCHEMA['registers'] if r['name'] == 'CTRL'
                             for f in r['fields'] if f['name'] == 'SOFT_RST')
            lib.gpu_emu_write(emu, REGS['CTRL'], 1 << reset_bit)
            assert lib.gpu_emu_usage(emu).texture_bytes == usage.texture_bytes
        lib.gpu_emu_destroy(emu)
        scene = Scene(0)
        scene.command('SET_TEX', OFFSET=192 * 1024, LOG2_W=3, LOG2_H=3, FORMAT=2, LEVELS=1)
        emu, data = run(lib, scene)
        error = lib.gpu_emu_read(emu, REGS['ERR_CODE'])
        assert error == (3 if capacity == 192 * 1024 else 0), (capacity, error)
        lib.gpu_emu_destroy(emu)
        print(f'PASS capacity={capacity}: TEX_LOAD/SET_TEX bounds and extended render')


if __name__ == '__main__':
    main()
