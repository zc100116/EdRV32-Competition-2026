#!/usr/bin/env python3
# File: selftest.py
# Spec: rnd 2.1–2.6, 6; Task R-T1 independent acceptance.
# Description: Arithmetic sweeps, hand-calculated command examples, vector generation
#              and stub build.
# Clock domain: host.
from dataclasses import replace
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from rnd_ref import (Command, area, blit, blur, border, box_shadow, copy, execute, fill,
                     glyph, load, selftest, store, temp_region, tilemap)
from vectors import configure, selections
from v2_selftest import selftest as v2_selftest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def equal(label, wanted, actual, command=0, coord=(0, 0)):
    assert wanted == actual, (f'FAIL {label} desc={command} coord={coord} '
                              f'expected={wanted!r} actual={actual!r} time=host')


def command_examples():
    """Expected constants below are calculated directly from simple known images."""
    memory = bytearray(8192)
    common = dict(dst_base=1024, dst_stride=32, rect=(0, 0, 2, 2), clip=(0, 0, 2, 2),
                  color=0x123456, opa=255)
    c = fill(**common)
    execute(memory, [c])
    equal('FILL', 0xff123456, load(memory, 1024, 4))
    for step, wanted in ((0x01000000, 0xffff0000), (-0x01000000, 0xff000000)):
        execute(memory, [fill(dst_base=3072, dst_stride=32, rect=(0, 0, 1, 0),
                              clip=(0, 0, 1, 0), flags=1, grad_start=0xff800000,
                              steps=(0, step, 0, 0), opa=255)])
        equal('FILL whole signed32 gradient step', wanted, load(memory, 3076, 4))
    c = border(width=1, sides=15, **{**common, 'color': 0xabcdef})
    execute(memory, [c])
    equal('BORDER outer', 0xffabcdef, load(memory, 1024, 4))
    equal('BORDER hole', 0xff123456, load(memory, 1060, 4))
    memory[0:2] = bytes((0x18, 0xf0))
    execute(memory, [glyph(src_fmt=3, src_base=0, src_stride=2, src_x=1,
                           **{**common, 'rect': (0, 0, 0, 0)})])
    # m=8 -> alpha=136, destination is opaque ABCDEF; mix gives 597B9D.
    equal('GLYPH A4 high-first offset', 0xff597b9d, load(memory, 1024, 4))
    store(memory, 0, 4, 0xff806040)
    store(memory, 4, 4, 0xff123456)
    c = blit(src_fmt=1, src_base=0, src_stride=8, flags=1,
             **{**common, 'rect': (0, 0, 1, 0)})
    execute(memory, [c])
    equal('BLIT HFLIP first', 0xff123456, load(memory, 1024, 4))
    equal('BLIT HFLIP second', 0xff806040, load(memory, 1028, 4))
    execute(memory, [copy(src_fmt=1, src_base=1024, src_stride=32,
                          **{**common, 'rect': (1, 0, 2, 0)})])
    equal('COPY overlap snapshot', (0xff123456, 0xff806040),
          (load(memory, 1028, 4), load(memory, 1032, 4)))
    execute(memory, [box_shadow(radius=0, blur=0, temp_base=4096, **common)])
    equal('BOX_SHADOW R0', 0xff123456, load(memory, 1024, 4))
    memory[2048:2176] = bytes(128)
    execute(memory, [box_shadow(radius=0, blur=1, temp_base=4096,
                                **{**common, 'dst_base': 2048, 'rect': (1, 1, 1, 1)})])
    for y in range(3):
        for x in range(3):
            equal('BOX_SHADOW R1 separable zero extension', 0x1c123456,
                  load(memory, 2048 + y * 32 + x * 4, 4), coord=(x, y))
    store(memory, 1024, 4, 0xff000000)
    store(memory, 1028, 4, 0xffffffff)
    execute(memory, [blur(radius=1, temp_base=4096,
                          **{**common, 'rect': (0, 0, 1, 0)})])
    equal('BLUR nearest left', 0xff555555, load(memory, 1024, 4))
    equal('BLUR nearest right', 0xffaaaaaa, load(memory, 1028, 4))
    store(memory, 128, 2, 0x3000)  # Tile zero, both flips.
    store(memory, 512 + 63 * 4, 4, 0xff2468ac)
    execute(memory, [tilemap(src_fmt=1, tile_base=512, map_base=128, map_stride=2,
                             **{**common, 'rect': (0, 0, 0, 0)})])
    equal('TILEMAP both flips', 0xff2468ac, load(memory, 1024, 4))
    # v0.2: truncating horizontal intermediates to RGB565 would erase this 2x2 pattern.
    for y, row in enumerate(((0, 0x1000), (0x1000, 0))):
        for x, value in enumerate(row):
            store(memory, 1024 + y * 32 + x * 2, 2, value)
    execute(memory, [blur(dst_fmt=0, radius=1, temp_base=4096,
                          **{**common, 'rect': (0, 0, 1, 1)})])
    equal('BLUR temporary four bytes/pixel', (4096, 96),
          temp_region(blur(dst_fmt=0, radius=1, temp_base=4096,
                           **{**common, 'rect': (0, 0, 16, 0), 'clip': (0, 0, 16, 0)})))
    equal('BLUR RGB565 8-bit intermediate', (0, 0x0800, 0x0800, 0),
          tuple(load(memory, 1024 + y * 32 + x * 2, 2)
                for y in range(2) for x in range(2)))
    # Illegal stops before accessing target and before a subsequent valid command.
    before = bytes(memory)
    result = execute(memory, [Command(255), fill(**common)])
    equal('illegal code', 3, result.error)
    equal('illegal count/cur', (0, 0), (result.completed, result.cur_desc))
    equal('illegal no stores', before, bytes(memory))
    # Reserved bits have no semantic effect, including all ignored SRC_FMT fields.
    encoded = c.words()
    encoded[0] |= 0xe00
    encoded[2] |= 0xffff0000
    encoded[3] |= 0xf000f000
    encoded[4] |= 0xf000f000
    import struct
    equal('reserved common bits', c, Command.decode(struct.pack('<16I', *encoded)))
    print('PASS RND hand-calculated examples: all eight commands, overlap, illegal stop, codec')


