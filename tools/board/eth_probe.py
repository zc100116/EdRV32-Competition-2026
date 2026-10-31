#!/usr/bin/env python3
"""eth_probe.py — eth-spec 2.3/2.4; UDP peer probe, host clock domain.

Bind one explicit PC address, send a control message each second and print replies.
"""

import argparse
from pathlib import Path
import select
import socket
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.debug_tool.core.ethernet import packets


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-ip', default='192.168.1.2')
    parser.add_argument('--board-ip', default='192.168.1.10')
    parser.add_argument('--port', type=int, default=5000)
    parser.add_argument('--listen', type=int, default=6000)
    return parser.parse_args(argv)


def probe(sock, args):
    packet = next(packets(b'\0', 3, 0))
    next_send = time.monotonic()
    while True:
        now = time.monotonic()
        if now >= next_send:
            sock.sendto(packet, (args.board_ip, args.port))
            print(f'TX {args.board_ip}:{args.port} {packet!r}', flush=True)
            next_send = now + 1
        ready, _, _ = select.select([sock], [], [], max(0, next_send - time.monotonic()))
        if ready:
            data, peer = sock.recvfrom(65535)
            print(f'RX {peer[0]}:{peer[1]} {data!r}', flush=True)


def main(argv=None):
    args = arguments(argv)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.local_ip, args.listen))
        print(f'Listening on {args.local_ip}:{args.listen}', flush=True)
        probe(sock, args)


if __name__ == '__main__':
    main()
