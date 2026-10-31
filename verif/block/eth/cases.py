# File: cases.py
# Spec: eth-testplan ET-01-16 and sections 4, 6.
# Description: Generates directed and seeded stimuli plus independent exact scoreboards.
# Clock domain: none (host vector generation).
from pathlib import Path
import random
import struct
import zlib

from eth_ref import (LOCAL_IP, LOCAL_MAC, PEER_IP, PEER_MAC, RX_PORT, TX_PORT,
                     Reference, Window, arp, frame, replace, udp)


class Case:
    def __init__(self, root, name, seed=1):
        self.name = name
        self.path = root / name
        self.path.mkdir(parents=True, exist_ok=True)
        self.ref = Reference()
        self.rng = random.Random(seed)
        self.commands = []
        self.frames = 0
        self.memfiles = 0
        self.tx = []
        self.initial = {}
        self.desc_done = 0
        self.irq = 0

    def cmd(self, op, a=0, b=0, c=0, d=0):
        self.commands.append(f'{op} {a & 0xffffffff:x} {b & 0xffffffff:x} '
                             f'{c & 0xffffffff:x} {d & 0xffffffff:x}\n')

    def w(self, addr, value):
        self.cmd('W', addr, value)

    def r(self, addr, value, mask=0xffffffff):
        self.cmd('R', addr, value, mask)

    def poll(self, addr, value, mask=0xffffffff):
        self.cmd('P', addr, value, mask)

    def control(self, field, value):
        self.cmd('T', field, value)

    def configure(self):
        for addr, value in [(0x100, int.from_bytes(LOCAL_MAC[2:], 'big')),
                            (0x104, int.from_bytes(LOCAL_MAC[:2], 'big')),
                            (0x108, int.from_bytes(LOCAL_IP, 'big')), (0x10c, RX_PORT),
                            (0x110, int.from_bytes(PEER_MAC[2:], 'big')),
                            (0x114, int.from_bytes(PEER_MAC[:2], 'big')),
                            (0x118, int.from_bytes(PEER_IP, 'big')),
                            (0x11c, (RX_PORT << 16) | TX_PORT)]:
            self.w(addr, value)
        for n, window in enumerate(self.ref.windows):
            self.window(n, window.base, window.size)
        self.w(4, 1)

    def window(self, index, base, size):
        self.ref.windows[index] = Window(base & ~31, size & 0xffffffff,
                                         self.ref.windows[index].count)
        self.w(0x140 + 16 * index, base)
        self.w(0x144 + 16 * index, size)

    def send(self, packet, *, gap=12, flip=-1, er=-1, trim=0, extend=0,
             evaluate=True, space=True):
        body = packet[:-4]
        (self.path / f'f{self.frames}.txt').write_text(
            f'{len(body)} {gap} {flip} {er} {trim} {extend}\n' + body.hex(' ') + '\n')
        self.cmd('S', self.frames)
        self.frames += 1
        wire = bytearray(b'\x55' * 7 + b'\xd5' + body + struct.pack('<I', zlib.crc32(body)))
        if trim:
            del wire[-trim:]
        wire += b'\0' * extend
        if flip >= 0:
            wire[flip] ^= 1
        if evaluate:
            action, result = self.ref.receive(bytes(wire[8:]), rx_er=er >= 0, space=space)
            if action == 'arp':
                self.tx.append(result[:-4])
            return action, result
        return None, None

    def wait_rx(self, cycles=2048):
        self.cmd('F', self.frames)
        self.cmd('D', cycles)

    def settle(self):
        self.wait_rx()
        self.poll(8, 2, 3)
        self.cmd('D', 32)

    def arp_drain(self):
        self.cmd('X', len(self.tx))
        self.ref.arp_sent()

    def memory_file(self, memory, check=False):
        index = self.memfiles
        self.memfiles += 1
        with (self.path / f'm{index}.txt').open('w') as output:
            output.write(f'{len(memory)}\n')
            output.writelines(f'{address:x} {value:02x}\n' for address, value in memory.items())
        self.cmd('C' if check else 'L', index)

    def preload(self, address, data):
        memory = {address + i: value for i, value in enumerate(data)}
        self.initial.update(memory)
        self.memory_file(memory)

    def descriptors(self, lengths, *, notify=True, random_ignored=True, random_fields=False):
        memory = {}
        descriptor_bytes = bytearray()
        packets = []
        for index, length in enumerate(lengths):
            base = 0x800000 + index * 0x400000
            if random_fields:
                base += self.rng.randrange(0, 4096, 32)
            data = (self.rng.randbytes(length) if random_fields else
                    bytes((i * 29 + index * 7 + 1) & 255 for i in range(length)))
            memory.update({base + i: value for i, value in enumerate(data)})
            words = [base | (31 if random_ignored else 0),
                     length | (0xa5000000 if random_ignored else 0),
                     (index & 3) | (0x100 if notify else 0), 0x17 + index * 10000,
                     *[self.rng.getrandbits(32) for _ in range(4)]]
            if random_fields:
                words[0] = base | self.rng.randrange(32)
                words[2] = self.rng.randrange(4) | (self.rng.randrange(2) << 8)
                words[3] = self.rng.getrandbits(32)
            if random_ignored:
                words[2] |= self.rng.getrandbits(32) & ~0x103
            descriptor_bytes.extend(struct.pack('<8I', *words))
            packets.extend(self.ref.transmit(words, memory))
        memory.update({0x1000 + i: value for i, value in enumerate(descriptor_bytes)})
        self.initial.update(memory)
        self.memory_file(memory)
        self.w(0x20, 0x101f)
        self.w(0x24, len(lengths))
        self.ref.perf[9] = 0
        self.ref.perf[10] = len(packets)
        return packets

    def start(self, packets):
        self.tx.extend(packet[:-4] for packet in packets)
        self.w(0x28, 0xdeadbeef)

    def finish_tx(self, count):
        self.cmd('X', len(self.tx))
        self.poll(0x10, 1, 1)
        self.poll(8, 2, 3)
        self.desc_done += count
        self.r(0x2c, self.desc_done)
        self.r(0x130, count)
        self.irq |= 1
        self.cmd('E', 1)

    def snapshot(self, *, counters=True, memory=True, peer=True, notify=True):
        if memory:
            expected = self.initial | self.ref.memory
            # The byte RAM also checks all actual writes, including any stray address.
            for window in self.ref.windows:
                for address in range(window.base - 32, window.base + window.size + 32):
                    expected.setdefault(address, 0xa5)
            self.memory_file(expected, check=True)
        for n, window in enumerate(self.ref.windows):
            self.r(0x148 + n * 16, window.count)
        if counters:
            for n in list(range(9)) + list(range(10, 16)):
                self.r(0x40 + n * 4, self.ref.perf[n])
        if peer:
            mac, ip, port = self.ref.peer
            self.r(0x120, int.from_bytes(mac[2:], 'big'))
            self.r(0x124, int.from_bytes(mac[:2], 'big'))
            self.r(0x128, int.from_bytes(ip, 'big'))
            self.r(0x12c, port)
        if notify:
            self.r(0x10, self.irq | self.ref.notify)

    def save(self):
        (self.path / 'script.txt').write_text(''.join(self.commands))
        with (self.path / 'expected.txt').open('w') as output:
            output.write(f'{len(self.tx)}\n')
            for packet in self.tx:
                wire_frame = packet + struct.pack('<I', zlib.crc32(packet))
                output.write(f'{len(wire_frame)}\n{wire_frame.hex(" ")}\n')
        return self.name, self.path


