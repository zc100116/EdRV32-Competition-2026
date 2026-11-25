#!/usr/bin/env python3
"""06a-2f: restore three imagegen readability edits on the existing pixel grid.
Host standard library; retain six I4 frames, registration and shared palettes.
The other five aura sheets and all original source pixels remain untouched.
"""
import json

from coast_assets import ASSETS
from normalize_atlases import grid_centers
from normalize_sample import decode_png, expand, png

AFFIXES = ('fanatic', 'reflect', 'dim')


def main():
    for affix in AFFIXES:
        stem = 'coast-elite-aura-' + affix + '-06a2e'
        source = 'coast-elite-aura-' + affix + '-06a2f-v2'
        metadata = ASSETS / (stem + '-sheet.json')
        sheet = json.loads(metadata.read_text())
        sw, sh, raw = decode_png((ASSETS / 'sources' / (source + '-input.png')).read_bytes())
        xs, _ = grid_centers(raw, sw, sh, 240, 0)
        ys, _ = grid_centers(raw, sw, sh, 160, 1)
        words = json.loads((ASSETS / sheet['palette_file']).read_text())[:16]
        palette = [expand((w >> 11 & 31, w >> 5 & 63, w & 31, w >> 16 & 15))
                   for w in words[1:]]
        sampled = [tuple(raw[(y * sw + x) * 4:(y * sw + x + 1) * 4])
                   for y in ys for x in xs]
        mapping = {p: (min(palette, key=lambda c: sum((p[k] - c[k]) ** 2
                                                     for k in range(3)))
                       if p[3] >= 192 else (0, 0, 0, 0)) for p in set(sampled)}
        png(ASSETS / (stem + '-native.png'), 240, 160, [mapping[p] for p in sampled])
        sheet['source_input'] = 'sources/' + source + '-input.png'
        sheet['source_prompt'] = 'sources/' + source + '-prompt.txt'
        metadata.write_text(json.dumps(sheet, indent=2) + '\n')
    print('Imported three 06a-2f readability edits / 18 I4 frames')


if __name__ == '__main__':
    main()
