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

    def start(self, path, elf=False, baud=2000000, addr=None, entry=None,
              eth=False, local_ip='192.168.1.2'):
        state = super().start(path, elf, baud, addr=addr, entry=entry,
                              eth=eth, local_ip=local_ip)
        self.log('已在 BIOS 菜单时直接开始；否则按住 KEY1 并复位')
        return state

    def fail(self, error):
        super().fail(error)
        self.log(f'BIOS programming failed: {error}')

    def feed_line(self, line):
        try:
            super().feed_line(line)
        except OSError as exc:
            self.fail(exc)
