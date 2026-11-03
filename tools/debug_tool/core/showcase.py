"""showcase.py — design 4.5.4 EDSC messages and serialized bulk transfers.
Host monotonic clock measures reply deadlines and echo round trips.
"""
import struct
import threading
import time

MESSAGE = struct.Struct('<4sHHI')
BULK_BEGIN, CAMERA, ECHO = 1, 2, 3
READY, DONE, ECHO_REPLY = 0x81, 0x82, 0x83
MODEL, IMAGE, GAME = 1, 2, 3
RESPONSE_TIMEOUT = 5.0
STATUS = {1: '长度不符', 2: '格式错误', 3: '空间不足'}


def encode(message_type, seq, payload=b''):
    if len(payload) > 1000:
        raise ValueError('EDSC payload exceeds 1000 bytes')
    return MESSAGE.pack(b'EDSC', message_type, len(payload), seq) + payload


def decode(data):
    magic, message_type, length, seq = MESSAGE.unpack_from(data)
    if magic != b'EDSC' or length > 1000 or len(data) != MESSAGE.size + length:
        raise ValueError('EDSC invalid magic or payload length')
    expected = {READY: 4, DONE: 8, CAMERA: 0, BULK_BEGIN: 8}
    if message_type in expected and length != expected[message_type]:
        raise ValueError(f'EDSC invalid payload length for type {message_type:#x}')
    if message_type not in (BULK_BEGIN, CAMERA, ECHO, READY, DONE, ECHO_REPLY):
        raise ValueError(f'EDSC unknown message type {message_type:#x}')
    return message_type, seq, bytes(data[MESSAGE.size:])


