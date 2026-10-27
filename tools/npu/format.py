"""format.py — NPU spec 2.2, 4.1–4.3: encode descriptors and DDR images.

Byte order follows DDR addresses; hex lines reverse bytes for $readmemh.
Clock domain: offline host tool.
"""

from dataclasses import dataclass
from pathlib import Path
import struct

import numpy as np


BASES = {"MODEL_BASE": 0x00100000, "WORK_BASE": 0x01000000,
         "INPUT_BASE": 0x04000000, "OUTPUT_BASE": 0x05000000,
         "DESC_BASE": 0x00080000}
REGIONS = ("model", "work", "input", "output")


def align(value: int, boundary: int = 32) -> int:
    return (value + boundary - 1) // boundary * boundary


@dataclass
class Descriptor:
    op: int = 0
    k3: bool = False
    s2: bool = False
    lut_en: bool = False
    res_en: bool = False
    in_c4: bool = False
    half_tail: bool = False
    in_sel: int = 1
    out_sel: int = 1
    res_sel: int = 1
    in_offset: int = 0
    in_plane_stride: int = 0
    out_offset: int = 0
    out_plane_stride: int = 0
    res_offset: int = 0
    weight_offset: int = 0
    quant_offset: int = 0
    in_w: int = 4
    in_h: int = 4
    out_w: int = 4
    out_h: int = 4
    cin_blocks: int = 1
    cout_blocks: int = 1
    out_zp: int = 0

    @property
    def k_count(self) -> int:
        return (9 if self.k3 else 1) * (1 if self.in_c4 else 2 * self.cin_blocks)

    @property
    def weight_block_bytes(self) -> int:
        return 256 * self.k_count

    @property
    def weight_bytes(self) -> int:
        tail = self.weight_block_bytes // (2 if self.half_tail and not self.in_c4 else 1)
        return (self.cout_blocks - 1) * self.weight_block_bytes + tail

    @property
    def output_planes(self) -> int:
        if self.op:
            return self.cin_blocks
        return self.cout_blocks * 2 - int(self.half_tail)

    def encode(self) -> bytes:
        flags = (self.op | int(self.k3) << 4 | int(self.s2) << 5 |
                 int(self.lut_en) << 6 | int(self.res_en) << 7 |
                 int(self.in_c4) << 8 | int(self.half_tail) << 9 |
                 self.in_sel << 12 | self.out_sel << 14 | self.res_sel << 16)
        words = [flags, self.in_offset, self.in_plane_stride, self.out_offset,
                 self.out_plane_stride, self.res_offset, self.weight_offset,
                 self.quant_offset, self.in_w | self.in_h << 16,
                 self.out_w | self.out_h << 16,
                 self.cin_blocks | self.cout_blocks << 8 | (self.out_zp & 255) << 16,
                 self.cin_blocks * self.in_w // 4 |
                 (self.k_count << 16 if self.op == 0 else 0),
                 self.weight_block_bytes if self.op == 0 else 0, 0, 0, 0]
        return struct.pack("<16I", *words)


def pack_weights(weight: np.ndarray, desc: Descriptor) -> bytes:
    """Spec 4.3: ordinary, folded HALF_TAIL, or IN_C4 rows of 256 bytes."""
    cout, cin, kernel, _ = weight.shape
    physical_cin = 8 if desc.in_c4 else desc.cin_blocks * 16
    padded = np.zeros((desc.cout_blocks * 32, physical_cin, kernel, kernel), np.int8)
    padded[:cout, :cin] = weight
    blocks = []
    for block in range(desc.cout_blocks):
        part = padded[block * 32:(block + 1) * 32]
        if desc.in_c4:
            ordered = part.transpose(2, 3, 0, 1)
        elif desc.half_tail and block == desc.cout_blocks - 1:
            ordered = part[:16].reshape(16, desc.cin_blocks, 2, 8, kernel, kernel)
            ordered = ordered.transpose(4, 5, 1, 2, 0, 3)
        else:
            ordered = part.reshape(32, desc.cin_blocks, 2, 8, kernel, kernel)
            ordered = ordered.transpose(4, 5, 1, 2, 0, 3)
        blocks.append(ordered.tobytes())
    return b"".join(blocks)


def pack_quant(bias, mult, shift, cout_blocks: int, lut: bytes = bytes(256)) -> bytes:
    """Spec 4.2: zero padding includes byte 7; zero point lives in the descriptor."""
    result = bytearray(cout_blocks * 512)
    for channel, (b, m, s) in enumerate(zip(bias, mult, shift, strict=True)):
        block, within = divmod(channel, 32)
        struct.pack_into("<ihBB", result, block * 512 + within * 8, int(b), int(m), int(s), 0)
    for block in range(cout_blocks):
        result[block * 512 + 256:(block + 1) * 512] = lut
    return bytes(result)


def pack_c4(rgb: np.ndarray) -> bytes:
    physical = np.zeros((*rgb.shape[:2], 4), dtype=np.int8)
    physical[:, :, :3] = rgb
    return physical.tobytes()


def pack_c16(chw: np.ndarray, plane_stride: int) -> bytes:
    channels, height, width = chw.shape
    result = bytearray(channels // 16 * plane_stride)
    for plane in range(channels // 16):
        packed = chw[plane * 16:(plane + 1) * 16].transpose(1, 2, 0).tobytes()
        start = plane * plane_stride
        result[start:start + len(packed)] = packed
    return bytes(result)


def write_hex(path: Path, segments: list[tuple[int, bytes]]) -> None:
    with path.open("w", encoding="ascii") as stream:
        for address, data in sorted(segments):
            stream.write(f"@{address // 32:08x}\n")
            padded = data + bytes(align(len(data)) - len(data))
            for start in range(0, len(padded), 32):
                stream.write(padded[start:start + 32][::-1].hex() + "\n")


def write_case(out: Path, descriptors: list[Descriptor], segments: dict,
               checks: list[tuple[str, int, int]], bases: dict = BASES) -> None:
    out.mkdir(parents=True, exist_ok=True)
    regs = bases | {"DESC_COUNT": len(descriptors)}
    (out / "regs.txt").write_text(
        "".join(f"{name} {value:08x}\n" for name, value in regs.items()), encoding="ascii")
    write_hex(out / "mem_desc.hex", [(bases["DESC_BASE"],
                                    b"".join(desc.encode() for desc in descriptors))])
    for region, contents in segments.items():
        if contents:
            write_hex(out / f"mem_{region}.hex", contents)
    (out / "check.txt").write_text(
        "".join(f"{name} {address:08x} {size:08x}\n" for name, address, size in checks),
        encoding="ascii")
