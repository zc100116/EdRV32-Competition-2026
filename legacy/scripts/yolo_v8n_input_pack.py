"""Convert an image to the YOLOv8n C16 input region in DDR.

The output contains 384 rows of 640 RGB pixels. Each pixel occupies 16 signed
INT8 bytes; channels 3..15 are zero. Two adjacent pixels form one 256-bit AXI
beat. Geometry and normalization match yolo_v8n_quantize.py.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
import torch

from yolo_v8n_quantize import PLAN_PATH, prepare_image
from yolo_serial_pack import pack_image


def pack(path: Path) -> tuple[bytes, dict]:
    source = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if source is None:
        raise ValueError(f"cannot read image: {path}")
    original_height, original_width = source.shape[:2]
    ratio = min(640.0 / original_width, 384.0 / original_height)
    scaled_width = round(original_width * ratio)
    scaled_height = round(original_height * ratio)
    left = (640 - scaled_width) // 2
    top = (384 - scaled_height) // 2
    normalized = prepare_image(path)
    quantized = torch.round(normalized * 127.0).to(torch.int8)
    rgb = quantized[0].permute(1, 2, 0).numpy()
    physical = np.zeros((384, 640, 16), dtype=np.int8)
    physical[:, :, :3] = rgb
    image = physical.tobytes(order="C")
    assert len(image) == 384 * 640 * 16
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    info = plan["tensors"]["input"]
    if info["channels"] != 16 or info["width"] != 640 or info["height"] != 384:
        raise ValueError("fixed ROM input geometry changed")
    return image, {
        "ddr_base": info["base"],
        "bytes": len(image),
        "original_width": original_width,
        "original_height": original_height,
        "scale": ratio,
        "scale_x": scaled_width / original_width,
        "scale_y": scaled_height / original_height,
        "scaled_width": scaled_width,
        "scaled_height": scaled_height,
        "pad_left": left,
        "pad_top": top,
        "input_width": 640,
        "input_height": 384,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--transport-output", type=Path,
                        help="also write a UART file at the manifest input address")
    args = parser.parse_args()
    output = args.output or args.image.with_suffix(".c16.bin")
    data, geometry = pack(args.image)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    output.with_suffix(".json").write_text(
        json.dumps(geometry, indent=2) + "\n", encoding="utf-8")
    if args.transport_output:
        args.transport_output.parent.mkdir(parents=True, exist_ok=True)
        args.transport_output.write_bytes(pack_image(data, geometry["ddr_base"]))
        print(f"UART input: {args.transport_output.resolve()}")
    print(f"DDR input: {output.resolve()} ({len(data)} bytes)")
    print(f"DDR base: 0x{geometry['ddr_base']:08X}")
    print(f"source {geometry['original_width']}x{geometry['original_height']} "
          f"scale={geometry['scale']:.6f} "
          f"pad=({geometry['pad_left']},{geometry['pad_top']})")


if __name__ == "__main__":
    main()
