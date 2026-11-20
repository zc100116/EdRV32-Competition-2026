"""demo.py — live-demo L3 phone relay; host TCP thread survives GUI minimization."""
import json
import select
import struct
import socket
import threading
import time

SCENES = ('目标检测（80 类）', '手势识别', '人体姿态', '工地安全帽检测',
          '智慧农场', '图像处理（PIX + GEO）', '图形引擎', '抓取实验', '弹弓打靶',
          'CoreMark 跑分（芯片信息）', 'NES 经典游戏')
CHAPTERS = (('自研 NPU · 多模型部署',) * 3 + ('落地应用',) * 2 + ('自研图像处理',) + ('自研渲染器',) +
            ('体感交互',) * 2 + ('自研 CPU · 跑分与经典游戏',) * 2)
PRESETS = ('原始', '暗光增强', '降噪', '暗光增强 + 降噪')


def read_demo(line):
    value = json.loads(line)
    if not isinstance(value, dict) or set(value) not in ({'demo'}, {'pad'}, {'ui_act'}):
        raise ValueError('需要 demo、pad 或 ui_act 对象')
    if 'ui_act' in value:
        act = value['ui_act']
        fields = {'revision', 'id', 'action', 'value'}
        if (not isinstance(act, dict) or set(act) != fields
                or any(type(act[key]) is not int for key in fields)):
            raise ValueError('ui_act 需要整数 revision、id、action、value')
        return value
    if 'pad' in value:
        pad = value['pad']
        if (not isinstance(pad, dict) or set(pad) != {'keys'}
                or type(pad['keys']) is not int):
            raise ValueError('pad 需要整数 keys')
        return value
    demo = value['demo']
    if (not isinstance(demo, dict) or set(demo) != {'action', 'arg'}
            or any(type(demo[key]) is not int for key in ('action', 'arg'))):
        raise ValueError('demo 需要整数 action 和 arg')
    return value


class PhoneRelay:
    def __init__(self, board):
        self.board = board
        self.connected = False
        self.error = ''
        self.stop = threading.Event()
        self.thread = None
        self.socket = None

    def snapshot(self):
        from .showcase import DEMO
        status = self.board.status()
        state = status['state']
        return dict(board=dict(connected=status['network']['peer']['done'],
                               scene=state['demo_scene'], preset=state['preset'],
                               luma=state['luma'],
                               busy=DEMO in self.board.ethernet.showcase.pending))

    def connect(self, address):
        self.close()
        self.stop = threading.Event()
        self.error = ''
        self.thread = threading.Thread(target=self._run, args=(address,), daemon=True,
                                       name='phone-relay')
        self.thread.start()

    def _run(self, address):
        while not self.stop.is_set():
            try:
                with socket.socket() as connection:
                    self.socket = connection
                    connection.settimeout(1)
                    connection.connect((address, 47633))
                    self.connected = True
                    self.error = ''
                    buffer = b''
                    previous = None
                    sent = 0
                    previous_ui = None
                    ui_sent = 0
                    while not self.stop.is_set():
                        snapshot = self.snapshot()
                        now = time.monotonic()
                        if snapshot != previous or now - sent >= 1:
                            connection.sendall((json.dumps(snapshot) + '\n').encode())
                            previous, sent = snapshot, now
                        ui = self.board.ethernet.showcase.ui.snapshot
                        if ui != previous_ui or now - ui_sent >= 1:
                            connection.sendall((json.dumps(dict(ui=ui)) + '\n').encode())
                            previous_ui, ui_sent = ui, now
                        errors = self.board.ethernet.showcase.ui_errors
                        while not errors.empty():
                            error = dict(ui_error=dict(message=errors.get()))
                            connection.sendall((json.dumps(error) + '\n').encode())
                        if not select.select([connection], [], [], .05)[0]:
                            continue
                        data = connection.recv(4096)
                        if not data:
                            raise ConnectionError('手机连接已断开')
                        buffer += data
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            message = read_demo(line.decode('utf-8'))
                            if 'demo' in message:
                                try:
                                    self.board.ethernet.showcase.demo(**message['demo'])
                                except RuntimeError as exc:
                                    self.error = f'命令错误：{exc}'
                            elif 'ui_act' in message:
                                try:
                                    self.board.ethernet.showcase.ui_act(**message['ui_act'])
                                except RuntimeError as exc:
                                    self.error = f'命令错误：{exc}'
                            else:
                                self.board.engine.virtual_input.update_relay(message['pad']['keys'])
            except (OSError, ValueError, UnicodeError, TypeError, struct.error) as exc:
                if not self.stop.is_set():
                    self.error = f'手机中继错误：{exc}'
            except RuntimeError as exc:
                if not self.stop.is_set():
                    self.error = f'命令错误：{exc}'
            finally:
                self.connected = False
                self.socket = None
                self.board.engine.virtual_input.clear_relay()
            self.stop.wait(1)

    def close(self):
        self.stop.set()
        connection = self.socket
        if connection is not None:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError as exc:
                self.error = f'手机中继关闭：{exc}'
        if self.thread is not None:
            self.thread.join()
        self.connected = False
