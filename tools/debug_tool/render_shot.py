"""render_shot.py — SoC console design 4.4 visual evidence; host Qt thread.

Render exact window sizes with explicit synthetic serial lines and real UDP data.
Example: QT_QPA_PLATFORM=offscreen python render_shot.py out.png --state vision
"""

import argparse
import os
from pathlib import Path
import socket
import struct
from concurrent.futures import ThreadPoolExecutor
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtCore import Qt, QPoint, QPointF
from PySide6.QtGui import QImage, QWheelEvent
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from core.engine import SerialEngine
from core.telemetry import encode
from gui.app import MainWindow
from telemetry_sim import demo_pixels, periodic, send_block, run_video, run_yolo


class SimulatedSerial:
    """Only for rendering: the simulated board never touches a physical serial port."""
    is_open = True
    port = 'SIMULATED'

    def write(self, data):
        return len(data)

    def flush(self):
        pass

    def close(self):
        self.is_open = False


def serial_line(engine, text):
    engine.add_entry('rx', text)
    engine._match_line(text)


def seed(engine, console, state):
    # This renderer models a ready loopback link rather than a physical NIC.
    engine.ethernet.wait_for_link = lambda local_ip: ('loopback', 0.0)
    engine._serial = SimulatedSerial()
    engine._config.update(port='SIMULATED', baud=115200)
    serial_line(engine, 'BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud')
    serial_line(engine, 'Demo: demo_vision' if state == 'vision' else 'Demo: demo')
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as board:
        board.bind(('127.0.0.1', 0))
        engine.board.establish_network('127.0.0.1', board.getsockname()[1], '127.0.0.1')
        board.settimeout(2)
        board.recvfrom(1024)
    for line in ('ETH peer IP: 0x7f000001', 'ETH peer port: 6000',
                 f'Scene: {2 if state == "vision" else 1}', 'PIX mode: 0', 'GEO mode: 0',
                 'Output mode: 2', 'Requested video fps: 30', 'Monitor Hz: 100',
                 'Switch: frames=2 mtime_ticks=6742100'):
        serial_line(engine, line)
    from core.showcase import HELLO, encode as control_message
    from telemetry_sim import PipelineBoard
    from core.pipeline import preset
    simulated = PipelineBoard()
    simulated.app, simulated.state = 1, 2
    simulated.chain, simulated.revision = preset(5), 1
    payload = simulated.state_payload()
    engine.ethernet.showcase.receive(control_message(
        HELLO, 0, struct.pack('<H2x16s', 3, b'SIMULATED') + payload))
    for message in simulated.messages()[1:]:
        engine.ethernet.showcase.receive(message)
    console.output.setCurrentIndex(2)
    console.scene.setCurrentIndex(0)
    # Feed a 60 s timeline using the same encoder and real socket as telemetry_sim.py.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as source:
        for batch in range(38):
            records = []
            for index in range(16):
                tick = batch * 16 + index
                record = periodic(tick, tick, 10)
                record['scene'] = 2 if state == 'vision' else 1
                if state == 'vision':
                    for key in ('npu_completed', 'npu_cycles', 'post_cycles', 'boxes'):
                        record[key] = 0
                    for port in (3, 4):
                        for key in ('rd_beat', 'wr_beat', 'rd_txn', 'wr_txn',
                                    'wait_sum', 'wait_max', 'urg_cnt'):
                            record[f'p{port}_{key}'] = 0
                records.append(encode(record))
            send_block(source, ('127.0.0.1', 6000), b''.join(records), 3)
    if state == 'detection':
        path = Path(__file__).resolve().parents[2] / 'build/debug_tool/input.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        QImage(demo_pixels(), 1280, 720, 2560, QImage.Format_RGB16).copy().save(str(path))
        console.image_path.setText(os.path.relpath(path))
        console._load_image()
        engine.yolo.request = 0
        engine.yolo.reset_capture()
        engine.yolo.source_image = str(path)
        engine.yolo.images = [path]
        console.display.setCurrentIndex(2)
    engine.add_entry('sys', '截图模拟数据 · 非实板测量')
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out')
    parser.add_argument('--state', choices=['disconnected', 'vision', 'detection', 'pipeline'],
                        default='disconnected')
    parser.add_argument('--scroll-position', type=float, default=0)
    parser.add_argument('--scroll-bottom', action='store_true')
    parser.add_argument('--page', type=int, default=0)
    parser.add_argument('--main-page', type=int, default=4)
    parser.add_argument('--ddr-view', choices=['highlight', 'paused'])
    parser.add_argument('--maximize', choices=['display', 'ddr', 'log', 'status'])
    parser.add_argument('--width', type=int, default=1366)
    parser.add_argument('--height', type=int, default=768)
    args = parser.parse_args()
    app = QApplication([])
    engine = SerialEngine()
    window = MainWindow(engine)
    window.setAttribute(Qt.WA_DeleteOnClose)
    window.resize(args.width, args.height)
    window.show()
    app.processEvents()
    simulator = None
    executor = ThreadPoolExecutor(max_workers=1)
    try:
        if args.state != 'disconnected':
            simulated_state = seed(engine, window.soc, args.state)
            if args.state in ('vision', 'pipeline'):
                simulator = executor.submit(run_video, '127.0.0.1', 6000, 3, 3, 2)
            else:
                simulator = executor.submit(run_yolo, '127.0.0.1', 6000)
        deadline = time.monotonic() + (3 if simulator else .3)
        while time.monotonic() < deadline:
            if args.state != 'disconnected':
                from core.showcase import STATE, encode as control_message
                engine.ethernet.showcase.receive(control_message(STATE, 0, simulated_state))
            app.processEvents()
            time.sleep(.01)
        if args.state == 'detection':
            engine.yolo.complete_capture()
        window.soc.pages.setCurrentIndex(1 if args.state == 'pipeline' else args.page)
        window.rail_group.button(args.main_page).setChecked(True)
        window._select_page(args.main_page)
        window.soc.refresh()
        app.processEvents()
        if args.scroll_bottom or args.scroll_position:
            scroll = (window.soc.pages.currentWidget() if args.main_page == 4 else
                      window.left_stack.currentWidget())
            fraction = 1 if args.scroll_bottom else args.scroll_position
            bar = scroll.verticalScrollBar()
            bar.setValue(round(bar.maximum() * fraction))
            app.processEvents()
        if args.state == 'vision' and engine.video.snapshot()['received'] == 0:
            raise RuntimeError('Simulator produced no complete EDVF frame')
        if args.state == 'detection' and engine.yolo.snapshot()[1] is None:
            raise RuntimeError('Simulator produced no complete YOLO return')
        if args.state != 'disconnected' and not engine.telemetry.status()['latest']:
            raise RuntimeError('Simulator produced no EDTM data')
        if (window.width(), window.height()) != (args.width, args.height):
            raise RuntimeError(f'Layout expanded window to {window.size()}')
        if args.maximize:
            panel = {'display': window.soc.canvas_card, 'ddr': window.soc.monitor_card,
                     'log': window.soc.log_card, 'status': window.soc.status_card}[args.maximize]
            window.soc.toggle_panel(panel)
            app.processEvents()
        if args.ddr_view:
            chart = window.soc.bandwidth
            if args.ddr_view == 'highlight':
                QTest.mouseClick(chart, Qt.LeftButton,
                                 pos=chart.legend_rects()[1].center().toPoint())
                QTest.mouseMove(chart, chart.legend_rects()[0].center().toPoint())
            else:
                center = chart.plot_bounds().center()
                wheel = QWheelEvent(center, QPointF(chart.mapToGlobal(center.toPoint())),
                                    QPoint(), QPoint(0, 480), Qt.NoButton, Qt.NoModifier,
                                    Qt.NoScrollPhase, False)
                app.sendEvent(chart, wheel)
                QTest.mousePress(chart, Qt.LeftButton, pos=center.toPoint())
                QTest.mouseMove(chart, center.toPoint() + QPoint(70, 0))
                QTest.mouseRelease(chart, Qt.LeftButton,
                                   pos=center.toPoint() + QPoint(70, 0))
                QTest.mouseMove(chart, QPoint(0, chart.height() - 1))
            app.processEvents()
        if args.main_page == 5:
            QTest.keyPress(window, Qt.Key_W)
            app.processEvents()
        if not window.grab().save(args.out):
            raise RuntimeError(f'Cannot save screenshot: {args.out}')
        print(f'Saved {args.out} ({args.width} × {args.height}, {args.state})')
        if simulator:
            simulator.result(timeout=15)
    finally:
        executor.shutdown(wait=True)
        window.close()
        app.processEvents()


if __name__ == '__main__':
    main()
