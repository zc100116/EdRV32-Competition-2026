# File: test_ranges.py
# Spec: edrv32-soc-spec 7.5(3a); Task B1-10.
# Description: Compile the firmware's actual predicates for host execution.
# Clock domain: none (host test).
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]


class BiosRangesTest(unittest.TestCase):
    def test_firmware_ranges(self):
        out = ROOT / 'build/boot_tests/ranges'
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                        '-I' + str(ROOT / 'sw/boot'), '-I' + str(ROOT / 'sw/bsp/include'),
                        str(Path(__file__).with_name('ranges.c')), '-o', str(out)], check=True)
        subprocess.run([str(out)], check=True)