def et01(root):
    case = Case(root, 'ET-01')
    case.configure()
    for i, length in enumerate([0, 1, 31, 32, 33, 1464, 17, 99]):
        case.send(udp(bytes((j + i) & 255 for j in range(length)),
                      win=i % 4, offset=[3000, 3, 127, 33, 1, 4000, 90, 300][i]))
        case.wait_rx()
    case.send(udp(b'repeat-one', offset=3))
    case.wait_rx()
    case.send(udp(b'repeat-two', offset=3))
    # WIN upper bits, FLAGS upper bits and reserved application bytes are ignored.
    packet = udp(b'ignored-bits', win=0xfc, offset=51)
    case.send(replace(packet, 43, b'\xfe\x12\x34'))
    case.settle()
    case.snapshot()
    return [case.save()]


def et02(root):
    case = Case(root, 'ET-02')
    case.configure()
    case.window(0, 0x1001f, 32)
    case.window(1, 0x20000, 0)
    for packet in [udp(b'X', offset=31), udp(b'X', offset=32),
                   udp(offset=32), udp(win=1), udp(b'AB', offset=0xffffffff)]:
        case.send(packet)
        case.wait_rx()
    case.settle()
    case.snapshot()
    case.w(0x148, 0xffffffff)
    case.ref.windows[0].count = 0
    case.snapshot()
    return [case.save()]


