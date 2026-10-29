"""program.py — SoC spec 7.5(3a), host BIOS programming/load/run (no clock domain).

The board tool owns ELF segmentation, byte encoding and the prompt-driven protocol.
"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.board.uart_tool import BiosTransfer


class BiosProgrammer(BiosTransfer):
    def __init__(self, write, log, set_baud):
        super().__init__(write, set_baud)
        self.log = log

    def start(self, path, elf=False, baud=2000000):
        state = super().start(path, elf, baud)
        self.log('按住 KEY1 按复位；等待 BIOS menu')
        return state

    def fail(self, error):
        super().fail(error)
        self.log(f'BIOS programming failed: {error}')

    def feed_line(self, line):
        try:
            super().feed_line(line)
        except OSError as exc:
            self.fail(exc)
