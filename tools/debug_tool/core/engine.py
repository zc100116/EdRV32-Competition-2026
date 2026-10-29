"""EdRV32 调试工具 -- serial engine core.

Framework-agnostic: no GUI imports, no HTTP imports. The PySide6 GUI,
the REST API server and the CLI all drive the same SerialEngine.

Buffer model: every RX line / TX frame / SYS event becomes an entry
{seq, ts(ms), dir: rx|tx|sys, text}. seq increases monotonically, so an
observer (GUI poller, AI agent) can ask for "everything after seq N".
"""

import datetime
import json
import os
import re
import threading
import time

from .program import BiosProgrammer
from .ethernet import EthernetTool
from .telemetry import Telemetry
from .yolo import YoloTool
from .scene import SceneControl
from .video import VideoReceiver

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    raise SystemExit("pyserial is required: pip install pyserial")

TOOL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG_DIR = os.path.join(TOOL_DIR, "logs")
COMMANDS_PATH = os.path.join(TOOL_DIR, "commands.json")
RULES_PATH = os.path.join(TOOL_DIR, "rules.json")
SETTINGS_PATH = os.path.join(TOOL_DIR, "settings.json")

BUFFER_MAX = 5000          # entries kept in memory
RX_FLUSH_IDLE_S = 0.25     # partial RX line flushed after this idle gap
FILE_CHUNK = 4096          # bytes per write during file transfer
FILE_MAX_SIZE = 256 * 1024 * 1024

ENDINGS = {"none": "", "cr": "\r", "lf": "\n", "crlf": "\r\n"}
PARITIES = {
    "none": serial.PARITY_NONE, "even": serial.PARITY_EVEN,
    "odd": serial.PARITY_ODD, "mark": serial.PARITY_MARK,
    "space": serial.PARITY_SPACE,
}
STOPBITS = {"1": serial.STOPBITS_ONE, "1.5": serial.STOPBITS_ONE_POINT_FIVE,
            "2": serial.STOPBITS_TWO}
ENCODINGS = ("utf-8", "gbk", "ascii")

# The command panel starts empty by design: users create their own
# quick-send buttons at runtime (persisted to commands.json).
DEFAULT_COMMANDS = []

DEFAULT_SETTINGS = {"port": "", "baud": 115200, "dataBits": 8,
                    "parity": "none", "stopBits": "1",
                    "encoding": "utf-8", "dtr": False, "rts": False}

# ------------------------------------------------------------ match rules --
# A match rule watches RX lines; on a regex hit it extracts a numeric value
# and publishes a live "parameter" (VOFA-style). Fields:
#   id, name, pattern, enabled, valueGroup (1-based, default 1),
#   keyGroup (0/None = single parameter per rule; otherwise the captured key
#   fans the rule out into many parameters, e.g. one per captured id),
#   base (10/16 for the value capture), scale (float multiplier), unit,
#   names ({key: displayName} override for keyed rules).
# The rule list starts EMPTY by design: this is a generic tool, users define
# their own protocols. Rules persist to rules.json.


def fmt_ts(ms):
    t = datetime.datetime.fromtimestamp(ms / 1000.0)
    return t.strftime("%H:%M:%S.") + f"{ms % 1000:03d}"


def format_entries(entries):
    return "\n".join(f"[{fmt_ts(e['ts'])}][{e['dir'].upper()}] {e['text']}"
                     for e in entries)