def et03(root):
    case = Case(root, 'ET-03')
    case.configure()
    case.w(4, 0)
    case.ref.enable = False
    case.send(udp(b'disabled'))
    case.wait_rx()
    case.w(4, 1)
    case.ref.enable = True
    case.send(udp(b'bad-fcs'), flip=8 + 63)
    case.send(udp(b'bad-rxer'), er=30)
    case.send(udp(), trim=1)
    case.send(frame(udp()[:-4].ljust(1515, b'\0')))
    case.send(udp(dst_mac=PEER_MAC))
    case.send(udp(dst_mac=b'\xff' * 6))
    case.settle()
    case.snapshot()
    # ERROR=1 coverage is created via the specified write-SLVERR mechanism in ET-11.
    return [case.save()]


def et04(root):
    case = Case(root, 'ET-04')
    case.configure()
    packets = [udp(vihl=0x65), udp(vihl=0x46), udp(fragment=0x2000),
               udp(fragment=1), udp(protocol=1), udp(dst_ip=PEER_IP),
               replace(udp(), 16, b'\x01\x00', fix_ip=True),
               replace(udp(), 24, b'\x00\x00'),
               replace(udp(b'checksum', udp_checksum=True), 50, b'!'),
               udp(b'zero-checksum'), udp(b'nonzero-checksum', udp_checksum=True),
               udp(dst_port=RX_PORT + 1), replace(udp(), 38, b'\x00\x11'),
               replace(udp(), 38, b'\x00\x0f'), udp(b'Z')]
    for packet in packets:
        case.send(packet)
        case.wait_rx()
    case.settle()
    case.snapshot()
    return [case.save()]


def et05(root):
    case = Case(root, 'ET-05')
    case.configure()
    case.w(0xc, 0xf00)
    case.control(2, 400)
    for win in range(4):
        case.control(4, 1)
        case.send(udp(b'prior-data', win=(win + 1) % 4, offset=win * 64))
        case.send(udp(b'last-data' if win < 3 else b'', win=win, notify=True,
                      offset=win * 64 + 17))
        case.wait_rx(512)
        case.cmd('Q', 1 << (8 + win))
        case.cmd('I', 0)
        case.control(4, 0)
        case.cmd('N', 1 << (8 + win), 1)
        case.settle()
        case.snapshot()
        case.w(0x10, 1 << (8 + win))
        case.ref.notify = 0
        case.cmd('I', 0)
    return [case.save()]


def et06(root):
    case = Case(root, 'ET-06')
    case.configure()
    for i in range(3):
        case.send(udp(b'peer', src_mac=bytes([2, 3, 4, 5, 6, i]),
                      src_ip=bytes([10, 20, 30, i]), src_port=1200 + i))
        case.settle()
        case.snapshot()
        case.send(udp(b'drop', src_port=999, dst_port=RX_PORT + 1))
        case.settle()
        case.snapshot()
    return [case.save()]


