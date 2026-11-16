#!/usr/bin/env python3
"""T-FACE-STICKER-R2: regress border haze removal and preserve the AA silhouette."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/sw'))
from png2c import decode_png
from prepare_showcase_stickers import clear_edge_haze

pixels = bytearray([255, 255, 255, 10]*81)
for y in range(3, 6):
    for x in range(3, 6):
        pixels[(y*9+x)*4+3] = 255
pixels[(4*9+4)*4+3] = 20  # Enclosed low-alpha detail is not border-connected.
pixels[(4*9+2)*4+3] = 20  # Anti-aliased edge touches the solid silhouette.
clear_edge_haze(pixels, 9, 9)
assert pixels[(1*9+1)*4+3] == 0, 'border-connected haze remains'
assert pixels[(4*9+2)*4+3] == 20, 'anti-aliased edge was removed'
assert pixels[(4*9+4)*4+3] == 20, 'enclosed element detail was removed'
assert pixels[(3*9+3)*4+3] == 255, 'solid foreground changed'

for path in sorted((ROOT / 'sw/apps/showcase/assets/stickers').glob('*.png')):
    width, height, rgba = decode_png(path.read_bytes())
    low = sum(1 <= a <= 39 for a in rgba[3::4])
    print(f'{path.name}: alpha 1..39 = {low}')
    # R2's six 160 px assets retain their original haze bound. New eyeglasses
    # contain enclosed translucent lens detail, preserved by the same cleanup.
    if width == 160:
        assert low <= 1000, f'{path.name}: {low} low-alpha pixels exceeds 1000'
    assert 0 in rgba[3::4] and max(rgba[3::4]) >= 40, f'{path.name}: missing transparent/foreground art'
    assert width == height and width in (48,64,96,112,160)
print('PASS sticker alpha: border connectivity, AA rim, enclosed detail, all PNG transparency, sizes and original haze bounds')
