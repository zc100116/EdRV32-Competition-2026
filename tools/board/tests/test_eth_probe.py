"""test_eth_probe.py — eth-spec 2.3/2.4; host UDP probe contract, no clock domain."""

import contextlib
import io
import socket
import unittest
from unittest.mock import Mock, patch

from tools.board import eth_probe
from tools.debug_tool.core.ethernet import packets


class ProbeTest(unittest.TestCase):
    def test_default_arguments_and_explicit_bind(self):
        args = eth_probe.arguments([])
        self.assertEqual((args.local_ip, args.board_ip, args.port, args.listen),
                         ('192.168.1.2', '192.168.1.10', 5000, 6000))
        with (patch.object(eth_probe.socket, 'socket') as factory,
              patch.object(eth_probe, 'probe') as probe,
              contextlib.redirect_stdout(io.StringIO())):
            sock = factory.return_value.__enter__.return_value
            eth_probe.main(['--local-ip', '127.0.0.1', '--listen', '6001'])
            factory.assert_called_once_with(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind.assert_called_once_with(('127.0.0.1', 6001))
            self.assertEqual(probe.call_args.args[1].local_ip, '127.0.0.1')

    def test_bind_failure_exits_without_fallback(self):
        with (patch.object(eth_probe.socket, 'socket') as factory,
              patch.object(eth_probe, 'probe') as probe):
            sock = factory.return_value.__enter__.return_value
            sock.bind.side_effect = OSError('requested address unavailable')
            with self.assertRaisesRegex(OSError, 'requested address unavailable'):
                eth_probe.main([])
            sock.bind.assert_called_once_with(('192.168.1.2', 6000))
            probe.assert_not_called()

    def test_peer_packet_and_raw_receive(self):
        sock = Mock()
        sock.recvfrom.return_value = (b'EDRV32 DIAG 7', ('192.168.1.10', 5000))
        output = io.StringIO()
        with (patch.object(eth_probe.time, 'monotonic', side_effect=[0, 0, 0, 1, 1]),
              patch.object(eth_probe.select, 'select',
                           side_effect=[([sock], [], []), KeyboardInterrupt]),
              contextlib.redirect_stdout(output)):
            with self.assertRaises(KeyboardInterrupt):
                eth_probe.probe(sock, eth_probe.arguments([]))
        expected = b'\x03\x01\x00\x00\x00\x00\x00\x00\x00'
        self.assertEqual(expected, next(packets(b'\0', 3, 0)))
        self.assertEqual(sock.sendto.call_count, 2)
        for call in sock.sendto.call_args_list:
            self.assertEqual(call.args, (expected, ('192.168.1.10', 5000)))
        self.assertIn("RX 192.168.1.10:5000 b'EDRV32 DIAG 7'", output.getvalue())
