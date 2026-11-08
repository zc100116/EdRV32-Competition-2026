# File: prepare.py
# Spec: npu-spec 2.2, 2.6, 4.1-4.5; npu-testplan TL-05, PP-01-13, PP-P-01/02.
# Description: Spec-encoded identity CONVs produce independently chosen box/cls data.
# Clock domain: host.
"""No RTL imports; fixed head shapes and INT8_C16 byte layout are the only contract."""
import json
from pathlib import Path
import struct
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from prepare import BUILD, ROOT, write_hex, write_regs  # noqa: E402
from oracle import SHAPES, decode, pack  # noqa: E402
sys.path.insert(0, str(ROOT))
from tools.npu.yolo_post_ref import (decode_candidates, pack_candidates,
                                     postprocess_candidates, pack_detections)  # noqa: E402

BASE = dict(MODEL_BASE=0x100000, WORK_BASE=0x1000000, INPUT_BASE=0x4000000,
            OUTPUT_BASE=0x5000000, DESC_BASE=0x80000, DESC_COUNT=6,
            POST_CTRL=1, POST_BASE=0x6000000, POST_INT8_TH0=103,
            POST_INT8_TH1=105, POST_INT8_TH2=103, POST_PROB_TH=4194304)
TIERS = {'TL-05': 'smoke', **{f'PP-{n:02}': 'full' if n in (10, 11, 12) else 'smoke'
                            for n in range(1, 14)},
         'PP-P-01': 'perf', 'PP-P-02': 'perf'}


def fixture(path, count=5, thresholds=(103, 105, 103), prob=4194304, ctrl=1,
            frame=0, best=None, pattern=0, raw_override=None):
    path.mkdir(parents=True, exist_ok=True)
    heads = json.loads((ROOT / 'sw/lib/yolo_tables.json').read_text())
    raw = bytearray([128]) * 725760
    active = set(range(count))
    # Put sparse candidates at row ends, both halves and every head boundary.
    if count < 20:
        boundary = [0, 1, 78, 79, 80, 3838, 3839, 3840, 3841, 4799, 4800, 5039]
        active = set(boundary[:count])
    for h, head in enumerate(heads):
        width, height, _, anchor_base = SHAPES[h]
        plane = head['plane_stride']
        for cell in range(width * height):
            anchor = anchor_base + cell
            for side in range(4):
                address = head['box_offset'] + side * plane + cell * 16
                bins = ([0] * 16 if pattern == 0 else
                        [127 if b == (anchor + side * 5) % 16 else -128 for b in range(16)])
                raw[address:address + 16] = bytes(value & 255 for value in bins)
            for c in range(80):
                value = -128
                if anchor in active and c in (0, 15, 16, 63, 64, 79):
                    value = 127 if best is None else best[h]
                # Vary the winning plane, retaining ties across a boundary in other cells.
                if pattern and anchor in active:
                    value = (127 if best is None else best[h]) if c >= anchor % 80 else -128
                address = head['class_offset'] + c // 16 * plane + cell * 16 + c % 16
                raw[address] = value & 255
    if raw_override is not None:
        raw = bytearray(raw_override)
    regs = BASE | dict(POST_CTRL=ctrl, POST_BASE=BASE['POST_BASE'] + frame * 0x100000,
                       INPUT_BASE=BASE['INPUT_BASE'] + frame * 0x100000,
                       OUTPUT_BASE=BASE['OUTPUT_BASE'] + frame * 0x100000,
                       POST_PROB_TH=prob)
    regs.update({f'POST_INT8_TH{h}': value & 511 for h, value in enumerate(thresholds)})
    memory = {}

    def put(address, data):
        memory.update(enumerate(data, address))

    descriptors = []
    cursor = 0
    for h, head in enumerate(heads):
        table_offset = 0x10000 + h * 2048
        put(regs['MODEL_BASE'] + table_offset,
            struct.pack('<512I', *(head['exp_q20'] + head['probability_q24'])))
        for kind, channels, key in [(1, 64, 'box_offset'), (2, 80, 'class_offset')]:
            width, height, _, _ = SHAPES[h]
            planes = channels // 16
            blocks = (channels + 31) // 32
            weight_offset = cursor
            # spec 4.3: ordinary blocks followed by compact HALF_TAIL.
            for block in range(blocks):
                tail = channels % 32 == 16 and block == blocks - 1
                for plane in range(planes):
                    for half in range(1 if tail else 2):
                        row = bytearray(256)
                        for oc in range(32):
                            source_half = oc // 16 if tail else half
                            output = block * 32 + (oc % 16 if tail else oc)
                            for lane in range(8):
                                source = plane * 16 + source_half * 8 + lane
                                row[oc * 8 + lane] = int(output == source)
                        put(regs['MODEL_BASE'] + cursor, row)
                        cursor += 256
            quant_offset = cursor
            for block in range(blocks):
                records = b''.join(struct.pack('<ihBB', 0, 1, 0, 0) for _ in range(32))
                put(regs['MODEL_BASE'] + cursor, records + bytes(256))
                cursor += 512
            flags = 2 << 12 | 3 << 14 | (512 if channels % 32 else 0)
            row = [flags, head[key], head['plane_stride'], head[key], head['plane_stride'],
                   0, weight_offset, quant_offset, width | height << 16,
                   width | height << 16, planes | blocks << 8, planes * width // 4 |
                   (planes * 2) << 16, planes * 2 * 256, kind | h << 2, table_offset, 0]
            descriptors.append(row)
    put(regs['DESC_BASE'], b''.join(struct.pack('<16I', *row) for row in descriptors))
    put(regs['INPUT_BASE'], raw)
    put(regs['OUTPUT_BASE'], bytes([0xA5]) * len(raw))
    put(regs['POST_BASE'], bytes([0xA5]) * 120960)
    write_hex(path / 'mem_state.hex', memory)
    write_regs(path, regs)
    candidates = (decode_candidates(raw, heads, int8_thresholds=thresholds,
                                    probability_threshold=prob) if ctrl & 1 else [])
    assert candidates == (decode(raw, heads, thresholds, prob) if ctrl & 1 else [])
    packed = pack_candidates(candidates)
    assert packed == pack(candidates)
    eddt, _ = postprocess_candidates(candidates)
    (path / 'eddt.bin').write_bytes(pack_detections(eddt))
    packed += bytes((-len(packed)) % 32)
    (path / 'candidates.bin').write_bytes(packed)
    (path / 'candidates.json').write_text(json.dumps(candidates) + '\n')
    (path / 'raw.bin').write_bytes(raw)
    checks = {}
    for head in heads:
        for key, planes in [('box_offset', 4), ('class_offset', 5)]:
            if key == 'class_offset' and ctrl == 1:
                continue
            start = head[key]
            checks.update(enumerate(raw[start:start + planes * head['plane_stride']],
                                    regs['OUTPUT_BASE'] + start))
    checks.update(enumerate(packed, regs['POST_BASE']))
    write_hex(path / 'ref_out.hex', checks)
    (path / 'expected.txt').write_text(f'{len(candidates)} {ctrl & 1}\n')
    # Exact enqueue order for the row/C32/plane/pair schedule: plane4 closes each row.
    (path / 'order.txt').write_text(''.join(f'{row[3]}\n' for row in candidates))
    return path


