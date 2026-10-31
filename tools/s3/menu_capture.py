#!/usr/bin/env python3
# File: menu_capture.py
# Spec: Task B3-3b C; RN-17 host execution; SoC 7.3 R3.
# Description: Draw the production application menu through LVGL and the RND reference model.
# Clock domain: deterministic host milliseconds.
"""Build lvgl_host.py first, then run this script from the repository root."""
import ctypes as C
import os
import subprocess
import sys
import traceback

sys.dont_write_bytecode = True
from rn17 import ROOT, OUT, REF, Batch, Memory, ppm


def main():
    library = OUT / 'lvgl_rn17.so'
    lib = C.CDLL(str(library), mode=C.RTLD_GLOBAL)
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                    '-shared', '-fPIC', '-DLV_CONF_INCLUDE_SIMPLE',
                    '-Ithird_party/lvgl', '-Isw/apps/s3/lvgl',
                    '-Isw/drivers/include', '-Isw/bsp/include',
                    'sw/apps/s3/menu.c', '-L' + str(OUT), '-l:lvgl_rn17.so',
                    '-Wl,--no-undefined', '-Wl,-rpath,$ORIGIN',
                    '-o', str(OUT / 'menu.so')], cwd=ROOT, check=True)
    menu = C.CDLL(str(OUT / 'menu.so'))
    menu.s3_menu_input.argtypes = [C.c_uint32]
    menu.s3_menu_input.restype = C.c_int
    lib.s3_host_time.argtypes = [C.c_uint32]
    lib.s3_lvgl_input.argtypes = [C.c_uint32]
    lib.s3_lvgl_rendered_pixels.restype = C.c_void_p
    totals = {'commands': 0, 'pixels': 0}
    descriptors = bytearray()
    callback_type = C.CFUNCTYPE(None, C.POINTER(Batch))

    def execute(pointer):
        batch = pointer.contents
        ranges = [(r.address & 0xffffffff, r.address, r.bytes)
                  for r in batch.sources[:batch.source_count]]
        memory = Memory(ranges)
        packed = C.string_at(batch.commands, batch.count * 64)
        descriptors.extend(packed)
        commands = [REF.Command.decode(packed[i:i + 64]) for i in range(0, len(packed), 64)]
        result = REF.execute(memory, commands)
        if result.error:
            raise RuntimeError(f'RND ERR_CODE={result.error} CUR_DESC={result.cur_desc}')
        for target in batch.targets[:batch.target_count]:
            address = target.address & 0xffffffff
            C.memmove(target.address, bytes(memory[address:address + target.bytes]), target.bytes)
        totals['commands'] += result.completed
        totals['pixels'] += result.pixels

    def execute_or_stop(pointer):
        # Exceptions may not unwind through a ctypes callback into the C renderer.
        try:
            execute(pointer)
        except (RuntimeError, StopIteration):
            traceback.print_exc()
            os._exit(1)

    callback = callback_type(execute_or_stop)
    lib.s3_host_install.argtypes = [callback_type]
    lib.s3_host_install(callback)
    lib.s3_lvgl_init()
    menu.s3_menu_show()
    assert menu.s3_menu_input(1) == -1
    assert menu.s3_menu_input(4) == 4  # Previous wraps from game to LAYERS.
    assert menu.s3_menu_input(2) == -1
    assert menu.s3_menu_input(4) == 0
    assert menu.s3_menu_input(2) == -1
    assert menu.s3_menu_input(4) == 1
    menu.s3_menu_input(1)
    menu.s3_menu_show()
    lib.s3_lvgl_input(0)
    lib.s3_host_time(16)
    lib.s3_lvgl_step()
    output = OUT / 'menu-rnd.ppm'
    ppm(output, lib.s3_lvgl_rendered_pixels())
    (OUT / 'menu.commands.bin').write_bytes(descriptors)
    print(f'PASS production menu navigation and real rnd_ref execution: {totals}')
    print(output.resolve())


if __name__ == '__main__':
    main()
