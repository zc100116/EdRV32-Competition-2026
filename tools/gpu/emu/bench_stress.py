#!/usr/bin/env python3
"""P-1 stress acceptance: three isolated frame timings with three GPU threads.
Uses the differential suite's scene and adapter; host monotonic clock.
"""
import ctypes as C
import json
import statistics
import subprocess
import time

import compare
from stress import scene


def main():
    compare.build(3)
    original = compare.Scene.__init__
    compare.Scene.__init__ = lambda self, base=0: original(self, base)
    stress = scene()
    writes = stress.finish()
    raw = bytes(stress.memory.data)
    data = compare.buffer(raw)
    lib = compare.library()
    emulator = lib.gpu_emu_create(data, len(raw))
    load = subprocess.check_output(['uptime'], text=True).strip()
    timings = []
    for _ in range(3):
        C.memmove(C.addressof(data), raw, len(raw))
        lib.gpu_emu_write(emulator, compare.REGS['CTRL'], 8)
        start = time.perf_counter_ns()
        for register, value in writes:
            lib.gpu_emu_write(emulator, compare.REGS[register], value)
        timings.append((time.perf_counter_ns() - start) / 1e6)
    lib.gpu_emu_destroy(emulator)
    result = dict(uptime=load, frame_ms=timings, median_ms=statistics.median(timings))
    output = json.dumps(result, indent=2) + '\n'
    (compare.BUILD / 'stress-acceptance.json').write_text(output)
    print(output, end='')


if __name__ == '__main__':
    main()
