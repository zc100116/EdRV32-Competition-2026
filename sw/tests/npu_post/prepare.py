#!/usr/bin/env python3
# prepare.py — npu-testplan 3.10 PP-SW-01/02, npu-spec 4.1/4.4/4.5.
# Build identity detection heads and oracle records without consulting DUT RTL.
# Clock domain: host; generated data stays under build/npu/post_sw.
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/npu'))
import yolo_post_ref as ref

OUT = ROOT / 'build/npu/post_sw/data'
OUT.mkdir(parents=True, exist_ok=True)
heads = ref.load_heads()
segments = []


def candidates(raw):
    return ref.decode_candidates(raw, heads, dict.fromkeys(ref.STAT_KEYS, 0))


def pack(items):
    return b''.join(struct.pack('<4iIHH', *box, probability, category, anchor)
                    for box, probability, category, anchor in items)


def finish(items):
    return ref.pack_detections(ref.postprocess_candidates(items)[0])


# The three pairs read raw INPUT through 1x1 identity CONV, so hardware must
# produce exactly the offline raw-head oracle. All heads retain the fixed shapes.
model = bytearray()
descriptors = bytearray()
for h, head in enumerate(heads):
    lut_offset = len(model)
    model.extend(struct.pack('<512I', *head['exp_q20'], *head['probability_q24']))
    for kind, channels, offset in ((1, 64, head['box_offset']),
                                   (2, 80, head['class_offset'])):
        blocks = (channels + 31) // 32
        cin_blocks = channels // 16
        half_tail = channels % 32 == 16
        weight_offset = len(model)
        for block in range(blocks):
            tail = half_tail and block == blocks - 1
            for cin in range(cin_blocks):
                for half in range(2):
                    for out in range(16 if tail else 32):
                        for lane in range(8):
                            model.append(int(block * 32 + out == cin * 16 + half * 8 + lane))
        quant_offset = len(model)
        for block in range(blocks):
            for c in range(32):
                model.extend(struct.pack('<ihBB', 0, 1 if block * 32 + c < channels else 0, 0, 0))
            model.extend(bytes(256))
        w, height = head['width'], head['height']
        stride = head['plane_stride']
        words = [(int(half_tail) << 9) | (2 << 12) | (3 << 14),
                 offset, stride, offset, stride, 0, weight_offset, quant_offset,
                 w | height << 16, w | height << 16, cin_blocks | blocks << 8,
                 cin_blocks * w // 4 | (2 * cin_blocks) << 16,
                 512 * cin_blocks, kind | h << 2, lut_offset, 0]
        descriptors.extend(struct.pack('<16I', *words))
segments += [(0x08400000, model), (0x08500000, descriptors)]
metadata = []
for frame in range(2):
    raw = bytearray(725760)
    for h, head in enumerate(heads):
        raw[head['class_offset']:head['class_offset'] + 5 * head['plane_stride']] = (
            bytes([128]) * (5 * head['plane_stride']))
        cells = list(range(0, 240, 2)) if h == 0 else [0, 11, 41]
        for n, cell in enumerate(cells):
            category = (n + frame * 7) % 80
            score = min(127, head['class_threshold'] + 1 + n % 20)
            at = head['class_offset'] + category // 16 * head['plane_stride'] + cell * 16
            raw[at + category % 16] = score
            for side in range(4):
                at = head['box_offset'] + side * head['plane_stride'] + cell * 16
                raw[at:at + 16] = bytes([128]) * 16
                raw[at + (0 if n % 3 else 3)] = 127
    items = candidates(raw)
    expected = finish(items)
    segments += [(0x08000000 + frame * 0x100000, raw),
                 (0x08600000 + frame * 0x10000, pack(items)),
                 (0x08700000 + frame * 0x10000, expected),
                 (0x08780000 + frame * 0x10000,
                  struct.pack('<4sHHII', b'EDDT', 1, len(expected) // 12,
                              100 + frame, 200 + frame) + expected)]
    metadata.append((len(items), len(expected) // 12))

# The same real COCO frame as board_npu acceptance, executed offline by its oracle.
# Identity heads replay those raw feature values through the hardware candidate path.
real_raw = bytearray(725760)
address = 0
for token in (ROOT / 'build/sw/board_npu/data/C-YOLO/ref_out.hex').read_text().split():
    if token.startswith('@'):
        address = int(token[1:], 16) * 32
    else:
        chunk = bytes.fromhex(token)[::-1]
        offset = address - 0x05000000
        if 0 <= offset < len(real_raw):
            real_raw[offset:offset + 32] = chunk
        address += 32
real_items = candidates(real_raw)
real_detections = ref.postprocess_candidates(real_items)[0]
real_expected = ref.pack_detections(real_detections)
segments += [(0x08200000, real_raw), (0x08620000, pack(real_items)),
             (0x08720000, real_expected),
             (0x087a0000, struct.pack('<4sHHII', b'EDDT', 1, len(real_detections),
                                    102, 202) + real_expected)]
metadata.append((len(real_items), len(real_detections)))
ui_default = sum(row[5] // 10 >= 50 for row in real_detections)
ui_whitelist = sum(row[5] // 10 >= 50 and row[4] != real_detections[0][4]
                   for row in real_detections)

# Exact IoU .45 and one Q8 unit either side, different classes, clipping after
# suppression, ties, >100 independent boxes, and probability order across heads.
directed = []
for group, delta in enumerate((0, -1, 1)):
    x = group * 200 * 256
    directed += [([x, -2560, x + 29 * 256, 0], 16000000, group, group * 2),
                 ([x + 11 * 256 + delta, -2560, x + 40 * 256 + delta, 0],
                  15000000, group, group * 2 + 1)]
directed += [([-256, -256, 25600, 25600], 14000000, 70, 4800),
             ([-256, -256, 25600, 25600], 14000000, 71, 3840)]
for n in range(120):
    directed.append(([n * 512, 10000, n * 512 + 256, 10256],
                     12000000 - n, 79, 100 + n))
directed.reverse()
segments += [(0x08800000, pack(directed)), (0x08900000, finish(directed))]
with (OUT / 'ddr.hex').open('w') as stream:
    for address, data in segments:
        stream.write(f'@{address:08x}\n')
        stream.write(''.join(f'{value:02x}\n' for value in data))
(OUT / 'data.h').write_text(
    '/* Generated by sw/tests/npu_post/prepare.py; npu-spec 4.5. */\n'
    f'#define PP_MODEL_BYTES {len(model)}u\n'
    f'#define PP_DESC_BYTES {len(descriptors)}u\n'
    f'#define PP_DIRECTED_COUNT {len(directed)}u\n'
    f'#define PP_DIRECTED_KEPT {len(finish(directed)) // 12}u\n'
    f'#define PP_UI_DEFAULT {ui_default}u\n'
    f'#define PP_UI_WHITELIST {ui_whitelist}u\n'
    'static const unsigned pp_counts[3] = {' + ','.join(str(n[0]) for n in metadata) + '};\n'
    'static const unsigned pp_kept[3] = {' + ','.join(str(n[1]) for n in metadata) + '};\n')
(OUT / 'oracle.json').write_text(json.dumps(dict(frames=metadata,
    directed_count=len(directed), directed_kept=len(finish(directed)) // 12), indent=2) + '\n')
print(f'PP-SW oracle: {metadata}, directed={len(directed)}, model={len(model)} B')