def et07(root):
    case = Case(root, 'ET-07-fields')
    case.configure()
    for packet in [arp(), arp(dst_mac=LOCAL_MAC)]:
        case.send(packet)
        case.cmd('F', case.frames)
        case.cmd('A', len(case.tx) - 1)
        case.wait_rx()
        case.arp_drain()
    for fields in [dict(target_ip=PEER_IP), dict(oper=2), dict(htype=2),
                   dict(ptype=0x86dd), dict(hlen=5), dict(plen=6)]:
        case.send(arp(**fields))
        case.wait_rx()
    case.settle()
    case.snapshot()
    results = [case.save()]
    case = Case(root, 'ET-07-pending')
    case.configure()
    packets = case.descriptors([3000])
    # ARP is queued while the first long UDP frame is on the wire.
    case.w(0x28, 1)
    case.cmd('H', 2)
    case.tx.append(packets[0][:-4])
    case.send(arp())
    case.send(arp(src_ip=bytes([10, 0, 0, 7])))
    case.wait_rx(0)
    case.tx.extend(packet[:-4] for packet in packets[1:])
    case.ref.arp_sent()
    case.finish_tx(1)
    case.snapshot()
    results.append(case.save())
    return results


def et08(root):
    case = Case(root, 'ET-08')
    case.configure()
    packets = case.descriptors([0, 1, 1023, 1024, 1025, 3000])
    case.start(packets)
    case.finish_tx(6)
    case.snapshot()
    return [case.save()]


def et09(root):
    case = Case(root, 'ET-09')
    case.configure()
    # DOORBELL is independent of ENABLE (eth 4.1).
    case.w(4, 0)
    case.ref.enable = False
    packets = case.descriptors([41, 1040, 13])
    case.start(packets)
    case.cmd('X', 1)
    case.cmd('H', 2)
    case.w(0x28, 0)
    case.finish_tx(3)
    case.w(0x10, 1)
    case.w(0x24, 0)
    case.w(0x28, 0)
    case.poll(0x10, 1, 1)
    case.r(0x28, 0)
    case.r(0x2c, 3)
    case.r(0x130, 0)
    case.cmd('K', 4)
    case.ref.perf[10] = 0
    case.snapshot()
    return [case.save()]


def et10(root):
    case = Case(root, 'ET-10-duplex')
    case.configure()
    case.window(0, 0x10000, 0x40000)
    packets = case.descriptors([256 * 1024])
    case.start(packets)
    for i in range(256):
        case.send(udp(bytes([i]) * 1024, offset=i * 1024))
    case.wait_rx(128)
    case.finish_tx(1)
    case.poll(0x148, 256 * 1024)
    case.settle()
    case.snapshot()
    results = [case.save()]
    case = Case(root, 'ET-10-overflow')
    case.configure()
    case.window(0, 0x10000, 65536)
    case.control(3, 1)
    for i in range(24):
        case.send(udp(bytes([i + 1]) * 1024, offset=i * 1024), evaluate=False)
    case.wait_rx(512)
    case.control(3, 0)
    case.settle()
    # The occupancy/depth is implementation-selected (eth 5.2). Check that every
    # packet is wholly written or wholly discarded and PERF7 accounts for discards.
    case.cmd('O', 0x10000, 24, 1024)
    case.send(udp(bytes([0x71]) * 1024, offset=32768, notify=True), evaluate=False)
    case.wait_rx()
    case.cmd('N', 0x100, 0)
    case.cmd('U', 0x10000 + 32768, 1024, 0x71)
    case.cmd('E')
    results.append(case.save())
    return results


