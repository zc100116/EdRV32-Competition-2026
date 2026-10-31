"""Stress test: blast the engine with RX lines and check the GUI event loop
stays responsive (a 10 ms ticker must keep ticking while data streams in).

Run: python stress_test.py (serial GUI); --udp-video (30 s, 720p, 30 fps).
UDP payload packets are paced at 116 MB/s to match a gigabit board link.
"""

import os
import socket
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.engine import SerialEngine

TOTAL_LINES = 8000          # deliberately beyond the 5000-line doc cap
RUN_MS = 6000


def serial_stress():
    from PySide6.QtCore import QTimer
    from PySide6.QtWidgets import QApplication
    from gui.app import MainWindow

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


def udp_sender(port):
    from core.ethernet import packets
    from core.video import VIDEO_HEADER
    payloads = list(packets(bytes(1280 * 720 * 2), 0, 32))
    start = time.monotonic()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for frame_id in range(900):
            header = VIDEO_HEADER.pack(b'EDVF', 1, 1, 1280, 720, 2560,
                                       frame_id, frame_id * 3333333, 1)
            wire_header = next(packets(header, 0, 0))
            sock.sendto(wire_header[:1] + b'\0' + wire_header[2:], ('127.0.0.1', port))
            next_packet = time.perf_counter()
            for packet in payloads:
                while time.perf_counter() < next_packet:
                    pass
                next_packet = time.perf_counter() + 1024 / 116_000_000
                sock.sendto(packet, ('127.0.0.1', port))
            delay = start + (frame_id + 1) / 30 - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    print(f'sender_seconds={time.monotonic() - start:.6f}', flush=True)


def udp_stress():
    import json
    import subprocess
    from tempfile import TemporaryDirectory
    engine = SerialEngine()
    ethernet = engine.ethernet
    ethernet.local_ip = '127.0.0.1'
    receive = ethernet._receive
    timing = {}

    def measured_receive(*args):
        started = time.thread_time()
        try:
            receive(*args)
        finally:
            timing['cpu_seconds'] = time.thread_time() - started

    ethernet._receive = measured_receive
    with TemporaryDirectory() as directory:
        state = ethernet.start_receive(0, directory, mode='console')
        actual_buffer = ethernet.rx_socket.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
        started = time.monotonic()
        sender = subprocess.run(
            [sys.executable, __file__, '--udp-sender', str(state['localPort'])],
            check=True, capture_output=True, text=True)
        sender_seconds = float(sender.stdout.strip().split('=')[1])
        print(sender.stdout, end='')
        time.sleep(.2)
        ethernet.stop_receive()
        elapsed = time.monotonic() - started
        video = engine.video.snapshot()
        rx = ethernet.status()['rx']
        print(json.dumps(dict(sent_frames=900, received_frames=video['received'],
                              received_fps=video['received'] / sender_seconds,
                              dropped_frames=video['dropped'],
                              missing_frames=900 - video['received'],
                              receive_cpu_seconds=timing['cpu_seconds'],
                              receive_cpu_percent=100 * timing['cpu_seconds'] / sender_seconds,
                              elapsed_seconds=elapsed, socket_buffer_bytes=actual_buffer,
                              packets=rx['packets'], error=rx['error']), indent=2))
        if rx['error']:
            raise RuntimeError(rx['error'])


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == '--udp-video':
        udp_stress()
    elif len(sys.argv) > 1 and sys.argv[1] == '--udp-sender':
        udp_sender(int(sys.argv[2]))
    else:
        serial_stress()
