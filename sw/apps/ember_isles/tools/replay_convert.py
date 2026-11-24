#!/usr/bin/env python3
# File: replay_convert.py; ember_isles tech 3.
# Convert EMBER1 decimal inputs to the shared PC/Spike demo header.
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[2]


def convert(path):
    words = path.read_text(encoding='ascii').split()
    if words[0] != 'EMBER1':
        raise ValueError(f'{path}: expected EMBER1')
    seed, count = map(int, words[1:3])
    inputs = list(map(int, words[3:]))
    if not 0 <= seed <= 0xffffffff or not 0 <= count <= 10800:
        raise ValueError(f'{path}: seed or count outside replay format')
    if len(inputs) != count or any(not 0 <= value <= 255 for value in inputs):
        raise ValueError(f'{path}: expected {count} decimal eight-bit inputs')
    out = ROOT / 'build/ember_isles/generated/replay.h'
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = ['/* Generated EMBER1 replay; ember_isles tech 3. */',
             '#ifndef EMBER_DEMO_REPLAY_H', '#define EMBER_DEMO_REPLAY_H',
             '#include <stdint.h>', f'static const uint32_t ember_demo_seed = {seed}u;',
             f'static const uint32_t ember_demo_count = {count}u;',
             'static const uint8_t ember_demo_input[] = {']
    for start in range(0, count, 24):
        lines.append('    ' + ', '.join(map(str, inputs[start:start + 24])) + ',')
    lines += ['};', '#endif', '']
    out.write_text('\n'.join(lines), encoding='ascii')
    print(f'replay: generated {out} ({count} frames, seed {seed})')


if __name__ == '__main__':
    convert(Path(sys.argv[1]) if len(sys.argv) > 1 else APP / 'assets/replays/coast.txt')
