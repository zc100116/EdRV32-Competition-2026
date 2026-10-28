#!/usr/bin/env python3
# File: uart_tool.py
# Spec: board-plan B1-5; sw/boot/README.md UART download protocol.
# Description: Optionally send an objcopy SRAM binary after the bootloader ready line, then
#              log UART. Optionally select a monitor menu item and enter the CoreMark
#              iteration count; emit the identical download bytes for simulation.
# Clock domain: none (Windows host tool).
"""Download a make-generated SRAM .bin (optional) over 115200 8N1, then capture UART until Ctrl-C."""
import argparse
from pathlib import Path
import struct
import sys


def wire_bytes(image):
    payload = image.read_bytes()
    return struct.pack('<I', len(payload)) + payload


def capture(port, image, log, menu, iterations):
    import serial

    ready = b'UART download ready\r\n'
    prompt = b'Menu: 1=CoreMark 2=Peripheral tests 3=System info\r\n'
    asked = b'Iterations input'
    pending = wire_bytes(image) if image else b''
    # A selection is one line; for CoreMark an empty count line selects the monitor default.
    selection = (menu + '\r').encode('ascii') if menu else b''
    count = ((str(iterations) if iterations else '') + '\r').encode('ascii') if menu == '1' else b''
    tail = b''
    log.parent.mkdir(parents=True, exist_ok=True)
    with serial.Serial(port, 115200) as uart, log.open('wb') as output:
        while True:
            data = uart.read(max(1, uart.in_waiting))
            output.write(data)
            output.flush()
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            tail += data
            if pending and ready in tail:
                uart.write(pending)
                uart.flush()
                pending = b''
            if selection and prompt in tail:
                uart.write(selection)
                uart.flush()
                selection = b''
                tail = b''
            if count and not selection and asked in tail:
                uart.write(count)
                uart.flush()
                count = b''
            tail = tail[-len(prompt):]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path, nargs='?',
                        help='build/sw/<program>/<program>.bin (ELF objcopy); omit to only log')
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument('--port', help='Windows serial port, e.g. COM3')
    destination.add_argument('--emit', type=Path, help='write length+payload bytes instead of serial I/O')
    parser.add_argument('--log', type=Path, default=Path('build/board/uart.log'))
    parser.add_argument('--menu', choices=('1', '2', '3'), help='select once after the monitor menu')
    parser.add_argument('--iterations', type=int, help='CoreMark iterations entered after --menu 1')
    args = parser.parse_args()
    if args.iterations and args.menu != '1':
        parser.error('--iterations requires --menu 1')
    if args.emit and not args.image:
        parser.error('--emit requires an image')
    if args.emit:
        args.emit.parent.mkdir(parents=True, exist_ok=True)
        args.emit.write_bytes(wire_bytes(args.image))
    else:
        try:
            capture(args.port, args.image, args.log, args.menu, args.iterations)
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
