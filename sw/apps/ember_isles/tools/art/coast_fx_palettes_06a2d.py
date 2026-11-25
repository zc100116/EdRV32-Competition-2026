#!/usr/bin/env python3
"""coast_fx_palettes_06a2d.py — art-plan6.1 shared I8 elemental palette groups.
Host-only standard library. Geometry and pixel indices remain unchanged;
four elemental ramps accompany the iron/weapon base palette.
"""
import json

from coast_assets import ASSETS
from normalize_sample import expand
from texture_sample import color_word

RAMPS = {
    'ember': [(16, 8, 24), (90, 20, 24), (190, 43, 18), (255, 135, 36), (255, 246, 177)],
    'tide': [(6, 17, 45), (8, 65, 103), (12, 142, 160), (74, 225, 222), (226, 255, 240)],
    'star': [(12, 12, 40), (53, 37, 120), (111, 80, 214), (202, 166, 255), (255, 248, 213)],
    'shadow': [(9, 8, 23), (36, 18, 62), (77, 38, 104), (154, 82, 177), (231, 183, 243)],
}


def main():
    base = json.loads((ASSETS / 'coast-weapon-fx-iron-06a2d-palette.json').read_text())
    for element, ramp in RAMPS.items():
        palette = []
        for word in base:
            rgba = expand((word >> 11 & 31, word >> 5 & 63, word & 31, word >> 16 & 15))
            luminance = (rgba[0] * 54 + rgba[1] * 183 + rgba[2] * 19) // 256
            interval = min(3, luminance * 4 // 255)
            fraction = luminance * 4 - interval * 255
            rgb = [(ramp[interval][i] * (255 - fraction)
                    + ramp[interval + 1][i] * fraction + 127) // 255 for i in range(3)]
            palette.append(color_word(tuple(rgb) + (rgba[3],)) if rgba[3] else 0)
        if element == 'star':
            layout = json.loads((ASSETS / 'coast-light-palette-layout-06a2d.json').read_text())
            palette += [0] * (256 - len(palette))
            for index, word in layout['light_reserved_words'].items():
                palette[int(index)] = word
        (ASSETS / f'coast-weapon-fx-{element}-06a2d-palette.json').write_text(
            json.dumps(palette) + '\n')
    print(f'Four elemental I8 groups, {len(base)} entries each; native indices unchanged')


if __name__ == '__main__':
    main()
