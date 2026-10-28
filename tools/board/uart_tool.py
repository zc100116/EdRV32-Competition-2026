#!/usr/bin/env python3
# File: uart_tool.py
# Spec: board-plan B1-5; sw/boot/README.md UART download protocol.
# Description: Send an objcopy SRAM binary after the bootloader ready line, then log UART.
#              Optionally select a monitor menu item; emit the identical wire bytes for simulation.
# Clock domain: none (Windows host tool).
"""Download a make-generated SRAM .bin over 115200 8N1, then capture UART until Ctrl-C."""
import argparse
from pathlib import Path
import struct
import sys


def wire_bytes(image):
    payload = image.read_bytes()
    return struct.pack('<I', len(payload)) + payload


def capture(port, image, log, menu):
    import serial

    ready = b'UART download ready\r\n'
    prompt = b'Menu: 1=CoreMark 2=Peripheral tests 3=System info\r\n'
    pending = wire_bytes(image)
    selection = (menu + '\r').encode('ascii') if menu else b''
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
            tail = tail[-len(prompt):]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path, help='build/sw/<program>/<program>.bin (ELF objcopy)')
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument('--port', help='Windows serial port, e.g. COM3')
    destination.add_argument('--emit', type=Path, help='write length+payload bytes instead of serial I/O')
    parser.add_argument('--log', type=Path, default=Path('build/board/uart.log'))
    parser.add_argument('--menu', choices=('1', '2', '3'), help='select once after the monitor menu')
    args = parser.parse_args()
    if args.emit:
        args.emit.parent.mkdir(parents=True, exist_ok=True)
        args.emit.write_bytes(wire_bytes(args.image))
    else:
        try:
            capture(args.port, args.image, args.log, args.menu)
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
