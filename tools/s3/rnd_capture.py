#!/usr/bin/env python3
# File: rnd_capture.py
# Spec: rnd 2.6/5.4/7; T-RNDMEAS.
# Description: Capture one RN-17 full refresh per real LVGL benchmark scene.
# Clock domain: deterministic host milliseconds.
import ctypes as C
import gzip
from pathlib import Path
import pickle
import subprocess
import sys

sys.dont_write_bytecode = True
from rn17 import Batch, Memory, REF
from lvgl_host import ROOT, OUT, FLAGS, build

DEST = ROOT / 'build/rnd_util/capture'


def main():
    build()
    DEST.mkdir(parents=True, exist_ok=True)
    obj = OUT / 'rnd_util_host.o'
    subprocess.run(['cc', *FLAGS, '-c', 'tools/s3/rnd_util_host.c', '-o', str(obj)],
                   cwd=ROOT, check=True)
    objects = sorted(p for p in (OUT / 'obj').rglob('*.o') if p.name != 's3_lvgl.c.o')
    wrap = ['lv_draw_sw_blend', 'lv_draw_sw_init', 'lv_draw_create_unit',
            'lv_timer_create', 'rnd_read_perf', 'mem_xbar_snapshot']
    library = OUT / 'rnd_util.so'
    subprocess.run(['cc', '-shared', '-Wl,--no-undefined',
                    *(f'-Wl,--wrap={name}' for name in wrap),
                    *map(str, objects), str(obj), '-lm', '-o', str(library)],
                   cwd=ROOT, check=True)
    lib = C.CDLL(str(library))
    lib.s3_host_time.argtypes = [C.c_uint32]
    lib.s3_lvgl_set_rnd.argtypes = [C.c_bool]
    lib.s3_util_name.restype = C.c_char_p
    callback_type = C.CFUNCTYPE(None, C.POINTER(Batch))
    output = None
    batches = 0

    def execute(pointer):
        nonlocal batches
        batch = pointer.contents
        ranges = [(r.address & 0xffffffff, r.address, r.bytes)
                  for r in batch.sources[:batch.source_count] if r.bytes]
        memory = Memory(ranges)
        packed = C.string_at(batch.commands, batch.count * 64)
        commands = [REF.Command.decode(packed[k:k + 64]) for k in range(0, len(packed), 64)]
        # Preserve physical addresses and full AXI boundary beats using a page map.
        pages = {}
        for address, host, size in ranges:
            for page in range(address // 4096, (address + size + 4095) // 4096):
                pages[page] = C.string_at(host + page * 4096 - address, 4096)
        for command in commands:
            base, size = REF.temp_region(command)
            for page in range(base // 4096, (base + size + 4095) // 4096) if size else ():
                # Temp is writable scratch; its initial value does not affect results.
                pages[page] = bytes(4096)
        result = REF.execute(memory, commands)
        if result.error:
            raise RuntimeError(f'RND ERR_CODE={result.error} CUR_DESC={result.cur_desc}')
        targets = []
        for target in batch.targets[:batch.target_count]:
            address = target.address & 0xffffffff
            data = bytes(memory[address:address + target.bytes])
            targets.append((address, data))
            C.memmove(target.address, data, target.bytes)
        pickle.dump((packed, pages, targets), output, protocol=4)
        batches += 1

    # Exceptions crossing a ctypes callback must terminate the renderer.
    def execute_or_stop(pointer):
        import os
        import traceback
        try:
            execute(pointer)
        except (RuntimeError, StopIteration, OSError):
            traceback.print_exc()
            os._exit(1)

    callback = callback_type(execute_or_stop)
    lib.s3_host_install.argtypes = [callback_type]
    lib.s3_host_install(callback)
    lib.s3_lvgl_init()
    lib.s3_util_capture_sync.argtypes = [C.c_bool]
    lib.s3_util_capture_sync(False)
    lib.s3_lvgl_set_rnd(False)
    lib.s3_lvgl_start_benchmark()
    captured = set()
    names = []
    entered = {0: 0}
    offsets = [1500] * 16
    offsets[8] = offsets[14] = 2500
    offsets[15] = 10000
    for now in range(100, 69000, 100):
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        scene = lib.s3_util_scene()
        if scene not in entered:
            entered[scene] = now
        if scene < 16 and scene not in captured and now - entered[scene] >= offsets[scene]:
            name = lib.s3_util_name().decode()
            batches = 0
            with gzip.open(DEST / f'{scene:02d}.pkl.gz', 'wb') as output:
                lib.s3_util_capture_sync(True)
                lib.s3_lvgl_self_compare()
                lib.s3_util_capture_sync(False)
                pickle.dump(None, output)
            captured.add(scene)
            names.append(name)
            print(f'CAPTURE {scene:02d} {name}: {batches} batches at {now} ms', flush=True)
    assert len(captured) == 16, captured
    (DEST / 'names.txt').write_text('\n'.join(names) + '\n')
    lib.s3_lvgl_stop_demo()


if __name__ == '__main__':
    main()
