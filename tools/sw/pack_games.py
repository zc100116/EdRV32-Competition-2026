#!/usr/bin/env python3
"""pack_games.py: showcase design 4.5; local games to one BIOS-loadable ELF.
Host tool; PNG pixels are decoded with zlib and scaled by nearest neighbour.
"""
import argparse
from pathlib import Path
import struct
import zlib

ICON_SIZE = 64


def decode_png(data):
    """Decode the specified 8-bit RGB/RGBA noninterlaced PNG subset."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('icon is not PNG')
    offset = 8
    compressed = bytearray()
    while offset < len(data):
        length, kind = struct.unpack_from('>I4s', data, offset)
        chunk = data[offset + 8:offset + 8 + length]
        offset += length + 12
        if kind == b'IHDR':
            width, height, depth, color, method, filtering, interlace = struct.unpack(
                '>IIBBBBB', chunk)
            if depth != 8 or color not in (2, 6) or method or filtering or interlace:
                raise ValueError('PNG requires 8-bit RGB/RGBA, noninterlaced')
        elif kind == b'IDAT':
            compressed.extend(chunk)
        elif kind == b'IEND':
            break
    channels = 3 if color == 2 else 4
    stride = width * channels
    raw = zlib.decompress(compressed)
    previous = bytearray(stride)
    rgba = bytearray()
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            above = previous[x]
            corner = previous[x - channels] if x >= channels else 0
            if kind == 0:
                predictor = 0
            elif kind == 1:
                predictor = left
            elif kind == 2:
                predictor = above
            elif kind == 3:
                predictor = (left + above) // 2
            elif kind == 4:
                p = left + above - corner
                distances = (abs(p - left), abs(p - above), abs(p - corner))
                predictor = (left, above, corner)[distances.index(min(distances))]
            else:
                raise ValueError(f'unsupported PNG filter {kind}')
            row[x] = (row[x] + predictor) & 255
        for x in range(0, stride, channels):
            rgba.extend(row[x:x + 3])
            rgba.append(row[x + 3] if channels == 4 else 255)
        previous = row
    return width, height, bytes(rgba)


def png_icon(data):
    width, height, rgba = decode_png(data)
    result = bytearray()
    for y in range(ICON_SIZE):
        for x in range(ICON_SIZE):
            offset = ((y * height // ICON_SIZE) * width + x * width // ICON_SIZE) * 4
            r, g, b, a = rgba[offset:offset + 4]
            result.extend((b, g, r, a))
    return bytes(result)

HEADER = struct.Struct('<4sHH')
ENTRY = struct.Struct('<64sIIIHHI')


def build_pack(directory):
    games = []
    for line in (directory / 'games.txt').read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        fields = line.split('|')
        if len(fields) not in (2, 3):
            raise ValueError('games.txt requires name|ROM|optional PNG')
        name = fields[0].encode('utf-8')
        if len(name) >= 64:
            raise ValueError('game name must fit 63 UTF-8 bytes')
        rom = (directory / fields[1]).read_bytes()
        icon = b''
        if len(fields) == 3 and fields[2]:
            icon = png_icon((directory / fields[2]).read_bytes())
        games.append((name, rom, icon))
    payload = bytearray(HEADER.pack(b'EDGP', 1, len(games)) + bytes(ENTRY.size * len(games)))
    for index, (name, rom, icon) in enumerate(games):
        payload.extend(bytes(-len(payload) % 4))
        rom_offset = len(payload)
        payload.extend(rom)
        payload.extend(bytes(-len(payload) % 4))
        icon_offset = len(payload) if icon else 0
        payload.extend(icon)
        size = ICON_SIZE if icon else 0
        ENTRY.pack_into(payload, HEADER.size + index * ENTRY.size, name,
                        rom_offset, len(rom), icon_offset, size, size, 1)
    return bytes(payload)


def pack_elf(elf, pack):
    """Append one PT_LOAD at the linker's .game_pack NOLOAD address."""
    if elf[:7] != b'\x7fELF\x01\x01\x01':
        raise ValueError('showcase ELF must be ELF32 little-endian')
    header = list(struct.unpack_from('<16sHHIIIIIHHHHHH', elf))
    phoff, shoff = header[5:7]
    phsize, phcount, shsize, shcount, names_index = header[9:14]
    sections = [struct.unpack_from('<10I', elf, shoff + i * shsize) for i in range(shcount)]
    names_section = sections[names_index]
    names = elf[names_section[4]:names_section[4] + names_section[5]]
    section = next(s for s in sections if names[s[0]:].split(b'\0', 1)[0] == b'.game_pack')
    address, capacity = section[3], section[5]
    if len(pack) > capacity:
        raise ValueError(f'game pack {len(pack)} bytes exceeds .game_pack {capacity} bytes')
    # GNU ld can emit a NOLOAD-only PT_LOAD for the reservation. Replace that entry
    # with the actual bytes so the BIOS does not subsequently zero the loaded pack.
    phdrs = []
    for i in range(phcount):
        phdr = elf[phoff + i * phsize:phoff + (i + 1) * phsize]
        fields = struct.unpack('<8I', phdr)
        if fields[0] == 1 and fields[2] == address and fields[4] == 0:
            continue
        phdrs.append(phdr)
    result = bytearray(elf)
    result.extend(bytes(-len(result) % 4))
    offset = len(result)
    result.extend(pack)
    result.extend(bytes(-len(result) % 4))
    header[5] = len(result)
    phdrs.append(struct.pack('<8I', 1, offset, address, address, len(pack), len(pack), 4, 4))
    header[10] = len(phdrs)
    result.extend(b''.join(phdrs))
    struct.pack_into('<16sHHIIIIIHHHHHH', result, 0, *header)
    return bytes(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('elf', type=Path)
    parser.add_argument('games', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_bytes(pack_elf(args.elf.read_bytes(), build_pack(args.games)))


if __name__ == '__main__':
    main()
