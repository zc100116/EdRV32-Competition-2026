#!/usr/bin/env python3
"""tech 4: measure GPU work for 1500 enemies, 3000 shots and 8000 live particles.
Synthetic command workload with Ember's primitive sizes; excludes CPU simulation.
Host monotonic/process clocks, generated CSV under build/gpu-emu.
"""
import csv
import ctypes as C
import time

import compare
from scene_support import Case


def scene():
    case = Case()
    case.scene = compare.Scene(0)
    case.ready(SC_X1=640, SC_Y1=180, VP_W=640, VP_H=360)
    s = case.scene
    palette = s.records('PAL_ENTRY', [dict(RGB565=(i * 4097) & 65535, A4=15)
                                      for i in range(256)])
    source, size = s.texture([[i % 256 for i in range(256 * 256)]], 1, 256, 256)
    s.command('PAL_LOAD', SRC=palette, GROUP=0, ENTRIES=256)
    s.command('TEX_LOAD', SRC=source, DST=0, BYTES=size)
    s.command('SET_TEX', LOG2_W=8, LOG2_H=8, FORMAT=1, LEVELS=1)
    case.matrix([1/320, 0, 0, -1, 0, -1/180, 0, 1, 0, 0, 0, .5, 0, 0, 0, 1])
    s.command('SET_PIXEL', DEPTH_FUNC=1, ST_FUNC=7, COLOR_WRITE=1, BL_FS=2, BL_FD=3)
    quads = s.records('QUAD', [dict(X=(i * 37) % 608, Y=(i * 17) % 328,
                                     W=32, H=32, ALPHA=255) for i in range(1500)])
    vertices = []
    for i in range(3000):
        x, y = (i * 41) % 622, (i * 23) % 342
        for dx, dy, u, v in [(0, 0, 0, 0), (18, 0, 8192, 0), (18, 18, 8192, 8192),
                              (0, 0, 0, 0), (18, 18, 8192, 8192), (0, 18, 0, 8192)]:
            vertices.append(dict(X=x+dx, Y=y+dy, Z=1, NZ=127, U=u, V=v, COLOR=65535))
    triangles = s.records('VERTEX', vertices)
    objects = s.records('OBJ', [dict(ALIVE=1, PX=((i * 31) % 632 + 4) * 256,
                                      PY=((i * 13) % 352 + 4) * 256, LIFE=120,
                                      W=8, H=8, ALPHA=255) for i in range(8000)])
    s.reg('OBJ_LIVE_RECT0', 0)
    s.reg('OBJ_LIVE_RECT1', 640 | (360 << 16))
    surface = s.reserve(640 * 360 * 2, 4096)
    for y0 in (0, 180):
        case.target(TGT_Y0=y0, SC_X1=640, SC_Y0=y0, SC_Y1=y0+180, VP_W=640, VP_H=360)
        case.clear()
        s.command('DRAW_QUAD', ADDR=quads, COUNT=1500)
        s.command('DRAW_TRI', ADDR=triangles, COUNT=6000)
        s.command('OBJ_STEP', ADDR=objects, COUNT=8000, STEP=int(y0 == 0), DRAW=1)
        s.command('RESOLVE', BASE=surface, STRIDE=1280, X1=640, Y0=y0, Y1=y0+180)
    return s


def main():
    compare.build(3)
    workload = scene()
    writes = workload.finish()
    raw = bytes(workload.memory.data)
    data = compare.buffer(raw)
    lib = compare.library()
    emulator = lib.gpu_emu_create(data, len(raw))
    # Separate commands to expose the costs of each primitive family.
    base, count = writes[-3][1], writes[-2][1]
    rows = []
    for frame in range(5):
        C.memmove(C.addressof(data), raw, len(raw))
        lib.gpu_emu_write(emulator, compare.REGS['CTRL'], 8)
        for register, value in writes[:-3]:
            lib.gpu_emu_write(emulator, compare.REGS[register], value)
        for index in range(count):
            opcode = raw[base + 32 * index]
            start, cpu = time.perf_counter_ns(), time.process_time_ns()
            for register, value in [('IRQ_STAT', 3), ('DESC_BASE', base + 32 * index),
                                     ('DESC_COUNT', 1), ('DOORBELL', 1)]:
                lib.gpu_emu_write(emulator, compare.REGS[register], value)
            rows.append((frame, opcode, (time.perf_counter_ns()-start)/1e6,
                         (time.process_time_ns()-cpu)/1e6))
        error = lib.gpu_emu_read(emulator, compare.REGS['ERR_CODE'])
        if error:
            raise RuntimeError(f'GPU error {error}')
    lib.gpu_emu_destroy(emulator)
    with (compare.BUILD / 'ember-target.csv').open('w') as output:
        writer = csv.writer(output)
        writer.writerow(('frame', 'opcode', 'wall_ms', 'cpu_ms'))
        writer.writerows(rows)
    for frame in range(5):
        samples = [row for row in rows if row[0] == frame]
        print(f'FRAME {frame} wall={sum(row[2] for row in samples):.6f} '
              f'cpu={sum(row[3] for row in samples):.6f} ms')
    for opcode in (33, 32, 34, 64):
        samples = [row for row in rows if row[1] == opcode]
        print(f'OPCODE {opcode} wall={sum(row[2] for row in samples)/5:.6f} '
              f'cpu={sum(row[3] for row in samples)/5:.6f} ms/frame')
    print('USAGE texture=65536 quads=1500 triangles=6000 live_objects=8000; CPU sim/DISP excluded')


if __name__ == '__main__':
    main()
