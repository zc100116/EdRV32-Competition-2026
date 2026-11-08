"""compile_yolo.py — NPU spec 2.5: compile YOLOv8n and one input image.

Write descriptors, model weights/parameters, C4 input and output intervals.
Clock domain: offline host tool.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
from time import perf_counter

from fixed_plan import build_plan, descriptors
from format import BASES, model_with_post_tables, write_case


def read_model_hex(path: Path, base: int) -> bytes:
    """Read compiler model bytes without importing calibration dependencies."""
    image = bytearray()
    for token in path.read_text().split():
        if token.startswith("@"):
            offset = int(token[1:], 16) * 32 - base
        else:
            data = bytes.fromhex(token)[::-1]
            if offset > len(image):
                image.extend(bytes(offset - len(image)))
            image[offset:offset + 32] = data
            offset += 32
    return bytes(image)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--image", type=Path)
    source.add_argument("--model-source", type=Path,
                        help="rebuild model/descriptor hex from an offline compiler snapshot")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    started = perf_counter()
    plan = build_plan()
    segments = {}
    if args.model_source is None:
        from input_pack import pack
        from quantize import load_quantized

        model, rows = load_quantized(plan)
        segments["input"] = [(BASES["INPUT_BASE"], pack(args.image))]
    else:
        rows = json.loads((args.model_source / "quantization.json").read_text())["convolutions"]
        model = read_model_hex(args.model_source / "mem_model.hex", BASES["MODEL_BASE"])
        model = model_with_post_tables(model, rows, plan)
    desc = descriptors(plan, rows)
    checks = []
    for scale in range(3):
        for branch in ("box", "cls"):
            name = f"D{scale}.{branch}"
            tensor = plan["tensors"][name]
            checks.append((name, tensor["base"], tensor["bytes"]))
    segments["model"] = [(BASES["MODEL_BASE"], model)]
    write_case(args.out, desc, segments, checks)
    counts = Counter(d.op for d in desc)
    print(f"descriptors={len(desc)} CONV={counts[0]} POOL={counts[1]} UPSAMPLE={counts[2]}")
    print(f"model_bytes={len(model)} work_bytes={plan['work_bytes']}")
    print(f"out={args.out} elapsed_s={perf_counter() - started:.3f}")


if __name__ == "__main__":
    main()
