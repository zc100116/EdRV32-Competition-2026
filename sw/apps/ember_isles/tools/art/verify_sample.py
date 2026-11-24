#!/usr/bin/env python3
"""verify_sample.py — ART-2 acceptance: dimensions, APNG duration, GPU palette/layout.
Host-only checks of requested art output contracts; no runtime game gates.
"""
import json
import struct
import sys

from normalize_sample import ASSETS, ROOT, OUTPUT, decode_png

sys.path.insert(0, str(ROOT))
from tools.gpu.model.texture import Texture


def main():
    w, h, source = decode_png((OUTPUT / 'art-sample.png').read_bytes())
    w2, h2, enlarged = decode_png((OUTPUT / 'art-sample-2x.png').read_bytes())
    assert (w, h, w2, h2) == (640, 360, 1280, 720)
    for y in range(720):
        for x in range(1280):
            a, b = (y // 2 * 640 + x // 2) * 4, (y * 1280 + x) * 4
            assert source[a:a + 4] == enlarged[b:b + 4]
    animation = (OUTPUT / 'art-sample.apng').read_bytes()
    position, frames, duration = 8, 0, 0
    while position < len(animation):
        length, kind = struct.unpack_from('>I4s', animation, position)
        if kind == b'fcTL':
            fields = struct.unpack_from('>IIIIIHHBB', animation, position + 8)
            frames += 1
            duration += fields[5] / fields[6]
        position += length + 12
    assert frames == 40 and 3 <= duration <= 5
    heights = []
    for stem, counts in [('04-keeper-animation', [4, 6, 6]), ('09-directions', [6, 6])]:
        sw, sh, pixels = decode_png((ASSETS / (stem + '-native.png')).read_bytes())
        for row, count in enumerate(counts):
            for col in range(count):
                ys = [y for y in range(48) for x in range(48)
                      if pixels[((row * 48 + y) * sw + col * 48 + x) * 4 + 3]]
                heights.append(max(ys) - min(ys) + 1)
    assert all(36 <= height <= 40 for height in heights), heights
    measurements = json.loads((ASSETS / 'texture-measurements.json').read_text())
    build = ROOT / 'build/ember_isles/art_sample'
    for group in measurements['groups']:
        palette = list(struct.unpack('<256I', (build / (group['name'] + '.pal')).read_bytes()))
        assert group['colors'] <= 256
        for number, page in enumerate(group['pages']):
            name = f"{group['name']}-{number}"
            w, h, rgba = decode_png((build / (name + '.png')).read_bytes())
            fmt = 0 if group['format'] == 'I4' else 1
            texture = Texture((build / (name + '.bin')).read_bytes(), [palette], {
                'LOG2_W': w.bit_length() - 1, 'LOG2_H': h.bit_length() - 1,
                'LEVELS': 1, 'FORMAT': fmt, 'OFFSET': 0, 'PAL_GROUP': 0})
            for y in range(h):
                for x in range(w):
                    expected = tuple(rgba[(y * w + x) * 4:(y * w + x) * 4 + 4])
                    actual = texture.texel(x, y, 0, 0)
                    assert actual == expected or (actual[3] == expected[3] == 0)
    print(f'PASS: exact 2x, APNG {frames} frames/{duration:.1f}s, '
          f'{len(measurements["groups"])} GPU I8/I4 palette/layout round trips; '
          f'keeper {min(heights)}..{max(heights)}px')


if __name__ == '__main__':
    main()
