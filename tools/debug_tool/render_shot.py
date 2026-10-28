"""Offscreen render test: build the main window, seed demo data, dump a PNG.

Run:  python render_shot.py [out.png]
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication

from core.engine import SerialEngine
from gui.app import MainWindow


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "render.png"
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
    window.show()

    def shoot():
        window.grab().save(out)
        print(f"saved {out}")
        app.quit()

    QTimer.singleShot(600, shoot)
    app.exec()


if __name__ == "__main__":
    main()
