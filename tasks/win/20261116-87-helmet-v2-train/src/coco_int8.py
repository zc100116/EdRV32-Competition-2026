"""T-HELMET-V2-INT8: count heads/helmets on the card 87 COCO list with the board INT8 path.

Run from the repo root with PYTHONPATH=tools/npu:third_party/ultralytics after compiling v2
and regenerating the v1 snapshot into build/npu/helmet_v2/v1/ (report 2026-11-16-helmet-v2-int8-eval).
"""
import json
from pathlib import Path
import torch
from models_eval import integer
from fixed_plan import build_plan, descriptors
from format import BASES
from model_data import DATA, ROOT
from quantize import prepare_image
from ref.npu_ref import Memory
from yolo_post_ref import make_heads

out = ROOT / 'build/npu/helmet_v2'
torch.set_num_threads(1)
selection = json.loads((ROOT / 'tasks/win/20261116-87-helmet-v2-train/artifacts/coco-evaluation.json').read_text())
paths = [DATA / 'val2017' / row['file'] for row in next(iter(selection['models'].values()))['per_image']]
plan = build_plan('detect', 2, 0)
results = {}
for version, source in [('v1', out / 'v1'),
                        ('v2', ROOT / 'build/npu/quantized_helmet')]:
    quantization = json.loads((source / 'quantization.json').read_text())
    rows = quantization['convolutions']
    desc = descriptors(plan, rows)
    memory = Memory()
    if version == 'v1':
        memory.load_hex(source / 'mem_model.hex')
    else:
        memory.write(BASES['MODEL_BASE'], (source / 'model.bin').read_bytes())
    memory.write(BASES['DESC_BASE'], b''.join(d.encode() for d in desc))
    registers = BASES | {'DESC_COUNT': len(desc)}
    heads = make_heads(quantization)
    per_image = []
    counts = {str(conf): {'helmet': 0, 'head': 0} for conf in (.25, .5)}
    for path in paths:
        boxes, scores, classes, _ = integer(memory, registers, plan, rows, heads, prepare_image(path))
        per_image.append(dict(file=path.name, boxes=boxes.tolist(), scores=scores.tolist(), classes=classes.tolist()))
        for conf in (.25, .5):
            for cls, name in enumerate(('helmet', 'head')):
                counts[str(conf)][name] += int(((scores > conf) & (classes == cls)).sum())
    results[version] = dict(counts=counts, per_image=per_image)
    print(version, counts, flush=True)
(out / 'coco-int8.json').write_text(json.dumps(dict(images=len(paths), persons=selection['persons'], models=results), indent=2) + '\n')
