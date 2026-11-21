# File: test_uart_tool.py
# Spec: edrv32-soc-spec 7.5(3a), eth-spec 2.3.
# Description: Exercise real host session encoding, prompts and bounded ETH resend.
# Clock domain: none (host).
from pathlib import Path
import socket
import ctypes
import io
from types import SimpleNamespace
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch
from tools.board.uart_tool import (
    BIOS_MENU, BiosTransfer, capture, descriptor_bytes, elf_segments, eth_packets,
    operations, wire_bytes,
    resolve_arp,
)
from tools.board.tests.elf_fixture import ENTRY, SEGMENTS, elf_fixture, expected_steps

ROOT = Path(__file__).resolve().parents[3]


class BiosToolTest(unittest.TestCase):
    def setUp(self):
        ready = patch('tools.board.uart_tool.wait_for_link', return_value=('Ethernet', 0.0))
        self.link_wait = ready.start()
        self.addCleanup(ready.stop)
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'app.elf'
        self.path.write_bytes(elf_fixture())

    def test_elf_physical_segments_filesz_and_entry(self):
        self.assertEqual(elf_segments(self.path), (ENTRY, SEGMENTS))
        plan = operations(self.path, elf=True, baud=115200)
        self.assertEqual(len(plan), 1)
        self.assertEqual(plan[0].selection, b'1\r')
        self.assertEqual(plan[0].payload, expected_steps(115200)[1][0])
        self.assertEqual(plan[0].success, f'Run: 0x{ENTRY:08x}')

    def test_bin_addresses_required(self):
        for kwargs in ({}, {'addr': 0x10000000}, {'entry': 0x10000000}):
            with self.assertRaisesRegex(ValueError, '.bin requires --addr and --entry'):
                operations(self.path, **kwargs)
        self.path.write_bytes(b'\x0a\x0d\0binary')
        op = operations(self.path, baud=115200, addr=0x80001000, entry=0x80001004)[0]
        self.assertEqual(op.payload, struct.pack('<IIII', 1, 0x80001004, 0x80001000, 9)
                         + self.path.read_bytes())
        self.assertEqual(op.payload, wire_bytes(self.path, 0x80001000, 0x80001004))

    def test_uart_prompt_and_auto_run(self):
        for baud in (115200, 921600, 2000000):
            writes = []
            switches = []
            transfer = BiosTransfer(writes.append, switches.append)
            transfer.start(self.path, elf=True, baud=baud)
            self.assertEqual(writes, [b'\r'])
            transfer.feed_line('BIOS: EdRV32')
            for data, reply in expected_steps(baud):
                if data in (b'4\r', b'1\r'):
                    transfer.feed_line(BIOS_MENU + ' extra')
                    transfer.feed_line(BIOS_MENU)
                for line in reply.decode().splitlines():
                    transfer.feed_line(line)
            self.assertEqual(b''.join(writes), b'\r' + b''.join(
                data for data, _ in expected_steps(baud)))
            state = transfer.status()
            self.assertEqual(state['programmedBytes'], sum(len(data) for _, data in SEGMENTS))
            self.assertEqual(state['result'], f'Run: 0x{ENTRY:08x}')
            self.assertEqual(state['sent'], state['total'])
            self.assertFalse(state['active'])
            self.assertEqual(switches, [] if baud == 115200 else [baud])

    def test_range_failure_stops(self):
        transfer = BiosTransfer(Mock(), Mock())
        transfer.start(self.path, elf=True, baud=115200)
        transfer.feed_line(BIOS_MENU)
        transfer.feed_line('UART load ready')
        transfer.feed_line('Load result: FAIL range')
        self.assertFalse(transfer.status()['active'])
        self.assertEqual(transfer.status()['result'], 'Load result: FAIL range')

    def test_eth_offsets_packet_size_and_notify(self):
        packets = eth_packets(ENTRY, SEGMENTS)
        for packet in packets:
            self.assertLessEqual(len(packet), 1472)
        ddr = [p for p in packets if p[0] == 2]
        self.assertEqual(b''.join(p[8:] for p in ddr), SEGMENTS[0][1])
        for index, packet in enumerate(ddr):
            self.assertEqual(struct.unpack('!BBHI', packet[:8]), (2, 0, 0, 0x100 + 1464 * index))
        self.assertEqual(struct.unpack('!BBHI', packets[-2][:8]), (3, 0, 0, 0x1203))
        self.assertEqual(packets[-2][8:], SEGMENTS[1][1])
        self.assertEqual(packets[-1][:8], b'\x03\x01\0\0\0\0\0\0')
        self.assertEqual(packets[-1][8:], descriptor_bytes(ENTRY, SEGMENTS))

    def test_eth_bind_and_exactly_one_resend(self):
        udp = Mock()
        udp.getsockname.return_value = ('192.168.1.9', 12345)
        with patch('tools.board.uart_tool.socket.socket', return_value=udp) as factory, \
                patch('tools.board.uart_tool.resolve_arp') as arp:
            writes = []
            transfer = BiosTransfer(writes.append, Mock())
            transfer.start(self.path, elf=True, baud=115200, eth=True, local_ip='192.168.1.9')
            factory.assert_called_once_with(socket.AF_INET, socket.SOCK_DGRAM)
            udp.bind.assert_called_once_with(('192.168.1.9', 0))
            transfer.feed_line(BIOS_MENU)
            self.assertEqual(writes, [b'\r', b'2\r'])
            self.assertEqual(udp.sendto.call_count, 0)
            transfer.feed_line('ETH load ready 192.168.1.10:5000')
            arp.assert_called_once_with('192.168.1.9')
            first = list(udp.sendto.call_args_list)
            failure = 'ETH load result: FAIL bytes win2=1 expect=8451 win3=37 expect=37'
            transfer.feed_line(failure)
            self.assertEqual(udp.sendto.call_args_list, first + first)
            transfer.feed_line(failure)
            self.assertEqual(udp.sendto.call_args_list, first + first)
            self.assertFalse(transfer.status()['active'])
            self.assertEqual(transfer.status()['result'], failure)
            udp.close.assert_called_once()

    def test_eth_waits_before_arp_and_packets(self):
        udp = Mock()
        udp.getsockname.return_value = ('192.168.1.2', 12345)
        events = []
        self.link_wait.side_effect = lambda ip: (events.append('ready') or ('Ethernet', 1.2))
        udp.sendto.side_effect = lambda *args: events.append('send')
        transfer = BiosTransfer(Mock(), Mock())
        transfer.log = Mock()
        with patch('tools.board.uart_tool.socket.socket', return_value=udp), \
                patch('tools.board.uart_tool.resolve_arp',
                      side_effect=lambda ip: events.append('arp')) as arp:
            transfer.start(self.path, elf=True, baud=115200, eth=True)
            transfer.feed_line(BIOS_MENU)
            self.assertEqual(events, [])
            transfer.feed_line('ETH load ready 192.168.1.10:5000')
        self.assertEqual(events, ['ready', 'arp'] + ['send'] * udp.sendto.call_count)
        arp.assert_called_once_with('192.168.1.2')
        transfer.log.assert_called_once_with('等待网卡 Ethernet 就绪 … 用时 1.2 s')

    def test_eth_link_timeout_stops_before_arp(self):
        udp = Mock()
        udp.getsockname.return_value = ('192.168.1.2', 12345)
        transfer = BiosTransfer(Mock(), Mock())
        with patch('tools.board.uart_tool.socket.socket', return_value=udp):
            transfer.start(self.path, elf=True, baud=115200, eth=True)
        transfer.feed_line(BIOS_MENU)
        self.link_wait.side_effect = OSError('Ethernet link timeout')
        with patch('tools.board.uart_tool.resolve_arp') as arp:
            with self.assertRaisesRegex(OSError, 'Ethernet link timeout'):
                transfer.feed_line('ETH load ready 192.168.1.10:5000')
        arp.assert_not_called()
        udp.sendto.assert_not_called()
        udp.close.assert_called_once()
        self.assertEqual(transfer.status()['phase'], 'error')

    def test_eth_no_arp_reply_stops_before_any_image_packet(self):
        udp = Mock()
        udp.getsockname.return_value = ('192.168.1.2', 12345)
        transfer = BiosTransfer(Mock(), Mock())
        with patch('tools.board.uart_tool.socket.socket', return_value=udp):
            transfer.start(self.path, elf=True, baud=115200, eth=True)
        transfer.feed_line(BIOS_MENU)
        with patch('tools.board.uart_tool.resolve_arp',
                   side_effect=OSError('ARP no reply')) as arp:
            with self.assertRaisesRegex(OSError, 'ARP no reply'):
                transfer.feed_line('ETH load ready 192.168.1.10:5000')
        udp.sendto.assert_not_called()
        udp.close.assert_called_once()
        arp.assert_called_once_with('192.168.1.2')
        self.assertEqual(transfer.status()['phase'], 'error')
        self.assertEqual(transfer.status()['sent'], 0)
        self.assertFalse(transfer.status()['active'])

    def test_eth_does_not_bind_wildcard(self):
        for address in ('', '0.0.0.0'):
            transfer = BiosTransfer(Mock(), Mock())
            with self.assertRaisesRegex(ValueError, 'explicit local IPv4'):
                transfer.start(self.path, elf=True, eth=True, local_ip=address)

    def test_windows_sendarp_uses_explicit_source_and_reports_failure(self):
        api = Mock(return_value=0)
        dll = SimpleNamespace(iphlpapi=SimpleNamespace(SendARP=api))
        with patch('tools.board.uart_tool.sys.platform', 'win32'), \
                patch('tools.board.uart_tool.ctypes.windll', dll, create=True):
            resolve_arp('192.168.1.2')
            destination, source, _, _ = api.call_args.args
            self.assertEqual(destination.value,
                             int.from_bytes(socket.inet_aton('192.168.1.10'), sys.byteorder))
            self.assertEqual(source.value,
                             int.from_bytes(socket.inet_aton('192.168.1.2'), sys.byteorder))
            api.return_value = 67
            with self.assertRaisesRegex(OSError, 'SendARP error 67'):
                resolve_arp('192.168.1.2')

    @unittest.skipUnless(sys.platform == 'linux', 'Linux raw ARP interface')
    def test_linux_arp_request_and_reply_on_selected_interface(self):
        source = bytes((192, 168, 1, 2))
        target = bytes((192, 168, 1, 10))
        mac = bytes.fromhex('020000000002')
        board = bytes.fromhex('024544525632')
        raw = Mock()
        raw.getsockname.return_value = ('eth0', 0x0806, 0, 1, mac)
        reply = mac + board + bytes.fromhex('08060001080006040002')
        raw.recv.side_effect = [bytes(60), reply + board + target + mac + source + bytes(18)]
        control = Mock()
        contexts = []
        for sock in (control, raw):
            context = Mock()
            context.__enter__ = Mock(return_value=sock)
            context.__exit__ = Mock(return_value=False)
            contexts.append(context)
        with patch('tools.board.uart_tool.sys.platform', 'linux'), \
                patch('tools.board.uart_tool.socket.socket', side_effect=contexts), \
                patch('tools.board.uart_tool.socket.if_nameindex', return_value=[(2, 'eth0')]), \
                patch('fcntl.ioctl', return_value=bytes(20) + source + bytes(232)), \
                patch('tools.board.uart_tool.select.select', return_value=([raw], [], [])):
            resolve_arp('192.168.1.2')
        raw.bind.assert_called_once_with(('eth0', 0x0806))
        expected = b'\xff' * 6 + mac + bytes.fromhex('08060001080006040001')
        expected += mac + source + bytes(6) + target + bytes(18)
        raw.send.assert_called_once_with(expected)

    def test_rom_is_part_of_same_session(self):
        self.path.write_bytes(elf_fixture(rom_slot=True))
        rom = ROOT / 'third_party/nes/FC游戏 536款 含封面/坦克大战/坦克大战.nes'
        op = operations(self.path, True, 115200, rom)[0]
        self.assertEqual(op.payload, expected_steps(115200, rom.read_bytes())[1][0])
        with self.assertRaisesRegex(ValueError, '--rom requires --elf'):
            operations(self.path, rom=rom)

    def test_cli_emit(self):
        output = Path(self.temp.name) / 'wire'
        subprocess.run([sys.executable, str(ROOT / 'tools/board/uart_tool.py'), str(self.path),
                        '--elf', '--emit', str(output)], check=True)
        self.assertEqual(output.read_bytes(), b''.join(d for d, _ in expected_steps()))

    def test_capture_fragmented_uart_switches_baud_and_logs(self):
        test = self
        menu = (BIOS_MENU + '\r\n').encode()
        probe_reply = b'Input error: type 1-4 then Enter\r\n' + menu
        steps = [(b'\r', probe_reply)] + expected_steps()

        class Peer:
            def __init__(self):
                self.pending = bytearray()
                self.writes = bytearray()
                self.step = 0
                self.offset = 0
                self.switches = []

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            @property
            def in_waiting(self):
                return min(7, len(self.pending))

            @property
            def baudrate(self):
                return self.switches[-1][0] if self.switches else 115200

            @baudrate.setter
            def baudrate(self, value):
                self.switches.append((value, self.step))

            def read(self, size):
                if not self.pending:
                    raise KeyboardInterrupt
                data = bytes(self.pending[:size])
                del self.pending[:size]
                return data

            def write(self, data):
                expected, reply = steps[self.step]
                test.assertEqual(data, expected[self.offset:self.offset + len(data)])
                self.writes.extend(data)
                self.offset += len(data)
                if self.offset == len(expected):
                    self.step += 1
                    self.offset = 0
                    self.pending.extend(reply)
                    if self.step > 1 and self.step % 2 and self.step < len(steps):
                        self.pending.extend(menu)

            def flush(self):
                pass

        peer = Peer()
        console = io.BytesIO()
        log = Path(self.temp.name) / 'capture.log'
        with patch.dict(sys.modules, {'serial': SimpleNamespace(Serial=lambda *args: peer)}), \
                patch('sys.stdout', SimpleNamespace(buffer=console)):
            with self.assertRaises(KeyboardInterrupt):
                capture('fake', self.path, log, None, None, elf=True)
        self.assertEqual(peer.step, len(steps))
        self.assertEqual(peer.switches, [(2000000, 3)])
        self.assertEqual(peer.writes, b''.join(data for data, _ in steps))
        expected_log = probe_reply + b''.join(
            reply + (menu if index % 2 and index != len(steps) - 2 else b'')
            for index, (_, reply) in enumerate(steps[1:]))
        self.assertEqual(log.read_bytes(), expected_log)
        self.assertEqual(console.getvalue(), expected_log)

    def test_rom_missing_symbols_and_oversize_stop_before_transfer(self):
        rom = Path(self.temp.name) / 'game.nes'
        rom.write_bytes(b'game')
        with self.assertRaisesRegex(ValueError, 'missing ROM slot symbol'):
            operations(self.path, elf=True, rom=rom)
        self.path.write_bytes(elf_fixture(rom_slot=True))
        from tools.board.tests.elf_fixture import ROM_SLOT_SIZE
        rom.write_bytes(bytes(ROM_SLOT_SIZE + 1))
        writes = []
        transfer = BiosTransfer(writes.append, Mock())
        with self.assertRaisesRegex(ValueError, 'exceeds ROM slot size'):
            transfer.start(self.path, elf=True, rom=rom)
        self.assertEqual(writes, [])


