#!/usr/bin/env python3
"""Convert a little-endian ELF32 RISC-V image into word-oriented readmemh.

Only Python's standard library is used so frozen ISA/ACT assets remain runnable
without a local RISC-V binutils installation. PT_LOAD segments are placed at
their physical address (or virtual address when p_paddr is zero). A sidecar JSON
records the entry point and useful compliance symbols.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


PT_LOAD = 1
SHT_SYMTAB = 2
SHT_DYNSYM = 11


def unpack_from(fmt: str, data: bytes, offset: int) -> tuple[int, ...]:
    size = struct.calcsize(fmt)
    if offset < 0 or offset + size > len(data):
        raise ValueError(f"ELF structure outside file at 0x{offset:x}")
    return struct.unpack_from(fmt, data, offset)


def c_string(table: bytes, offset: int) -> str:
    if offset < 0 or offset >= len(table):
        return ""
    end = table.find(b"\0", offset)
    if end < 0:
        end = len(table)
    return table[offset:end].decode("utf-8", errors="replace")


def parse_elf(path: Path) -> tuple[int, list[tuple[int, bytes, int]], dict[str, int]]:
    data = path.read_bytes()
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise ValueError(f"{path} is not an ELF file")
    if data[4] != 1 or data[5] != 1:
        raise ValueError("only little-endian ELF32 is supported")

    header = unpack_from("<16sHHIIIIIHHHHHH", data, 0)
    machine = header[2]
    entry = header[4]
    phoff = header[5]
    shoff = header[6]
    phentsize = header[9]
    phnum = header[10]
    shentsize = header[11]
    shnum = header[12]
    if machine != 243:
        raise ValueError(f"expected EM_RISCV (243), found {machine}")
    if phentsize < 32 and phnum:
        raise ValueError(f"invalid program-header size {phentsize}")
    if shentsize < 40 and shnum:
        raise ValueError(f"invalid section-header size {shentsize}")

    segments: list[tuple[int, bytes, int]] = []
    for index in range(phnum):
        fields = unpack_from("<IIIIIIII", data, phoff + index * phentsize)
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, _, _ = fields
        if p_type != PT_LOAD or p_memsz == 0:
            continue
        if p_offset + p_filesz > len(data) or p_filesz > p_memsz:
            raise ValueError(f"invalid PT_LOAD #{index}")
        address = p_paddr if p_paddr else p_vaddr
        segments.append((address, data[p_offset : p_offset + p_filesz], p_memsz))

    sections: list[tuple[int, ...]] = []
    for index in range(shnum):
        sections.append(unpack_from("<IIIIIIIIII", data, shoff + index * shentsize))

    symbols: dict[str, int] = {}
    for section in sections:
        sh_type = section[1]
        sh_offset = section[4]
        sh_size = section[5]
        sh_link = section[6]
        sh_entsize = section[9]
        if sh_type not in (SHT_SYMTAB, SHT_DYNSYM) or sh_entsize < 16:
            continue
        if sh_link >= len(sections):
            raise ValueError("symbol table has invalid linked string table")
        string_section = sections[sh_link]
        string_data = data[string_section[4] : string_section[4] + string_section[5]]
        for offset in range(sh_offset, sh_offset + sh_size, sh_entsize):
            st_name, st_value, _, _, _, _ = unpack_from("<IIIBBH", data, offset)
            name = c_string(string_data, st_name)
            if name and name not in symbols:
                symbols[name] = st_value

    if not segments:
        raise ValueError("ELF contains no loadable segments")
    return entry, segments, symbols


def build_image(
    segments: list[tuple[int, bytes, int]], base_address: int
) -> tuple[bytearray, int]:
    highest = base_address
    for address, _, mem_size in segments:
        if address < base_address:
            raise ValueError(
                f"segment at 0x{address:08x} is below base 0x{base_address:08x}"
            )
        highest = max(highest, address + mem_size)
    image = bytearray(highest - base_address)
    occupied: list[tuple[int, int]] = []
    for address, payload, mem_size in sorted(segments):
        start = address - base_address
        stop = start + mem_size
        for old_start, old_stop in occupied:
            if start < old_stop and old_start < stop:
                raise ValueError(f"overlapping PT_LOAD segment at 0x{address:08x}")
        occupied.append((start, stop))
        image[start : start + len(payload)] = payload
    while len(image) % 4:
        image.append(0)
    return image, highest


def write_hex(path: Path, image: bytearray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as output:
        for offset in range(0, len(image), 4):
            word = int.from_bytes(image[offset : offset + 4], "little")
            output.write(f"{word:08x}\n")


def parse_int(value: str) -> int:
    return int(value, 0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("elf", type=Path)
    parser.add_argument("hex", type=Path)
    parser.add_argument("--base", type=parse_int, default=0x80000000)
    parser.add_argument("--metadata", type=Path)
    args = parser.parse_args()

    entry, segments, symbols = parse_elf(args.elf)
    image, highest = build_image(segments, args.base)
    write_hex(args.hex, image)
    metadata_path = args.metadata or args.hex.with_suffix(args.hex.suffix + ".json")
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    useful_symbols = {
        name: symbols[name]
        for name in ("tohost", "fromhost", "begin_signature", "end_signature")
        if name in symbols
    }
    metadata = {
        "elf": str(args.elf),
        "base": args.base,
        "entry": entry,
        "highest_address": highest,
        "word_count": len(image) // 4,
        "symbols": useful_symbols,
    }
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(
        f"ELF32_MEM entry=0x{entry:08x} words={len(image)//4} "
        f"tohost={useful_symbols.get('tohost', 0):#010x}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
