"""virtual_input.py — Task T-VIN1 complete input frames; host monotonic clock.

One state change sends immediately. Held buttons repeat every 20 ms.
"""
import struct
import threading

from .ethernet import packets

FRAME = struct.Struct('<HhhBB')
KEYS = ('up', 'down', 'left', 'right', 'a', 'b', 'select', 'start',
        'enter', 'esc', 'next', 'prev')


class VirtualInput:
    def __init__(self, send):
        self.send = send
        self.state = (0, 0, 0, 0, 0)
        self.lock = threading.RLock()
        self.stopped = threading.Event()
        self.thread = None

    def update(self, keys, x, y, mouse, wheel=None):
        with self.lock:
            state = (keys, x, y, mouse, self.state[4] if wheel is None else wheel & 255)
            if state == self.state:
                return
            self.state = state
            self._send()
            if (keys or mouse) and (self.thread is None or not self.thread.is_alive()):
                self.stopped.clear()
                self.thread = threading.Thread(target=self._repeat, daemon=True,
                                               name='virtual-input')
                self.thread.start()

    def _send(self):
        self.send(FRAME.pack(*self.state))

    def _repeat(self):
        while not self.stopped.wait(.02):
            with self.lock:
                if not (self.state[0] or self.state[3]):
                    self.thread = None
                    return
                self._send()

    def close(self):
        self.stopped.set()
        if self.thread:
            self.thread.join()


def channel(engine):
    board = engine.board.status()
    return '网口' if board['network']['peer']['done'] and engine.ethernet.rx_socket else '串口'


def send_frame(engine, frame):
    if channel(engine) == '网口':
        engine.ethernet.send_datagram(next(packets(frame, 2, 0)),
                                    engine.board.network_endpoint)
    elif not engine.virtual_serial_paused:
        engine.send((b'\x1bV' + frame).hex(), ending='none', hex_mode=True)
