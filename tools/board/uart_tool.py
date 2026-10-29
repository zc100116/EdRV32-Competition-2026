#!/usr/bin/env python3
# File: uart_tool.py
# Spec: edrv32-soc-spec 7.5(3a); sw/boot/README.md UART protocol.
# Description: Shared BIOS protocol for SRAM programming and ELF segment loading/run.
#              Capture UART or emit the exact protocol bytes for simulation.
# Clock domain: none (host tool).
"""Program an SRAM .bin or load and run an RV32 ELF through BIOS, then capture UART."""
import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import sys
import threading

BIOS_MENU = 'BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud'
BAUDS = (115200, 921600, 2000000)


def wire_bytes(image):
    payload = image.read_bytes()
    return struct.pack('<I', len(payload)) + payload


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


def load_wire_bytes(address, payload):
    return struct.pack('<II', address, len(payload)) + payload


@dataclass(frozen=True)
class BiosOperation:
    selection: bytes
    ready: str
    payload: bytes
    success: str
    baud: int = 0


def operations(image, elf=False, baud=2000000):
    if not elf:
        return [BiosOperation(b'1\r', 'UART download ready', wire_bytes(image),
                              'Program SRAM result: PASS, press reset to run')]
    entry, segments = elf_segments(image)
    result = []
    if baud not in BAUDS:
        raise ValueError(f'baud must be one of {BAUDS}')
    if baud != 115200:
        result.append(BiosOperation(b'4\r', 'Baud:', f'{baud}\r'.encode(),
                                    f'Baud result: {baud}', baud))
    result.extend(BiosOperation(b'2\r', 'UART load ready', load_wire_bytes(address, payload),
                                'Load result: PASS') for address, payload in segments)
    result.append(BiosOperation(b'3\r', 'Run address:', f'0x{entry:08x}\r'.encode(),
                                f'Run: 0x{entry:08x}'))
    return result


class BiosTransfer:
    """Prompt-driven protocol shared by the board CLI and the desktop serial engine."""
    def __init__(self, write, set_baud):
        self.write = write
        self.set_baud = set_baud
        self.lock = threading.Lock()
        self.state = {'active': False, 'phase': 'idle', 'sent': 0, 'total': 0,
                      'programmedBytes': None, 'result': None, 'error': None}

    def status(self):
        with self.lock:
            return dict(self.state)

    def start(self, path, elf=False, baud=2000000):
        plan = operations(Path(path), elf, baud)
        with self.lock:
            if self.state['active']:
                raise RuntimeError('BIOS programming is already active')
            self.plan = plan
            self.index = 0
            self.state = {'active': True, 'phase': 'wait_menu', 'path': str(path),
                          'sent': 0, 'total': sum(len(op.payload) for op in plan), 'bios': False,
                          'programmedBytes': None, 'result': None, 'error': None}
        return self.status()

    def fail(self, error):
        with self.lock:
            self.state.update(active=False, phase='error', error=str(error))

    def feed_line(self, line):
        action = b''
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
            elif phase == 'wait_result':
                count = re.fullmatch(r'Program SRAM bytes: (\d+)', line)
                load_count = re.fullmatch(r'Load bytes: (\d+) at 0x[0-9a-f]{8}', line)
                if count:
                    self.state['programmedBytes'] = int(count[1])
                elif load_count:
                    self.state['programmedBytes'] = (
                        self.state['programmedBytes'] or 0) + int(load_count[1])
                if line in ('Program SRAM result: FAIL length', 'Load result: FAIL range',
                            'Run result: FAIL address', 'Baud result: FAIL'):
                    self.state.update(active=False, phase='done', result=line)
                elif line == op.success:
                    change_baud = op.baud
                    self.index += 1
                    if self.index == len(self.plan):
                        self.state.update(active=False, phase='done', result=line)
                    else:
                        self.state['phase'] = 'wait_menu'
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


def capture(port, image, log, menu, iterations, elf=False, baud=2000000):
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
            transfer.start(image, elf, baud)
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
                        help='make-generated SRAM .bin, or ELF with --elf; omit to only log')
    parser.add_argument('--elf', action='store_true',
                        help='load PT_LOAD segments, then run ELF entry')
    parser.add_argument('--baud', type=int, choices=BAUDS, default=2000000,
                        help='ELF transfer baud (default 2000000; 115200 skips the switch)')
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
    if (args.emit or args.elf) and not args.image:
        parser.error('--emit and --elf require an image')
    if args.emit:
        args.emit.parent.mkdir(parents=True, exist_ok=True)
        stream = (b''.join(op.selection + op.payload for op in
                           operations(args.image, True, args.baud)) if args.elf
                  else wire_bytes(args.image))
        args.emit.write_bytes(stream)
    else:
        try:
            capture(args.port, args.image, args.log, args.menu, args.iterations,
                    args.elf, args.baud)
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
