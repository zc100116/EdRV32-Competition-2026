#!/usr/bin/env python3
# File: eth_ref.py
# Spec: eth 2.1-2.6, 4.3.
# Description: Independent Ethernet/ARP/IPv4/UDP framing and ordered receive reference.
# Clock domain: none (host reference).
"""Frames exclude preamble/SFD; frame() includes the little-endian Ethernet FCS."""
from dataclasses import dataclass, field
import struct
import zlib

LOCAL_MAC = bytes.fromhex('020000000001')
PEER_MAC = bytes.fromhex('020000000002')
LOCAL_IP = bytes([192, 168, 1, 10])
PEER_IP = bytes([192, 168, 1, 20])
RX_PORT = 5000
TX_PORT = 6000


def checksum(data):
    data += b'\0' * (len(data) % 2)
    total = sum(struct.unpack('!' + 'H' * (len(data) // 2), data))
    while total >> 16:
        total = (total & 0xffff) + (total >> 16)
    return (~total) & 0xffff


def frame(body):
    body = body.ljust(60, b'\0')
    return body + struct.pack('<I', zlib.crc32(body))


def application(win, notify, offset):
    return struct.pack('!BBHI', win, int(notify), 0, offset & 0xffffffff)


def udp(data=b'', *, win=0, notify=False, offset=0, ident=0, src_mac=PEER_MAC,
        dst_mac=LOCAL_MAC, src_ip=PEER_IP, dst_ip=LOCAL_IP, src_port=TX_PORT,
        dst_port=RX_PORT, udp_checksum=False, **ip_fields):
    payload = application(win, notify, offset) + data
    header = struct.pack('!HHHH', src_port, dst_port, len(payload) + 8, 0)
    if udp_checksum:
        pseudo = src_ip + dst_ip + struct.pack('!BBH', 0, 17, len(header + payload))
        value = checksum(pseudo + header + payload) or 0xffff
        header = header[:6] + struct.pack('!H', value)
    ip = struct.pack('!BBHHHBBH4s4s', ip_fields.get('vihl', 0x45), 0,
                     len(header + payload) + 20, ident,
                     ip_fields.get('fragment', 0x4000), 64,
                     ip_fields.get('protocol', 17), 0, src_ip, dst_ip)
    ip = ip[:10] + struct.pack('!H', checksum(ip)) + ip[12:]
    return frame(dst_mac + src_mac + b'\x08\x00' + ip + header + payload)


def arp(*, src_mac=PEER_MAC, dst_mac=b'\xff' * 6, src_ip=PEER_IP,
        target_mac=b'\0' * 6, target_ip=LOCAL_IP, oper=1, htype=1,
        ptype=0x0800, hlen=6, plen=4):
    body = struct.pack('!HHBBH', htype, ptype, hlen, plen, oper)
    body += src_mac + src_ip + target_mac + target_ip
    return frame(dst_mac + src_mac + b'\x08\x06' + body)


def replace(packet, offset, value, *, fix_ip=False):
    body = bytearray(packet[:-4])
    body[offset:offset + len(value)] = value
    if fix_ip:
        body[24:26] = b'\0\0'
        body[24:26] = struct.pack('!H', checksum(bytes(body[14:34])))
    return bytes(body) + struct.pack('<I', zlib.crc32(body))


@dataclass
class Window:
    base: int
    size: int
    count: int = 0


@dataclass
class Reference:
    windows: list = field(default_factory=lambda: [Window(0x10000 + i * 0x10000, 8192)
                                                 for i in range(4)])
    mac: bytes = LOCAL_MAC
    ip: bytes = LOCAL_IP
    port: int = RX_PORT
    enable: bool = True
    error: bool = False
    perf: list = field(default_factory=lambda: [0] * 16)
    memory: dict = field(default_factory=dict)
    peer: tuple = (b'\0' * 6, b'\0' * 4, 0)
    notify: int = 0
    ident: int = 0
    arp_pending: bool = False

    def receive(self, packet, *, rx_er=False, space=True):
        """Apply 2.2 in order; completion effects represent all B responses returned."""
        self.perf[0] = (self.perf[0] + 1) & 0xffffffff
        if not self.enable or self.error:
            return 'disabled', None
        drop = None
        if (rx_er or not 64 <= len(packet) <= 1518
                or zlib.crc32(packet[:-4]) != int.from_bytes(packet[-4:], 'little')):
            drop = 3
        else:
            body = packet[:-4]
            ethertype = body[12:14]
            if not (body[:6] == self.mac or
                    (body[:6] == b'\xff' * 6 and ethertype == b'\x08\x06')):
                drop = 5
            elif ethertype == b'\x08\x06':
                if (body[14:22] != bytes.fromhex('0001080006040001')
                        or body[38:42] != self.ip or self.arp_pending):
                    drop = 5
                else:
                    reply = arp(src_mac=self.mac, dst_mac=body[22:28], src_ip=self.ip,
                                target_mac=body[22:28], target_ip=body[28:32], oper=2)
                    self.arp_pending = True
                    return 'arp', reply
            elif (ethertype != b'\x08\x00' or body[14] != 0x45
                  or int.from_bytes(body[20:22], 'big') & 0x3fff or body[23] != 17
                  or body[30:34] != self.ip
                  or int.from_bytes(body[16:18], 'big') > len(body) - 14):
                drop = 5
            else:
                ip_length = int.from_bytes(body[16:18], 'big')
                udp_length = int.from_bytes(body[38:40], 'big')
                pseudo = body[26:34] + struct.pack('!BBH', 0, 17, udp_length)
                if (checksum(body[14:34]) != 0 or
                        (body[40:42] != b'\0\0' and
                         checksum(pseudo + body[34:34 + udp_length]) != 0)):
                    drop = 4
                elif (int.from_bytes(body[36:38], 'big') != self.port
                      or udp_length != ip_length - 20 or udp_length < 16):
                    drop = 5
                else:
                    win = body[42] & 3
                    notify = body[43] & 1
                    offset = int.from_bytes(body[46:50], 'big')
                    data = body[50:34 + udp_length]
                    window = self.windows[win]
                    if window.size == 0 or offset + len(data) > window.size:
                        drop = 6
                    elif not space:
                        drop = 7
                    else:
                        for i, value in enumerate(data):
                            self.memory[window.base + offset + i] = value
                        window.count = (window.count + len(data)) & 0xffffffff
                        self.perf[1] = (self.perf[1] + 1) & 0xffffffff
                        self.perf[2] = (self.perf[2] + len(data)) & 0xffffffff
                        self.peer = (body[6:12], body[26:30],
                                     int.from_bytes(body[34:36], 'big'))
                        if notify:
                            self.notify |= 1 << (8 + win)
                        return 'write', (window.base + offset, data)
        self.perf[drop] = (self.perf[drop] + 1) & 0xffffffff
        return f'perf{drop}', None

    def transmit(self, words, memory, *, dst_mac=PEER_MAC, dst_ip=PEER_IP,
                 src_port=RX_PORT, dst_port=TX_PORT):
        source = words[0] & 0xffffffe0
        length = words[1] & 0xffffff
        packets = []
        for offset in range(0, max(1, length), 1024):
            size = min(1024, length - offset)
            data = bytes(memory[source + offset + i] for i in range(size))
            packets.append(udp(data, win=words[2] & 3,
                               notify=bool(words[2] & 0x100) and offset + size == length,
                               offset=words[3] + offset, ident=self.ident,
                               src_mac=self.mac, dst_mac=dst_mac, src_ip=self.ip,
                               dst_ip=dst_ip, src_port=src_port, dst_port=dst_port))
            self.ident = (self.ident + 1) & 0xffff
        self.perf[10] += len(packets)
        return packets

    def arp_sent(self):
        self.arp_pending = False
        self.perf[8] = (self.perf[8] + 1) & 0xffffffff
