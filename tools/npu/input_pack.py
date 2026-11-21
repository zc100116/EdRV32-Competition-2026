"""input_pack.py — NPU spec 2.2: letterbox, quantize and pack RGB as INT8_C4.

The resize, centered 114 padding and round(RGB / 255 × 127) match calibration.
Clock domain: offline host tool.
"""

from pathlib import Path

import torch

from format import pack_c4
from quantize import prepare_image


def pack(path: Path) -> bytes:
    normalized = prepare_image(path)
    quantized = torch.round(normalized * 127.0).to(torch.int8)
    return pack_c4(quantized[0].permute(1, 2, 0).numpy())
