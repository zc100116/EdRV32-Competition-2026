# File: elf_fixture.py
# Spec: edrv32-soc-spec 7.5(3a); Task B1-10.
# Description: Independent ELF32 fixture with distinct VMA/LMA, BSS and non-load headers.
# Clock domain: none (host test).
import struct

ENTRY = 0x80000100
SEGMENTS = [(0x80000100, bytes(range(256)) * 33 + b'\x0a\x0d\x00'),
            (0x10000203, b'initial data\x00\xff')]
ROM_SLOT_VMA = 0x90003080
ROM_SLOT_PHYSICAL = 0x10003080
ROM_SLOT_SIZE = 1024 * 1024


def elf_fixture(rom_slot=False):
    count = 4
    offset = 52 + count * 32
    headers = []
    payload = bytearray()
    for index, (address, data) in enumerate(SEGMENTS):
        headers.append(struct.pack('<IIIIIIII', 1, offset + len(payload),
                                   address + 0x1000, address, len(data), len(data) + 16, 5, 4))
        payload.extend(data)
    headers.append(struct.pack('<IIIIIIII', 1, 0,
                               ROM_SLOT_VMA - 128 if rom_slot else 0x10001000,
                               ROM_SLOT_PHYSICAL - 128 if rom_slot else 0x10001000,
                               0, 128 + (ROM_SLOT_SIZE if rom_slot else 0), 6, 4))
    headers.append(struct.pack('<IIIIIIII', 4, 0, 0, 0, 4, 4, 0, 4))
    ident = b'\x7fELF\x01\x01\x01' + bytes(9)
    sections = b''
    if rom_slot:
        names = b'\0nes_rom_slot\0nes_rom_slot_end\0'
        names_offset = offset + len(payload)
        payload.extend(names)
        symbols_offset = offset + len(payload)
        symbols = bytes(16) + struct.pack('<IIIBBH', 1, ROM_SLOT_VMA, ROM_SLOT_SIZE, 17, 0, 3)
        symbols += struct.pack('<IIIBBH', 14, ROM_SLOT_VMA + ROM_SLOT_SIZE, 0, 16, 0, 3)
        payload.extend(symbols)
        sections = bytes(40)
        sections += struct.pack('<IIIIIIIIII', 0, 3, 0, 0, names_offset, len(names), 0, 0, 1, 0)
        sections += struct.pack('<IIIIIIIIII', 0, 2, 0, 0, symbols_offset, len(symbols),
                                1, 1, 4, 16)
        sections += struct.pack('<IIIIIIIIII', 0, 8, 3, ROM_SLOT_VMA, 0, ROM_SLOT_SIZE,
                                0, 0, 64, 0)
    header = struct.pack('<16sHHIIIIIHHHHHH', ident, 2, 243, 1, ENTRY, 52,
                         offset + len(payload) if rom_slot else 0, 0,
                         52, 32, count, 40 if rom_slot else 0, 4 if rom_slot else 0, 0)
    return header + b''.join(headers) + payload + sections


def expected_steps(baud=2000000, rom=None):
    steps = []
    if baud != 115200:
        steps += [(b'4\r', b'Baud:\r\n'),
                  (f'{baud}\r'.encode(), f'Baud result: {baud}\r\n'.encode())]
    segments = SEGMENTS + ([(ROM_SLOT_PHYSICAL, rom)] if rom is not None else [])
    descriptor = struct.pack('<II', len(segments), ENTRY)
    descriptor += b''.join(struct.pack('<II', address, len(data)) for address, data in segments)
    payload = descriptor + b''.join(data for _, data in segments)
    total = sum(len(data) for _, data in segments)
    steps += [(b'1\r', b'UART load ready\r\n'),
              (payload, f'Load bytes: {total} segments: {len(segments)}\r\n'
               f'Load result: PASS\r\nRun: 0x{ENTRY:08x}\r\n'.encode())]
    return steps