def et11(root):
    results = []
    for kind in ['desc-error', 'data-error', 'write-error',
                 'abort-desc', 'abort-data', 'abort-frame']:
        case = Case(root, 'ET-11-' + kind)
        case.configure()
        if kind == 'write-error':
            case.control(8, 0)
            case.send(udp(b'write-response-error'))
            case.wait_rx()
            case.poll(0x10, 2, 2)
            case.r(0x14, 2)
            case.ref.error = True
            case.send(udp(b'ERROR-must-drop', offset=100))
            case.settle()
            case.ref.error = False
            case.w(0x10, 2)
            case.r(0x14, 0)
            case.control(8, -1)
            case.send(udp(b'recovered', offset=200))
            case.settle()
            case.snapshot()
        else:
            packets = case.descriptors([3000, 64])
            if kind == 'desc-error':
                case.control(10, 0x1000)
            elif kind == 'data-error':
                case.control(10, 0x800000)
                case.control(1, 200)
            if kind == 'abort-desc':
                case.control(6, 1)
            elif kind == 'abort-data':
                case.control(1, 200)
            case.w(0x28, 0)
            if kind.startswith('abort'):
                if kind == 'abort-desc':
                    case.cmd('H', 0, 0)
                elif kind == 'abort-data':
                    case.cmd('H', 1, 0x800000, 0xc00000)
                else:
                    case.cmd('H', 2)
                    case.tx.append(packets[0][:-4])
                case.w(4, 5)
                case.control(6, 0)
                case.poll(8, 2, 3)
                case.r(0x10, 0)
            else:
                case.poll(0x10, 2, 2)
                case.r(0x14, 1)
                case.poll(8, 6, 7)
            case.r(0x130, 0)
            case.r(0x2c, 0)
            case.cmd('E', 1)
            case.w(0x10, 2)
            case.r(0x14, 0)
            case.control(10, 0xffffffff)
            case.control(1, 0)
            # Coordinator clarification 2584a91: only an actually sent UDP packet
            # consumes an ID. Restart directly after clearing ERROR, without reset.
            case.ref.ident = 1 if kind == 'abort-frame' else 0
            packets = case.descriptors([33])
            case.start(packets)
            case.finish_tx(1)
            case.snapshot()
        results.append(case.save())
    return results


def reset_registers(case):
    case.r(0, 0x00070001)
    for addr in [4, 0xc, 0x10, 0x14, 0x20, 0x24, 0x28, 0x2c,
                 *range(0x40, 0x80, 4), *range(0x100, 0x134, 4),
                 *[0x140 + n * 16 + k for n in range(4) for k in (0, 4, 8)],
                 0x180, 0x184, 0x18, 0x1c, 0x134, 0x13c, 0x17c, 0x18c, 0xffc]:
        case.r(addr, 0)
    case.r(8, 2)
    case.r(0x188, 1)


def et12(root):
    case = Case(root, 'ET-12')
    reset_registers(case)
    for addr in [0, 8, 0x14, 0x2c, *range(0x40, 0x80, 4),
                 0x120, 0x124, 0x128, 0x12c, 0x130, 0x184, 0xffc]:
        case.w(addr, 0xffffffff)
    reset_registers(case)
    case.configure()
    for addr, value in [(0x104, 0xffff1234), (0x10c, 0xffff5678),
                        (0x114, 0xffff4321), (0x20, 0x101f), (0x24, 0xabcd0000),
                        (0x134, 0xff123456), (0x144, 0xf0000100)]:
        case.w(addr, value)
        case.r(addr, value & (0xffff if addr in [0x104, 0x10c, 0x114, 0x24]
                             else 0xffffffe0 if addr == 0x20
                             else 0x00ffffff if addr == 0x134 else 0xffffffff))
    case.w(4, 8)
    reset_registers(case)
    case.ref = Reference()
    case.configure()
    case.w(4, 3)
    case.r(4, 1)
    case.control(4, 1)
    case.send(udp(b'already-accepted', notify=True))
    case.wait_rx(256)
    case.cmd('H', 3, 0)
    case.w(4, 0)
    case.ref.enable = False
    case.send(udp(b'disabled-later', offset=100))
    case.wait_rx()
    case.control(4, 0)
    case.cmd('N', 0x100, 0)
    case.settle()
    case.snapshot()
    packets = case.descriptors([3000])
    case.start(packets)
    case.cmd('H', 2)
    case.w(4, 9)
    case.r(0x108, int.from_bytes(LOCAL_IP, 'big'))
    case.finish_tx(1)
    case.snapshot()
    case.w(0xc, 0x101)
    case.cmd('I', 1)
    case.w(0x10, 0x101)
    case.cmd('I', 0)
    case.r(0x10, 0)
    case.w(4, 8)
    reset_registers(case)
    results = [case.save()]
    case = Case(root, 'ET-12-rx-soft-reset')
    case.configure()
    case.send(udp(bytes([0x37]) * 1024, notify=True), evaluate=False)
    case.cmd('H', 4)
    case.cmd('D', 64)
    case.r(8, 2, 3)  # 387619f: an unvalidated receiving frame is not BUSY.
    case.w(4, 8)
    reset_registers(case)
    case.ref = Reference()
    # Re-enable well before this long frame's end, proving discard-to-end rather
    # than relying on ENABLE remaining zero through its FCS.
    case.configure()
    case.wait_rx()
    case.ref.perf[0] = 1
    case.snapshot()
    case.send(udp(b'after-reset', offset=1, notify=True))
    case.settle()
    case.snapshot()
    results.append(case.save())
    case = Case(root, 'ET-12-arp-soft-reset')
    case.configure()
    case.send(arp())
    case.cmd('H', 2)
    case.r(8, 1, 3)
    case.w(4, 9)
    case.r(0x108, int.from_bytes(LOCAL_IP, 'big'))
    case.arp_drain()
    case.settle()
    case.snapshot()
    case.w(4, 8)
    reset_registers(case)
    results.append(case.save())
    return results


