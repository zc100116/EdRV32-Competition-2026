#!/usr/bin/env python3
# File: run.py
# Spec: edrv32-soc-spec 7.5(3a); T-BIOS2 acceptance.
# Description: Build actual BIOS and multi-segment DDR ELF, drive UART and ETH front doors.
# Clock domain: host.
from pathlib import Path
import struct
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.board.uart_tool import descriptor_bytes, elf_segments, eth_packets
from tools.regress import expand_files
from verif.soc.common.network import checksum
from verif.soc.common.run import command
from tools.fpga.mem_init import pack_image

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/sc_bios_eth'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    command(['make', '-C', 'sw', 'PROGRAM=bootloader', '-j', '1'], OUT / 'boot.log')
    command(['make', '-C', 'sw', 'PROGRAM=bios_app', 'MEMORY=ddr', '-j', '1',
             'PROGRAM_SOURCES=verif/soc/sc_bios_eth/app.c sw/drivers/uart.c',
             'CFLAGS_EXTRA=-I' + str(ROOT / 'sw/drivers/include')], OUT / 'app.log')
    entry, segments = elf_segments(ROOT / 'build/sw/bios_app/bios_app.elf')
    segments.append((0x10000000, struct.pack('<I', 0xdecaf123)))
    descriptor = descriptor_bytes(entry, segments)
    (OUT / 'bios_uart.bin').write_bytes(descriptor + b''.join(p for _, p in segments))
    arp_reply = bytes.fromhex('02000000000202454452563208060001080006040002'
                              '024544525632c0a8010a020000000002c0a80102')
    # common/eth_stimulus.svh checks all reply bytes; eth_peer_model checks its FCS.
    (OUT / 'arp.bin').write_bytes(arp_reply + bytes(60 - len(arp_reply)))
    with (OUT / 'bios_rx.bin').open('wb') as stream:
        for packet in eth_packets(entry, segments):
            udp = struct.pack('!HHHH', 6000, 5000, len(packet) + 8, 0) + packet
            ip = struct.pack('!BBHHHBBH4s4s', 0x45, 0, len(udp) + 20, 0, 0x4000,
                             64, 17, 0, bytes((192, 168, 1, 2)), bytes((192, 168, 1, 10)))
            ip = ip[:10] + struct.pack('!H', checksum(ip)) + ip[12:]
            frame = bytes.fromhex('0245445256320200000000020800') + ip + udp
            frame += bytes(max(0, 60 - len(frame)))
            stream.write(struct.pack('<I', len(frame)) + frame)
    pack_image(ROOT / 'build/sw/bootloader/rom.hex', 2048, OUT / 'rom.hex')
    files = expand_files(HERE / 'files.f')
    command(['python3', 'verif/soc/common/check_style.py'], OUT / 'style.log')
    flags = ['--timing', '-Wall', '+define+SIM_MODE', '--top-module', 'edrv32_soc_tb']
    command(['verilator', '--lint-only'] + flags + files, OUT / 'lint.log')
    obj = OUT / 'obj'
    command(['verilator', '--binary', '-j', '1', '--output-split', '10000',
             '--output-split-cfuncs', '100', '-CFLAGS', '-O1', '--Mdir', str(obj),
             '-o', 'sim'] + flags + files, OUT / 'compile.log')
    for name, extra in [('uart', ['+BIOS_UART=1']), ('eth', []),
                        ('eth_retry', ['+BIOS_RETRY=1'])]:
        log = OUT / f'{name}.log'
        # Keep retry's omit-first-UDP test unchanged; prepend ARP for the full session.
        if name == 'eth':
            image_frames = (OUT / 'bios_rx.bin').read_bytes()
            arp = bytes.fromhex('ffffffffffff02000000000208060001080006040001'
                                '020000000002c0a80102000000000000c0a8010a')
            arp += bytes(60 - len(arp))
            (OUT / 'bios_rx.bin').write_bytes(struct.pack('<I', len(arp)) + arp + image_frames)
        elif name == 'eth_retry':
            (OUT / 'bios_rx.bin').write_bytes(image_frames)
        command([str(obj / 'sim'), '+CASE=18', '+DATA_DIR=' + str(OUT),
                 '+ROM_HEX=' + str(OUT / 'rom.hex')] + extra, log)
        text = log.read_text()
        for marker in ('Load result: PASS', 'BIOS application PASS', 'PASS SC-18'):
            if marker not in text:
                raise RuntimeError(f'{name}: missing {marker}')
        if name == 'eth_retry':
            ddr_bytes = sum(len(data) for addr, data in segments if addr >= 0x80000000)
            stage_bytes = len(descriptor) + 4
            failure = (f'ETH load result: FAIL bytes win2={ddr_bytes - len(segments[0][1])}'
                       f' expect={ddr_bytes} win3={stage_bytes} expect={stage_bytes}')
            if failure not in text:
                raise RuntimeError(f'retry: expected {failure}')
        if name == 'eth' and 'CHECK ETH ARP reply' not in text:
            raise RuntimeError(f'{name}: missing checked BIOS ARP reply')
        print(f'PASS BIOS {name}: automatic DDR entry and SRAM segment', flush=True)


if __name__ == '__main__':
    main()