class ShowcaseTool:
    def __init__(self, ethernet):
        self.ethernet = ethernet
        self.condition = threading.Condition()
        self.replies = []
        self.receive_error = None
        self.seq = 0
        self.echo = dict(count=0, received=0, lost=0, averageMs=None)

    def receive(self, data):
        try:
            reply = decode(data)
        except (ValueError, struct.error) as exc:
            self.fail(str(exc))
            raise
        with self.condition:
            self.replies.append(reply)
            self.condition.notify()

    def fail(self, error):
        with self.condition:
            self.receive_error = error
            self.condition.notify()

    def _wait(self, seq):
        deadline = time.monotonic() + RESPONSE_TIMEOUT
        with self.condition:
            while True:
                if self.receive_error:
                    raise RuntimeError(self.receive_error)
                if self.replies:
                    reply = self.replies.pop(0)
                    if reply[1] != seq:
                        raise ValueError(f'EDSC reply sequence {reply[1]}, expected {seq}')
                    return reply[0], reply[2]
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f'设备回复超时（{RESPONSE_TIMEOUT:g} s）')
                self.condition.wait(remaining)

    def _start(self, operation, board_ip, board_port, local_port, total, name):
        eth = self.ethernet
        with eth.lock:
            if eth.tx['active']:
                raise RuntimeError('已有传输正在进行')
            eth.tx = dict(active=True, sent=0, total=total, packets=0, error=None,
                          path=name, index=None, phase='等待设备')
        try:
            if eth.rx_socket is not None and eth.rx_socket.getsockname()[0] != eth.local_ip:
                eth.stop_receive()
            if eth.rx_socket is None:
                eth.start_receive(local_port, mode=eth.mode)
        except (OSError, RuntimeError):
            with eth.lock:
                eth.tx['active'] = False
            raise
        with self.condition:
            self.replies.clear()
            self.receive_error = None
        threading.Thread(target=self._run, args=(operation, (board_ip, board_port)),
                         daemon=True, name='showcase-tx').start()
        return eth.status()['tx']

    def _run(self, operation, destination):
        eth = self.ethernet
        try:
            eth.wait_for_link(eth.local_ip)
            operation(destination)
        except (OSError, ValueError, RuntimeError, struct.error) as exc:
            with eth.lock:
                eth.tx['error'] = str(exc)
                eth.tx['phase'] = '失败'
        finally:
            if eth.yolo is not None:
                if eth.tx['error'] and eth.yolo.capture_pending:
                    with eth.yolo.lock:
                        eth.yolo._fail_capture(eth.tx['error'])
                else:
                    eth.yolo.image_sent(eth.tx['path'])
            with eth.lock:
                eth.tx['active'] = False
                if not eth.tx['error']:
                    eth.tx['phase'] = '完成'
            if eth.session:
                if eth.tx['error']:
                    eth.session.fail(f"传输失败：{eth.tx['error']}")
                else:
                    index = eth.tx['index']
                    suffix = f' · 序号 {index}' if index is not None else ''
                    eth.session.log(f"传输完成：{eth.tx['path']}{suffix}")

    def _message(self, destination, message_type, payload=b''):
        from .ethernet import packets
        self.seq = (self.seq + 1) & 0xffffffff
        self.ethernet.rx_socket.sendto(next(packets(encode(message_type, self.seq, payload),
                                                   3, 0)), destination)
        return self.seq

    @staticmethod
    def _done(payload, kind):
        actual_kind, status, index = struct.unpack('<BB2xI', payload)
        if actual_kind != kind:
            raise ValueError(f'EDSC DONE kind {actual_kind}, expected {kind}')
        if status:
            raise ValueError(f'设备拒绝传输：{STATUS.get(status, f"未知状态 {status}")}')
        return index

    def bulk(self, kind, data, board_ip, board_port, local_port, name):
        def transfer(destination):
            from .ethernet import HEADER, packets
            seq = self._message(destination, BULK_BEGIN, struct.pack('<B3xI', kind, len(data)))
            message_type, payload = self._wait(seq)
            if message_type == DONE:
                self._done(payload, kind)
                raise ValueError('EDSC DONE received before READY')
            if message_type != READY or payload != struct.pack('<B3x', kind):
                raise ValueError('EDSC expected READY for this transfer')
            with self.ethernet.lock:
                self.ethernet.tx['phase'] = '上传中'
            for packet in packets(data, 0, 0):
                self.ethernet.rx_socket.sendto(packet, destination)
                with self.ethernet.lock:
                    self.ethernet.tx['sent'] += len(packet) - HEADER.size
                    self.ethernet.tx['packets'] += 1
            with self.ethernet.lock:
                self.ethernet.tx['phase'] = '等待设备处理'
            message_type, payload = self._wait(seq)
            if message_type != DONE:
                raise ValueError('EDSC expected DONE')
            index = self._done(payload, kind)
            with self.ethernet.lock:
                self.ethernet.tx['index'] = index
        return self._start(transfer, board_ip, board_port, local_port, len(data), name)

    def camera(self, board_ip, board_port, local_port):
        return self._start(lambda dest: self._message(dest, CAMERA), board_ip, board_port,
                           local_port, 0, '回到摄像头检测')

    def echo_test(self, count, board_ip, board_port, local_port):
        def test(destination):
            elapsed = []
            self.echo = dict(count=count, received=0, lost=0, averageMs=None)
            for trial in range(count):
                payload = struct.pack('<I', trial)
                started = time.monotonic()
                seq = self._message(destination, ECHO, payload)
                with self.ethernet.lock:
                    self.ethernet.tx['sent'] += len(payload)
                    self.ethernet.tx['packets'] += 1
                    self.ethernet.tx['phase'] = '回环测试'
                try:
                    message_type, reply = self._wait(seq)
                except TimeoutError as exc:
                    with self.ethernet.lock:
                        self.echo['lost'] += 1
                        self.ethernet.tx['error'] = str(exc)
                    if self.ethernet.session:
                        self.ethernet.session.fail(f'回环测试第 {trial + 1} 次：{exc}')
                    continue
                if message_type != ECHO_REPLY or reply != payload:
                    raise ValueError('EDSC ECHO reply differs from request')
                elapsed.append((time.monotonic() - started) * 1000)
                with self.ethernet.lock:
                    self.echo.update(received=len(elapsed), averageMs=sum(elapsed) / len(elapsed))
            if self.ethernet.session:
                self.ethernet.session.log(f'回环测试：{self.echo}')
        return self._start(test, board_ip, board_port, local_port, count * 4, '回环测试')