def et13(root):
    case = Case(root, 'ET-13')
    case.r(0x188, 1)
    case.cmd('Y', 0)
    case.w(0x188, 0)
    case.r(0x188, 0)
    case.cmd('Y', 1)
    case.w(0x188, 1)
    case.r(0x188, 1)
    case.cmd('Y', 0)
    case.w(0x180, (0x1234 << 16) | (1 << 10) | (17 << 5) | 3)
    case.r(0x180, 0)
    case.r(0x184, 1, 1)
    case.w(0x180, (0xbeef << 16) | (1 << 10) | (2 << 5) | 9)
    case.poll(0x184, 0, 1)
    case.cmd('J', 1, 17, 3, 0x1234)
    case.w(0x180, (17 << 5) | 3)
    case.poll(0x184, 0, 1)
    case.r(0x184, 0x12340000)
    case.cmd('J', 2, 17, 3, 0x1234)
    return [case.save()]


def et14(root):
    case = Case(root, 'ET-14-rx')
    case.configure()
    case.window(0, 0x10000, 2 * 1024 * 1024)
    case.control(1, 40)
    case.control(2, 40)
    case.cmd('B')
    for i in range(2048):
        case.send(udp(bytes((j + i) & 255 for j in range(1024)), offset=i * 1024))
    case.cmd('F', case.frames)
    case.poll(0x148, 2 * 1024 * 1024)
    case.poll(8, 2, 3)
    case.cmd('G', 2 * 1024 * 1024)
    case.snapshot()
    results = [case.save()]
    case = Case(root, 'ET-14-tx')
    case.configure()
    case.control(1, 40)
    case.control(2, 40)
    packets = case.descriptors([1024 * 1024])
    case.cmd('B')
    case.start(packets)
    case.cmd('X', len(case.tx))
    case.poll(0x10, 1, 1)
    case.cmd('G', 1024 * 1024)
    case.finish_tx(1)
    case.snapshot()
    results.append(case.save())
    case = Case(root, 'ET-14-arp')
    case.configure()
    case.control(1, 40)
    case.control(2, 40)
    packets = case.descriptors([3000])
    case.w(0x28, 0)
    case.cmd('H', 2)
    case.tx.append(packets[0][:-4])
    case.send(arp())
    case.cmd('F', case.frames)
    case.cmd('A', 1)
    case.tx.extend(packet[:-4] for packet in packets[1:])
    case.ref.arp_sent()
    case.finish_tx(1)
    case.snapshot()
    results.append(case.save())
    return results


def et16(root):
    results = []
    for gap in [0, 1, 100, 2125]:
        case = Case(root, f'ET-16-gap-{gap}')
        case.configure()
        case.w(0x134, 0xff000000 | gap)
        case.r(0x134, gap)
        # One multi-packet descriptor followed by a second descriptor.
        packets = case.descriptors([3072, 1024])
        case.cmd('M', gap, 3 if gap == 2125 else 2)
        case.start(packets)
        case.finish_tx(2)
        case.cmd('Z', 3)
        case.snapshot()
        results.append(case.save())
    case = Case(root, 'ET-16-arp')
    case.configure()
    case.w(0x134, 2125)
    packets = case.descriptors([3072, 1024])
    case.cmd('M', 2125, 3)
    case.w(0x28, 1)
    case.cmd('H', 2)
    case.tx.append(packets[0][:-4])
    case.send(arp())
    case.wait_rx(0)
    case.tx.extend(packet[:-4] for packet in packets[1:])
    case.ref.arp_sent()
    case.finish_tx(2)
    case.cmd('Z', 3, 1)
    case.snapshot()
    results.append(case.save())
    return results


