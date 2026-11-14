#!/usr/bin/env python3
"""T-POSE-BOARD: compare board C with pose_eval.int8 on two val2017 images.

Resize to the camera's 1280x720 before the common 640x384 letterbox; host clock.
Fixtures and reference outputs remain in build/.
"""
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/npu'))
import cv2
import torch
from fixed_plan import build_plan, descriptors
from format import BASES
from compile_yolo import read_model_hex
from pose_eval import int8, output_bytes, integer_keep
from quantize import DATA
from ref.npu_ref import Memory
from yolo_post_ref import make_heads, decode_candidates, postprocess


def main():
    torch.set_num_threads(1)
    out = ROOT / 'build/npu/pose_board/test'
    out.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'sw/apps/showcase/models/yolov8n-pose'
    quant = json.loads((source / 'quantization.json').read_text())
    plan = build_plan('pose')
    encoded = descriptors(plan, quant['convolutions'])
    memory = Memory()
    memory.write(BASES['MODEL_BASE'], read_model_hex(source / 'mem_model.hex', BASES['MODEL_BASE']))
    memory.write(BASES['DESC_BASE'], b''.join(d.encode() for d in encoded))
    registers = BASES | {'DESC_COUNT': len(encoded)}
    heads = make_heads(quant)
    for image_id in (139, 785):
        path = out / f'{image_id}.png'
        image = cv2.imread(str(DATA / f'val2017/{image_id:012d}.jpg'))
        cv2.imwrite(str(path), cv2.resize(image, (1280, 720)))
        boxes, _, points = int8(memory, registers, plan, quant['convolutions'], heads,
                                path, {'width': 1280, 'height': 720})
        raw = memory.read(BASES['OUTPUT_BASE'], output_bytes(plan))
        raw_path = out / f'{image_id}.output'
        raw_path.write_bytes(raw)
        kept = integer_keep(decode_candidates(raw, heads))
        mapped, _ = postprocess(raw, heads)
        expected = bytearray(struct.pack('<I', len(kept)))
        for i, (candidate, detection) in enumerate(zip(kept, mapped)):
            # pose_eval returns unrounded box coordinates; board uses specified integer mapping.
            assert max(abs(boxes[i] - detection[:4])) <= .5
            expected.extend(struct.pack('<H6H', candidate[3], *detection))
            expected.extend(struct.pack('<51f', *points[i].flatten()))
        expected_path = out / f'{image_id}.expected'
        expected_path.write_bytes(expected)
        subprocess.run([sys.argv[1], raw_path, expected_path], check=True)


if __name__ == '__main__':
    main()
