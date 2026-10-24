"""Pack INT8 YOLO convolution weights into the fixed 8-bank DDR tile order.

This module handles layout only. Quantization and calibrated activation
scales must be supplied separately before producing an executable image.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / "out/board/yolo_v8n_fixed_plan.json"
FUSED = ROOT / "out/models/yolov8n_fused_conv.npz"
CHECK_IMAGE = ROOT / "out/models/yolov8n_weight_layout_check.bin"


def pack_int8(weight: np.ndarray, command: dict) -> bytes:
    """Map [out,in,ky,kx] to [block,ky,kx,C16,half,bank,OC4,K8]."""
    if weight.dtype != np.int8 or weight.ndim != 4:
        raise ValueError("weight must be a 4D signed INT8 array")
    actual_cout, actual_cin, ky, kx = weight.shape
    kernel = 3 if command["kernel3"] else 1
    padded_cout = command["output_blocks"] * 32
    padded_cin = command["cin_blocks"] * 16
    expected_cout = padded_cout - (16 if command["last_c16_only"] else 0)
    if (actual_cout, ky, kx) != (expected_cout, kernel, kernel):
        raise ValueError(f"{command['name']} output/kernel shape mismatch")
    if actual_cin != padded_cin and not (
        command["layer"] == 0 and actual_cin == 3 and padded_cin == 16
    ):
        raise ValueError(f"{command['name']} input channel count mismatch")

    padded = np.zeros((padded_cout, padded_cin, kernel, kernel),
                      dtype=np.int8)
    padded[:actual_cout, :actual_cin] = weight
    blocks = padded.reshape(command["output_blocks"], 32,
                            command["cin_blocks"], 2, 8,
                            kernel, kernel)
    ordered = blocks.transpose(0, 5, 6, 2, 3, 1, 4)
    image = ordered.tobytes(order="C")
    if len(image) != command["weight_bytes"]:
        raise AssertionError(f"{command['name']} physical byte count mismatch")
    return image


def unpack_int8(image: bytes, command: dict) -> np.ndarray:
    """Return the physically padded [out,in,ky,kx] array for verification."""
    kernel = 3 if command["kernel3"] else 1
    shape = (command["output_blocks"], kernel, kernel,
             command["cin_blocks"], 2, 32, 8)
    ordered = np.frombuffer(image, dtype=np.int8).reshape(shape)
    logical = ordered.transpose(0, 5, 3, 4, 6, 1, 2)
    return logical.reshape(command["output_blocks"] * 32,
                           command["cin_blocks"] * 16, kernel, kernel)


def check_real_weights() -> None:
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    first = plan["commands"][0]
    pattern = np.fromfunction(
        lambda oc, ic, ky, kx: (oc * 17 + ic * 5 + ky * 3 + kx) % 127,
        (16, 3, 3, 3), dtype=int,
    ).astype(np.int8)
    pattern_bytes = pack_int8(pattern, first)
    expected_bank0 = bytes(int(pattern[oc, ic, 0, 0]) if ic < 3 else 0
                           for oc in range(4) for ic in range(8))
    expected_next_kx = bytes(int(pattern[oc, ic, 0, 1]) if ic < 3 else 0
                             for oc in range(4) for ic in range(8))
    if (pattern_bytes[:32] != expected_bank0 or
        pattern_bytes[128:160] != bytes(32) or
        pattern_bytes[256:512] != bytes(256) or
        pattern_bytes[512:544] != expected_next_kx):
        raise AssertionError("physical bank/K ordering does not match RTL")

    image = bytearray(plan["weight_bytes"])
    checked = 0
    with np.load(FUSED) as fused:
        for command in plan["commands"]:
            if command["kind"] != "conv":
                continue
            weight = fused[f"w_{command['index']:02d}"]
            max_abs = np.max(np.abs(weight), axis=(1, 2, 3))
            scales = np.maximum(max_abs / 127.0, np.finfo(np.float32).tiny)
            quantized = np.clip(np.rint(weight / scales[:, None, None, None]),
                                -127, 127).astype(np.int8)
            packed = pack_int8(quantized, command)
            recovered = unpack_int8(packed, command)
            cout, cin, _, _ = quantized.shape
            if not np.array_equal(recovered[:cout, :cin], quantized):
                raise AssertionError(f"{command['name']} round-trip mismatch")
            if np.any(recovered[cout:]) or np.any(recovered[:cout, cin:]):
                raise AssertionError(f"{command['name']} padded terms are nonzero")
            offset = command["weight_base"] - plan["model_base"]
            image[offset:offset + len(packed)] = packed
            checked += 1
    CHECK_IMAGE.parent.mkdir(parents=True, exist_ok=True)
    CHECK_IMAGE.write_bytes(image)
    print(f"layout round-trip passed for {checked} fused convolutions")
    print(f"weights-only check image: {CHECK_IMAGE} ({len(image)} bytes)")
    print("This image has no calibrated quantization records; do not run it.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-real", action="store_true",
                        help="pack and round-trip-check fused checkpoint weights")
    args = parser.parse_args()
    if not args.check_real:
        parser.error("use --check-real to validate the current checkpoint")
    check_real_weights()


if __name__ == "__main__":
    main()
