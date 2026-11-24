#!/usr/bin/env python3
"""normalize_atlases.py — tech §5/§7: restore AI pixel grids and RGB565/A4 palettes.
Host pipeline; no clock domain. Pixel art is generated, never drawn by this tool.
Logical grids and cell layouts are recorded with every source in art_sample.
"""
import json

from normalize_sample import ASSETS, decode_png, palette_for, png

SHEETS = [
    ('04-keeper-animation', 288, 144, 48, 'alpha'),
    ('05-enemies', 320, 256, 64, 'alpha'),
    ('06-terrain', 448, 192, 64, 'opaque'),
    ('07-props', 192, 128, 64, 'alpha'),
    ('08-effects', 256, 128, 48, 'black'),
    ('09-directions', 288, 96, 48, 'alpha'),
    ('10-upgrade', 640, 360, 192, 'opaque'),
]


def grid_centers(raw, sw, sh, count, axis):
    """Detect strongest cluster edges near the declared logical grid boundaries."""
    length, across = (sw, sh) if axis == 0 else (sh, sw)
    scores = [0] * length
    for t in range(1, length):
        for u in range(0, across, 12):
            i = ((u * sw + t) if axis == 0 else (t * sw + u)) * 4
            j = i - (4 if axis == 0 else sw * 4)
            if raw[i + 3] >= 192 or raw[j + 3] >= 192:
                scores[t] += max(abs(raw[i + k] - raw[j + k]) for k in range(4))
    pitch = length / count
    edges = [0]
    for n in range(1, count):
        center = n * pitch
        positions = range(max(1, round(center - pitch / 5)),
                          min(length, round(center + pitch / 5) + 1))
        edge = max(positions, key=lambda t: scores[t] - abs(t - center) * 100)
        edges.append(edge)
    edges.append(length)
    return [(edges[i] + edges[i + 1]) // 2 for i in range(count)], pitch


def restore(stem, width, height, colors, mode):
    sw, sh, raw = decode_png((ASSETS / (stem + '-input.png')).read_bytes())
    xs, pitch_x = grid_centers(raw, sw, sh, width, 0)
    ys, pitch_y = grid_centers(raw, sw, sh, height, 1)
    # Invert the display enlargement by sampling each logical grid square's center.
    # No interpolation, per-character bounding-box fit, rotation, or pose synthesis.
    pixels = []
    for y in range(height):
        sy = ys[y]
        for x in range(width):
            sx = xs[x]
            i = (sy * sw + sx) * 4
            p = tuple(raw[i:i + 4])
            if mode == 'black':
                p = (*p[:3], 255) if max(p[:3]) > 18 else (0, 0, 0, 0)
            elif mode == 'alpha':
                p = (*p[:3], 255) if p[3] >= 192 else (0, 0, 0, 0)
            else:
                p = (*p[:3], 255)
            pixels.append(p)
    if stem == '04-keeper-animation':
        # Visual pixel correction: remove the AI-baked orb outside the release hand.
        # The actual projectile is a separate VFX layer in the sample composition.
        for y in range(108, 124):
            for x in range(230, 240):
                pixels[y * width + x] = (0, 0, 0, 0)
    # Remove isolated alpha specks without changing intentional internal highlights.
    if mode == 'alpha':
        original = pixels[:]
        for y in range(1, height - 1):
            for x in range(1, width - 1):
                i = y * width + x
                if original[i][3] and not any(original[i + d][3]
                                              for d in (-width, -1, 1, width)):
                    pixels[i] = (0, 0, 0, 0)
        original = pixels[:]
        for y in range(1, height - 1):
            for x in range(1, width - 1):
                i = y * width + x
                adjacent = [original[i + d] for d in (-width, -1, 1, width)
                            if original[i + d][3]]
                # Repair a missing contour pixel beside a bright exposed cluster.
                # Existing dark contour pixels and internal colors are preserved.
                if (not original[i][3] and adjacent
                        and all((p[0] + 2 * p[1] + p[2]) // 4 >= 100 for p in adjacent)):
                    pixels[i] = (8, 12, 33, 255)
    palette = palette_for(pixels, colors)
    cache = {(0, 0, 0, 0): (0, 0, 0, 0)}
    for p in set(pixels):
        if p[3]:
            cache[p] = min(palette[1:], key=lambda c: sum(
                (p[k] - c[k]) ** 2 for k in range(3)))
    pixels = [cache[p] for p in pixels]
    png(ASSETS / (stem + '-native.png'), width, height, pixels)
    entries = [((p[3] // 17) << 16 | (p[0] >> 3) << 11 | (p[1] >> 2) << 5
                | p[2] >> 3) for p in palette]
    (ASSETS / (stem + '-palette.json')).write_text(json.dumps(entries) + '\n')
    return {'sheet': stem, 'input': [sw, sh], 'grid': [width, height],
            'source_square_pitch': [pitch_x, pitch_y],
            'grid_center_method': 'cluster-edge projection, search +/- 1/5 nominal pitch',
            'palette_entries': len(palette), 'format': 'RGB565+A4 [19:0]'}


def main():
    measurements = [restore(*sheet) for sheet in SHEETS]
    (ASSETS / 'grid-measurements.json').write_text(
        json.dumps(measurements, indent=2) + '\n')
    print(json.dumps(measurements, indent=2))


if __name__ == '__main__':
    main()
