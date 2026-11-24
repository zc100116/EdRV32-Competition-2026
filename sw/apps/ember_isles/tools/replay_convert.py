#!/usr/bin/env python3
# File: replay_convert.py; ember_isles tech 3.
# Convert EMBER2 decimal inputs to the shared PC/Spike demo header.
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[2]


def convert(path):
    words = path.read_text(encoding='ascii').split()
    if words[0] != 'EMBER2':
        raise ValueError(f'{path}: expected EMBER2')
    seed, count = map(int, words[1:3])
    inputs = list(map(int, words[3:]))
    if not 0 <= seed <= 0xffffffff or not 0 <= count <= 60000:
        raise ValueError(f'{path}: seed or count outside replay format')
    if len(inputs) != count or any(not 0 <= value <= 8191 for value in inputs):
        raise ValueError(f'{path}: expected {count} decimal sixteen-bit inputs')
    out = ROOT / 'build/ember_isles/generated/replay.h'
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = ['/* Generated EMBER2 replay; ember_isles tech 3. */',
             '#ifndef EMBER_DEMO_REPLAY_H', '#define EMBER_DEMO_REPLAY_H',
             '#include <stdint.h>', f'static const uint32_t ember_demo_seed = {seed}u;',
             f'static const uint32_t ember_demo_count = {count}u;',
             'static const uint16_t ember_demo_input[] = {']
    for start in range(0, count, 24):
        lines.append('    ' + ', '.join(map(str, inputs[start:start + 24])) + ',')
    lines += ['};', '#endif', '']
    out.write_text('\n'.join(lines), encoding='ascii')
    print(f'replay: generated {out} ({count} frames, seed {seed})')


if __name__ == '__main__':
    convert(Path(sys.argv[1]) if len(sys.argv) > 1 else APP / 'assets/replays/coast.txt')
