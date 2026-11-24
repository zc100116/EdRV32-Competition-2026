#!/usr/bin/env python3
"""Ember Isles art -> GPU I8 swizzle, palettes and original 5x7 font (stdlib)."""
import argparse
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
COLORS = [
    (0, 0, 0), (5, 12, 24), (9, 24, 42), (13, 39, 59),
    (17, 59, 78), (25, 82, 102), (37, 113, 133), (58, 151, 167),
    (90, 198, 205), (151, 237, 232), (27, 38, 57), (43, 58, 78),
    (62, 80, 101), (87, 108, 129), (121, 144, 161), (178, 195, 204),
    (51, 25, 23), (84, 38, 23), (127, 52, 23), (174, 66, 19),
    (218, 84, 17), (246, 113, 24), (255, 151, 42), (255, 186, 65),
    (255, 217, 109), (255, 239, 170), (92, 66, 53), (132, 94, 65),
    (177, 134, 91), (218, 176, 123), (241, 209, 164), (248, 245, 224),
]
# Each digit is one five-bit row, in hexadecimal. Lowercase maps to uppercase.
FONT = {
    ' ': '00000000000000', '!': '04040404040004', '"': '0a0a0a00000000',
    '#': '0a0a1f0a1f0a0a', '$': '040f140e050f04', '%': '19190204081313',
    '&': '0c12140c15120d', "'": '04040800000000', '(': '02040808080402',
    ')': '08040202020408', '*': '000a041f040a00', ',': '00000000040408',
    ';': '00040400040408', '<': '01020408040201', '=': '00001f001f0000',
    '>': '10080402040810', '@': '0e11171517100e', '\\': '10100804020101',
    '^': '040a1100000000', '_': '0000000000001f',
    '+': '0004041f040400', '-': '0000001f000000', '.': '00000000000c0c',
    '/': '01010204081010', ':': '000c0c000c0c00', '?': '0e110102040004',
    '0': '0e11131519110e', '1': '040c040404040e', '2': '0e11010204081f',
    '3': '1e01010e01011e', '4': '02060a121f0202', '5': '1f10101e01011e',
    '6': '0e10101e11110e', '7': '1f010204080808', '8': '0e11110e11110e',
    '9': '0e11110f01010e', 'A': '0e11111f111111', 'B': '1e11111e11111e',
    'C': '0e11101010110e', 'D': '1e11111111111e', 'E': '1f10101e10101f',
    'F': '1f10101e101010', 'G': '0e11101711110f', 'H': '1111111f111111',
    'I': '0e04040404040e', 'J': '0702020212120c', 'K': '11121418141211',
    'L': '1010101010101f', 'M': '111b1515111111', 'N': '11191513111111',
    'O': '0e11111111110e', 'P': '1e11111e101010', 'Q': '0e11111115120d',
    'R': '1e11111e141211', 'S': '0f10100e01011e', 'T': '1f040404040404',
    'U': '1111111111110e', 'V': '11111111110a04', 'W': '11111115151b11',
    'X': '11110a040a1111', 'Y': '11110a04040404', 'Z': '1f01020408101f',
    '[': '0e08080808080e', ']': '0e02020202020e',
}


def read_png(path):
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'{path}: expected PNG')
    pos, packed = 8, bytearray()
    while pos < len(data):
        size, = struct.unpack_from('>I', data, pos)
        tag, chunk = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + size]
        if tag == b'IHDR':
            width, height, depth, kind, _, _, interlace = struct.unpack('>IIBBBBB', chunk)
            if depth != 8 or kind not in (2, 6) or interlace:
                raise ValueError(f'{path}: requires non-interlaced RGB/RGBA8 PNG')
        if tag == b'IDAT':
            packed.extend(chunk)
        pos += size + 12
    channels = 3 if kind == 2 else 4
    stride = width * channels
    raw = zlib.decompress(packed)
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        mode, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            if mode == 0:
                prediction = 0
            elif mode == 1:
                prediction = a
            elif mode == 2:
                prediction = b
            elif mode == 3:
                prediction = (a + b) // 2
            elif mode == 4:
                p = a + b - c
                distances = (abs(p - a), abs(p - b), abs(p - c))
                prediction = (a, b, c)[distances.index(min(distances))]
            else:
                raise ValueError(f'{path}: invalid PNG filter {mode}')
            row[x] = (row[x] + prediction) & 255
        rows.append([tuple(row[x:x + 3]) for x in range(0, stride, channels)])
        previous = row
    return width, height, rows


