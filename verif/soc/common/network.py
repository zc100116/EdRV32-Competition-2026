#!/usr/bin/env python3
# File: network.py
# Spec: eth 2.1-2.5; soc-testplan SC-06.
# Description: Construct independent ARP/IPv4/UDP stimuli with one wrong port and checksum.
# Clock domain: host.
import struct

LOCAL_MAC = bytes.fromhex('020000000001')
PEER_MAC = bytes.fromhex('020000000002')
LOCAL_IP = bytes((192, 168, 1, 100))
PEER_IP = bytes((192, 168, 1, 1))


def checksum(data):
    if len(data) % 2:
        data += b'\0'
    total = sum(struct.unpack('>' + 'H' * (len(data) // 2), data))
    while total >> 16:
        total = (total & 65535) + (total >> 16)
    return (~total) & 65535


def prepare_network(out):
    arp = struct.pack('>HHBBH', 1, 0x0800, 6, 4, 1)
    arp += PEER_MAC + PEER_IP + bytes(6) + LOCAL_IP
    frames = [bytes(6 * [255]) + PEER_MAC + b'\x08\x06' + arp + bytes(18)]
    expected_arp = (PEER_MAC + LOCAL_MAC + b'\x08\x06' +
                    struct.pack('>HHBBH', 1, 0x0800, 6, 4, 2) +
                    LOCAL_MAC + LOCAL_IP + PEER_MAC + PEER_IP + bytes(18))
    (out / 'arp.bin').write_bytes(expected_arp)
    def packet(offset, port=9000, bad_checksum=False, notify=False):
        payload = struct.pack('>BBHI', 2, int(notify), 0, offset)
        payload += bytes(((offset + i) * 73 + 19) & 255 for i in range(1024))
        udp = struct.pack('>HHHH', 9001, port, len(payload) + 8, 0) + payload
        ip = struct.pack('>BBHHHBBH4s4s', 0x45, 0, len(udp) + 20, offset // 1024,
                         0x4000, 64, 17, 0, PEER_IP, LOCAL_IP)
        check = checksum(ip) ^ int(bad_checksum)
        ip = ip[:10] + struct.pack('>H', check) + ip[12:]
        return LOCAL_MAC + PEER_MAC + b'\x08\x00' + ip + udp
    for index in range(64):
        if index == 16:
            frames.append(packet(0, port=9002))
        if index == 32:
            frames.append(packet(0, bad_checksum=True))
        frames.append(packet(index * 1024, notify=index == 63))
    with (out / 'rx.bin').open('wb') as stream:
        for frame in frames:
            stream.write(struct.pack('<I', len(frame)))
            stream.write(frame)
