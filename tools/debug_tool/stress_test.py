"""Stress test: blast the engine with RX lines and check the GUI event loop
stays responsive (a 10 ms ticker must keep ticking while data streams in).

Run: python stress_test.py (serial GUI); --udp-video (30 s, 720p, 30 fps).
UDP payload packets are paced at 116 MB/s to match a gigabit board link.
--pattern uniform spreads 1800 packets across each 1/30 s frame;
--pattern short sends complete 1280x160 frames (400 packets); --gui shows video.
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


def udp_sender(port, pattern='line'):
    import json
    from core.ethernet import packets
    from core.video import VIDEO_HEADER
    height = 160 if pattern == 'short' else 720
    payloads = list(packets(bytes(1280 * height * 2), 0, 32))
    interval = 1 / (30 * len(payloads)) if pattern == 'uniform' else 1024 / 116_000_000
    start = time.monotonic()
    next_packet = time.perf_counter()
    sent_frames = 0
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for frame_id in range(900):
            if time.monotonic() - start >= 30:
                break
            header = VIDEO_HEADER.pack(b'EDVF', 1, 1, 1280, height, 2560,
                                       frame_id, frame_id * 3333333, 1)
            wire_header = next(packets(header, 0, 0))
            sock.sendto(wire_header[:1] + b'\0' + wire_header[2:], ('127.0.0.1', port))
            if pattern != 'uniform':
                next_packet = time.perf_counter()
            for packet in payloads:
                while time.perf_counter() < next_packet:
                    pass
                next_packet = time.perf_counter() + interval
                sock.sendto(packet, ('127.0.0.1', port))
            sent_frames += 1
            delay = start + (frame_id + 1) / 30 - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    print(json.dumps(dict(sender_seconds=time.monotonic() - start,
                          sent_frames=sent_frames)), flush=True)


def udp_stress(pattern='line', gui=False):
    import json
    import subprocess
    from tempfile import TemporaryDirectory
    engine = SerialEngine()
    if gui:
        from PySide6.QtCore import QTimer
        from PySide6.QtWidgets import QApplication
        from gui.app import MainWindow
        app = QApplication([])
        window = MainWindow(engine)
        window._select_page(4)
        window.show()
        app.processEvents()
    ethernet = engine.ethernet
    ethernet.local_ip = '127.0.0.1'
    with TemporaryDirectory() as directory:
        state = ethernet.start_receive(0, directory, mode='console')
        actual_buffer = ethernet.rx_socket.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
        started = time.monotonic()
        sender = subprocess.Popen(
            [sys.executable, __file__, '--udp-sender', str(state['localPort']), pattern],
            stdout=subprocess.PIPE, text=True)
        if gui:
            timer = QTimer()
            timer.timeout.connect(lambda: app.quit() if sender.poll() is not None else None)
            timer.start(20)
            app.exec()
        stdout, _ = sender.communicate()
        if sender.returncode:
            raise subprocess.CalledProcessError(sender.returncode, sender.args)
        sent = json.loads(stdout)
        sender_seconds = sent['sender_seconds']
        sent_frames = sent['sent_frames']
        time.sleep(.2)
        ethernet.stop_receive()
        elapsed = time.monotonic() - started
        video = engine.video.snapshot()
        rx = ethernet.status()['rx']
        cpu_seconds = rx['receiveCpuSeconds']
        print(json.dumps(dict(pattern=pattern, gui=gui,
                              sent_frames=sent_frames, received_frames=video['received'],
                              sender_seconds=sender_seconds,
                              sender_fps=sent_frames / sender_seconds,
                              received_fps=video['received'] / sender_seconds,
                              dropped_frames=video['dropped'],
                              missing_frames=sent_frames - video['received'],
                              receive_cpu_seconds=cpu_seconds,
                              receive_cpu_percent=100 * cpu_seconds / sender_seconds,
                              elapsed_seconds=elapsed, socket_buffer_bytes=actual_buffer,
                              dropped_packets=sent_frames * (401 if pattern == 'short' else 1801)
                                              - rx['packets'],
                              packets=rx['packets'], error=rx['error']), indent=2))
        if rx['error']:
            raise RuntimeError(rx['error'])
        if gui:
            print(f'displayed_frame_id={window.soc.displayed_frame.frame_id}', flush=True)
            window.close()
            app.processEvents()


def udp_yolo_sender(port):
    """Keep telemetry_sim's board return format, replacing only its slow pacing."""
    import telemetry_sim
    from core.ethernet import packets
    from core.showcase import encode, DONE, IMAGE
    import struct

    def line_block(sock, destination, data, window, offset=0, notify=True):
        deadline = time.perf_counter()
        for packet in packets(data, window, offset):
            if not notify:
                packet = packet[:1] + b'\0' + packet[2:]
            while time.perf_counter() < deadline:
                pass
            deadline = time.perf_counter() + 1024 / 116_000_000
            sock.sendto(packet, destination)

    telemetry_sim.send_block = line_block
    for _ in sys.stdin:
        telemetry_sim.run_yolo('127.0.0.1', port)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as done:
            message = encode(DONE, 0, struct.pack('<BB2xI', IMAGE, 0, 0))
            done.sendto(next(packets(message, 3, 0)), ('127.0.0.1', port))
        print('sent', flush=True)