class SerialEngine:
    """Owns the serial port, the reader thread and the entry buffer."""

    def __init__(self):
        self._lock = threading.Lock()
        self._serial = None
        self._reader = None
        self._reader_running = False
        self._entries = []
        self._seq = 0
        self._rx_bytes = 0
        self._tx_bytes = 0
        self._config = dict(DEFAULT_SETTINGS)
        self._config.update(self._read_json(SETTINGS_PATH, {}))
        self._commands = self._load_commands()
        self._rules = self._load_rules()
        self._compiled_rules = self._compile_rules(self._rules)
        self._params = {}          # key -> param dict
        self._file_tx = None       # file transfer state dict
        self._listeners = []
        self.program = BiosProgrammer(self._program_write,
                                      lambda text: self.add_entry("sys", text))
        self.telemetry = Telemetry()
        self.ethernet = EthernetTool(self.telemetry)
        self.yolo = YoloTool(self.ethernet)
        self.video = VideoReceiver()
        self.ethernet.yolo = self.yolo
        self.ethernet.video = self.video
        self.scenes = SceneControl(self)

    # ---------------------------------------------------------- observer --
    def add_listener(self, callback):
        """callback(entry) is invoked (from a worker thread) per new entry."""
        self._listeners.append(callback)

    def _emit(self, entry):
        for cb in list(self._listeners):
            try:
                cb(dict(entry))
            except Exception:
                pass

    # ------------------------------------------------------------ buffer --
    def add_entry(self, direction, text, hex_data=None):
        if not text and hex_data is None:
            return None
        with self._lock:
            self._seq += 1
            entry = {"seq": self._seq, "ts": int(time.time() * 1000),
                     "dir": direction, "text": text}
            if hex_data is not None:
                entry["hex"] = hex_data
            self._entries.append(entry)
            if len(self._entries) > BUFFER_MAX:
                self._entries = self._entries[-BUFFER_MAX:]
        self._emit(entry)
        return dict(entry)

    def get_entries(self, since=0, limit=1000, direction=None):
        with self._lock:
            out = [e for e in self._entries if e["seq"] > since]
            if direction:
                out = [e for e in out if e["dir"] == direction]
            return [dict(e) for e in out[:limit]], self._seq

    def clear(self):
        with self._lock:
            self._entries = []
            seq = self._seq
            self._rx_bytes = 0
            self._tx_bytes = 0
        self._emit({"seq": seq, "ts": int(time.time() * 1000),
                    "dir": "cleared", "text": ""})
        return seq

    # ------------------------------------------------------------ serial --
    def ports(self):
        return [{"device": p.device, "description": p.description}
                for p in sorted(list_ports.comports(), key=lambda p: p.device)]

    def status(self):
        with self._lock:
            connected = self._serial is not None and self._serial.is_open
            return {"connected": connected, "config": dict(self._config),
                    "encoding": self._config.get("encoding", "utf-8"),
                    "dtr": bool(self._config.get("dtr")),
                    "rts": bool(self._config.get("rts")),
                    "rxBytes": self._rx_bytes, "txBytes": self._tx_bytes,
                    "lastSeq": self._seq}

    def set_encoding(self, encoding):
        encoding = str(encoding).lower()
        if encoding not in ENCODINGS:
            raise ValueError(f"encoding must be one of {list(ENCODINGS)}")
        with self._lock:
            self._config["encoding"] = encoding
        self._persist_config()
        return self.status()

    def set_modem(self, dtr=None, rts=None):
        with self._lock:
            ser = self._serial
            if dtr is not None:
                self._config["dtr"] = bool(dtr)
            if rts is not None:
                self._config["rts"] = bool(rts)
            cfg = dict(self._config)
        if ser is not None and ser.is_open:
            if dtr is not None:
                ser.dtr = bool(dtr)
            if rts is not None:
                ser.rts = bool(rts)
        self._write_json(SETTINGS_PATH, cfg)
        return self.status()

    def _persist_config(self):
        with self._lock:
            cfg = dict(self._config)
        self._write_json(SETTINGS_PATH, cfg)

    def connect(self, port, baud=115200, data_bits=8, parity="none",
                stop_bits="1", dtr=False, rts=False):
        if not port:
            raise ValueError("port is required")
        if parity not in PARITIES:
            raise ValueError(f"parity must be one of {sorted(PARITIES)}")
        if str(stop_bits) not in STOPBITS:
            raise ValueError("stopBits must be 1, 1.5 or 2")
        if int(data_bits) not in (5, 6, 7, 8):
            raise ValueError("dataBits must be 5..8")
        baud = int(baud)
        if not (300 <= baud <= 12_000_000):
            raise ValueError("baud out of range")
        self.disconnect(silent=True)
        # serial_for_url accepts plain COM ports as well as pyserial URL
        # handlers (loop://, socket://...), which enables full-loop tests.
        ser = serial.serial_for_url(str(port), do_not_open=True)
        ser.baudrate = baud
        ser.bytesize = int(data_bits)
        ser.parity = PARITIES[parity]
        ser.stopbits = STOPBITS[str(stop_bits)]
        ser.timeout = 0.1
        ser.write_timeout = 1.0
        ser.open()
        ser.dtr = bool(dtr)
        ser.rts = bool(rts)
        with self._lock:
            self._serial = ser
            self._config.update({"port": str(port), "baud": baud,
                                 "dataBits": int(data_bits), "parity": parity,
                                 "stopBits": str(stop_bits),
                                 "dtr": bool(dtr), "rts": bool(rts)})
        self._persist_config()
        self._reader_running = True
        self._reader = threading.Thread(target=self._reader_loop,
                                        name="serial-rx", daemon=True)
        self._reader.start()
        self.add_entry("sys", f"connected {port} @ {baud} "
                              f"{int(data_bits)}{parity[0].upper()}{stop_bits}")
        return self.status()

    def disconnect(self, silent=False):
        if self.program.status()["active"]:
            self.program.fail("serial port disconnected during BIOS programming")
        self._reader_running = False
        reader = self._reader
        if reader and reader.is_alive() and reader is not threading.current_thread():
            reader.join(timeout=1.0)
        self._reader = None
        with self._lock:
            ser, self._serial = self._serial, None
        if ser is not None:
            try:
                ser.close()
            except serial.SerialException:
                pass
            if not silent:
                self.add_entry("sys", f"disconnected {ser.port}")
        return self.status()

    def send(self, text, ending="cr", hex_mode=False):
        if ending not in ENDINGS:
            raise ValueError(f"ending must be one of {sorted(ENDINGS)}")
        with self._lock:
            ser = self._serial
            encoding = self._config.get("encoding", "utf-8")
        if ser is None or not ser.is_open:
            raise RuntimeError("serial port is not connected")
        if hex_mode:
            cleaned = re.sub(r"[\s,]+", "", text)
            if not cleaned or len(cleaned) % 2 != 0 or \
                    not re.fullmatch(r"[0-9A-Fa-f]+", cleaned):
                raise ValueError("非法 HEX 字符串（应为偶数个十六进制字符）")
            data = bytes.fromhex(cleaned) + ENDINGS[ending].encode("ascii")
            shown = " ".join(f"{b:02X}" for b in data)
        else:
            wire = text + ENDINGS[ending]
            data = wire.encode(encoding, errors="replace")
            shown = wire.replace("\r", "<CR>").replace("\n", "<LF>")
        ser.write(data)
        ser.flush()
        with self._lock:
            self._tx_bytes += len(data)
        hex_data = " ".join(f"{b:02X}" for b in data)
        self.add_entry("tx", shown, hex_data)
        return self.status()

    def _reader_loop(self):
        pending = bytearray()
        last_rx = 0.0
        while self._reader_running:
            with self._lock:
                ser = self._serial
            if ser is None or not ser.is_open:
                time.sleep(0.05)
                continue
            try:
                waiting = ser.in_waiting
                data = ser.read(waiting if waiting else 1)
            except (serial.SerialException, OSError) as exc:
                self.add_entry("sys", f"serial error: {exc}; link closed")
                self.disconnect(silent=True)
                continue
            with self._lock:
                encoding = self._config.get("encoding", "utf-8")
            if data:
                pending.extend(data)
                last_rx = time.time()
                with self._lock:
                    self._rx_bytes += len(data)
                while True:
                    nl = pending.find(b"\n")
                    if nl < 0:
                        break
                    line = bytes(pending[:nl]).rstrip(b"\r")
                    del pending[:nl + 1]
                    text = line.decode(encoding, "replace")
                    hex_data = " ".join(f"{b:02X}" for b in line)
                    self.add_entry("rx", text, hex_data)
                    self._match_line(text)
            else:
                if pending and (time.time() - last_rx) >= RX_FLUSH_IDLE_S:
                    line = bytes(pending)
                    pending.clear()
                    text = line.decode(encoding, "replace")
                    hex_data = " ".join(f"{b:02X}" for b in line)
                    self.add_entry("rx", text, hex_data)
                    self._match_line(text)
                time.sleep(0.02)

    # -------------------------------------------------------------- save --
    def start_program(self, path):
        if not self.status()["connected"]:
            raise RuntimeError("serial port is not connected")
        return self.program.start(path)

    def _program_write(self, data):
        with self._lock:
            ser = self._serial
        if ser is None or not ser.is_open:
            raise OSError("serial port disconnected during BIOS programming")
        ser.write(data)
        with self._lock:
            self._tx_bytes += len(data)

    def save_log(self, path=None):
        entries, _ = self.get_entries(since=0, limit=BUFFER_MAX)
        if not path:
            os.makedirs(LOG_DIR, exist_ok=True)
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            path = os.path.join(LOG_DIR, f"serial-{stamp}.log")
        elif not os.path.isabs(path):
            path = os.path.join(os.getcwd(), path)
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(format_entries(entries) + ("\n" if entries else ""))
        return {"path": path, "lines": len(entries)}

    # ---------------------------------------------------------- commands --
    @staticmethod
    def _read_json(path, fallback):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, json.JSONDecodeError):
            return fallback

    @staticmethod
    def _write_json(path, obj):
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, ensure_ascii=False, indent=2)
        os.replace(tmp, path)

    def _load_commands(self):
        data = self._read_json(COMMANDS_PATH, None)
        if isinstance(data, list) and all(
                isinstance(c, dict) and "label" in c and "payload" in c
                for c in data):
            return data
        return [dict(c) for c in DEFAULT_COMMANDS]

    def list_commands(self):
        with self._lock:
            return [dict(c) for c in self._commands]

    def _find_command(self, cid):
        for cmd in self._commands:
            if cmd.get("id") == cid:
                return cmd
        return None

    def upsert_command(self, body, cid=None):
        label = str(body.get("label", "")).strip()
        payload = str(body.get("payload", ""))
        ending = body.get("ending", "cr")
        if not label:
            raise ValueError("label is required")
        if ending not in ENDINGS:
            raise ValueError(f"ending must be one of {sorted(ENDINGS)}")
        with self._lock:
            if cid is not None:
                cmd = self._find_command(cid)
                if cmd is None:
                    raise KeyError(cid)
                cmd.update({"label": label, "payload": payload,
                            "ending": ending})
            else:
                cid = str(body.get("id") or f"cmd-{int(time.time()*1000):x}")
                if self._find_command(cid) is not None:
                    raise ValueError(f"command id already exists: {cid}")
                cmd = {"id": cid, "label": label, "payload": payload,
                       "ending": ending}
                self._commands.append(cmd)
            self._write_json(COMMANDS_PATH, self._commands)
            return dict(cmd)

    def delete_command(self, cid):
        with self._lock:
            cmd = self._find_command(cid)
            if cmd is None:
                raise KeyError(cid)
            self._commands.remove(cmd)
            self._write_json(COMMANDS_PATH, self._commands)

    def replace_commands(self, commands):
        """Validate and replace the whole command list (import/restore)."""
        if not isinstance(commands, list):
            raise ValueError("命令配置必须是数组")
        cleaned, seen = [], set()
        for item in commands:
            if not isinstance(item, dict):
                raise ValueError("每条命令必须是对象 {label, payload, ...}")
            label = str(item.get("label", "")).strip()
            if not label:
                raise ValueError("每条命令都需要 label")
            payload = str(item.get("payload", ""))
            ending = item.get("ending", "cr")
            if ending not in ENDINGS:
                raise ValueError(f"非法 ending: {ending}")
            cid = str(item.get("id") or f"cmd-{len(cleaned):x}")
            while cid in seen:
                cid += "-x"
            seen.add(cid)
            cleaned.append({"id": cid, "label": label, "payload": payload,
                            "ending": ending})
        with self._lock:
            self._commands = cleaned
            self._write_json(COMMANDS_PATH, self._commands)
            return [dict(c) for c in self._commands]

    def export_commands(self, path):
        commands = self.list_commands()
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(commands, fh, ensure_ascii=False, indent=2)
        return {"path": path, "count": len(commands)}

    def import_commands(self, path):
        data = self._read_json(path, None)
        if data is None:
            raise ValueError("配置文件不存在或不是合法 JSON")
        return self.replace_commands(data)

    # ------------------------------------------------------ match rules --
    def _load_rules(self):
        data = self._read_json(RULES_PATH, None)
        if isinstance(data, list) and all(
                isinstance(r, dict) and "pattern" in r for r in data):
            return data
        return []

    @staticmethod
    def _compile_rules(rules):
        compiled = []
        for rule in rules:
            if not rule.get("enabled", True):
                continue
            try:
                compiled.append((rule, re.compile(rule["pattern"])))
            except re.error:
                continue  # a broken pattern just never matches
        return compiled

    def list_rules(self):
        with self._lock:
            return [dict(r) for r in self._rules]

    def _find_rule(self, rid):
        for rule in self._rules:
            if rule.get("id") == rid:
                return rule
        return None

    def upsert_rule(self, body, rid=None):
        with self._lock:
            old = self._find_rule(rid) if rid is not None else None
            if rid is not None and old is None:
                raise KeyError(rid)
            # updates are partial: omitted fields keep their stored values
            merged = {**(dict(old) if old else {}), **body}
            name = str(merged.get("name", "")).strip()
            pattern = str(merged.get("pattern", ""))
            if not name:
                raise ValueError("name is required")
            if not pattern:
                raise ValueError("pattern is required")
            try:
                re.compile(pattern)
            except re.error as exc:
                raise ValueError(f"invalid regex: {exc}")
            rule = {
                "name": name,
                "pattern": pattern,
                "enabled": bool(merged.get("enabled", True)),
                "keyGroup": int(merged.get("keyGroup") or 0),
                "valueGroup": int(merged.get("valueGroup") or 1),
                "base": 16 if int(merged.get("base", 10)) == 16 else 10,
                "scale": float(merged.get("scale", 1) or 1),
                "unit": str(merged.get("unit", "")),
            }
            names = body.get("names", merged.get("names"))
            if isinstance(names, dict):
                rule["names"] = {str(k): str(v) for k, v in names.items()}
            if old is not None:
                old.update(rule)
                rule = old
            else:
                rid = str(body.get("id") or f"rule-{int(time.time()*1000):x}")
                if self._find_rule(rid) is not None:
                    raise ValueError(f"rule id already exists: {rid}")
                rule["id"] = rid
                self._rules.append(rule)
            self._compiled_rules = self._compile_rules(self._rules)
            self._write_json(RULES_PATH, self._rules)
            return dict(rule)

    def delete_rule(self, rid):
        with self._lock:
            rule = self._find_rule(rid)
            if rule is None:
                raise KeyError(rid)
            self._rules.remove(rule)
            self._compiled_rules = self._compile_rules(self._rules)
            self._write_json(RULES_PATH, self._rules)

    # ------------------------------------------------------- file transfer --
    def file_status(self):
        with self._lock:
            if not self._file_tx:
                return {"active": False}
            return dict(self._file_tx)

    def send_file(self, path, echo=False):
        """Send a file as raw bytes in background chunks.

        echo=True additionally logs each chunk as a TX buffer entry (text
        decoded with the active encoding, plus its hex form), so the
        transfer shows up in the console; by default only start/finish
        sys lines are logged."""
        with self._lock:
            ser = self._serial
        if ser is None or not ser.is_open:
            raise RuntimeError("serial port is not connected")
        path = os.path.abspath(str(path))
        if not os.path.isfile(path):
            raise ValueError(f"file not found: {path}")
        size = os.path.getsize(path)
        if size > FILE_MAX_SIZE:
            raise ValueError(
                f"file too large: {size} B (cap {FILE_MAX_SIZE} B)")
        with self._lock:
            if self._file_tx and self._file_tx.get("active"):
                raise RuntimeError("a file transfer is already running")
            self._file_tx = {"active": True, "path": path,
                             "name": os.path.basename(path), "total": size,
                             "sent": 0, "done": False, "cancelled": False,
                             "error": None}
        threading.Thread(target=self._file_loop, args=(path, size, echo),
                         name="serial-file-tx", daemon=True).start()
        self.add_entry("sys", f"sending file: {os.path.basename(path)} "
                              f"({size} B)")
        return self.file_status()

    def cancel_file(self):
        with self._lock:
            if self._file_tx and self._file_tx.get("active"):
                self._file_tx["cancelled"] = True
        return self.file_status()

    def _file_loop(self, path, size, echo):
        sent = 0
        error = None
        try:
            with open(path, "rb") as fh:
                while True:
                    with self._lock:
                        if self._file_tx.get("cancelled"):
                            break
                        ser = self._serial
                        encoding = self._config.get("encoding", "utf-8")
                    if ser is None or not ser.is_open:
                        error = "serial port closed during transfer"
                        break
                    chunk = fh.read(FILE_CHUNK)
                    if not chunk:
                        break
                    ser.write(chunk)
                    sent += len(chunk)
                    with self._lock:
                        self._tx_bytes += len(chunk)
                        self._file_tx["sent"] = sent
                    if echo:
                        hex_data = " ".join(f"{b:02X}" for b in chunk)
                        self.add_entry("tx", chunk.decode(encoding, "replace"),
                                       hex_data)
        except (serial.SerialException, OSError) as exc:
            error = str(exc)
        with self._lock:
            cancelled = bool(self._file_tx.get("cancelled"))
            self._file_tx.update({"active": False,
                                  "done": error is None and not cancelled,
                                  "error": error, "sent": sent})
        name = os.path.basename(path)
        if error:
            self.add_entry("sys", f"file transfer failed: {name}: "
                                  f"{error} ({sent} B sent)")
        elif cancelled:
            self.add_entry("sys", f"file transfer cancelled: {name} "
                                  f"({sent}/{size} B)")
        else:
            self.add_entry("sys", f"file sent: {name} ({size} B)")

    # ------------------------------------------------------------ params --
    def _match_line(self, text):
        self.program.feed_line(text)
        with self._lock:
            compiled = list(self._compiled_rules)
        for rule, regex in compiled:
            m = regex.search(text)
            if m is None:
                continue
            try:
                if rule.get("keyGroup"):
                    key = m.group(rule["keyGroup"])
                    raw = m.group(rule.get("valueGroup") or 1)
                else:
                    key = ""
                    raw = m.group(rule.get("valueGroup") or 1)
            except IndexError:
                continue
            if raw is None or key is None:
                continue
            try:
                value = (int(raw, 16) if rule.get("base") == 16
                         else float(raw))
            except ValueError:
                continue
            value *= float(rule.get("scale", 1))
            names = rule.get("names") or {}
            if key:
                display = names.get(key, f"{rule['name']} {key}")
                param_key = f"{rule['id']}:{key}"
            else:
                display = rule["name"]
                param_key = rule["id"]
            with self._lock:
                prev = self._params.get(param_key)
                self._params[param_key] = {
                    "key": param_key, "name": display, "rule": rule["id"],
                    "value": value, "raw": raw, "unit": rule.get("unit", ""),
                    "ts": int(time.time() * 1000),
                    "count": (prev["count"] + 1) if prev else 1,
                }

    def get_params(self):
        with self._lock:
            return [dict(p) for p in self._params.values()]

    def clear_params(self):
        with self._lock:
            self._params = {}

    def send_command(self, cid):
        with self._lock:
            cmd = self._find_command(cid)
            if cmd is None:
                raise KeyError(cid)
            cmd = dict(cmd)
        return self.send(cmd["payload"], cmd.get("ending", "cr"))

    @property
    def config(self):
        with self._lock:
            return dict(self._config)
