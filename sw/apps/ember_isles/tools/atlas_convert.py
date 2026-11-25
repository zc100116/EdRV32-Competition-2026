#!/usr/bin/env python3
"""tech 5b: compile native PC/FPGA frame tables and compact I8 DDR libraries.
Consumes ART production outputs; never paints or resamples source artwork.
"""
import json
import pathlib
import struct

APP = pathlib.Path(__file__).resolve().parents[1]
ROOT = APP.parents[2]
PACK = ROOT / 'build/ember_isles/art_coast_production'
OUT = ROOT / 'build/ember_isles/generated/atlas.h'


def emit_package(stream, profile):
    table = json.loads((PACK / (profile + '-frames.json')).read_text())
    source = (PACK / table['ddr_library']).read_bytes()
    frames = sorted(table['frames'], key=lambda f: (f['actor'], f['action'], f['direction'], f['frame']))
    blob = bytearray()
    for frame in frames:
        blob.extend(b'\0' * (-len(blob) % 32))
        begin = frame['ddr_offset']
        frame['compiled_offset'] = len(blob)
        blob.extend(source[begin:begin + frame['bytes']])
    stream.write(f'#define EMBER_ART_FRAMES {len(frames)}u\n#define EMBER_ART_BYTES {len(blob)}u\n')
    stream.write('static const struct ember_art_frame ember_art_frames[] = {\n')
    for f in frames:
        hand = f.get('hand') or [-32768, -32768]
        fields = [json.dumps(f[k]) for k in ('actor', 'action', 'direction')]
        fields += [str(v) for v in (f['frame'], f['w'], f['h'], *f['block_aligned_size'],
                                   *f['anchor'], *hand, f['palette_group'], int(f['cache'] == 'fixed'),
                                   f['compiled_offset'], f['bytes'])]
        # Native metadata can carry directional and element palette variants.
        variants = f.get('palette_variants', {})
        fields.append('{' + ','.join(str(variants.get(element, f['palette_group']))
                                    for element in ('iron', 'ember', 'tide', 'star', 'shadow', 'iron')) + '}')
        blend = f.get('blend', {'Fs': 'Sa', 'Fd': '1-Sa', 'op': 'ADD'})
        if isinstance(blend, str):
            blend = {'alpha': {'Fs': 'Sa', 'Fd': '1-Sa', 'op': 'ADD'},
                     'add': {'Fs': 'Sa', 'Fd': '1', 'op': 'ADD'}}[blend]
        factors = {'0': 0, '1': 1, 'Sa': 2, '1-Sa': 3, 'S': 4, '1-S': 5,
                   'D': 6, '1-D': 7, 'constant_alpha': 8, '1-constant_alpha': 9}
        operations = {'ADD': 0, 'SUB': 1, 'REVSUB': 2, 'MIN': 3, 'MAX': 4}
        directions = {'down': 12, 'down_right': 14, 'right': 0, 'up_right': 2, 'up': 4,
                      'up_left': 6, 'left': 8, 'down_left': 10, 'lean_right': 0, 'lean_left': 8}
        fields += [str(value) for value in (factors[blend['Fs']], factors[blend['Fd']],
                   operations[blend['op']], {'nearest': 0, 'bilinear': 1}[f.get('filter', 'nearest')],
                   int(f['role'] == 'ui'), directions[f['direction']],
                   {'none': 0, 'telegraph': 1, 'falling': 2}[f.get('effect_phase', 'none')],
                   f.get('global_alpha', 255), {'I4': 0, 'I8': 1}[f['format']])]
        stream.write('    {' + ','.join(fields) + '},\n')
    stream.write('};\nstatic const uint8_t ember_art_pixels[EMBER_ART_BYTES] = {\n')
    for i in range(0, len(blob), 32):
        stream.write(','.join(str(v) for v in blob[i:i + 32]) + ',\n')
    stream.write('};\n')


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    palettes = (PACK / 'palettes.bin').read_bytes()
    with OUT.open('w') as stream:
        stream.write('/* Generated native ART pack. tech 5b. CPU DDR library only. */\n')
        stream.write('#ifndef EMBER_ATLAS_H\n#define EMBER_ATLAS_H\n#include <stdint.h>\n')
        stream.write('#include \"gfx2d/cache.h\"\n')
        stream.write('#if EMBER_FPGA_ART\n')
        emit_package(stream, 'fpga')
        stream.write('#else\n')
        emit_package(stream, 'pc')
        stream.write('#endif\n')
        stream.write(f'#define EMBER_ART_PALETTES {len(palettes) // 1024}u\n')
        stream.write('static const uint32_t ember_art_palettes[][256] = {\n')
        for begin in range(0, len(palettes), 1024):
            stream.write('{' + ','.join(hex(v) for v in struct.unpack('<256I', palettes[begin:begin + 1024])) + '},\n')
        stream.write('};\n#endif\n')
    print(f'{OUT}: compiled both native packages')


if __name__ == '__main__':
    main()
