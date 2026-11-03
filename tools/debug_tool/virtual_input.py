#!/usr/bin/env python3
"""Task T-VIN1: send timed UDP frames using the GUI sender."""
import argparse
import socket
import time
from core.ethernet import packets
from core.virtual_input import KEYS, VirtualInput


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--udp', required=True, help='destination IP:port')
    parser.add_argument('--keys', default='', help='comma separated: ' + ','.join(KEYS))
    parser.add_argument('--x', type=int, default=0)
    parser.add_argument('--y', type=int, default=0)
    parser.add_argument('--mouse', type=int, default=0)
    parser.add_argument('--wheel', type=int, default=0, help='cumulative wheel count, down positive')
    parser.add_argument('--hold', type=float, default=.2, help='hold duration in seconds')
    args = parser.parse_args()
    keys = sum(1 << KEYS.index(key) for key in args.keys.split(',') if key)
    host, port = args.udp.rsplit(':', 1)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        run(lambda frame: sock.sendto(next(packets(frame, 2, 0)), (host, int(port))),
            args, keys)


def run(send, args, keys):
    controller = VirtualInput(send)
    try:
        controller.update(keys, args.x, args.y, args.mouse, args.wheel)
        time.sleep(args.hold)
        controller.update(0, args.x, args.y, 0)
    finally:
        controller.close()


if __name__ == '__main__':
    main()
