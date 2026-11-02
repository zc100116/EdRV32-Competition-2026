"""ethernet.py — eth spec 2.1–2.6 UDP application files; host, no clock domain.

Send at most 1024 data bytes per datagram and set NOTIFY on the last datagram.
Receive each window into its own file at the exact application OFFSET.
"""

from pathlib import Path
import multiprocessing
from multiprocessing import shared_memory
import socket
import selectors
import struct
import threading
import time

from tools.board.link_wait import wait_for_link

HEADER = struct.Struct("!BBHI")
DATA_BYTES = 1024
DEFAULT_SAVE_DIR = Path(__file__).resolve().parents[3] / "build/debug_tool/udp-rx"
VIDEO_SLOT_BYTES = 1280 * 720 * 2
VIDEO_SLOTS = 3


def _video_process(sock, name, connection, stop, capture_event, capture_epoch,
                   return_time, mode, counts):
    """Own the socket and frame assembly outside Qt's Python interpreter."""
    memory = shared_memory.SharedMemory(name=name)
    started = time.process_time()
    try:
        _video_loop(sock, memory.buf, connection, stop, capture_event, capture_epoch,
                    return_time, mode, counts)
    except (OSError, struct.error, ValueError) as exc:
        connection.send(('error', str(exc)))
    finally:
        memory.close()
        sock.close()
        connection.send(('done', time.process_time() - started))
        connection.close()


def _video_loop(sock, storage, connection, stop, capture_event, capture_epoch,
                return_time, mode, counts):
    from .video import VideoReceiver
    from .yolo import YoloTool, INPUT_BYTES, OUTPUT_BYTES

    free = list(range(VIDEO_SLOTS))
    active = None

    def take_slot():
        while connection.poll():
            free.append(connection.recv())
        if not free:
            free.append(connection.recv())
        return free.pop()

    def allocate(size):
        nonlocal active
        if active is None:
            active = take_slot()
        start = active * VIDEO_SLOT_BYTES
        return storage[start:start + size]

    video = VideoReceiver(buffer_factory=allocate)
    video.received, video.dropped = counts
    yolo = YoloTool(None)
    capture_started = False
    epoch = 0
    routes = {}
    packet = storage[VIDEO_SLOTS * VIDEO_SLOT_BYTES:]
    sock.setblocking(True)
    connection.send(('ready',))
    count = byte_count = notifications = video_count = 0
    route_video = mode == 'video'
    last = None

    def publish():
        nonlocal count, byte_count, notifications, video_count
        if count:
            connection.send(('stats', count, byte_count, notifications, video_count, last,
                             video.received, video.dropped))
            count = byte_count = notifications = video_count = 0

    try:
        while True:
            length, peer = sock.recvfrom_into(packet)
            if length == 0 and stop.is_set():
                break
            window, flags, _, offset = HEADER.unpack_from(packet[:length])
            window &= 3
            notify = bool(flags & 1)
            data = packet[HEADER.size:length]
            if offset == 0 and capture_epoch.value != epoch:
                epoch = capture_epoch.value
                yolo.reset_capture()
                capture_started = False
            if window == 0 and offset == 0 and mode == 'console':
                route_video = data[:4] == b'EDVF'
            if mode == 'yolo':
                is_yolo = window in (0, 1, 2)
            else:
                if offset == 0:
                    if window == 0 and route_video:
                        routes[window] = False
                    elif window == 2 and data[:4] == b'EDDT':
                        routes[window] = capture_started
                    else:
                        routes[window] = window in (0, 1, 2) and capture_event.is_set()
                is_yolo = routes.get(window, False)
            if is_yolo:
                return_time.value = time.monotonic()
                if not capture_started:
                    yolo.reset_capture()
                    capture_started = True
                yolo.receive(window, offset, data, notify)
                if window == 2 and notify:
                    capture_started = False
                    capture_event.clear()
                    if yolo.error is not None:
                        connection.send(('yolo_failed', epoch, yolo.error))
                    else:
                        slot = take_slot()
                        start = slot * VIDEO_SLOT_BYTES
                        ch2, output, _ = yolo.capture
                        storage[start:start + INPUT_BYTES] = ch2
                        storage[start + INPUT_BYTES:start + INPUT_BYTES + OUTPUT_BYTES] = output
                        connection.send(('yolo', epoch, slot, yolo.blocks[2].data()))
                # These packets are accounted here, rather than again on bulk delivery.
                count += 1
                byte_count += len(data)
                notifications += int(notify)
                last = window, offset, notify, peer
                if count >= 256 or notify:
                    publish()
                continue
            if window != 0 or not route_video:
                connection.send(('packet', bytes(packet[:length]), peer))
                continue
            before = video.received
            video.receive(0, offset, data, notify)
            if video.received != before:
                frame = video.frame
                connection.send(('frame', active, frame.width, frame.height,
                                 frame.stride, frame.frame_id, frame.mtime, frame.scene,
                                 video.received, video.dropped))
                active = None
            count += 1
            video_count += 1
            byte_count += len(data)
            notifications += int(notify)
            last = window, offset, notify, peer
            if count >= 256 or notify:
                publish()
        video.finish()
        publish()
        connection.send(('video_counts', video.received, video.dropped))
    finally:
        sock.setblocking(False)