def swizzle(pixels, width, height):
    output = bytearray(width * height)
    for y in range(height):
        for x in range(width):
            bx = x // 2
            address = 8 * ((y // 2) * (width // 4) + bx // 2)
            address += 2 * ((bx & 1) + 2 * (y & 1)) + (x & 1)
            output[address] = pixels[y * width + x]
    return output


def array(name, values, ctype, columns):
    lines = [f'static const {ctype} {name}[{len(values)}] = {{']
    for i in range(0, len(values), columns):
        lines.append('    ' + ','.join(f'0x{v:x}' for v in values[i:i + columns]) + ',')
    return '\n'.join(lines + ['};'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path,
                        default=ROOT.parents[2] / 'build/ember_isles/generated/atlas.h')
    args = parser.parse_args()
    width, height, rows = read_png(ROOT / 'assets/art/ember-isles-weapons.png')
    atlas = bytearray(256 * 256)
    for cell in range(16):
        for y in range(32):
            sy = (cell // 4 * height + y * height // 32 + height // 64) // 4
            for x in range(32):
                sx = (cell % 4 * width + x * width // 32 + width // 64) // 4
                rgb = rows[sy][sx]
                # Black is the source's sprite matte; terrain remains opaque.
                if cell >= 4 and max(rgb) < 20:
                    index = 0
                else:
                    index = min(range(1, len(COLORS)), key=lambda i: sum(
                        (rgb[k] - COLORS[i][k]) ** 2 for k in range(3)))
                atlas[(cell // 4 * 32 + y) * 256 + cell % 4 * 32 + x] = index
    for code in range(32, 96):
        glyph = FONT[chr(code)]
        for y in range(7):
            bits = int(glyph[y * 2:y * 2 + 2], 16)
            for x in range(5):
                if bits & (16 >> x):
                    atlas[(128 + (code - 32) // 16 * 8 + y) * 256
                          + (code - 32) % 16 * 8 + x] = 31
                    for dy in range(2):
                        for dx in range(2):
                            atlas[((code - 32) // 8 * 16 + y * 2 + dy) * 256
                                  + 128 + (code - 32) % 8 * 16 + x * 2 + dx] = 31
    # Tiny particle and glyph masks are native-size crops derived from original art.
    for y in range(32):
        for x in range(32):
            if (x - 15) ** 2 + (y - 15) ** 2 < 210:
                atlas[(160 + y) * 256 + x] = atlas[y * 256 + 96 + x]
    for y in range(8):
        for x in range(8):
            atlas[(192 + y) * 256 + x] = atlas[(96 + y * 4) * 256 + 96 + x * 4]
    palette = [0] * (11 * 256)
    for i, (r, g, b) in enumerate(COLORS[1:], 1):
        palette[i] = 0xf0000 | (r >> 3 << 11) | (g >> 2 << 5) | (b >> 3)
        palette[256 + i] = 0xfffff
        # The ground palette keeps dense rock texture quieter than combat silhouettes.
        r, g, b = r * 3 // 5, g * 3 // 5, b * 3 // 5
        palette[10 * 256 + i] = 0xf0000 | (r >> 3 << 11) | (g >> 2 << 5) | (b >> 3)
    ui = [0x08121f, 0x35566c, 0xff9830, 0x59c9d1, 0xf8f5e0,
          0xd05b45, 0x14283b, 0x030810]
    for group, rgb in enumerate(ui, 2):
        r, g, b = rgb >> 16, (rgb >> 8) & 255, rgb & 255
        palette[group * 256 + 1] = 0xf0000 | (r >> 3 << 11) | (g >> 2 << 5) | (b >> 3)
    texture = swizzle(atlas, 256, 256) + swizzle(bytes([1] * 64), 8, 8)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text('/* Generated by ember_isles/tools/atlas_convert.py. */\n'
                           '#ifndef EMBER_ATLAS_H\n#define EMBER_ATLAS_H\n'
                           '#include <stdint.h>\n'
                           '#define EMBER_ATLAS_BYTES 65600u\n'
                           '#define EMBER_PALETTE_GROUPS 11u\n'
                           + array('ember_atlas', texture, 'uint8_t', 32) + '\n'
                           + array('ember_palette', palette, 'uint32_t', 16) + '\n#endif\n')
    print(f'I8 textures: {len(texture)} bytes; palettes: {len(palette) * 4} bytes; '
          f'total: {len(texture) + len(palette) * 4} bytes / 196608 bytes')


if __name__ == '__main__':
    main()
