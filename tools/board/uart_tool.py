#!/usr/bin/env python3
# File: uart_tool.py
# Spec: edrv32-soc-spec 7.5(3a); sw/boot/README.md UART protocol.
# Description: Shared UART/UDP BIOS session encoding and automatic application entry.
#              Capture UART or emit the exact protocol bytes for simulation.
# Clock domain: none (host tool).
"""Load and run a .bin or RV32 ELF through UART/UDP BIOS, then capture UART."""
import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import socket
import sys
import threading

BIOS_MENU = 'BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud'
BAUDS = (115200, 921600, 2000000)


def descriptor_bytes(entry, segments):
    return struct.pack('<II', len(segments), entry) + b''.join(
        struct.pack('<II', address, len(payload)) for address, payload in segments)


def wire_bytes(image, addr, entry):
    segments = [(addr, image.read_bytes())]
    return descriptor_bytes(entry, segments) + segments[0][1]


def eth_packets(entry, segments):
    """ETH 2.3 / SoC 7.5: data first, descriptor last with NOTIFY."""
    blocks = []
    for address, payload in segments:
        window = 2 if address >= 0x80000000 else 3
        offset = address - 0x80000000 if window == 2 else 0x1000 + address - 0x10000000
        blocks.append((window, offset, payload))
    blocks.append((3, 0, descriptor_bytes(entry, segments)))
    packets = []
    for index, (window, offset, payload) in enumerate(blocks):
        for start in range(0, len(payload), 1464):
            chunk = payload[start:start + 1464]
            notify = int(index == len(blocks) - 1 and start + len(chunk) == len(payload))
            packets.append(struct.pack('!BBHI', window, notify, 0, offset + start) + chunk)
    return tuple(packets)


def elf_segments(image):
    """Return entry and nonempty PT_LOADs at physical (initial-image/LMA) addresses."""
    blob = image.read_bytes()
    if blob[:7] != b'\x7fELF\x01\x01\x01':
        raise ValueError(f'{image}: expected ELF32 little-endian input')
    header = struct.unpack_from('<16sHHIIIIIHHHHHH', blob)
    segments = []
    for index in range(header[10]):
        kind, offset, _vaddr, address, size, _memsz, _flags, _align = struct.unpack_from(
            '<IIIIIIII', blob, header[5] + index * header[9])
        if kind == 1 and size != 0:
            segments.append((address, blob[offset:offset + size]))
    return header[4], segments


