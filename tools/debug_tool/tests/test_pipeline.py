"""Pipeline 7.1/7.3 boundary codecs, board rejection and Qt/UDP workflow."""
import copy
import os
from pathlib import Path
import socket
import struct
import sys
import threading
import unittest
from unittest.mock import Mock, patch

from tools.debug_tool.core.pipeline import (
    block, preset, pack_chain, unpack_chain, chain_error, pack_stats, unpack_stats,
)
from tools.debug_tool.core.showcase import (
    CHAIN, PRESET, CHAIN_STATE, PIPE_STATS, ACK, encode, decode,
)
from tools.debug_tool.core.engine import SerialEngine
from test_program import wait_for
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from telemetry_sim import PipelineBoard, simulated_stats, run_pipeline


class PipelineTest(unittest.TestCase):
    @staticmethod
    def dispose(widget):
        from PySide6.QtCore import QCoreApplication, QEvent, Qt
        if hasattr(widget, 'details'):
            widget.details.setAttribute(Qt.WA_DeleteOnClose)
            widget.details.close()
        widget.setAttribute(Qt.WA_DeleteOnClose)
        widget.close()
        QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)

    def test_exact_chain_layout_and_all_presets(self):
        for number in range(1, 9):
            chain = preset(number)
            payload = pack_chain(chain)
            self.assertEqual(len(payload), 100)
            self.assertEqual(chain_error(payload), (0, ''))
            self.assertEqual(unpack_chain(payload), chain)
            self.assertEqual(payload[4 + len(chain['blocks']) * 12:],
                             bytes((8 - len(chain['blocks'])) * 12))
            for kind, data in ((CHAIN, payload), (PRESET, struct.pack('<B3x', number)),
                               (CHAIN_STATE, struct.pack('<I', 123) + payload)):
                self.assertEqual(decode(encode(kind, 17, data)), (kind, 17, data))
        self.assertEqual(pack_chain(preset(3))[4:16],
                         struct.pack('<BB5h', 7, 0, 90, 100, 0, 0, 0))
        with self.assertRaisesRegex(ValueError, 'unknown'):
            decode(encode(6, 0, bytes(24)))

    def test_rejected_fields_ranges_and_chain_rules(self):
        self.assertEqual(chain_error(bytes(99))[0], 1)
        for kind, parameters in ((1, [-257, 256]), (1, [0, 513]), (2, [2]),
                                 (2, [31]), (3, [0]), (3, [7]), (5, [256]),
                                 (7, [-181, 100]), (7, [181, 100]),
                                 (7, [0, 49]), (7, [0, 401]),
                                 (7, [0, 100, -1281]), (7, [0, 100, 0, 721])):
            chain = dict(source=0, view=255, preset=0, blocks=[block(kind, p=parameters)])
            self.assertEqual(chain_error(pack_chain(chain))[0], 2)
        for blocks, message in (([block(8), block(8)], '检测最多'),
                                 ([block(9, 1)], '之前必须有检测'),
                                 ([block(9)], '必须选择'),
                                 ([block(4, 1)], '标志位'),
                                 ([block(4, p=[1])], '参数')):
            data = pack_chain(dict(source=0, view=255, preset=0, blocks=blocks))
            self.assertIn(message, chain_error(data)[1])
        for offset, value in ((0, 3), (1, 9), (2, 9), (3, 9), (99, 1)):
            payload = bytearray(pack_chain(preset(1)))
            payload[offset] = value
            self.assertEqual(chain_error(payload)[0], 2)
        chain = dict(source=2, view=255, preset=0, blocks=[])
        self.assertEqual(chain_error(pack_chain(chain))[0], 0)
        chain['view'] = 254
        self.assertEqual(chain_error(pack_chain(chain))[0], 0)
        board = PipelineBoard()
        result = board.handle(encode(CHAIN, 23, pack_chain(chain)))
        self.assertEqual(decode(result[0])[2], struct.pack('<HBB', CHAIN, 2, 0))
        self.assertEqual(board.chain['view'], 254)

    def test_stats_variable_length(self):
        for number in range(1, 9):
            stats = simulated_stats(preset(number))
            data = pack_stats(stats)
            self.assertEqual(len(data), 24 + 8 * len(stats['hops']))
            self.assertEqual(unpack_stats(data), stats)
            self.assertEqual(decode(encode(PIPE_STATS, 0, data))[2], data)
            with self.assertRaises(ValueError):
                decode(encode(PIPE_STATS, 0, data[:-1]))

    def test_simulator_rejects_atomically(self):
        board = PipelineBoard()
        before = copy.deepcopy(board.chain)
        chain = dict(source=0, view=255, preset=0, blocks=[block(9, 1)])
        replies = board.handle(encode(CHAIN, 19, pack_chain(chain)))
        self.assertEqual(decode(replies[0]), (ACK, 19, struct.pack('<HBB', CHAIN, 3, 2)))
        self.assertEqual(board.chain, before)
        self.assertEqual(board.revision, 0)

    def test_udp_gui_preset_drag_stats_and_rejection(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtCore import Qt, QMimeData, QPointF
        from PySide6.QtGui import QDropEvent
        from PySide6.QtWidgets import QApplication
        from gui.pipeline import PipelinePanel, MIME
        import json
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        engine.ethernet.local_ip = '127.0.0.1'
        engine.ethernet.start_receive(0, mode='files')
        self.addCleanup(engine.ethernet.stop_receive)
        self.addCleanup(engine.virtual_input.close)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(('127.0.0.1', 0))
        self.addCleanup(sock.close)
        engine.board.network_endpoint = sock.getsockname()
        thread = threading.Thread(target=run_pipeline, args=(sock, 3), daemon=True)
        thread.start()
        self.addCleanup(thread.join, 4)
        panel = PipelinePanel(engine, lambda action: action())
        self.addCleanup(self.dispose, panel)
        panel.show()
        with patch.object(engine.virtual_input, 'start'), patch.object(engine.ethernet, 'wait_for_link'):
            engine.board._send_connection_request()
            wait_for(self, lambda: engine.board.steps['peer']['done'])
            engine.ethernet.showcase.app(1)
            wait_for(self, lambda: not engine.ethernet.showcase.pending)
            panel.presets[4].click()
            wait_for(self, lambda: engine.board.chain['preset'] == 5)
            panel.refresh()
            self.assertEqual(panel.chain.count(), 3)
            # Real Qt drop event: move geometry ahead of detection, keeping overlay valid.
            mime = QMimeData()
            mime.setData(MIME, json.dumps(dict(index=2, block=block(7, p=[30, 80]))).encode())
            app.processEvents()
            point = panel.chain.visualItemRect(panel.chain.item(0)).center()
            event = QDropEvent(QPointF(point), Qt.MoveAction, mime, Qt.LeftButton, Qt.NoModifier)
            panel.chain.dropEvent(event)
            self.assertTrue(event.isAccepted())
            wait_for(self, lambda: engine.board.chain['preset'] == 0)
            wait_for(self, lambda: engine.board.pipe_stats is not None)
            panel.refresh()
            self.assertEqual([b['type'] for b in engine.board.chain['blocks']], [7, 8, 9])
            self.assertIn('端到端', panel.metrics.text())
            self.assertGreater(panel.hops.count(), 0)
            # Dragging detection behind its overlay must be rejected, retaining the board chain.
            panel.chain.move_block(1, 3, block(8))
            wait_for(self, lambda: engine.board.error is not None)
            panel.refresh()
            self.assertIn('之前必须有检测', panel.notice.text())
            self.assertEqual([b['type'] for b in engine.board.chain['blocks']], [7, 8, 9])
            print('PASS connection → preset → Qt drag → CHAIN_STATE / PIPE_STATS → rejection reason')

    def test_all_parameter_editors_library_source_delete_and_view(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtCore import Qt
        from PySide6.QtWidgets import QApplication, QSpinBox, QCheckBox, QComboBox
        from gui.pipeline import PipelinePanel
        app = QApplication.instance() or QApplication([])
        engine = SerialEngine()
        panel = PipelinePanel(engine, lambda action: action())
        self.addCleanup(self.dispose, panel)
        with patch.object(engine.pipeline, 'send') as send:
            for kind in range(1, 10):
                engine.board.chain = dict(source=0, view=255, preset=0,
                                         blocks=[block(kind, 1 if kind == 9 else 0)])
                engine.board.chain_rev += 1
                panel.refresh()
                panel.chain.setCurrentRow(0)
                for spin in panel.details.findChildren(QSpinBox):
                    spin.setValue(spin.maximum())
                    self.assertEqual(send.call_args.args[0]['preset'], 0)
                for combo in panel.details.findChildren(QComboBox):
                    combo.setCurrentIndex(combo.count() - 1)
                for check in panel.details.findChildren(QCheckBox):
                    check.setChecked(not check.isChecked())
                self.assertEqual(panel.chain.item(0).data(Qt.UserRole)['type'], kind)
                panel.change_view(0)
                self.assertEqual(send.call_args.args[0]['view'], 0)
                panel.change_view(254)
                self.assertEqual(send.call_args.args[0]['view'], 254)
                panel.change_view(255)
                panel.source.setCurrentIndex(2)
                self.assertEqual(send.call_args.args[0]['source'], 2)
                panel.delete()
                self.assertEqual(send.call_args.args[0]['blocks'], [])
                app.processEvents()
            value = panel.library.item(3).data(Qt.UserRole)
            panel.chain.move_block(-1, 0, value)
            self.assertEqual(send.call_args.args[0]['blocks'], [value])
            panel.source_view.click()
            self.assertEqual(send.call_args.args[0]['view'], 254)

    def test_pipeline_strip_and_controls_do_not_overlap_at_both_sizes(self):
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
        from PySide6.QtWidgets import QApplication
        from gui.app import MainWindow
        app = QApplication.instance() or QApplication([])
        window = MainWindow(SerialEngine())
        self.addCleanup(self.dispose, window)
        window.show()
        window.soc.pages.setCurrentIndex(1)
        window.engine.board.pipe_stats = simulated_stats(preset(5))
        for width, height in ((1366, 768), (1920, 1080)):
            window.resize(width, height)
            window.soc.refresh()
            app.processEvents()
            console = window.soc
            self.assertEqual((window.width(), window.height()), (width, height))
            self.assertLess(console.pipeline_strip.geometry().bottom(), console.workspace_frame.y())
            panel = console.pipeline
            self.assertLess(panel.chain.geometry().bottom(), panel.metrics.y())
            self.assertLess(panel.notice.geometry().bottom(), panel.height())
            for button in panel.presets:
                self.assertGreaterEqual(button.width(),
                    button.fontMetrics().horizontalAdvance(button.text()) + 8)
