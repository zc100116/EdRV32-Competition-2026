"""compile_yolo.py — NPU spec 2.5: compile YOLOv8n and one input image.

Write descriptors, model weights/parameters, C4 input and output intervals.
Clock domain: offline host tool.
"""

import argparse
from collections import Counter
from pathlib import Path
from time import perf_counter

from fixed_plan import build_plan, descriptors
from format import BASES, write_case
from input_pack import pack
from quantize import load_quantized


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    started = perf_counter()
    plan = build_plan()
    model, rows = load_quantized(plan)
    desc = descriptors(plan, rows)
    checks = []
    for scale in range(3):
        for branch in ("box", "cls"):
            name = f"D{scale}.{branch}"
            tensor = plan["tensors"][name]
            checks.append((name, tensor["base"], tensor["bytes"]))
    write_case(args.out, desc, {
        "model": [(BASES["MODEL_BASE"], model)],
        "input": [(BASES["INPUT_BASE"], pack(args.image))],
    }, checks)
    counts = Counter(d.op for d in desc)
    print(f"descriptors={len(desc)} CONV={counts[0]} POOL={counts[1]} UPSAMPLE={counts[2]}")
    print(f"model_bytes={len(model)} work_bytes={plan['work_bytes']}")
    print(f"out={args.out} elapsed_s={perf_counter() - started:.3f}")


if __name__ == "__main__":
    main()
