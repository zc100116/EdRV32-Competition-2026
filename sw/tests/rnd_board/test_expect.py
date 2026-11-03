#!/usr/bin/env python3
# File: test_expect.py
# Spec: Task B3-3a CRC log comparison.
# Description: Ensure matching logs pass, mismatches/missing groups/errors fail.
# Clock domain: host.
import contextlib
import io
import sys
import unittest

sys.dont_write_bytecode = True
from expect import compare


class Logs(unittest.TestCase):
    def test_compare(self):
        values = {'fill_rgb565': 0x1234abcd, 'blit_argb8888': 0x87654321}
        log = '\n'.join(f'RND {name} crc=0x{value:08x}' for name, value in values.items())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(compare(log, values))
            self.assertFalse(compare(log.replace('1234abcd', '1234abce'), values))
            self.assertFalse(compare(log.splitlines()[0], values))
            self.assertFalse(compare(log + '\nRND unknown crc=0x00000000', values))
            self.assertFalse(compare(log + '\nRND ERR_CODE=0x00000003 CUR_DESC=0x00000001',
                                     values))


if __name__ == '__main__':
    unittest.main()