class LinkWaitTest(unittest.TestCase):
    def test_already_ready_returns_without_sleep(self):
        from tools.board.link_wait import wait_for_link
        with patch('tools.board.link_wait._linux_state',
                   return_value=('eth0', True, 'operstate=up')) as state, \
                patch('tools.board.link_wait.sys.platform', 'linux'), \
                patch('tools.board.link_wait.time.monotonic', side_effect=[5, 5]), \
                patch('tools.board.link_wait.time.sleep') as sleep:
            self.assertEqual(wait_for_link('192.168.1.2'), ('eth0', 0))
        state.assert_called_once_with('192.168.1.2')
        sleep.assert_not_called()

    def test_delayed_ready_polls_each_100_ms(self):
        from tools.board.link_wait import wait_for_link
        states = [('Ethernet', False, 'OperStatus=Down, DAD=Preferred'),
                  ('Ethernet', False, 'OperStatus=Up, DAD=Tentative'),
                  ('Ethernet', True, 'OperStatus=Up, DAD=Preferred')]
        with patch('tools.board.link_wait._windows_state', side_effect=states), \
                patch('tools.board.link_wait.sys.platform', 'win32'), \
                patch('tools.board.link_wait.time.monotonic', side_effect=[0, 0, .1, .2]), \
                patch('tools.board.link_wait.time.sleep') as sleep:
            self.assertEqual(wait_for_link('192.168.1.2'), ('Ethernet', .2))
        self.assertEqual(sleep.call_args_list, [unittest.mock.call(.1)] * 2)

    def test_timeout_reports_ip_name_and_last_state(self):
        from tools.board.link_wait import wait_for_link
        with patch('tools.board.link_wait._linux_state',
                   return_value=('eth0', False, 'operstate=down')), \
                patch('tools.board.link_wait.sys.platform', 'linux'), \
                patch('tools.board.link_wait.time.monotonic', side_effect=[0, 0, 10]), \
                patch('tools.board.link_wait.time.sleep') as sleep:
            with self.assertRaisesRegex(OSError, 'eth0.*192.168.1.2.*operstate=down.*10.0 s'):
                wait_for_link('192.168.1.2')
        sleep.assert_called_once_with(.1)

    def test_windows_requires_both_up_and_preferred(self):
        from tools.board import link_wait as link
        raw_address = ctypes.create_string_buffer(b'\x02\0\0\0' + socket.inet_aton('192.168.1.2'))
        address = link._Unicast()
        address.socket.address = ctypes.addressof(raw_address)
        address.socket.length = 16
        adapter = link._Adapter()
        adapter.unicast = ctypes.pointer(address)
        adapter.friendly_name = 'Ethernet'

        def query(family, flags, reserved, buffer, size):
            if buffer is None:
                ctypes.cast(size, ctypes.POINTER(ctypes.c_uint32))[0] = ctypes.sizeof(adapter)
                return 111
            ctypes.memmove(buffer, ctypes.byref(adapter), ctypes.sizeof(adapter))
            return 0

        api = Mock(side_effect=query)
        dll = SimpleNamespace(iphlpapi=SimpleNamespace(GetAdaptersAddresses=api))
        with patch.object(ctypes, 'windll', dll, create=True):
            for oper, dad, ready in [(2, 4, False), (1, 1, False), (1, 4, True)]:
                adapter.oper_status, address.dad_state = oper, dad
                name, actual, state = link._windows_state('192.168.1.2')
                self.assertEqual((name, actual), ('Ethernet', ready))
                self.assertIn('DAD=', state)

    @unittest.skipUnless(sys.platform == 'linux', 'Linux interface enumeration')
    def test_linux_reads_operstate_for_address_owner(self):
        from tools.board.link_wait import _linux_state
        with patch('tools.board.link_wait.Path.read_text', return_value='up\n') as read:
            self.assertEqual(_linux_state('127.0.0.1'), ('lo', True, 'operstate=up'))
        read.assert_called_once_with()
