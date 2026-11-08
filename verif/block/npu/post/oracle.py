# File: oracle.py
# Spec: npu-spec 2.6, 4.1, 4.4, 4.5, 5.6; npu-testplan 3.9.
# Description: Independent integer candidate decoder and public image checks.
# Clock domain: host.
"""All candidates before NMS; arithmetic never uses floating point."""
import struct

SHAPES = ((80, 48, 8, 0), (40, 24, 16, 3840), (20, 12, 32, 4800))
RECORD = struct.Struct('<iiiiIHH')


def distance(bins, table):
    peak = max(bins)
    weights = [table[peak - value] for value in bins]
    den = sum(weights)
    num = sum(index * weight for index, weight in enumerate(weights))
    return (num * 256 + den // 2) // den


def decode(raw, heads, thresholds, probability_threshold):
    result = []
    signed = memoryview(raw).cast('b')
    for h, head in enumerate(heads):
        width, height, stride, anchor = SHAPES[h]
        plane = head['plane_stride']
        for cell in range(width * height):
            values = [signed[head['class_offset'] + c // 16 * plane + cell * 16 + c % 16]
                      for c in range(80)]
            best = max(values)
            cls = values.index(best)
            probability = head['probability_q24'][best + 128]
            if best < thresholds[h] or probability <= probability_threshold:
                continue
            xyxy = []
            for side in range(4):
                address = head['box_offset'] + side * plane + cell * 16
                delta = distance(signed[address:address + 16], head['exp_q20'])
                axis = cell // width if side & 1 else cell % width
                xyxy.append(((axis * 256 + 128) + (-delta if side < 2 else delta)) * stride)
            result.append([xyxy, probability, cls, anchor + cell])
    return result


def pack(candidates):
    return b''.join(RECORD.pack(*box, probability, cls, anchor)
                    for box, probability, cls, anchor in candidates)


def compare(actual, expected, order):
    """Compare every field by anchor, then independently check enqueue order and padding."""
    size = len(expected) * RECORD.size
    assert len(actual) == (size + 31) // 32 * 32, 'candidate beat count'
    decoded = [RECORD.unpack_from(actual, offset) for offset in range(0, size, 24)]
    anchors = [row[-1] for row in decoded]
    assert anchors == order, f'enqueue order expected={order} actual={anchors}'
    expected_by_anchor = {row[3]: (*row[0], row[1], row[2], row[3]) for row in expected}
    assert len(set(anchors)) == len(anchors), 'duplicate anchor'
    for row in decoded:
        assert row == expected_by_anchor[row[-1]], (
            f'anchor={row[-1]} expected={expected_by_anchor[row[-1]]} actual={row}')
    assert not any(actual[size:]), 'nonzero final-beat padding'


def check_image(words, read, model_base, heads):
    """TL-05: decode all 68 descriptors and the three complete offline tables."""
    assert len(words) == 68
    pairs = {}
    for index, row in enumerate(words):
        tag, offset, reserved = row[13:16]
        assert reserved == 0, f'desc={index} word15'
        kind, h = tag & 3, (tag >> 2) & 3
        assert tag >> 4 == 0, f'desc={index} reserved tag bits'
        if kind == 0:
            assert tag == offset == 0, f'desc={index} ordinary words13/14'
            continue
        assert kind in (1, 2) and h < 3
        assert offset % 32 == 0
        width, height, stride, anchor = SHAPES[h]
        assert row[9] == width | height << 16
        assert row[4] == heads[h]['plane_stride'] == width * height * 16
        assert (row[10] >> 8) & 15 == (2 if kind == 1 else 3)
        assert bool(row[0] & 512) == (kind == 2)
        assert (row[0] >> 14) & 3 == 3
        expected_offset = heads[h]['box_offset' if kind == 1 else 'class_offset']
        assert row[3] == expected_offset
        assert (h, kind) not in pairs
        pairs[h, kind] = (index, offset)
        assert (stride, anchor) == ((8, 0), (16, 3840), (32, 4800))[h]
    assert len(pairs) == 6
    for h in range(3):
        box, cls = pairs[h, 1], pairs[h, 2]
        assert box[0] < cls[0] and box[1] == cls[1]
        for table, limit, delta in [('exp_q20', 1 << 21, 0),
                                    ('probability_q24', 1 << 25, 1024)]:
            expected = heads[h][table]
            assert len(expected) == 256 and all(0 <= value < limit for value in expected)
            actual = struct.unpack('<256I', read(model_base + box[1] + delta, 1024))
            assert list(actual) == expected, f'head={h} {table}'
        assert heads[h]['exp_q20'][0] == 1 << 20
