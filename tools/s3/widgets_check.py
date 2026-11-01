#!/usr/bin/env python3
# File: widgets_check.py
# Spec: Task T-S3WID; RN-17; SoC 7.4.
# Description: Exercise the production menu/demo lifecycle under ASan/UBSan with rnd_ref.
# Clock domain: deterministic host milliseconds.
"""Run with: python3 tools/s3/widgets_check.py."""
import ctypes as C
import os
import subprocess
import sys
import traceback

from rn17 import Batch, Memory, REF, OUT, build


def main():
    if len(sys.argv) == 1:
        build(sanitize=True)
        asan = subprocess.check_output(['cc', '-print-file-name=libasan.so'], text=True).strip()
        env = dict(os.environ, LD_PRELOAD=asan,
                   ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',
                   UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
        os.execve(sys.executable, [sys.executable, __file__, '--run'], env)
    lib = C.CDLL(str(OUT / 'sanitized/lvgl_rn17.so'))
    lib.s3_host_time.argtypes = [C.c_uint32]
    callback_type = C.CFUNCTYPE(None, C.POINTER(Batch))
    totals = {'batches': 0, 'commands': 0, 'pixels': 0}
    opcodes = {}

    def execute(pointer):
        try:
            batch = pointer.contents
            ranges = [(r.address & 0xffffffff, r.address, r.bytes)
                      for r in batch.sources[:batch.source_count]]
            memory = Memory(ranges)
            packed = C.string_at(batch.commands, batch.count * 64)
            commands = [REF.Command.decode(packed[i:i + 64])
                        for i in range(0, len(packed), 64)]
            result = REF.execute(memory, commands)
            assert not result.error, (result.error, result.cur_desc)
            for target in batch.targets[:batch.target_count]:
                address = target.address & 0xffffffff
                C.memmove(target.address, bytes(memory[address:address + target.bytes]),
                          target.bytes)
            totals['batches'] += 1
            totals['commands'] += result.completed
            totals['pixels'] += result.pixels
            for i in range(0, len(packed), 64):
                opcodes[packed[i]] = opcodes.get(packed[i], 0) + 1
        except (AssertionError, RuntimeError, StopIteration):
            traceback.print_exc()
            os._exit(1)

    callback = callback_type(execute)
    lib.s3_host_install.argtypes = [callback_type]
    lib.s3_host_install(callback)
    lib.s3_lvgl_init()
    now = 0
    rendered = 0

    def frames(name, count=4, duration=32):
        nonlocal now, rendered
        before = lib.s3_frame_count()
        for _ in range(count):
            now += duration
            lib.s3_host_time(now)
            lib.s3_lvgl_step()
        count_rendered = lib.s3_frame_count() - before
        rendered += count_rendered
        print(f'PASS {name}: {count} steps, {count_rendered} frames; '
              f'RND {totals}; opcodes={opcodes}', flush=True)

    def launch(index):
        # Match main.c: KEY2 selects the card, KEY3 dispatches synchronously.
        while lib.s3_menu_input(4) != index:
            lib.s3_lvgl_input(2)
            lib.s3_menu_input(2)
            frames("menu KEY2 press", 1)
            lib.s3_lvgl_input(0)
            frames("menu KEY2 release", 1)
        if index == 1:
            lib.s3_lvgl_start_widgets()
        else:
            lib.s3_lvgl_start_benchmark()

    lib.s3_menu_show()
    frames('menu')
    launch(1)
    frames('menu -> WIDGETS')
    lib.s3_lvgl_stop_demo()
    lib.s3_menu_show()
    launch(2)
    frames('BENCHMARK scene 0')
    for scene in range(1, 16):
        frames(f'BENCHMARK scene {scene}', 1, 5032 if scene in (9, 15) else 3032)
        frames(f'BENCHMARK scene {scene} animation', 3)
    frames('BENCHMARK end', 1, 20032)
    lib.s3_lvgl_stop_demo()
    lib.s3_menu_show()
    frames('menu before LAYERS')
    lib.s3_layers_lvgl_check()
    frames('LAYERS opa_layered')
    lib.s3_lvgl_restore_display()
    lib.s3_menu_show()
    launch(1)
    frames('LAYERS -> menu -> WIDGETS')
    lib.s3_lvgl_stop_demo()
    print(f'PASS ASan/UBSan lifecycle: {rendered} frames; '
          f'RND {totals}; opcodes={opcodes}', flush=True)


if __name__ == '__main__':
    main()
