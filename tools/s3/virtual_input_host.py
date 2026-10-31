#!/usr/bin/env python3
"""Task T-VIN1 real LVGL input acceptance using the existing host library."""
import ctypes as C
import subprocess
from lvgl_host import ROOT, OUT, build

library = build()
lib = C.CDLL(str(library), mode=C.RTLD_GLOBAL)
subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC',
                '-DLV_CONF_INCLUDE_SIMPLE', '-Ithird_party/lvgl', '-Isw/apps/s3/lvgl',
                '-Isw/lib', '-Isw/apps/nes', '-Isw/apps/s3', '-Isw/drivers/include',
                '-Isw/bsp/include', 'tools/s3/virtual_input_host.c',
                '-L' + str(OUT), '-l:lvgl_rn17.so', '-Wl,--no-undefined',
                '-Wl,-rpath,$ORIGIN', '-o', str(OUT / 'virtual_input.so')], cwd=ROOT, check=True)
lib.s3_lvgl_init()
C.CDLL(str(OUT / 'virtual_input.so')).virtual_input_host_check()
