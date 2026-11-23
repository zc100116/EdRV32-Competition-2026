#!/usr/bin/env python3
# File: run.py
# Spec: gpu-soc-testplan ST-13; visual SC-06 and BIOS Ethernet load.
# Description: Build a multi-segment ELF, prepare real ETH boot traffic and RX regression.
# Clock domain: host.
from pathlib import Path
import struct
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.board.uart_tool import elf_segments, eth_packets
from verif.soc.common.network import checksum, prepare_network
from tools.regress import expand_files
from tools.fpga.mem_init import pack_image
from verif.soc.common.run import command

HERE = Path(__file__).resolve().parent
out = ROOT / 'build/gpu_soc' / HERE.name
out.mkdir(parents=True, exist_ok=True)
# Only the Boot ROM is preloaded: the application must enter DDR through Ethernet.
command(['make', '-C', 'sw', 'PROGRAM=gpu_eth', 'SOC=gpu', 'MEMORY=ddr', '-j1',
         'ARCH=rv32im_zicsr_zifencei',
         'PROGRAM_SOURCES=sw/tests/gpu_eth/main.c sw/drivers/uart.c sw/drivers/plic.c',
         'CFLAGS_EXTRA=-I' + str(ROOT / 'sw/drivers/include')], out / 'sw_build.log')
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
command(['make', '-C', 'sw', 'PROGRAM=bootloader', 'SOC=gpu', 'MEMORY=rom', '-j1'],
        out / 'boot_build.log')
pack_image(ROOT / 'build/sw/bootloader/rom.hex', 2048, out / 'rom.hex')
files = expand_files(HERE / 'files.f')
flags = ['--timing', '-Wall', '+define+SIM_MODE', '--top-module', 'edrv32_gpu_soc_tb']
command(['python3', 'sw/tests/gpu_drivers/check_style.py'], out / 'style.log')
command(['verilator', '--lint-only'] + flags + files, out / 'lint.log')
command(['verilator', '--binary', '-j', '1', '--output-split', '10000',
         '--output-split-cfuncs', '100', '-CFLAGS', '-O2', '--Mdir', str(out / 'obj'),
         '-o', 'sim'] + flags + files, out / 'compile.log')
command([str(out / 'obj/sim'), '+CASE=13', '+DATA_DIR=' + str(out),
         '+ROM_HEX=' + str(out / 'rom.hex'), '+GPU_PARTIAL=0'], out / 'run.log')
print((out / 'run.log').read_text(), end='')
