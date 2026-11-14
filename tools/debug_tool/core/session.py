"""session.py — SoC console design 4.2–4.3; host, no clock domain.

Own the board's serial reference, UDP receiver and project capabilities.
HELLO establishes the peer; STATE owns application settings.
"""

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
        self.discovery_stop = threading.Event()
        self.listeners = []
        self.build = ''
        self.state_generation = 0
        self.last_state = None
        self.last_request = None
        from .pipeline import preset
        self.chain = preset(1)
        self.chain_rev = 0
        self.pipe_stats = None
        self.board_state = dict(app=0, state=0, error=0, boxes=0, threshold=25,
                                classes=[0xffffffff, 0xffffffff, 0xffff],
                                chain_rev=0, request=0, frame=0, image_status=0)
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

    def received(self, kind, count=1):
        with self.lock:
            self.counts[kind] += count
            self.data_times[kind] = int(time.time() * 1000)
            self.mark('data')

    def fail(self, error):
        with self.lock:
            self.error = str(error)
        self.engine.add_entry('sys', str(error))

    def log(self, text):
        self.engine.add_entry('sys', text)

    def disconnect_network(self):
        with self.lock:
            self.discovery_stop.set()
            self.steps['peer']['done'] = False
            self.engine.virtual_input.reset()

    def disconnect(self):
        with self.lock:
            self.phase = 'disconnected'

    def feed_line(self, line):
        with self.lock:
            if 'BIOS menu:' in line:
                self.phase = 'bios'
            if (re.match(r'(Demo|Render(?:er)?|Showcase):', line)
                    or line.startswith(('RND display ready', 'board_render IDs', 'S3:', 'NPU '))):
                self.phase = 'application'
            key, separator, value = line.partition(':')
            key, value = key.strip(), value.strip()
            if key in ('DEMO ERROR', 'Input error'):
                self.fail(line)
            if separator and key in STATUS_KEYS:
                self.summary[key] = value
    def notify(self):
        for listener in list(self.listeners):
            listener()

    def receive_state(self, message_type, payload):
        import struct
        from .showcase import HELLO, CHAIN_STATE, PIPE_STATS
        from .pipeline import unpack_chain, unpack_stats
        if message_type == CHAIN_STATE:
            with self.lock:
                self.chain_rev = struct.unpack_from("<I", payload)[0]
                self.chain = unpack_chain(payload[4:])
                self.error = None
            self.notify()
            return
        if message_type == PIPE_STATS:
            with self.lock:
                self.pipe_stats = unpack_stats(payload)
            self.notify()
            return
        with self.lock:
            if message_type == HELLO:
                proto, = struct.unpack_from('<H', payload)
                if proto != 3:
                    raise ValueError(f'HELLO protocol {proto}, expected 3')
                self.build = payload[4:20].split(b'\0', 1)[0].decode('ascii')
                payload = payload[20:]
                self.mark('peer')
                self.phase = 'application'
                self.engine.virtual_input.start()
            self.state_generation += 1
            self.last_state = time.monotonic()
            app, state, error, boxes, threshold = struct.unpack_from('<5B', payload)
            classes = list(struct.unpack_from('<3I', payload, 8))
            request, frame, image_status = struct.unpack_from('<IIB', payload, 44)
            self.board_state = dict(app=app, state=state, error=error, boxes=boxes,
                                    threshold=threshold, classes=classes,
                                    chain_rev=struct.unpack_from('<I', payload, 20)[0],
                                    request=request, frame=frame, image_status=image_status)
        self.notify()

    def network_tick(self, now=None):
        now = time.monotonic() if now is None else now
        with self.lock:
            if self.steps['peer']['done'] and now - self.last_state >= 3:
                self.steps['peer']['done'] = False
                self.last_request = None
                self.engine.virtual_input.reset()
                self.notify()
            if not self.steps['peer']['done']:
                if self.last_request is None or now - self.last_request >= 2:
                    self._send_connection_request()
                    self.last_request = now

    def _monitor_network(self, stop):
        while not stop.wait(.05):
            try:
                with self.lock:
                    if stop.is_set():
                        return
                    self.network_tick()
            except (OSError, ValueError, RuntimeError) as exc:
                self.fail(f'建立网口连接失败：{exc}')
                return

    def _send_connection_request(self):
        self.ethernet.wait_for_link(self.ethernet.local_ip)
        with self.lock:
            self.ethernet.rx_socket.sendto(next(packets(b'\0', 3, 0)),
                                          self.network_endpoint)
            self.mark('win3')
            board_ip, board_port = self.network_endpoint
            self.log(f'连接请求已发送：{board_ip}:{board_port}；本机 {self.expected_peer}')

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
            self.discovery_stop.set()
            self.discovery_stop = threading.Event()
            self.last_request = None
            self.network_tick()
            threading.Thread(target=self._monitor_network, args=(self.discovery_stop,),
                             daemon=True, name='network-discovery').start()
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
                        build=self.build, state=dict(self.board_state),
                        error=self.error or self.engine.program.status()['error'])
