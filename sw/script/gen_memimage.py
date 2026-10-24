#!/usr/bin/env python3
# ============================================================================
# File        : gen_memimage.py
# Author      : Edward ZC
# Description : Convert an objcopy raw binary into a word-per-line hex image for
#               $readmemh in edrv32_mem_model (little-endian 32-bit words).
# Usage       : python3 sw/script/gen_memimage.py <input.bin> <output.hex>
#               [word_bytes]
# ============================================================================
import sys


def main():
    if len(sys.argv) not in (3, 4):
        print("usage: gen_memimage.py <input.bin> <output.hex> [word_bytes]",
              file=sys.stderr)
        sys.exit(2)
    src, dst = sys.argv[1], sys.argv[2]
    word_bytes = int(sys.argv[3], 0) if len(sys.argv) == 4 else 4
    if word_bytes not in (1, 2, 4, 8, 16):
        print("word_bytes must be one of 1, 2, 4, 8, 16", file=sys.stderr)
        sys.exit(2)
    with open(src, "rb") as f:
        data = f.read()
    pad = (-len(data)) % word_bytes
    if pad:
        data += b"\x00" * pad
    with open(dst, "w", encoding="ascii") as f:
        for i in range(0, len(data), word_bytes):
            word = int.from_bytes(data[i:i + word_bytes], "little")
            f.write(f"{word:0{word_bytes * 2}x}\n")
    print(f"[gen_memimage] {src} -> {dst} "
          f"word_bytes={word_bytes} words={len(data)//word_bytes}")


if __name__ == "__main__":
    main()
