#!/usr/bin/env python3
# File: run.py
# Spec: gpu-soc-testplan ST-13; visual SC-06 and BIOS Ethernet load.
# Description: Build a multi-segment ELF, prepare real ETH boot traffic and RX regression.
# Clock domain: host.
from pathlib import Path
import struct
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.board.uart_tool import elf_segments, eth_packets
from verif.soc.common.network import checksum, prepare_network
from verif.soc.gpu_common.run import run

HERE = Path(__file__).resolve().parent
out = ROOT / 'build/gpu_soc' / HERE.name
out.mkdir(parents=True, exist_ok=True)
subprocess.run(['make', '-C', 'sw', 'PROGRAM=gpu_eth', 'SOC=gpu', 'MEMORY=sram', '-j1'],
               cwd=ROOT, check=True)
entry, segments = elf_segments(ROOT / 'build/sw/gpu_eth/gpu_eth.elf')
segments.append((0x80200000, struct.pack('<I', 0x1234abcd)))
# An ARP request primes the real BIOS loader, followed by board-tool download packets.
arp = bytes.fromhex('ffffffffffff02000000000208060001080006040001'
                    '020000000002c0a80102000000000000c0a8010a')
frames = [arp + bytes(60-len(arp))]
for packet in eth_packets(entry, segments):
    udp = struct.pack('!HHHH', 6000, 5000, len(packet)+8, 0) + packet
    ip = struct.pack('!BBHHHBBH4s4s', 0x45, 0, len(udp)+20, 0, 0x4000,
                     64, 17, 0, bytes((192, 168, 1, 2)), bytes((192, 168, 1, 10)))
    ip = ip[:10] + struct.pack('!H', checksum(ip)) + ip[12:]
    frame = bytes.fromhex('0245445256320200000000020800') + ip + udp
    frames.append(frame + bytes(max(0, 60-len(frame))))
with (out / 'bios_rx.bin').open('wb') as stream:
    for frame in frames:
        stream.write(struct.pack('<I', len(frame)) + frame)
prepare_network(out)
run(HERE, 13, bios=True, software_sources='sw/tests/gpu_eth/main.c sw/drivers/uart.c '
    'sw/drivers/plic.c')
