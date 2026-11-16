#!/usr/bin/env python3
"""T-DEMO-PAGES: one evaluation image/model, models_eval.integer vs board C; host."""
import json
from pathlib import Path
import struct
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/npu'))
import cv2
import numpy as np
import torch
from compile_yolo import read_model_hex
from fixed_plan import build_plan, descriptors
from format import BASES
from model_data import evaluation_paths
from models_eval import integer
from quantize import prepare_image
from pose_eval import output_bytes
from ref.npu_ref import Memory
from yolo_post_ref import (make_heads, decode_candidates, postprocess,
                           integer_sort, suppresses, STAT_KEYS)


def main():
    torch.set_num_threads(1)
    out = ROOT / 'build/npu/demo_pages_test'
    out.mkdir(parents=True, exist_ok=True)
    for name, nc, nk in [('gesture',14,21),('face',1,5),('doodle',20,0),('helmet',2,0)]:
        source = ROOT / 'sw/apps/showcase/models' / name
        quant = json.loads((source / 'quantization.json').read_text())
        task = name if nk else 'detect'
        plan = build_plan(task, nc, nk*3)
        encoded = descriptors(plan, quant['convolutions'])
        memory = Memory()
        memory.write(BASES['MODEL_BASE'],
                     read_model_hex(source/'mem_model.hex', BASES['MODEL_BASE']))
        memory.write(BASES['DESC_BASE'], b''.join(d.encode() for d in encoded))
        heads = make_heads(quant)
        path = evaluation_paths(name)[0]
        boxes, scores, classes, points = integer(memory, BASES | {'DESC_COUNT':len(encoded)},
            plan, quant['convolutions'], heads, prepare_image(path))
        raw = memory.read(BASES['OUTPUT_BASE'], output_bytes(plan))
        candidates = decode_candidates(raw, heads)
        integer_sort(candidates, dict.fromkeys(STAT_KEYS, 0))
        kept = []
        for candidate in candidates:
            if any(p[2] == candidate[2] and suppresses(p[0], candidate[0]) for p in kept):
                continue
            kept.append(candidate)
            if len(kept) == 100: break
        mapped, _ = postprocess(raw, heads)
        assert len(kept) == len(boxes) == len(mapped) and len(kept) > 0
        if nk:
            points[:,:,0] = np.clip(points[:,:,0]*2, 0, 1280)
            points[:,:,1] = np.clip((points[:,:,1]-12)*2, 0, 720)
        expected = bytearray(struct.pack('<I', len(kept)))
        for i, (candidate, detection) in enumerate(zip(kept, mapped)):
            assert detection[4] == classes[i]
            transformed = np.clip((boxes[i]-[0,12,0,12])*2, 0, [1280,720,1280,720])
            expected.extend(struct.pack('<H6H4f', candidate[3], *detection, *transformed))
            if nk: expected.extend(struct.pack(f'<{nk*3}f', *points[i].flatten()))
        raw_path = out / f'{name}.output'
        expected_path = out / f'{name}.expected'
        raw_path.write_bytes(raw); expected_path.write_bytes(expected)
        rgb = prepare_image(path)[0].permute(1,2,0).numpy()[12:372]
        rgb = cv2.resize((rgb*255).round().astype(np.uint8), (1280,720),
                         interpolation=cv2.INTER_NEAREST).astype(np.uint16)
        if name == 'doodle':
            gray = (rgb[:,:,0]*77 + rgb[:,:,1]*150 + rgb[:,:,2]*29 + 128) >> 8
            rgb = np.repeat(np.where(gray >= 128, 255, 0)[:,:,None], 3, axis=2).astype(np.uint16)
        pixels = ((rgb[:,:,0] >> 3) << 11) | ((rgb[:,:,1] >> 2) << 5) | (rgb[:,:,2] >> 3)
        (out / f'{name}.rgb565').write_bytes(pixels.astype('<u2').tobytes())
        print(f'{name} image={path}', flush=True)
        subprocess.run([sys.argv[1], name, raw_path, expected_path], check=True)


if __name__ == '__main__':
    main()