def et15(root):
    results = []
    for seed in range(10):
        case = Case(root, f'ET-15-seed-{seed}', seed)
        case.configure()
        case.control(9, seed + 1)
        for i in range(200):
            case.control(0, case.rng.randrange(0, 65))
            case.control(1, case.rng.randrange(0, 51))
            case.control(2, case.rng.randrange(0, 51))
            win = case.rng.randrange(4)
            size = case.rng.choice([0, 32, 1024, 8192])
            base = 0x10000 + win * 0x10000 + case.rng.randrange(0, 4096, 32)
            case.window(win, base, size)
            length = case.rng.choice([0, 1, 31, 32, 33, 1023, 1024, 1464])
            packet = udp(case.rng.randbytes(length), win=win,
                         offset=case.rng.choice([0, 1, 17, size, max(0, size - length)]),
                         notify=bool(case.rng.getrandbits(1)),
                         udp_checksum=bool(case.rng.getrandbits(1)))
            kind = case.rng.randrange(32)
            if kind == 0:
                packet = arp()
            elif kind == 1:
                packet = replace(packet, 36, b'\x00\x00')
            elif kind == 2:
                packet = replace(packet, 14, b'\x46', fix_ip=True)
            elif kind == 3:
                packet = replace(packet, 24, b'\x00\x00')
            elif kind == 4:
                packet = replace(packet, 0, PEER_MAC)
            elif kind == 9:
                packet = udp(case.rng.randbytes(length), win=win, udp_checksum=True)
                bad = (int.from_bytes(packet[40:42], 'big') ^ 1) or 2
                packet = replace(packet, 40, bad.to_bytes(2, 'big'))
            elif kind == 10:
                packet = replace(packet, 20, b'\x20\x00', fix_ip=True)
            elif kind == 11:
                packet = replace(packet, 30, b'\x01\x02\x03\x04', fix_ip=True)
            elif kind == 12:
                packet = replace(packet, 23, b'\x01', fix_ip=True)
            elif kind == 13:
                packet = replace(packet, 14, b'\x65', fix_ip=True)
            elif kind == 14:
                packet = replace(packet, 16, b'\x7f\xff', fix_ip=True)
            elif kind == 15:
                bad = int.from_bytes(packet[38:40], 'big') + 1
                packet = replace(packet, 38, bad.to_bytes(2, 'big'))
            elif kind == 16:
                packet = replace(packet, 38, b'\x00\x0f')
            elif kind == 17:
                packet = arp(target_ip=PEER_IP)
            elif kind == 18:
                packet = arp(htype=2)
            elif kind == 19:
                packet = arp(ptype=0x86dd)
            elif kind == 20:
                packet = arp(plen=5)
            elif kind == 21:
                packet = arp(oper=2)
            elif kind == 22:
                packet = arp(hlen=5)
            action, _ = case.send(packet, gap=case.rng.randrange(12, 81),
                                  flip=30 if kind == 5 else -1,
                                  er=40 if kind == 6 else -1,
                                  trim=1 if kind == 7 else 0,
                                  extend=1500 if kind == 8 else 0)
            case.settle()
            if action == 'arp':
                case.arp_drain()
            if i % 17 == 0:
                packets = case.descriptors([case.rng.choice([0, 1, 1023, 1024, 1025])],
                                           random_fields=True)
                case.start(packets)
                case.finish_tx(1)
            case.snapshot(memory=False)
        case.snapshot()
        results.append(case.save())
    return results


def generate(tier, root):
    selected = [et15] if tier == 'random' else [et14] if tier == 'perf' else [
        et01, et02, et03, et04, et05, et06, et07, et08, et09, et10, et11, et12, et13, et16]
    return [item for function in selected for item in function(Path(root))]
