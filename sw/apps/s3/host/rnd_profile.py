#!/usr/bin/env python3
# Task T-RND2D: build/run the host-only supported() census, native SW rasterization.
# No sources or flags from this directory are included by sw/Makefile.
import ctypes as C
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/s3'))
from lvgl_host import build, FLAGS, OUT

build()
obj = OUT / 'rnd_profile.o'
subprocess.run(['cc', *FLAGS, '-c', 'sw/apps/s3/host/rnd_profile.c', '-o', str(obj)],
               cwd=ROOT, check=True)
objects = sorted(p for p in (OUT / 'obj').rglob('*.o')
                 if p.name not in ('draw_rnd.c.o', 's3_lvgl.c.o'))
library = OUT / 'rnd_profile.so'
wrap = ['lv_draw_sw_blend', 'lv_draw_sw_init', 'lv_draw_create_unit',
        'lv_timer_create', 'rnd_read_perf', 'mem_xbar_snapshot']
subprocess.run(['cc', '-shared', '-Wl,--no-undefined',
                *(f'-Wl,--wrap={name}' for name in wrap),
                *map(str, objects), str(obj), '-lm', '-o', str(library)], cwd=ROOT, check=True)
lib = C.CDLL(str(library))
lib.s3_host_time.argtypes = [C.c_uint32]
lib.s3_lvgl_init()
lib.s3_profile_native_sync()
lib.s3_lvgl_start_benchmark()
# 16 benchmark scene periods sum to 69 s; stop before summary tasks enter census.
for now in range(100, 69000, 100):
    lib.s3_host_time(now)
    lib.s3_lvgl_step()
lib.s3_profile_dump()
lib.s3_lvgl_stop_demo()
