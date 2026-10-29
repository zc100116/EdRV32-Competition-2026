#!/usr/bin/env python3
# File: game_check.py
# Spec: Task B3-3b host acceptance; rnd 2.5/2.6, DISP 2.7.
# Description: Compile real game logic/encoders, execute captured lists in rnd_ref, emit PPM.
# Clock domain: host.
"""Run from the repository root: python3 tools/s3/game_check.py."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
OUT = Path('build/s3/game')


def main():
    subprocess.run([sys.executable, 'tools/s3/game_assets.py'], check=True)
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-no-pie',
                    '-ffunction-sections', '-fdata-sections',
                    '-Isw/apps/s3', '-Isw/apps/s3/game', '-Isw/drivers/include',
                    '-Isw/bsp/include', '-Ibuild/s3/game',
                    'tools/s3/game_host.c', 'sw/apps/s3/game/game_logic.c',
                    'sw/apps/s3/game/game_render.c', 'build/s3/game/game_assets.c',
                    'sw/drivers/rnd.c', '-Wl,--gc-sections', '-Wl,--wrap=rnd_physical',
                    '-o', str(OUT / 'game_host')], check=True)
    subprocess.run([str(OUT / 'game_host')], check=True)
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                    '-ffunction-sections', '-fdata-sections',
                    '-Isw/apps/s3', '-Isw/apps/s3/game', '-Isw/drivers/include',
                    '-Isw/bsp/include', '-Ibuild/s3/game',
                    'tools/s3/game_loop_host.c', 'sw/apps/s3/game/game.c',
                    'sw/apps/s3/game/game_logic.c', 'sw/apps/s3/game/game_render.c',
                    'build/s3/game/game_assets.c', 'sw/drivers/rnd.c',
                    '-Wl,--gc-sections', '-o', str(OUT / 'game_loop_host')], check=True)
    subprocess.run([str(OUT / 'game_loop_host')], check=True)
    spec = importlib.util.spec_from_file_location('rnd_ref', 'verif/block/rnd/rnd_ref.py')
    ref = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = ref
    spec.loader.exec_module(ref)
    memory = bytearray((OUT / 'memory.bin').read_bytes())
    all_commands = []
    stats = []
    for batch in range(4):
        data = (OUT / f'batch{batch}.cmd').read_bytes()
        commands = [ref.Command.decode(data[i:i+64]) for i in range(0, len(data), 64)]
        result = ref.execute(memory, commands)
        assert result.error == 0 and result.completed == len(commands), result
        all_commands.extend(commands)
        clear_pixels = sum((ref.area(c)[2] - ref.area(c)[0] + 1) *
                           (ref.area(c)[3] - ref.area(c)[1] + 1)
                           for c in commands if c.op == 5)
        stats.append(f'batch={batch} commands={len(commands)} pixels={result.pixels} '
                     f'copy_pixels={clear_pixels}')
        print(f'PASS rnd_ref batch={batch} commands={result.completed} pixels={result.pixels}',
              flush=True)
    (OUT / 'render-stats.txt').write_text('\n'.join(stats) + '\n')
    background, overlay, camera = map(int, (OUT / 'view.txt').read_text().split())
    rgb = bytearray()
    for y in range(720):
        for x in range(1280):
            value = struct.unpack_from('<H', memory, background + y * 10240 +
                                       (x + camera) * 2)[0]
            base = ref.e565(value)
            top = ref.argb(struct.unpack_from('<I', memory, overlay + y * 5120 + x * 4)[0])
            rgb.extend(ref.mix(top[0], fg, bg) for fg, bg in zip(top[1:], base[1:]))
    ppm = OUT / 'game-frame.ppm'
    ppm.write_bytes(b'P6\n1280 720\n255\n' + rgb)
    # The player left its first position; clearing the reused buffer must erase it.
    assert struct.unpack_from('<I', memory, overlay + 600 * 5120 + 90 * 4)[0] == 0
    assert any(c.op == 4 and c.flags & 1 for c in all_commands)
    assert sum(c.op == 8 for c in all_commands) == 2
    assert any(c.op == 4 and c.src_fmt == 0 and c.flags & 4 for c in all_commands)
    assert any(c.op == 4 and c.src_fmt == 6 and not c.flags & 4 for c in all_commands)
    print(f'PASS composite/old-sprite-clear/HFLIP/I8-alpha/RGB565-key: {ppm.resolve()}')


if __name__ == '__main__':
    main()
