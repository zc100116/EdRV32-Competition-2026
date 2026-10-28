"""program.py — SoC spec 7.5(3a), host BIOS SRAM programming (no clock domain).

Recognize the fixed BIOS lines while the engine continues displaying all UART output.
Use the board tool's wire_bytes() as the sole download stream encoder.
"""

from pathlib import Path
import re
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.board.uart_tool import wire_bytes


class BiosProgrammer:
    def __init__(self, write, log):
        self.write = write
        self.log = log
        self.lock = threading.Lock()
        self.state = {"active": False, "phase": "idle", "sent": 0, "total": 0,
                      "programmedBytes": None, "result": None, "error": None}

    def status(self):
        with self.lock:
            return dict(self.state)

    def start(self, path):
        wire = wire_bytes(Path(path))
        with self.lock:
            if self.state["active"]:
                raise RuntimeError("BIOS programming is already active")
            self.wire = wire
            self.state = {"active": True, "phase": "wait_menu", "path": str(path),
                          "sent": 0, "total": len(wire), "bios": False,
                          "programmedBytes": None, "result": None, "error": None}
        self.log("按住 KEY1 按复位；等待 BIOS menu")
        return self.status()

    def fail(self, error):
        with self.lock:
            self.state.update(active=False, phase="error", error=str(error))
        self.log(f"BIOS programming failed: {error}")

    def feed_line(self, line):
        with self.lock:
            if not self.state["active"]:
                return
            phase = self.state["phase"]
            if line == "BIOS: EdRV32":
                self.state["bios"] = True
            if line == "BIOS menu: 1=Program SRAM" and phase == "wait_menu":
                self.state["phase"] = "wait_ready"
                select = True
            else:
                select = False
            upload = line == "UART download ready" and phase == "wait_ready"
            if upload:
                self.state["phase"] = "sending"
            count = re.fullmatch(r"Program SRAM bytes: (\d+)", line)
            if count:
                self.state["programmedBytes"] = int(count.group(1))
            if line in ("Program SRAM result: PASS, press reset to run",
                        "Program SRAM result: FAIL length"):
                self.state.update(active=False, phase="done", result=line)
        if select:
            try:
                self.write(b"1\r")
            except OSError as exc:
                self.fail(exc)
        if upload:
            threading.Thread(target=self._upload, name="bios-upload", daemon=True).start()

    def _upload(self):
        try:
            for offset in range(0, len(self.wire), 4096):
                chunk = self.wire[offset:offset + 4096]
                self.write(chunk)
                with self.lock:
                    self.state["sent"] = offset + len(chunk)
            with self.lock:
                if self.state["active"]:
                    self.state["phase"] = "wait_result"
        except OSError as exc:
            self.fail(exc)