def rom_segment(image, rom):
    """Resolve the named ROM slot through its PT_LOAD VMA-to-physical mapping."""
    blob = image.read_bytes()
    header = struct.unpack_from('<16sHHIIIIIHHHHHH', blob)
    sections = [struct.unpack_from('<IIIIIIIIII', blob, header[6] + index * header[11])
                for index in range(header[12])]
    symbols = {}
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        strings = sections[section[6]]
        names = blob[strings[4]:strings[4] + strings[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            name, value, _size, _info, _other, _shndx = struct.unpack_from('<IIIBBH', blob,
                                                                         offset)
            name = names[name:names.index(b'\0', name)].decode()
            if name in ('nes_rom_slot', 'nes_rom_slot_end'):
                symbols[name] = value
    missing = {'nes_rom_slot', 'nes_rom_slot_end'} - symbols.keys()
    if missing:
        raise ValueError(f'{image}: missing ROM slot symbol(s): {", ".join(sorted(missing))}')
    start = symbols['nes_rom_slot']
    end = symbols['nes_rom_slot_end']
    payload = Path(rom).read_bytes()
    if len(payload) > end - start:
        raise ValueError(f'{rom}: ROM is {len(payload)} bytes, exceeds ROM slot '
                         f'size {end - start} bytes')
    for index in range(header[10]):
        kind, _offset, vaddr, address, _size, memsz, _flags, _align = struct.unpack_from(
            '<IIIIIIII', blob, header[5] + index * header[9])
        if kind == 1 and vaddr <= start < end <= vaddr + memsz:
            return address + start - vaddr, payload
    raise ValueError(f'{image}: ROM slot is not covered by a PT_LOAD segment')


@dataclass(frozen=True)
class BiosOperation:
    selection: bytes
    ready: str
    payload: bytes
    success: str
    baud: int = 0
    packets: tuple = ()


def operations(image, elf=False, baud=2000000, rom=None, addr=None, entry=None, eth=False):
    if rom is not None and not elf:
        raise ValueError('--rom requires --elf')
    if elf:
        entry, segments = elf_segments(image)
    else:
        if addr is None or entry is None:
            raise ValueError('.bin requires --addr and --entry')
        segments = [(addr, image.read_bytes())]
    if rom is not None:
        segments.append(rom_segment(image, rom))
    result = []
    if baud not in BAUDS:
        raise ValueError(f'baud must be one of {BAUDS}')
    if baud != 115200:
        result.append(BiosOperation(b'4\r', 'Baud:', f'{baud}\r'.encode(),
                                    f'Baud result: {baud}', baud))
    if eth:
        result.append(BiosOperation(b'2\r', 'ETH load ready 192.168.1.10:5000', b'',
                                    f'Run: 0x{entry:08x}', packets=eth_packets(entry, segments)))
    else:
        payload = descriptor_bytes(entry, segments) + b''.join(data for _, data in segments)
        result.append(BiosOperation(b'1\r', 'UART load ready', payload,
                                    f'Run: 0x{entry:08x}'))
    return result


class BiosTransfer:
    """Prompt-driven protocol shared by the board CLI and the desktop serial engine."""
    def __init__(self, write, set_baud):
        self.write = write
        self.set_baud = set_baud
        self.lock = threading.Lock()
        self.udp = None
        self.state = {'active': False, 'phase': 'idle', 'sent': 0, 'total': 0,
                      'programmedBytes': None, 'result': None, 'error': None}

    def status(self):
        with self.lock:
            return dict(self.state)

    def start(self, path, elf=False, baud=2000000, rom=None, addr=None, entry=None,
              eth=False, local_ip='192.168.1.2'):
        plan = operations(Path(path), elf, baud, rom, addr, entry, eth)
        with self.lock:
            if self.state['active']:
                raise RuntimeError('BIOS programming is already active')
            if eth:
                self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                self.udp.bind((local_ip, 0))
            self.attempt = 0
            self.plan = plan
            self.index = 0
            self.state = {'active': True, 'phase': 'wait_menu', 'path': str(path),
                          'sent': 0, 'total': sum(len(op.payload) + sum(map(len, op.packets))
                                               for op in plan), 'bios': False,
                          'programmedBytes': None, 'result': None, 'error': None}
        # An empty command makes an already-open BIOS menu print its prompt again.
        self.write(b'\r')
        return self.status()

    def close_udp(self):
        if self.udp is not None:
            self.udp.close()
            self.udp = None

    def fail(self, error):
        with self.lock:
            self.state.update(active=False, phase='error', error=str(error))
            self.close_udp()

    def feed_line(self, line):
        action = b''
        packets = ()
        change_baud = 0
        with self.lock:
            if not self.state['active']:
                return
            phase = self.state['phase']
            op = self.plan[self.index]
            if line == 'BIOS: EdRV32':
                self.state['bios'] = True
            if phase == 'wait_menu' and line == BIOS_MENU:
                self.state['phase'] = 'wait_ready'
                action = op.selection
            elif phase == 'wait_ready' and line == op.ready:
                self.state['phase'] = 'wait_result'
                action = op.payload
                packets = op.packets
            elif phase == 'wait_result':
                count = re.fullmatch(r'Load bytes: (\d+) segments: (\d+)', line)
                if count:
                    self.state['programmedBytes'] = int(count[1])
                if line.startswith('ETH load result: FAIL bytes '):
                    if self.attempt == 0:
                        self.attempt = 1
                        packets = op.packets
                        self.state['total'] += sum(map(len, packets))
                    else:
                        self.state.update(active=False, phase='done', result=line)
                        self.close_udp()
                if line in ('Load result: FAIL range',
                            'Run result: FAIL address', 'Baud result: FAIL'):
                    self.state.update(active=False, phase='done', result=line)
                    self.close_udp()
                elif line == op.success:
                    change_baud = op.baud
                    self.index += 1
                    if self.index == len(self.plan):
                        self.state.update(active=False, phase='done', result=line)
                        self.close_udp()
                    else:
                        self.state['phase'] = 'wait_menu'
        for packet in packets:
            self.udp.sendto(packet, ('192.168.1.10', 5000))
            with self.lock:
                self.state['sent'] += len(packet)
        if change_baud:
            self.set_baud(change_baud)
        # The peer produces no result until the complete payload is received.
        # Keep the phase set before writing so a buffered result can be consumed next.
        for offset in range(0, len(action), 4096):
            chunk = action[offset:offset + 4096]
            self.write(chunk)
            if phase == 'wait_ready':
                with self.lock:
                    self.state['sent'] += len(chunk)


def capture(port, image, log, menu, iterations, elf=False, baud=2000000, rom=None,
            addr=None, entry=None, eth=False, local_ip='192.168.1.2'):
    import serial

    prompt = 'Menu: 1=CoreMark 2=Peripheral tests 3=System info'
    selection = (menu + '\r').encode('ascii') if menu else b''
    count = ((str(iterations) if iterations else '') + '\r').encode() if menu == '1' else b''
    pending = bytearray()
    log.parent.mkdir(parents=True, exist_ok=True)
    with serial.Serial(port, 115200) as uart, log.open('wb') as output:
        def write(data):
            uart.write(data)
            uart.flush()

        transfer = BiosTransfer(write, lambda value: setattr(uart, 'baudrate', value))
        if image:
            transfer.start(image, elf, baud, rom, addr, entry, eth, local_ip)
        while True:
            data = uart.read(max(1, uart.in_waiting))
            output.write(data)
            output.flush()
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            pending.extend(data)
            while b'\n' in pending:
                line, _, rest = pending.partition(b'\n')
                pending = bytearray(rest)
                text = line.rstrip(b'\r').decode('ascii', 'replace')
                transfer.feed_line(text)
                result = transfer.status()['result']
                if result and 'FAIL' in result:
                    raise RuntimeError(result)
                if selection and text == prompt:
                    write(selection)
                    selection = b''
                if count and not selection and text.startswith('Iterations input'):
                    write(count)
                    count = b''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path, nargs='?',
                        help='.bin with --addr/--entry, or ELF with --elf; omit to only log')
    parser.add_argument('--elf', action='store_true',
                        help='send one PT_LOAD session and automatically run ELF entry')
    parser.add_argument('--rom', type=Path,
                        help='load an external .nes file into the ELF ROM slot before run')
    parser.add_argument('--baud', type=int, choices=BAUDS, default=2000000,
                        help='transfer baud (default 2000000; 115200 skips the switch)')
    parser.add_argument('--addr', type=lambda value: int(value, 0))
    parser.add_argument('--entry', type=lambda value: int(value, 0))
    parser.add_argument('--eth', action='store_true', help='menu over UART, data over UDP')
    parser.add_argument('--local-ip', default='192.168.1.2', help='bind UDP source address')
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument('--port', help='Windows serial port, e.g. COM3')
    destination.add_argument('--emit', type=Path, help='write protocol bytes instead of serial I/O')
    parser.add_argument('--log', type=Path, default=Path('build/board/uart.log'))
    parser.add_argument('--menu', choices=('1', '2', '3'),
                        help='select once after the monitor menu')
    parser.add_argument('--iterations', type=int, help='CoreMark iterations entered after --menu 1')
    args = parser.parse_args()
    if args.iterations and args.menu != '1':
        parser.error('--iterations requires --menu 1')
    if args.rom is not None and not args.elf:
        parser.error('--rom requires --elf')
    if (args.emit or args.elf) and not args.image:
        parser.error('--emit and --elf require an image')
    if args.emit:
        args.emit.parent.mkdir(parents=True, exist_ok=True)
        if args.eth:
            parser.error('--emit supports the UART stream; --eth requires --port')
        stream = b''.join(op.selection + op.payload for op in operations(
            args.image, args.elf, args.baud, args.rom, args.addr, args.entry))
        args.emit.write_bytes(stream)
    else:
        try:
            capture(args.port, args.image, args.log, args.menu, args.iterations,
                    args.elf, args.baud, args.rom, args.addr, args.entry, args.eth, args.local_ip)
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