def udp_yolo_stress():
    import json
    import subprocess
    from tempfile import TemporaryDirectory
    from core.showcase import DONE, IMAGE
    engine = SerialEngine()
    engine.ethernet.local_ip = '127.0.0.1'
    complete = 0
    with TemporaryDirectory() as directory:
        state = engine.ethernet.start_receive(0, directory, mode='console')
        sender = subprocess.Popen(
            [sys.executable, __file__, '--udp-yolo-sender', str(state['localPort'])],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        for _ in range(30):
            engine.yolo.request = 0
            engine.yolo.reset_capture()
            sender.stdin.write('send\n')
            sender.stdin.flush()
            if sender.stdout.readline() != 'sent\n':
                raise RuntimeError('YOLO sender exited before completing the return')
            message_type, payload = engine.ethernet.showcase._wait(0)
            if message_type != DONE:
                raise ValueError('YOLO sender expected DONE')
            engine.ethernet.showcase._done(payload, IMAGE)
            try:
                engine.yolo.complete_capture()
            except ValueError as exc:
                print(f'Image {_}: {exc}', file=sys.stderr)
            complete += engine.yolo.snapshot()[1] is not None
        sender.stdin.close()
        sender.wait()
        engine.ethernet.stop_receive()
        rx = engine.ethernet.status()['rx']
        print(json.dumps(dict(sent_images=30, complete_images=complete,
                              failed_images=engine.yolo.failed,
                              unfinished_images=30 - complete - engine.yolo.failed,
                              receive_cpu_seconds=rx['receiveCpuSeconds'],
                              socket_buffer_bytes=rx['socketBufferBytes'], error=rx['error']),
                         indent=2))
        if rx['error']:
            raise RuntimeError(rx['error'])


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == '--udp-video':
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument('--udp-video', action='store_true')
        parser.add_argument('--pattern', choices=['line', 'uniform', 'short'], default='line')
        parser.add_argument('--gui', action='store_true')
        args = parser.parse_args()
        udp_stress(args.pattern, args.gui)
    elif len(sys.argv) > 1 and sys.argv[1] == '--udp-sender':
        udp_sender(int(sys.argv[2]), sys.argv[3])
    elif len(sys.argv) > 1 and sys.argv[1] == '--udp-yolo':
        udp_yolo_stress()
    elif len(sys.argv) > 1 and sys.argv[1] == '--udp-yolo-sender':
        udp_yolo_sender(int(sys.argv[2]))
    else:
        serial_stress()
