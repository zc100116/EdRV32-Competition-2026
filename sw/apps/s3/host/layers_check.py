#!/usr/bin/env python3
# File: layers_check.py
# Spec: DISP 4; DS-20; RN-30.
# Description: Check frame writes and execute the LVGL layer's real RND descriptors.
# Clock domain: deterministic host time.
import ctypes as C
import os
from pathlib import Path
import subprocess
import sys
import traceback

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/s3'))
from lvgl_host import FLAGS, OUT
from rn17 import REF, Batch, Memory, ppm

lib = C.CDLL(str(OUT / 'lvgl_rn17.so'), mode=C.RTLD_GLOBAL)
subprocess.run(['cc', *FLAGS, '-shared', 'sw/apps/s3/host/layers_check.c',
                '-L' + str(OUT), '-l:lvgl_rn17.so', '-Wl,--no-undefined',
                '-Wl,-rpath,$ORIGIN', '-o', str(OUT / 'layers_check.so')],
               cwd=ROOT, check=True)
check = C.CDLL(str(OUT / 'layers_check.so'))
check.s3_layers_register_check()
callback_type = C.CFUNCTYPE(None, C.POINTER(Batch))


def execute(pointer):
    try:
        batch = pointer.contents
        ranges = [(r.address & 0xffffffff, r.address, r.bytes)
                  for r in batch.sources[:batch.source_count]]
        memory = Memory(ranges)
        packed = C.string_at(batch.commands, batch.count * 64)
        commands = [REF.Command.decode(packed[i:i + 64]) for i in range(0, len(packed), 64)]
        result = REF.execute(memory, commands)
        assert not result.error, (result.error, result.cur_desc)
        for target in batch.targets[:batch.target_count]:
            address = target.address & 0xffffffff
            C.memmove(target.address, bytes(memory[address:address + target.bytes]), target.bytes)
    except (AssertionError, RuntimeError, StopIteration):
        traceback.print_exc()
        os._exit(1)


callback = callback_type(execute)
lib.s3_host_install.argtypes = [callback_type]
lib.s3_host_install(callback)
lib.s3_lvgl_init()
check.s3_layers_lvgl_check()
lib.s3_lvgl_rendered_pixels.restype = C.c_void_p
ppm(OUT / 'layers-rnd.ppm', lib.s3_lvgl_rendered_pixels())
print('PASS production LVGL layer through rnd_ref; build/s3/lvgl/layers-rnd.ppm')
