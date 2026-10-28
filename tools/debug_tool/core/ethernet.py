"""ethernet.py — eth spec 2.1–2.6 UDP application files; host, no clock domain.

Send at most 1024 data bytes per datagram and set NOTIFY on the last datagram.
Receive each window into its own file at the exact application OFFSET.
"""

from pathlib import Path
import socket
import struct
import threading
import time

HEADER = struct.Struct("!BBHI")
DATA_BYTES = 1024
DEFAULT_SAVE_DIR = Path(__file__).resolve().parents[3] / "build/debug_tool/udp-rx"


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
    def __init__(self):
        self.lock = threading.Lock()
        self.rx_socket = None
        self.rx_thread = None
        self.stop_event = threading.Event()
        self.tx = {"active": False, "sent": 0, "total": 0, "packets": 0, "error": None}
        self.rx = {"active": False, "packets": 0, "bytes": 0, "notifyCount": 0,
                   "lastNotify": False, "files": {}, "error": None}

    def status(self):
        with self.lock:
            return {"tx": dict(self.tx), "rx": {**self.rx, "files": dict(self.rx["files"])}}

    def send_file(self, path, board_ip, board_port, local_port, window=0, offset=0,
                  interval=0):
        data = Path(path).read_bytes()
        # Materialize headers before starting so format errors reach the caller directly.
        datagrams = list(packets(data, window, offset))
        if interval < 0:
            raise ValueError("packet interval must be nonnegative")
        with self.lock:
            if self.tx["active"]:
                raise RuntimeError("UDP file send is already active")
            self.tx = {"active": True, "sent": 0, "total": len(data), "packets": 0,
                       "path": str(path), "error": None}
            receiver = self.rx_socket
        threading.Thread(target=self._send, args=(datagrams, board_ip, board_port,
                                                  local_port, interval, receiver),
                         name="udp-file-tx", daemon=True).start()
        return self.status()["tx"]

    def _send(self, datagrams, board_ip, board_port, local_port, interval, receiver):
        sock = (receiver if receiver is not None
                else socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
        try:
            if receiver is None:
                sock.bind(("", local_port))
            for index, packet in enumerate(datagrams):
                if index and interval:
                    time.sleep(interval)
                sock.sendto(packet, (board_ip, board_port))
                with self.lock:
                    self.tx["sent"] += len(packet) - HEADER.size
                    self.tx["packets"] += 1
        except OSError as exc:
            with self.lock:
                self.tx["error"] = str(exc)
        finally:
            if receiver is None:
                sock.close()
            with self.lock:
                self.tx["active"] = False

    def start_receive(self, local_port, directory=None):
        if self.rx_socket is not None:
            raise RuntimeError("UDP receive is already active")
        directory = Path(directory) if directory else DEFAULT_SAVE_DIR
        directory.mkdir(parents=True, exist_ok=True)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind(("", local_port))
            sock.settimeout(0.1)  # Poll only to let the user stop the listener.
        except OSError:
            sock.close()
            raise
        self.stop_event.clear()
        with self.lock:
            self.rx_socket = sock
            self.rx = {"active": True, "localPort": sock.getsockname()[1],
                       "directory": str(directory), "packets": 0, "bytes": 0,
                       "notifyCount": 0, "lastNotify": False, "files": {}, "error": None}
        self.rx_thread = threading.Thread(target=self._receive, args=(sock, directory),
                                          name="udp-file-rx", daemon=True)
        self.rx_thread.start()
        return self.status()["rx"]

    def _receive(self, sock, directory):
        files = {}
        try:
            while not self.stop_event.is_set():
                try:
                    packet, peer = sock.recvfrom(65535)
                except socket.timeout:
                    continue
                window, notify, offset, data = unpack(packet)
                if window not in files:
                    path = directory / f"window{window}.bin"
                    files[window] = path.open("w+b")
                    with self.lock:
                        self.rx["files"][str(window)] = str(path)
                output = files[window]
                output.seek(offset)
                output.write(data)
                output.flush()
                with self.lock:
                    self.rx["packets"] += 1
                    self.rx["bytes"] += len(data)
                    self.rx["notifyCount"] += int(notify)
                    self.rx.update(lastWindow=window, lastOffset=offset, lastNotify=notify,
                                   peer=[peer[0], peer[1]])
        except (OSError, struct.error) as exc:
            with self.lock:
                self.rx["error"] = str(exc)
        finally:
            for output in files.values():
                output.close()
            sock.close()
            with self.lock:
                self.rx_socket = None
                self.rx["active"] = False

    def stop_receive(self):
        self.stop_event.set()
        if self.rx_thread is not None:
            self.rx_thread.join()
            self.rx_thread = None
        return self.status()["rx"]
