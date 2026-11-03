"""virtual_input.py — Task T-VIN1 complete input frames; host monotonic clock.

One state change sends immediately. Connected devices send every 100 ms, including released state.
"""
import struct
import threading

from .ethernet import packets

FRAME = struct.Struct('<HhhBB')
KEYS = ('up', 'down', 'left', 'right', 'a', 'b', 'select', 'start',
        'enter', 'esc', 'next', 'prev')


class VirtualInput:
    def __init__(self, send, available=lambda: True):
        self.send = send
        self.available = available
        self.state = (0, 0, 0, 0, 0)
        self.lock = threading.RLock()
        self.stopped = threading.Event()
        self.thread = None

    def update(self, keys, x, y, mouse, wheel=None):
        with self.lock:
            state = (keys, x, y, mouse, self.state[4] if wheel is None else wheel & 255)
            if state == self.state:
                return
            if not self.available():
                raise RuntimeError('网口未连接，虚拟设备不可用')
            self.state = state
            self._send()
            self.start()

    def start(self):
        if self.thread is None or not self.thread.is_alive():
            self.stopped.clear()
            self.thread = threading.Thread(target=self._repeat, daemon=True,
                                           name='virtual-input')
            self.thread.start()

    def reset(self):
        with self.lock:
            self.state = (0, self.state[1], self.state[2], 0, self.state[4])

    def _send(self):
        self.send(FRAME.pack(*self.state))

    def _repeat(self):
        while not self.stopped.wait(.1):
            with self.lock:
                if not self.available():
                    self.thread = None
                    return
                self._send()

    def close(self):
        self.stopped.set()
        if self.thread:
            self.thread.join()


def channel(engine):
    return ('网口' if engine.board.steps['peer']['done'] and engine.ethernet.rx_socket
            else '未连接')


def send_frame(engine, frame):
    if channel(engine) == '网口':
        engine.ethernet.send_datagram(next(packets(frame, 2, 0)),
                                    engine.board.network_endpoint)
    else:
        raise RuntimeError('网口未连接，虚拟设备不可用')
