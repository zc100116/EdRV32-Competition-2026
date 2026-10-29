# File: elf_fixture.py
# Spec: edrv32-soc-spec 7.5(3a); Task B1-10.
# Description: Independent ELF32 fixture with distinct VMA/LMA, BSS and non-load headers.
# Clock domain: none (host test).
import struct

ENTRY = 0x80000100
SEGMENTS = [(0x80000100, bytes(range(256)) * 33 + b'\x0a\x0d\x00'),
            (0x10000203, b'initial data\x00\xff')]


def elf_fixture():
    count = 4
    offset = 52 + count * 32
    headers = []
    payload = bytearray()
    for index, (address, data) in enumerate(SEGMENTS):
        headers.append(struct.pack('<IIIIIIII', 1, offset + len(payload),
                                   address + 0x1000, address, len(data), len(data) + 16, 5, 4))
        payload.extend(data)
    headers.append(struct.pack('<IIIIIIII', 1, 0, 0x10001000, 0x10001000, 0, 128, 6, 4))
    headers.append(struct.pack('<IIIIIIII', 4, 0, 0, 0, 4, 4, 0, 4))
    ident = b'\x7fELF\x01\x01\x01' + bytes(9)
    header = struct.pack('<16sHHIIIIIHHHHHH', ident, 2, 243, 1, ENTRY, 52, 0, 0,
                         52, 32, count, 0, 0, 0)
    return header + b''.join(headers) + payload


def expected_steps(baud=2000000):
    steps = []
    if baud != 115200:
        steps += [(b'4\r', b'Baud:\r\n'),
                  (f'{baud}\r'.encode(), f'Baud result: {baud}\r\n'.encode())]
    for address, data in SEGMENTS:
        steps += [(b'2\r', b'UART load ready\r\n'),
                  (struct.pack('<II', address, len(data)) + data,
                   f'Load bytes: {len(data)} at 0x{address:08x}\r\n'
                   'Load result: PASS\r\n'.encode())]
    steps += [(b'3\r', b'Run address:\r\n'),
              (f'0x{ENTRY:08x}\r'.encode(), f'Run: 0x{ENTRY:08x}\r\n'.encode())]
    return steps
