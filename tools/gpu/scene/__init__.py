"""scene/__init__.py — gpu-spec 2.2–2.11: DDR and command construction.
Host Python API; no clock domain. Integer fields use their encoded fixed-point units.
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = json.loads((ROOT / 'rtl/include/regs/gpu.json').read_text())
LAYOUTS = {item['name']: item for item in SCHEMA['layouts']}
OPCODES = dict(zip(('SET_MATRIX', 'SET_LIGHT', 'SET_TEX', 'SET_PIXEL', 'SET_TARGET',
                    'CLEAR', 'DRAW_TRI', 'DRAW_QUAD', 'OBJ_STEP', 'TEX_LOAD',
                    'PAL_LOAD', 'RESOLVE'),
                   (1, 2, 3, 4, 5, 16, 32, 33, 34, 48, 49, 64)))
# These fields encode byte addresses/counts with low zero bits omitted in the schema.
BYTE_FIELDS = {'ADDR', 'SRC', 'DST', 'BASE', 'STRIDE', 'OFFSET', 'BYTES'}
SIGNED = {'X', 'Y', 'Z', 'NX', 'NY', 'NZ', 'LX', 'LY', 'LZ', 'LOD_BIAS',
          'PX', 'PY', 'VX', 'VY', 'AX', 'AY', 'TGT_X0', 'TGT_Y0',
          'SC_X0', 'SC_Y0', 'SC_X1', 'SC_Y1', 'VP_X0', 'VP_Y0'}


def pack(layout, **values):
    """Pack one schema record; omitted fields are explicitly encoded as zero."""
    desc = LAYOUTS[layout]
    if layout.startswith('CMD_'):
        values = {'OPCODE': OPCODES[layout[4:]], **values}
    words = [0] * (desc['size'] // 4)
    for field in desc['fields']:
        name, bit, width = field['name'], field['lsb'], field['width']
        value = values.get(name, 0)
        if name in BYTE_FIELDS:
            value >>= bit
        words[int(field['offset'], 0) // 4] |= (value & ((1 << width) - 1)) << bit
    return struct.pack('<' + 'I' * len(words), *words)


def unpack(layout, data):
    """Decode signed fields and restore byte-address units from the canonical layout."""
    desc = LAYOUTS[layout]
    values = {}
    for field in desc['fields']:
        name, bit, width = field['name'], field['lsb'], field['width']
        word = struct.unpack_from('<I', data, int(field['offset'], 0))[0]
        value = (word >> bit) & ((1 << width) - 1)
        if name in SIGNED and value & (1 << (width - 1)):
            value -= 1 << width
        values[name] = value << bit if name in BYTE_FIELDS else value
    return values


class Memory:
    """Contiguous DDR image at an explicit byte base; bus errors may be injected by address."""
    def __init__(self, base, data):
        self.base = base
        self.data = bytearray(data)
        self.read_errors = set()
        self.write_errors = set()

    def read(self, address, size):
        if any(address <= item < address + size for item in self.read_errors):
            raise BusError(f'DDR read error at {address:#x}')
        offset = address - self.base
        return bytes(self.data[offset:offset + size])

    def write(self, address, data):
        if any(address <= item < address + len(data) for item in self.write_errors):
            raise BusError(f'DDR write error at {address:#x}')
        offset = address - self.base
        self.data[offset:offset + len(data)] = data

    def write_hex(self, path):
        """One little-endian 32-bit word per line; origin is provided separately."""
        padded = self.data + bytes((-len(self.data)) % 4)
        Path(path).write_text(''.join(f'{word[0]:08x}\n'
                                    for word in struct.iter_unpack('<I', padded)))

    @classmethod
    def read_hex(cls, path, base):
        return cls(base, b''.join(struct.pack('<I', int(line, 16))
                                  for line in Path(path).read_text().splitlines()))


class BusError(Exception):
    """An injected AXI response error (gpu-spec 6, ERR_CODE 2)."""


class Scene:
    """Allocate records and build a serial command stream; addresses are byte addresses."""
    def __init__(self, base=0x80000000):
        self.memory = Memory(base, b'')
        self.commands = []
        self.registers = []

    def reserve(self, size, alignment=32):
        data = self.memory.data
        data.extend(bytes((-(self.memory.base + len(data))) % alignment))
        address = self.memory.base + len(data)
        data.extend(bytes(size))
        return address

    def blob(self, data, alignment=32):
        address = self.reserve(len(data), alignment)
        self.memory.write(address, data)
        return address

    def records(self, layout, records):
        return self.blob(b''.join(pack(layout, **item) for item in records))

    def matrix(self, values):
        """Sixteen row-major floats, converted to s15.16 using nearest-even."""
        return self.blob(struct.pack('<16i', *(round(v * 65536) for v in values)))

    def texture(self, levels, format, width, height):
        """Interleave row-major mip texels; return DDR source address and DMA byte count."""
        from ..model.layout import interleave_texture
        data = bytearray(interleave_texture(levels, width, height, format))
        data.extend(bytes((-len(data)) % 32))
        return self.blob(data), len(data)

    def command(self, name, **values):
        self.commands.append(pack('CMD_' + name, OPCODE=OPCODES[name], **values))

    def reg(self, name, value):
        """Append a register write; indexed names use e.g. OBJ_TGT0[3]."""
        self.registers.append([name, value])

    def finish(self):
        address = self.blob(b''.join(self.commands), 64)
        return self.registers + [['DESC_BASE', address], ['DESC_COUNT', len(self.commands)],
                                 ['DOORBELL', 1]]

    def export(self, hex_path, registers_path):
        writes = self.finish()
        self.memory.write_hex(hex_path)
        Path(registers_path).write_text(json.dumps(writes, indent=2) + '\n')
        return writes
