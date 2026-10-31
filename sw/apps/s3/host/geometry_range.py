#!/usr/bin/env python3
# Spec: rnd-testplan v0.3 driver range checks; build/run real evaluation callbacks.
# No sources or flags from this directory are included by sw/Makefile.
import ctypes as C
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/s3'))
from lvgl_host import build, FLAGS, OUT

build()
sys.stdout.flush()
obj = OUT / 'geometry_range.o'
subprocess.run(['cc', *FLAGS, '-c', 'sw/apps/s3/host/geometry_range.c', '-o', str(obj)],
               cwd=ROOT, check=True)
objects = sorted(p for p in (OUT / 'obj').rglob('*.o')
                 if p.name not in ('draw_rnd.c.o',))
library = OUT / 'geometry_range.so'
wrap = ['lv_draw_sw_blend', 'lv_draw_sw_init', 'lv_draw_create_unit',
        'lv_timer_create', 'rnd_read_perf', 'mem_xbar_snapshot']
subprocess.run(['cc', '-shared', '-Wl,--no-undefined',
                *(f'-Wl,--wrap={name}' for name in wrap),
                *map(str, objects), str(obj), '-lm', '-o', str(library)], cwd=ROOT, check=True)
lib = C.CDLL(str(library))
lib.s3_lvgl_init()
if lib.s3_geometry_range_test():
    raise SystemExit(1)
print('PASS TRIANGLE/LINE/ARC use existing unsupported path')