def vector_selftest():
    total = 0
    random_commands = 0
    op_seen = set()
    fmt_seen = set()
    for tier in ('smoke', 'full'):
        for number, variant, seed in selections(tier):
            meta, commands, initial, expected, partial, recovery, temps = configure(
                number, variant, seed)
            equal('memory size conserved', len(initial), len(expected))
            equal('expected error field', (number == 15 and variant[0] != 'abort')
                  or (number == 28 and variant[0].endswith('error')),
                  meta['error'] != 0)
            if number == 19:
                equal('random list length', 50, len(commands))
                random_commands += len(commands)
            for cmd in commands:
                if not cmd.illegal():
                    op_seen.add(cmd.op)
                    fmt_seen.add(cmd.src_fmt)
                equal('codec round-trip', cmd.encode(), Command.decode(cmd.encode()).encode())
            # Both companion images must preserve their original descriptor-list length.
            equal('partial image size', len(initial), len(partial))
            equal('recovery image size', len(initial), len(recovery))
            total += 1
    equal('random commands', 500, random_commands)
    equal('all operations', set(range(1, 14)), op_seen)
    equal('all pixel formats', set(range(10)), fmt_seen)
    print(f'PASS RND vectors: {total} cases, 10 seeds x 50 commands, all 13 OP/all 10 formats')


def main():
    selftest()
    v2_selftest()
    command_examples()
    vector_selftest()
    subprocess.run([sys.executable, str(HERE / 'check.py')], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(HERE / 'run.py'), 'stub'], cwd=ROOT, check=True)
    sys.path.insert(0, str(ROOT / 'tools'))
    from regress import expand_files
    obj = ROOT / 'build/rnd/memory_obj'
    obj.mkdir(parents=True, exist_ok=True)
    command = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
               '-CFLAGS', '-O0', '--top-module', 'edrv32_rnd_memory_tb',
               '--Mdir', str(obj), '-o', 'sim',
               *expand_files(HERE / 'selftest/memory.f')]
    with (obj / 'compile.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((obj / 'compile.log').read_text())
        return result.returncode
    subprocess.run([str(obj / 'sim')], cwd=ROOT, check=True)
    print('PASS RND independent verification acceptance; '
          'real RTL execution deferred to integration')


if __name__ == '__main__':
    sys.exit(main())