def packets(data, window, offset):
    """eth 2.3 / 2.6: zero ignored fields; an empty file sends one notification."""
    if window not in range(4):
        raise ValueError("window must be 0..3 (eth spec 2.3)")
    for start in range(0, max(1, len(data)), DATA_BYTES):
        chunk = data[start:start + DATA_BYTES]
        notify = start + len(chunk) == len(data)
        yield HEADER.pack(window, int(notify), 0, offset + start) + chunk


def unpack(packet):
    window, flags, _, offset = HEADER.unpack(packet[:HEADER.size])
    return window & 3, bool(flags & 1), offset, packet[HEADER.size:]


class EthernetTool:
    def __init__(self, telemetry=None, local_ip="192.168.1.2"):
        self.local_ip = local_ip
        self.session = None
        self.telemetry = telemetry
        self.video = None
        self.yolo = None
        self.mode = "files"
        self.lock = threading.Lock()
        self.rx_socket = None
        self.rx_thread = None
        self.rx_process = None
        self.rx_memory = None
        self.rx_process_stop = None
        self.rx_capture_event = None
        self.rx_capture_epoch = None
        self.rx_return_time = None
        self.stop_event = threading.Event()
        self.tx = {"active": False, "sent": 0, "total": 0, "packets": 0, "error": None}
        self.rx = {"active": False, "packets": 0, "bytes": 0, "notifyCount": 0,
                   "lastNotify": False, "files": {}, "error": None, "socketBufferBytes": 0}

    def status(self):
        with self.lock:
            return {"tx": dict(self.tx), "rx": {**self.rx, "files": dict(self.rx["files"])}}

    def send_file(self, path, board_ip, board_port, local_port, window=0, offset=0,
                  interval=0):
        data = Path(path).read_bytes()
        return self.send_blocks([(window, offset, data)], board_ip, board_port,
                                local_port, interval, str(path))

    def send_blocks(self, blocks, board_ip, board_port, local_port, interval=0,
                    name="data"):
        datagrams = []
        total = 0
        for window, offset, data in blocks:
            datagrams.extend(packets(data, window, offset))
            total += len(data)
        # One notification marks the end of the entire image, including sparse blocks.
        datagrams = [packet[:1] + bytes([int(i == len(datagrams) - 1)]) + packet[2:]
                     for i, packet in enumerate(datagrams)]
        if interval < 0:
            raise ValueError("packet interval must be nonnegative")
        with self.lock:
            if self.tx["active"]:
                raise RuntimeError("UDP file send is already active")
            self.tx = {"active": True, "sent": 0, "total": total, "packets": 0,
                       "path": name, "error": None}
            receiver = self.rx_socket
            if receiver is not None and receiver.getsockname()[0] != self.local_ip:
                receiver = None
        threading.Thread(target=self._send, args=(datagrams, board_ip, board_port,
                                                  local_port, interval, receiver, self.local_ip),
                         name="udp-file-tx", daemon=True).start()
        return self.status()["tx"]

    def _send(self, datagrams, board_ip, board_port, local_port, interval, receiver,
              local_ip):
        sock = (receiver if receiver is not None
                else socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        try:
            if receiver is None:
                sock.bind((local_ip, local_port))
            self.wait_for_link(local_ip)
            for index, packet in enumerate(datagrams):
                if index and interval:
                    time.sleep(interval)
                sock.sendto(packet, (board_ip, board_port))
                with self.lock:
                    self.tx["sent"] += len(packet) - HEADER.size
                    self.tx["packets"] += 1
        except OSError as exc:
            with self.lock:
                self.tx["error"] = f"UDP {local_ip}:{local_port}: {exc}"
        finally:
            if receiver is None:
                sock.close()
            if self.yolo is not None:
                self.yolo.image_sent(self.tx['path'])
            with self.lock:
                self.tx["active"] = False
            if self.session:
                state = self.status()['tx']
                if state['error']:
                    self.session.fail(f"UDP 发送失败：{state['error']}")
                else:
                    self.session.log(f"UDP 发送完成：{state['sent']} B · {state['path']}")

    def wait_for_link(self, local_ip):
        name, elapsed = wait_for_link(local_ip)
        message = f'等待网卡 {name} 就绪 … 用时 {elapsed:.1f} s'
        if self.session:
            self.session.log(message)
        else:
            print(message)

    def send_datagram(self, packet, destination):
        """Send a single control/input packet through the listening socket."""
        self.wait_for_link(self.local_ip)
        self.rx_socket.sendto(packet, destination)

    def start_receive(self, local_port, directory=None, mode="files"):
        if self.rx_socket is not None:
            raise RuntimeError("UDP receive is already active")
        self.mode = mode
        if mode == 'yolo':
            self.yolo.reset_capture()
        directory = Path(directory) if directory else DEFAULT_SAVE_DIR
        directory.mkdir(parents=True, exist_ok=True)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 64 * 1024 * 1024)
            buffer_bytes = sock.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
            sock.bind((self.local_ip, local_port))
            sock.setblocking(False)
        except OSError as exc:
            sock.close()
            raise OSError(f"UDP bind {self.local_ip}:{local_port}: {exc}") from exc
        self.stop_event.clear()
        with self.lock:
            self.rx_socket = sock
            self.rx = {"active": True, "localIp": sock.getsockname()[0],
                       "localPort": sock.getsockname()[1], "socketBufferBytes": buffer_bytes,
                       "directory": str(directory), "packets": 0, "bytes": 0,
                       "notifyCount": 0, "lastNotify": False, "files": {}, "error": None,
                       "receiveCpuSeconds": 0.0}
        if self.session:
            self.session.listening(sock.getsockname()[1])
            self.session.log(f'UDP 已监听 {self.local_ip}:{sock.getsockname()[1]} · {mode}')
        connection = None
        if mode in ('video', 'console', 'yolo'):
            context = multiprocessing.get_context('spawn')
            self.rx_memory = shared_memory.SharedMemory(
                create=True, size=VIDEO_SLOTS * VIDEO_SLOT_BYTES + 65535)
            connection, child = context.Pipe()
            self.rx_process_stop = context.Event()
            self.rx_capture_event = context.Event()
            self.rx_capture_epoch = context.Value('Q', 0)
            self.rx_return_time = context.Value('d', 0)
            if self.yolo.capture_pending:
                self.rx_capture_event.set()
            counts = self.video.snapshot()
            self.rx_process = context.Process(
                target=_video_process,
                args=(sock, self.rx_memory.name, child, self.rx_process_stop,
                      self.rx_capture_event, self.rx_capture_epoch, self.rx_return_time, mode,
                      (counts['received'], counts['dropped'])),
                name='udp-video-rx', daemon=True)
            self.rx_process.start()
            child.close()
            message = connection.recv()
            if message != ('ready',):
                raise RuntimeError(f'UDP receive process startup: {message}')
        self.rx_thread = threading.Thread(target=self._receive,
                                          args=(sock, directory, connection),
                                          name="udp-file-rx", daemon=True)
        self.rx_thread.start()
        return self.status()["rx"]

    def _receive(self, sock, directory, connection=None):
        files = {}
        routes = {}
        selector = selectors.DefaultSelector()
        if connection is None:
            selector.register(sock, selectors.EVENT_READ)
        storage = bytearray(65535)
        view = memoryview(storage)
        count = byte_count = notifications = video_count = 0
        last = None

        def publish():
            nonlocal count, byte_count, notifications, video_count
            if not count:
                return
            with self.lock:
                self.rx["packets"] += count
                self.rx["bytes"] += byte_count
                self.rx["notifyCount"] += notifications
                self.rx.update(lastWindow=last[0], lastOffset=last[1], lastNotify=last[2],
                               peer=[last[3][0], last[3][1]])
            if self.session and video_count:
                self.session.received('video', video_count)
            count = byte_count = notifications = video_count = 0

        readable = False
        try:
            while connection is not None or not self.stop_event.is_set():
                if connection is not None:
                    self.yolo.check_timeout()
                    if not connection.poll(.05):
                        continue
                    message = connection.recv()
                    if message[0] == 'done':
                        with self.lock:
                            self.rx['receiveCpuSeconds'] = message[1]
                        break
                    if message[0] == 'error':
                        raise ValueError(message[1])
                    if message[0] == 'video_counts':
                        with self.video.lock:
                            self.video.received, self.video.dropped = message[1:]
                        continue
                    if message[0] == 'stats':
                        _, n, size, notified, video_packets, latest, received, dropped = message
                        with self.lock:
                            self.rx['packets'] += n
                            self.rx['bytes'] += size
                            self.rx['notifyCount'] += notified
                            self.rx.update(lastWindow=latest[0], lastOffset=latest[1],
                                           lastNotify=latest[2], peer=list(latest[3]))
                        with self.video.lock:
                            self.video.received, self.video.dropped = received, dropped
                        if self.session and video_packets:
                            self.session.received('video', video_packets)
                        continue
                    if message[0] == 'frame':
                        from .video import VideoFrame
                        (_, slot, width, height, stride, frame_id, mtime, scene,
                         received, dropped) = message
                        start = slot * VIDEO_SLOT_BYTES
                        pixels = bytes(self.rx_memory.buf[start:start + height * stride])
                        connection.send(slot)
                        frame = VideoFrame(width, height, stride, frame_id, mtime, scene,
                                           memoryview(pixels))
                        with self.video.lock:
                            self.video.frame = frame
                            self.video.received, self.video.dropped = received, dropped
                            self.video.frame_detections = None
                            self.video.rate.add(self.video.clock())
                        continue
                    if message[0] == 'yolo_failed':
                        if message[1] != self.rx_capture_epoch.value:
                            continue
                        with self.yolo.lock:
                            self.yolo._fail_capture(message[2])
                        continue
                    if message[0] == 'yolo':
                        from .yolo import INPUT_BYTES, OUTPUT_BYTES
                        _, epoch, slot, detections = message
                        if epoch != self.rx_capture_epoch.value:
                            connection.send(slot)
                            continue
                        start = slot * VIDEO_SLOT_BYTES
                        raw = bytes(self.rx_memory.buf[start:start + INPUT_BYTES + OUTPUT_BYTES])
                        connection.send(slot)
                        for window, block in enumerate((raw[:INPUT_BYTES], raw[INPUT_BYTES:],
                                                        detections)):
                            self.yolo.receive(window, 0, block, window == 2)
                            if window not in files:
                                path = directory / f'window{window}.bin'
                                files[window] = path.open('w+b')
                                with self.lock:
                                    self.rx['files'][str(window)] = str(path)
                            files[window].seek(0)
                            files[window].truncate(0)
                            files[window].write(block)
                            files[window].flush()
                        continue
                    _, packet, peer = message
                    length = len(packet)
                    view = memoryview(packet)
                else:
                    if not readable:
                        readable = bool(selector.select(0.1))
                        if not readable:
                            publish()
                            continue
                    try:
                        length, peer = sock.recvfrom_into(storage)
                    except BlockingIOError:
                        readable = False
                        continue
                window, flags, _, offset = HEADER.unpack_from(view[:length])
                window &= 3
                notify = bool(flags & 1)
                data = view[HEADER.size:length]
                fast_video = (window == 0 and offset != 0 and
                              (self.mode == 'video' or
                               (self.mode == 'console' and routes.get(0) == 'video')))
                if fast_video:
                    self.video.receive(0, offset, data, notify)
                else:
                    video = self.mode == 'video' and window in (0, 2)
                    yolo = self.mode == 'yolo' and window in (0, 1, 2)
                    telemetry = window == 3 and self.telemetry is not None
                    save_file = not video
                    if self.mode == 'console':
                        if offset == 0:
                            if window == 0 and data[:4] == b'EDVF':
                                routes[window] = 'video'
                            elif window == 2 and data[:4] == b'EDDT':
                                routes[window] = ('yolo' if self.yolo.capture_pending and
                                                  self.yolo.capture_started else 'video')
                            elif window in (0, 1, 2) and self.yolo.capture_pending:
                                routes[window] = 'yolo'
                                self.yolo.capture_started = True
                            elif window == 3 and data[:4] == b'EDTM':
                                routes[window] = 'telemetry'
                            else:
                                routes[window] = 'files'
                        route = routes.get(window, 'files')
                        video, yolo = route == 'video', route == 'yolo'
                        telemetry = route == 'telemetry'
                        save_file = route in ('files', 'yolo')
                    if telemetry:
                        self.telemetry.receive(offset, data, notify)
                        if self.session:
                            self.session.received('telemetry')
                    if video:
                        self.video.receive(window, offset, data, notify)
                    elif yolo:
                        self.yolo.receive(window, offset, data, notify)
                    if save_file:
                        if window not in files:
                            path = directory / f"window{window}.bin"
                            files[window] = path.open("w+b")
                            with self.lock:
                                self.rx["files"][str(window)] = str(path)
                        output = files[window]
                        if yolo and offset == 0:
                            output.truncate(0)
                        output.seek(offset)
                        output.write(data)
                        output.flush()
                    fast_video = video and window == 0
                count += 1
                video_count += int(fast_video)
                byte_count += len(data)
                notifications += int(notify)
                last = window, offset, notify, peer
                if not fast_video or notify or count >= 256:
                    publish()
        except (OSError, struct.error, ValueError) as exc:
            with self.lock:
                self.rx["error"] = str(exc)
            if self.session:
                self.session.fail(f"UDP 接收失败：{exc}")
            if connection is not None:
                self.rx_process_stop.set()
                sock.sendto(b'', sock.getsockname())
        finally:
            publish()
            if self.mode in ('video', 'console') and connection is None:
                self.video.finish()
            for output in files.values():
                output.close()
            selector.close()
            if connection is not None:
                connection.close()
            sock.close()
            with self.lock:
                self.rx_socket = None
                self.rx["active"] = False

    def stop_receive(self):
        self.stop_event.set()
        if self.rx_process_stop is not None:
            self.rx_process_stop.set()
            if self.rx_socket is not None:
                self.rx_socket.sendto(b'', self.rx_socket.getsockname())
        if self.rx_thread is not None:
            self.rx_thread.join()
            self.rx_thread = None
        if self.rx_process is not None:
            self.rx_process.join()
            exitcode = self.rx_process.exitcode
            self.rx_process.close()
            self.rx_process = None
            self.rx_process_stop = None
            self.rx_capture_event = None
            self.rx_capture_epoch = None
            self.rx_return_time = None
            self.rx_memory.close()
            self.rx_memory.unlink()
            self.rx_memory = None
            if exitcode:
                raise RuntimeError(f'UDP receive process exit: {exitcode}')
        return self.status()["rx"]
