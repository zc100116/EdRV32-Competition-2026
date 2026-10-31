"""session.py — SoC console design 4.2–4.3; host, no clock domain.

Own the board's serial reference, UDP receiver and project capabilities.
Serial status lines confirm the phase and the peer learned by the FPGA.
"""

import ipaddress
import re
import threading
import time

from .ethernet import EthernetTool, packets
from .telemetry import Telemetry
from .video import VideoReceiver
from .yolo import YoloTool

STATUS_KEYS = ('Scene', 'PIX mode', 'GEO mode', 'Output mode', 'Requested video fps',
               'Monitor Hz', 'Detection count', 'Overlay CPU cycles',
               'Monitor dropped records', 'Switch', 'PIX parameters', 'GEO parameters')


class BoardSession:
    def __init__(self, engine):
        self.engine = engine
        self.lock = threading.RLock()
        self.phase = 'disconnected'
        self.error = None
        self.summary = {}
        self.network_endpoint = ('192.168.1.10', 5000)
        self.expected_peer = None
        self.peer_ip = None
        self.peer_port = None
        self.steps = {key: dict(done=False, time=None) for key in
                      ('listen', 'win3', 'peer', 'data')}
        self.counts = dict(video=0, telemetry=0)
        self.data_times = dict(video=None, telemetry=None)
        self.telemetry = Telemetry()
        self.video = VideoReceiver()
        self.ethernet = EthernetTool(self.telemetry)
        self.yolo = YoloTool(self.ethernet)
        self.ethernet.video = self.video
        self.ethernet.yolo = self.yolo
        self.ethernet.session = self

    def mark(self, name, done=True):
        self.steps[name] = dict(done=done, time=int(time.time() * 1000))

    def listening(self, port):
        with self.lock:
            self.steps = {key: dict(done=False, time=None) for key in self.steps}
            self.mark('listen')
            self.counts = dict(video=0, telemetry=0)
            self.data_times = dict(video=None, telemetry=None)
            self.expected_peer = None
            self.peer_ip = self.peer_port = None
            self.error = None

    def received(self, kind):
        with self.lock:
            self.counts[kind] += 1
            self.data_times[kind] = int(time.time() * 1000)
            self.mark('data')

    def fail(self, error):
        with self.lock:
            self.error = str(error)
        self.engine.add_entry('sys', str(error))

    def log(self, text):
        self.engine.add_entry('sys', text)

    def disconnect(self):
        with self.lock:
            self.phase = 'disconnected'
            self.steps['peer']['done'] = False

    def feed_line(self, line):
        with self.lock:
            if 'BIOS menu:' in line:
                self.phase = 'bios'
                self.steps['peer']['done'] = False
            if (re.match(r'(Demo|Render(?:er)?):', line)
                    or line.startswith(('RND display ready', 'board_render IDs', 'S3:', 'NPU '))):
                self.phase = 'application'
            key, separator, value = line.partition(':')
            key, value = key.strip(), value.strip()
            if key in ('DEMO ERROR', 'Input error'):
                self.fail(line)
            if separator and key in STATUS_KEYS:
                self.summary[key] = value
            if key == 'ETH peer IP':
                self.peer_ip = str(ipaddress.IPv4Address(int(value, 16)))
            if key == 'ETH peer port':
                self.peer_port = int(value)
                actual = [self.peer_ip, self.peer_port]
                self.mark('peer', self.expected_peer is not None and actual == self.expected_peer)
                if self.expected_peer is not None and actual != self.expected_peer:
                    self.fail(f'ETH peer 不一致：板端 {actual}，本机 {self.expected_peer}')

    def establish_network(self, board_ip='192.168.1.10', board_port=5000,
                          local_ip=None):
        self.network_endpoint = (board_ip, board_port)
        if local_ip is not None:
            self.ethernet.local_ip = local_ip
        local_ip = self.ethernet.local_ip
        try:
            rx = self.ethernet.status()['rx']
            if rx['active'] and (rx['localPort'] != 6000 or rx['localIp'] != local_ip):
                self.ethernet.stop_receive()
                rx = self.ethernet.status()['rx']
            if not rx['active']:
                self.ethernet.start_receive(6000, mode='console')
            self.ethernet.mode = 'console'
            with self.lock:
                self.expected_peer = [local_ip, self.ethernet.status()['rx']['localPort']]
                self.peer_ip = self.peer_port = None
                self.steps['peer'] = dict(done=False, time=None)
                self.error = None
            self.ethernet.rx_socket.sendto(next(packets(b'\0', 3, 0)),
                                           (board_ip, board_port))
            with self.lock:
                self.mark('win3')
            self.log(f'连接请求已发送：{board_ip}:{board_port}；本机 {self.expected_peer}')
        except (OSError, ValueError, RuntimeError) as exc:
            self.fail(f'建立网口连接失败：{exc}')
            raise
        return self.status()

    def status(self):
        rx = self.ethernet.status()['rx']
        with self.lock:
            steps = {key: dict(value) for key, value in self.steps.items()}
            steps['listen']['done'] = rx['active']
            return dict(phase=self.phase, network=steps, counts=dict(self.counts),
                        dataTimes=dict(self.data_times), expectedPeer=self.expected_peer,
                        peer=[self.peer_ip, self.peer_port], summary=dict(self.summary),
                        error=self.error or self.engine.program.status()['error'])
