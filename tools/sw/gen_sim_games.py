#!/usr/bin/env python3
"""gen_sim_games.py — showcase design §4.4: build names and portrait covers.
Read the manifest and optional PNG covers only; never open ROM files.
"""
import json
from pathlib import Path
import sys
from png2c import decode_png, resize_rgb565, image_c


def cover_pixels(data):
    """Fit a PNG within 120x160 without cropping; center on a white canvas."""
    source = decode_png(data)
    width, height = source[:2]
    if width * 160 > height * 120:
        scaled_width, scaled_height = 120, max(1, height * 120 // width)
    else:
        scaled_width, scaled_height = max(1, width * 160 // height), 160
    scaled = resize_rgb565(source, scaled_width, scaled_height)
    pixels = [0xffff] * (120 * 160)
    left = (120 - scaled_width) // 2
    top = (160 - scaled_height) // 2
    for y in range(scaled_height):
        start = (top + y) * 120 + left
        pixels[start:start + scaled_width] = scaled[y * scaled_width:(y + 1) * scaled_width]
    return pixels


def make_path(path):
    """Escape dependency paths for GNU Make, including the collection's spaces."""
    return str(path).replace('$', '$$').replace('#', '\\#').replace(' ', '\\ ')


def main():
    output = Path(sys.argv[1])
    root = Path(__file__).resolve().parents[2]
    manifest = root / 'sw/apps/showcase/games/games.txt'
    lines = ['/* Generated from games.txt; ROM paths are not opened. */', '#include "ui_data.h"']
    entries = []
    covers = []
    for line in manifest.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        name, _rom, cover = line.split('|')
        image = 'NULL'
        if cover:
            path = manifest.parent / cover
            if path.suffix.lower() in ('.jpg', '.jpeg'):
                raise ValueError(f'{path}: JPG covers are not supported; use 8-bit RGB/RGBA PNG')
            image_name = f'sim_game_cover_{len(entries)}'
            lines.extend(image_c(image_name, cover_pixels(path.read_bytes()), 120, 160))
            image = f'&{image_name}'
            covers.append(path)
        quoted_name = json.dumps(name, ensure_ascii=False)
        initial = json.dumps(name[0], ensure_ascii=False)
        entries.append(f'    {{{quoted_name}, {initial}, {image}}},')
    lines.extend(['const ui_game_t sim_games[] = {', *entries, '};',
                  'const unsigned sim_game_count = sizeof(sim_games) / sizeof(sim_games[0]);'])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text('\n'.join(lines) + '\n')
    output.with_suffix('.d').write_text(make_path(output) + ': ' +
                                       ' '.join(make_path(p) for p in covers) + '\n')


if __name__ == '__main__':
    main()
