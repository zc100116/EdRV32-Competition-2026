#!/usr/bin/env python3
# File: test_encode.py
# Spec: Task B3-3a; rnd-spec 2.5–2.6.
# Description: Compare all C-generated descriptor bytes against the Python oracle.
# Clock domain: host.
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
from scenes import GROUPS, ROOT, generate, ref


class Encoding(unittest.TestCase):
    def test_all_commands(self):
        out = ROOT / 'build/sw/rnd_board/host'
        out.mkdir(parents=True, exist_ok=True)
        generate(out / 'scenes.h')
        subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                        '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                        '-I' + str(ROOT / 'sw/bsp/include'),
                        '-I' + str(ROOT / 'sw/drivers/include'), '-I' + str(out),
                        str(Path(__file__).with_name('host_encode.c')),
                        str(ROOT / 'sw/drivers/rnd.c'), '-o', str(out / 'encode')], check=True)
        data = subprocess.check_output([str(out / 'encode')])
        offset = 0
        for name, _, commands in GROUPS:
            for index, command in enumerate(commands):
                with self.subTest(group=name, command=index):
                    actual = data[offset:offset + 64]
                    self.assertEqual(actual, command.encode())
                    self.assertEqual(ref.Command.decode(actual).encode(), command.encode())
                offset += 64
        self.assertEqual(len(data), offset)


if __name__ == '__main__':
    unittest.main()
