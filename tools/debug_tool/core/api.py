"""Embedded HTTP REST API for the serial engine.

Runs in a daemon thread next to the GUI (or standalone in --headless mode).
Every GUI action has a matching endpoint so a terminal (cli.py) or an AI
agent can fully control and observe the live session.

All endpoints return JSON. Buffer entries are polled incrementally via
GET /api/buffer?since=<lastSeq>.
"""

import datetime
import json
import struct
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import serial

from .engine import BUFFER_MAX, format_entries


def make_handler(engine):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # keep the console clean
            pass

        # -- helpers -----------------------------------------------------
        def _json(self, code, obj):
            body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _error(self, code, message):
            self._json(code, {"error": message})

        def _body(self):
            length = int(self.headers.get("Content-Length") or 0)
            if length == 0:
                return {}
            raw = self.rfile.read(length)
            try:
                return json.loads(raw.decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                raise ValueError("request body must be JSON")

        def _query(self):
            return urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)

        # -- routing -----------------------------------------------------
        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            try:
                if path == "/api/telemetry":
                    return self._json(200, engine.telemetry.status())
                if path == "/api/scenes":
                    return self._json(200, engine.scenes.mapping())
                if path == "/api/telemetry/csv":
                    data = engine.telemetry.csv_text().encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "text/csv; charset=utf-8")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    return self.wfile.write(data)
                if path == "/api/ports":
                    return self._json(200, {"ports": engine.ports()})
                if path == "/api/status":
                    return self._json(200, engine.status())
                if path == "/api/buffer":
                    q = self._query()
                    since = int(q.get("since", [0])[0])
                    limit = min(int(q.get("limit", [1000])[0]), BUFFER_MAX)
                    direction = q.get("dir", [None])[0]
                    entries, last = engine.get_entries(since, limit, direction)
                    return self._json(200, {"entries": entries, "lastSeq": last})
                if path == "/api/buffer/download":
                    return self._download()
                if path == "/api/commands":
                    return self._json(200, {"commands": engine.list_commands()})
                if path == "/api/rules":
                    return self._json(200, {"rules": engine.list_rules()})
                if path == "/api/params":
                    return self._json(200, {"params": engine.get_params()})
                if path == "/api/file/status":
                    return self._json(200, engine.file_status())
                if path == "/api/program/status":
                    return self._json(200, engine.program.status())
                if path == "/api/ethernet/status":
                    return self._json(200, engine.ethernet.status())
                return self._error(404, "unknown endpoint")
            except ValueError as exc:
                return self._error(400, str(exc))

        def do_POST(self):
            path = urllib.parse.urlsplit(self.path).path
            try:
                body = self._body()
                if path == "/api/telemetry/export":
                    return self._json(200, engine.telemetry.export_csv(body["path"]))
                if path == "/api/telemetry/replay":
                    return self._json(200, engine.telemetry.load_csv(body["path"]))
                if path == "/api/telemetry/clear":
                    engine.telemetry.clear()
                    return self._json(200, engine.telemetry.status())
                if path == "/api/scenes/send":
                    return self._json(200, engine.scenes.send(
                        body["name"], int(body.get("rate", 100))))
                if path in ("/api/yolo/model", "/api/yolo/image"):
                    send = (engine.yolo.send_model if path.endswith("model")
                            else engine.yolo.send_image)
                    options = {} if path.endswith("model") else {
                        "window": int(body.get("window", 0))}
                    return self._json(200, send(
                        body["path"], body["boardIp"], int(body["boardPort"]),
                        int(body["localPort"]), **options))
                if path == "/api/connect":
                    return self._json(200, engine.connect(
                        port=body.get("port", ""),
                        baud=body.get("baud", 115200),
                        data_bits=body.get("dataBits", 8),
                        parity=body.get("parity", "none"),
                        stop_bits=str(body.get("stopBits", "1")),
                        dtr=bool(body.get("dtr", False)),
                        rts=bool(body.get("rts", False))))
                if path == "/api/disconnect":
                    return self._json(200, engine.disconnect())
                if path == "/api/send":
                    return self._json(200, engine.send(
                        str(body.get("text", "")), body.get("ending", "cr"),
                        hex_mode=bool(body.get("hex", False))))
                if path == "/api/options":
                    return self._json(200, engine.set_encoding(
                        body.get("encoding", "utf-8")))
                if path == "/api/modem":
                    return self._json(200, engine.set_modem(
                        dtr=body.get("dtr"), rts=body.get("rts")))
                if path == "/api/file/send":
                    return self._json(200, engine.send_file(
                        str(body.get("path", "")),
                        echo=bool(body.get("echo", False))))
                if path == "/api/file/cancel":
                    return self._json(200, engine.cancel_file())
                if path == "/api/program":
                    return self._json(200, engine.start_program(body["path"]))
                if path == "/api/ethernet/send":
                    return self._json(200, engine.ethernet.send_file(
                        body["path"], body["boardIp"], int(body["boardPort"]),
                        int(body["localPort"]), int(body.get("window", 0)),
                        int(body.get("offset", 0)), float(body.get("interval", 0))))
                if path == "/api/ethernet/receive/start":
                    return self._json(200, engine.ethernet.start_receive(
                        int(body["localPort"]), body.get("directory"), body.get("mode", "files")))
                if path == "/api/ethernet/receive/stop":
                    return self._json(200, engine.ethernet.stop_receive())
                if path == "/api/clear":
                    return self._json(200, {"lastSeq": engine.clear()})
                if path == "/api/save":
                    return self._json(200, engine.save_log(body.get("path")))
                if path == "/api/commands":
                    return self._json(200, engine.upsert_command(body))
                if path == "/api/commands/replace":
                    if "commands" not in body:
                        raise ValueError("body must contain a 'commands' array")
                    return self._json(200, {"commands": engine.replace_commands(
                        body["commands"])})
                if path == "/api/rules":
                    return self._json(200, engine.upsert_rule(body))
                if path == "/api/params/clear":
                    engine.clear_params()
                    return self._json(200, {"cleared": True})
                if path.startswith("/api/commands/"):
                    cid, _, tail = path[len("/api/commands/"):].partition("/")
                    if tail == "send":
                        return self._json(200, engine.send_command(cid))
                    return self._error(404, "unknown endpoint")
                return self._error(404, "unknown endpoint")
            except KeyError as exc:
                return self._error(404, f"unknown command id: {exc.args[0]}")
            except (ValueError, struct.error) as exc:
                return self._error(400, str(exc))
            except RuntimeError as exc:
                return self._error(409, str(exc))
            except serial.SerialException as exc:
                return self._error(500, str(exc))
            except OSError as exc:
                return self._error(500, str(exc))

        def do_PUT(self):
            path = urllib.parse.urlsplit(self.path).path
            try:
                if path.startswith("/api/commands/"):
                    cid = path[len("/api/commands/"):]
                    return self._json(200,
                                      engine.upsert_command(self._body(), cid))
                if path.startswith("/api/rules/"):
                    rid = path[len("/api/rules/"):]
                    return self._json(200,
                                      engine.upsert_rule(self._body(), rid))
                return self._error(404, "unknown endpoint")
            except KeyError as exc:
                return self._error(404, f"unknown id: {exc.args[0]}")
            except ValueError as exc:
                return self._error(400, str(exc))

        def do_DELETE(self):
            path = urllib.parse.urlsplit(self.path).path
            if path.startswith("/api/commands/"):
                try:
                    engine.delete_command(path[len("/api/commands/"):])
                except KeyError as exc:
                    return self._error(404, f"unknown command id: {exc.args[0]}")
                return self._json(200, {"deleted": True})
            if path.startswith("/api/rules/"):
                try:
                    engine.delete_rule(path[len("/api/rules/"):])
                except KeyError as exc:
                    return self._error(404, f"unknown rule id: {exc.args[0]}")
                return self._json(200, {"deleted": True})
            return self._error(404, "unknown endpoint")

        def _download(self):
            entries, _ = engine.get_entries(since=0, limit=BUFFER_MAX)
            body = (format_entries(entries) + "\n").encode("utf-8")
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Disposition",
                             f'attachment; filename="serial-{stamp}.log"')
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return Handler


class ApiServer:
    """Thin wrapper so the GUI can start/stop the API with one call."""

    def __init__(self, engine, host="127.0.0.1", port=8765):
        self.engine = engine
        self.host = host
        self.port = port
        self._httpd = None
        self._thread = None

    @property
    def running(self):
        return self._httpd is not None

    @property
    def url(self):
        return f"http://{self.host}:{self.port}"

    def start(self):
        if self._httpd is not None:
            return self.url
        handler = make_handler(self.engine)
        self._httpd = ThreadingHTTPServer((self.host, self.port), handler)
        self._httpd.daemon_threads = True
        self._thread = threading.Thread(target=self._httpd.serve_forever,
                                        name="serial-api", daemon=True)
        self._thread.start()
        return self.url

    def stop(self):
        if self._httpd is None:
            return
        self._httpd.shutdown()
        self._httpd.server_close()
        self._httpd = None
        self._thread = None
