"""Build a YOLO UART transport file for Serial Console 2's file sender.

The input must already be an INT8 model image in the accelerator's DDR
layout. A PyTorch .pt checkpoint is not such an image.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import struct
import zlib


CHUNK_SIZE = 1024
GUARD_BYTES = 32
MAX_SIZE = 65535 * CHUNK_SIZE


def pack_image(image: bytes, base: int) -> bytes:
    """Return YCFG followed by self-checking YM packets and UART guard bytes."""
    image += bytes(-len(image) % 32)
    if not image or len(image) > MAX_SIZE:
        raise ValueError("padded image must contain 1..65535 KiB")
    if base < 0 or base & 31 or base + len(image) > 2**32:
        raise ValueError("DDR base must be aligned and the range must not wrap")

    stream = bytearray(b"YCFG")
    stream += struct.pack("<III", base, len(image), zlib.crc32(image))
    stream += bytes(GUARD_BYTES)
    for seq, offset in enumerate(range(0, len(image), CHUNK_SIZE)):
        payload = image[offset : offset + CHUNK_SIZE]
        header = struct.pack("<HH", seq, len(payload))
        stream += b"YM" + header + payload
        stream += struct.pack("<I", zlib.crc32(header + payload))
        stream += bytes(GUARD_BYTES)
    return bytes(stream)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, nargs="?",
                        help="packed INT8 model image")
    parser.add_argument("--smoke", action="store_true",
                        help="use a deterministic 32-byte test image")
    parser.add_argument("--output", type=Path,
                        help="output file for Serial Console 2")
    parser.add_argument("--base", type=lambda value: int(value, 0),
                        default=0x00100000, help="32-byte aligned DDR base")
    args = parser.parse_args()

    if args.smoke:
        if args.image is not None:
            parser.error("omit image when using --smoke")
        image = bytes((index * 7 + 3) & 0xFF for index in range(32))
        output = args.output or Path("out/board/yolo_uart_smoke.ymod")
    else:
        if args.image is None:
            parser.error("image is required unless --smoke is used")
        if args.image.suffix.lower() == ".pt":
            parser.error("convert and quantize .pt weights before packing")
        image = args.image.read_bytes()
        output = args.output or args.image.with_suffix(".ymod")

    try:
        stream = pack_image(image, args.base)
    except ValueError as exc:
        parser.error(str(exc))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(stream)
    padded_size = (len(image) + 31) & ~31
    print(f"file: {output.resolve()}")
    print(f"image: {padded_size} bytes, CRC32=0x{zlib.crc32(image + bytes(padded_size - len(image))):08X}")
    print(f"transport: {len(stream)} bytes, {((padded_size + CHUNK_SIZE - 1) // CHUNK_SIZE)} packets")


if __name__ == "__main__":
    main()
