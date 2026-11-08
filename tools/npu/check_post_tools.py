#!/usr/bin/env python3
"""check_post_tools.py — npu-spec 2.6/4.1/4.4/4.5; testplan TL-05.

Decode real compiler artifacts and compare complete candidates/EDDT with the old path.
Clock domain: offline host; generated data remains under build/.
"""
import argparse
import importlib.util
from pathlib import Path
import struct

from compile_yolo import read_model_hex
from fixed_plan import build_plan
from format import BASES, pack_post_tables
from ref.npu_ref import Memory, load_case
import yolo_post_ref as post


def check_images(directory, legacy_directory):
    memory, regs = load_case(directory)
    old, old_regs = load_case(legacy_directory)
    assert regs == old_regs
    plan = build_plan()
    heads = post.load_heads()
    commands = [c for c in plan['commands'] if c['kind'] != 'add']
    tagged = 0
    for index, command in enumerate(commands):
        address = regs['DESC_BASE'] + index * 64
        words = struct.unpack('<16I', memory.read(address, 64))
        previous = list(struct.unpack('<16I', old.read(address, 64)))
        assert words[15] == 0, index
        if 'post_kind' in command:
            head_id = command['head_id']
            head = heads[head_id]
            kind = command['post_kind']
            offset = plan['post_lut_offset'] + head_id * 2048
            assert words[13:15] == (kind | head_id << 2, offset), index
            assert offset % 32 == 0
            assert words[9] == head['width'] | head['height'] << 16
            assert words[4] == head['plane_stride']
            assert words[3] == head['box_offset' if kind == 1 else 'class_offset']
            assert words[10] >> 8 & 15 == (2 if kind == 1 else 3)
            assert bool(words[0] & 512) == (kind == 2)
            assert head['stride'] == (8 << head_id)
            anchor_base = sum(h['width'] * h['height'] for h in heads[:head_id])
            assert anchor_base == (0, 3840, 4800)[head_id]
            previous[13:15] = words[13:15]
            tagged += 1
            print(f'TL-05 desc={index} {command["name"]} words=' +
                  ' '.join(f'{word:08x}' for word in words))
        else:
            assert words[13:15] == (0, 0), index
        assert words == tuple(previous), index
    assert tagged == 6
    for head_id, head in enumerate(heads):
        offset = plan['post_lut_offset'] + head_id * 2048
        table = memory.read(regs['MODEL_BASE'] + offset, 2048)
        exp = struct.unpack('<256I', table[:1024])
        probability = struct.unpack('<256I', table[1024:])
        assert exp == tuple(head['exp_q20'])
        assert probability == tuple(head['probability_q24'])
        assert max(exp).bit_length() <= 21 and exp[0] == 1 << 20
        assert max(probability).bit_length() <= 25
    unity_head = dict(heads[0], probability_q24=[1 << 24] * 256)
    assert struct.unpack_from('<I', pack_post_tables(unity_head), 1024)[0] == 1 << 24
    model = read_model_hex(directory / 'mem_model.hex', regs['MODEL_BASE'])
    previous = read_model_hex(legacy_directory / 'mem_model.hex', regs['MODEL_BASE'])
    assert model[:len(previous)] == previous
    assert len(model) == len(previous) + 6144 == plan['image_bytes']
    print(f'TL-05 PASS: 6 tagged + 62 ordinary descriptors; 1536 u32 entries; '
          f'21/25 bits; preserved {len(previous)} model bytes')
    return heads


def check_frame(directory, legacy_directory, legacy_ref, heads):
    spec = importlib.util.spec_from_file_location('legacy_post', legacy_ref)
    legacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    images = []
    for case in (directory, legacy_directory):
        memory = Memory()
        memory.load_hex(case / 'ref_out.hex')
        images.append(memory.read(BASES['OUTPUT_BASE'], 725760))
    assert images[0] == images[1], 'raw network outputs differ'
    stats = dict.fromkeys(post.STAT_KEYS, 0)
    candidates = post.decode_candidates(images[0], heads, stats)
    old_stats = dict.fromkeys(post.STAT_KEYS, 0)
    assert candidates == legacy.decode_candidates(images[1], heads, old_stats)
    assert stats == old_stats
    detections, stats = post.postprocess(images[0], heads)
    assert (detections, stats) == legacy.postprocess(images[1], heads)
    assert post.postprocess_candidates(candidates)[0] == detections
    packed = post.pack_candidates(candidates)
    assert len(packed) == 24 * len(candidates)
    for index, (box, probability, class_id, anchor) in enumerate(candidates):
        record = struct.unpack_from('<4iIHH', packed, index * 24)
        assert record == (*box, probability, class_id, anchor)
    (directory / 'output.bin').write_bytes(images[0])
    (directory / 'candidates.bin').write_bytes(packed)
    (directory / 'eddt.bin').write_bytes(post.pack_detections(detections))
    print(f'Real COCO128 000000000009 PASS: {len(candidates)} complete candidates, '
          f'{len(detections)} EDDT entries, all fields and statistics identical')


def check_thresholds(heads):
    assert post.int8_thresholds_for_probability(heads) == [103, 105, 103]
    for threshold in (0, 4194304, 8388608, 1 << 24):
        prefilters = post.int8_thresholds_for_probability(heads, threshold)
        for head, prefilter in zip(heads, prefilters, strict=True):
            for q in range(-128, 128):
                probability = head['probability_q24'][q + 128]
                assert (q >= prefilter and probability > threshold) == (probability > threshold)
    output = bytearray(b'\x7f' * 725760)
    assert len(post.decode_candidates(output, heads)) == 5040
    assert post.decode_candidates(output, heads, probability_threshold=1 << 24) == []
    assert post.decode_candidates(output, heads, int8_thresholds=[128] * 3) == []
    threshold = heads[0]['probability_q24'][255]
    candidates = post.decode_candidates(output, heads, int8_thresholds=[127] * 3,
                                        probability_threshold=threshold)
    assert all(row[3] >= 3840 for row in candidates)
    assert len(candidates) == 1200
    print('Thresholds PASS: default 103/105/103, all signed INT8 values at four Q24 '
          'thresholds, strict equality, 5040/zero candidates')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', type=Path, required=True)
    parser.add_argument('--legacy-case', type=Path, required=True)
    parser.add_argument('--legacy-ref', type=Path, required=True)
    args = parser.parse_args()
    heads = check_images(args.case, args.legacy_case)
    check_frame(args.case, args.legacy_case, args.legacy_ref, heads)
    check_thresholds(heads)
    print('PASS NPU post tools')


if __name__ == '__main__':
    main()