def variants(test):
    if test == 'PP-01':
        for h in range(3):
            heads = json.loads((ROOT / 'sw/lib/yolo_tables.json').read_text())
            th = (103, 105, 103)
            for delta in (-1, 0, 1):
                best = list(th)
                best[h] += delta
                yield f'h{h}_int{delta}', dict(count=12, best=best)
                p = heads[h]['probability_q24'][th[h] + 128]
                yield f'h{h}_prob{delta}', dict(count=12, best=th, prob=p + delta)
        for threshold in (-128, 127, 128):
            yield f'th{threshold}', dict(count=12, thresholds=(threshold,) * 3)
        yield 'zero', dict(count=0)
        yield 'raised', dict(count=12, thresholds=(127,) * 3, prob=1 << 23)
    elif test == 'PP-06':
        for count in (0, 12):
            yield f'count{count}', dict(count=count, ctrl=3)
    elif test == 'PP-05':
        for count in range(1, 6):
            yield f'count{count}', dict(count=count)
    elif test == 'PP-10':
        yield 'real', dict()
        for count in (0, 5040):
            yield f'count{count}', dict(count=count, pattern=1)
    elif test == 'PP-12':
        for count in (0, 5040):
            yield f'count{count}', dict(count=count, pattern=1)
    elif test == 'PP-11':
        for ctrl in (0, 1, 3):
            yield f'ctrl{ctrl}', dict(count=37, ctrl=ctrl, pattern=1)
    elif test == 'PP-P-01':
        for count in (37, 5040):
            for mode in ('zero', 'latency', 'bw'):
                yield f'count{count}_raw_{mode}', dict(count=count, pattern=1, ctrl=0)
                yield f'count{count}_{mode}', dict(count=count, pattern=1, ctrl=3)
    else:
        yield 'directed', dict(count=12, pattern=int(test in ('PP-03', 'PP-04', 'PP-13')))
