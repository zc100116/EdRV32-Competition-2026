"""Stress test: blast the engine with RX lines and check the GUI event loop
stays responsive (a 10 ms ticker must keep ticking while data streams in).

Run:  python stress_test.py
"""

import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication

from core.engine import SerialEngine
from gui.app import MainWindow

TOTAL_LINES = 8000          # deliberately beyond the 5000-line doc cap
RUN_MS = 6000


def main():
    app = QApplication(sys.argv)
    engine = SerialEngine()
    window = MainWindow(engine)
    window.show()

    stats = {"ticks": 0, "flushes": 0, "max_batch": 0,
             "t0": time.perf_counter()}

    ticker = QTimer(window)
    ticker.setInterval(10)
    ticker.timeout.connect(lambda: stats.__setitem__("ticks",
                                                     stats["ticks"] + 1))
    ticker.start()

    orig_flush = window._flush_entries

    def timed_flush():
        t0 = time.perf_counter()
        orig_flush()
        n = window.console.text.document().blockCount()
        stats["flushes"] += 1
        stats["max_batch"] = max(stats["max_batch"], n)
        stats.setdefault("slowest", 0)
        stats["slowest"] = max(stats["slowest"], time.perf_counter() - t0)

    window._flush_entries = timed_flush  # noqa: method assignment

    def producer():
        for i in range(TOTAL_LINES):
            engine.add_entry("rx", f"[bench] frame {i:05d} "
                                   f"payload=0xDEADBEEF{i:08X}")
            if i % 500 == 0:
                time.sleep(0.001)

    threading.Thread(target=producer, daemon=True).start()

    def finish():
        elapsed = time.perf_counter() - stats["t0"]
        blocks = window.console.text.document().blockCount()
        expected_ticks = elapsed * 100
        print(f"elapsed          : {elapsed:.2f}s")
        print(f"GUI ticker ticks : {stats['ticks']} "
              f"(expected ~{expected_ticks:.0f}; "
              f"ratio {stats['ticks']/expected_ticks:.2f})")
        print(f"flushes          : {stats['flushes']}")
        print(f"slowest flush    : {stats.get('slowest', 0)*1000:.1f} ms")
        print(f"doc blocks       : {blocks} (cap {engine and 5000})")
        ok = stats["ticks"] >= expected_ticks * 0.9
        print("RESULT:", "PASS - GUI stayed responsive" if ok
              else "FAIL - event loop starved")
        app.quit()

    QTimer.singleShot(RUN_MS, finish)
    app.exec()


if __name__ == "__main__":
    main()
