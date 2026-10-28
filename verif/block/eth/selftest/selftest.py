#!/usr/bin/env python3
# File: selftest.py
# Spec: eth 2.1-2.6; V-T5 model selftest.
# Description: Checks hand-derived ARP, checksum/FCS, window and segmentation vectors.
# Clock domain: none (host test).
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True

BASE = Path(__file__).resolve().parents[1]
ROOT = BASE.parents[2]
sys.path.insert(0, str(BASE))
from eth_ref import Reference, arp, checksum, udp  # noqa: E402


def equal(name, expected, actual):
    if actual != expected:
        raise AssertionError(f'FAIL {name} expected={expected!r} actual={actual!r} time=host')


def main():
    ref = Reference()
    request = arp()
    equal('ARP request fields',
          'ffffffffffff02000000000208060001080006040001020000000002c0a80114'
          '000000000000c0a8010a' + '00' * 18, request[:-4].hex())
    action, reply = ref.receive(request)
    equal('ARP decision', 'arp', action)
    equal('ARP reply fields',
          '02000000000202000000000108060001080006040002020000000001c0a8010a'
          '020000000002c0a80114' + '00' * 18, reply[:-4].hex())
    packet = udp()
    # IPv4 words: 4500+0024+0000+4000+4011+c0a8+0114+c0a8+010a
    # fold = 48a5, ones complement = b75a. FCS is a separately fixed wire vector.
    equal('minimum UDP IPv4 checksum', 'b75a', packet[24:26].hex())
    equal('minimum UDP FCS', 'b4003fa5', packet[-4:].hex())
    equal('minimum UDP frame length', 64, len(packet))
    equal('IPv4 checksum verification', 0, checksum(packet[14:34]))
    ref.windows[0].size = 32
    equal('window exact end', 'write', ref.receive(udp(b'Z', offset=31))[0])
    equal('window beyond end', 'perf6', ref.receive(udp(b'Z', offset=32))[0])
    equal('33-bit overflow', 'perf6', ref.receive(udp(b'ZZ', offset=0xffffffff))[0])
    equal('window byte address', ord('Z'), ref.memory[0x1001f])
    equal('window count', 1, ref.windows[0].count)
    memory = {0x20000+i: i & 255 for i in range(1025)}
    packets = ref.transmit([0x2001f, 1025, 0x103, 7, 0, 0, 0, 0], memory)
    equal('LEN1025 packet count', 2, len(packets))
    equal('first app header', '0300000000000007', packets[0][42:50].hex())
    equal('last app header', '0301000000000407', packets[1][42:50].hex())
    equal('first data', bytes(i & 255 for i in range(1024)), packets[0][50:1074])
    equal('last data', 0, packets[1][50])
    equal('identifiers', (0, 1), tuple(int.from_bytes(p[18:20], 'big') for p in packets))
    equal('receive counters PERF0/1/2/6', (4, 1, 1, 2),
          tuple(ref.perf[i] for i in [0, 1, 2, 6]))
    equal('send counter PERF10', 2, ref.perf[10])
    out = ROOT / 'build/eth/selftest'
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                    '--top-module', 'eth_selftest', '--Mdir', str(out / 'obj'),
                    '-o', 'sim', str(BASE / 'lint.vlt'),
                    str(ROOT / 'verif/common/edrv32_axi256_if.sv'),
                    str(ROOT / 'verif/common/edrv32_axi256_checker.sv'),
                    str(ROOT / 'verif/models/eth_peer_model.sv'),
                    str(BASE / 'edrv32_eth_memory.sv'),
                    str(BASE / 'edrv32_eth_phy.sv'),
                    str(Path(__file__).with_name('eth_models_selftest.sv')),
                    str(Path(__file__).with_name('eth_selftest.sv'))], check=True)
    subprocess.run([str(out / 'obj/sim')], check=True)
    print('PASS ETH reference selftest')


if __name__ == '__main__':
    main()
