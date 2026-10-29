"""Offscreen render test: build the main window, seed demo data, dump a PNG.

Run:  python render_shot.py [out.png]
"""

import argparse
import subprocess
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import QApplication

from core.engine import SerialEngine
from gui.app import MainWindow


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out', nargs='?', default='render.png')
    parser.add_argument('--page', choices=['serial', 'ddr', 'scene', 'yolo'], default='serial')
    parser.add_argument('--simulate-seconds', type=int, default=0)
    args = parser.parse_args()
    out = args.out
    app = QApplication(sys.argv)
    engine = SerialEngine()

    # in-memory demo match rules (not persisted) driving the data panel
    engine._rules = [
        {"id": "temp", "name": "温度", "enabled": True,
         "pattern": r"TEMP=(\d+)", "keyGroup": 0, "valueGroup": 1,
         "base": 10, "scale": 0.1, "unit": "℃"},
        {"id": "ch", "name": "ADC CH", "enabled": True,
         "pattern": r"ch(\d+):0x([0-9a-fA-F]+)", "keyGroup": 1,
         "valueGroup": 2, "base": 16, "scale": 1, "unit": ""},
        {"id": "score", "name": "CoreMark/MHz", "enabled": True,
         "pattern": r"CoreMark/MHz x1000:\s*(\d+)", "keyGroup": 0,
         "valueGroup": 1, "base": 10, "scale": 0.001, "unit": ""},
    ]
    engine._compiled_rules = engine._compile_rules(engine._rules)

    demo = [
        ("sys", "connected COM7 @ 115200 8N1"),
        ("rx",  "boot ok, streaming sensor frames"),
        ("rx",  "TEMP=235"),
        ("rx",  "ch1:0x3F8 ch2:0x12"),
        ("tx",  "6<CR>"),
        ("rx",  "TEMP=241"),
        ("rx",  "CoreMark/MHz x1000: 3125"),
        ("rx",  "ch1:0x400 ch2:0x18"),
        ("tx",  "status<CR>"),
        ("rx",  "TEMP=238"),
    ]
    base = int(time.time() * 1000) - 60_000
    for i, (direction, text) in enumerate(demo):
        engine.add_entry(direction, text)
        engine._entries[-1]["ts"] = base + i * 1377  # spread timestamps
        if direction == "rx":
            engine._match_line(text)

    # in-memory demo commands (not persisted) to preview the command grid
    engine._commands = [
        {"id": f"demo{i}", "label": label, "payload": payload,
         "ending": "cr"}
        for i, (label, payload) in enumerate([
            ("UART 回环", "1"), ("GPIO / LED", "2"), ("SRAM / CACHE", "3"),
            ("CLINT", "4"), ("PLIC", "5"), ("CoreMark + HPM", "6"),
        ])
    ]

    window = MainWindow(engine)
    window.setAttribute(Qt.WA_DeleteOnClose)
    index = {'serial': 0, 'ddr': 5, 'scene': 6, 'yolo': 7}[args.page]
    window.rail_group.button(index).setChecked(True)
    window._select_page(index)
    window.show()
    simulator = None
    if args.simulate_seconds:
        rx = engine.ethernet.start_receive(0)
        simulator = subprocess.Popen([
            sys.executable, os.path.join(os.path.dirname(__file__), 'telemetry_sim.py'),
            '--seconds', str(args.simulate_seconds), '--port', str(rx['localPort'])])

    def shoot():
        if simulator:
            simulator.wait(timeout=3)
            if simulator.returncode:
                raise RuntimeError(f'telemetry simulator exited {simulator.returncode}')
        window.telemetry.refresh(force=True)
        window.grab().save(out)
        engine.ethernet.stop_receive()
        print(f"saved {out}")
        window.close()

    QTimer.singleShot(args.simulate_seconds * 1000 + 800, shoot)
    app.exec()


if __name__ == "__main__":
    main()
