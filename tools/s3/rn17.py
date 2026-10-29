#!/usr/bin/env python3
# File: rn17.py
# Spec: rnd-testplan RN-17(a)/6; RND 2.1–2.6/5.4.
# Description: Execute real LVGL draw-unit commands with rnd_ref and compare identical frames.
# Clock domain: deterministic host milliseconds, no SoC simulation.
"""Run LVGL widgets/benchmark RN-17 with the board configuration and real RND descriptors."""
import argparse
import ctypes as C
import importlib.util
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
from lvgl_host import ROOT, OUT, build

SPEC = importlib.util.spec_from_file_location("rnd_ref", ROOT / "verif/block/rnd/rnd_ref.py")
REF = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REF
SPEC.loader.exec_module(REF)


class Range(C.Structure):
    _fields_ = [("address", C.c_void_p), ("bytes", C.c_uint32)]


class Batch(C.Structure):
    _fields_ = [("commands", C.c_void_p), ("count", C.c_uint16),
                ("sources", C.POINTER(Range)), ("source_count", C.c_size_t),
                ("targets", C.POINTER(Range)), ("target_count", C.c_size_t)]


class Comparison(C.Structure):
    _fields_ = [("full_max_lsb", C.c_uint32), ("edge_max_lsb", C.c_uint32),
                ("over1", C.c_uint32), ("pixels", C.c_uint32)]
    _fields_ += [("histogram", C.c_uint32 * 5), ("rnd_tasks", C.c_uint32),
                 ("sw_tasks", C.c_uint32)]


class Memory:
    """Sparse byte slices preserve the real 32-bit descriptor addresses."""
    def __init__(self, ranges):
        self.regions = [(address, bytearray(C.string_at(pointer, size)))
                        for address, pointer, size in ranges]

    def region(self, start, stop):
        return next((address, data) for address, data in self.regions
                    if address <= start and stop <= address + len(data))

    def __getitem__(self, key):
        address, data = self.region(key.start, key.stop)
        return data[key.start - address:key.stop - address]

    def __setitem__(self, key, value):
        address, data = self.region(key.start, key.stop)
        data[key.start - address:key.stop - address] = value


def ppm(path, pixels):
    raw = C.string_at(pixels, 1280 * 720 * 2)
    image = bytearray(1280 * 720 * 3)
    for i, (value,) in enumerate(struct.iter_unpack("<H", raw)):
        _, r, g, b = REF.e565(value)
        image[i * 3:i * 3 + 3] = bytes((r, g, b))
    path.write_bytes(b"P6\n1280 720\n255\n" + image)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()
    library = OUT / "lvgl_rn17.so" if args.no_build else build()
    lib = C.CDLL(str(library))
    lib.s3_host_time.argtypes = [C.c_uint32]
    lib.s3_lvgl_input.argtypes = [C.c_uint32]
    lib.s3_lvgl_set_rnd.argtypes = [C.c_bool]
    lib.s3_lvgl_comparison.restype = C.POINTER(Comparison)
    lib.s3_compare_passes.argtypes = [C.POINTER(Comparison)]
    lib.s3_compare_passes.restype = C.c_bool
    lib.s3_lvgl_reference_pixels.restype = C.c_void_p
    lib.s3_lvgl_rendered_pixels.restype = C.c_void_p
    callback_type = C.CFUNCTYPE(None, C.POINTER(Batch))
    totals = {"batches": 0, "commands": 0, "pixels": 0}
    failures = []
    descriptors = bytearray()

    def execute(batch_pointer):
        batch = batch_pointer.contents
        ranges = []
        for i in range(batch.source_count):
            source = batch.sources[i]
            ranges.append((source.address & 0xffffffff, source.address, source.bytes))
        memory = Memory(ranges)
        packed = C.string_at(batch.commands, batch.count * 64)
        descriptors.extend(packed)
        commands = [REF.Command.decode(packed[i:i + 64]) for i in range(0, len(packed), 64)]
        result = REF.execute(memory, commands)
        if result.error:
            raise RuntimeError(f"RND ERR_CODE={result.error} CUR_DESC={result.cur_desc}")
        for i in range(batch.target_count):
            target = batch.targets[i]
            data = memory[target.address & 0xffffffff:(target.address & 0xffffffff) + target.bytes]
            C.memmove(target.address, bytes(data), target.bytes)
        totals["batches"] += 1
        totals["commands"] += result.completed
        totals["pixels"] += result.pixels

    # A Python exception must stop the C renderer immediately; ctypes otherwise
    # prints it and returns to C, which could produce a false successful frame.
    import os
    import traceback

    def execute_or_stop(batch):
        try:
            execute(batch)
        except (RuntimeError, StopIteration):
            traceback.print_exc()
            os._exit(1)

    callback = callback_type(execute_or_stop)
    lib.s3_host_install.argtypes = [callback_type]
    lib.s3_host_install(callback)
    lib.s3_lvgl_init()
    lib.s3_lvgl_set_rnd(False)
    lib.s3_lvgl_input(0)
    rows = ["frame|full max LSB|edge max LSB|>1 LSB pixels|>1 LSB %|RND/SW tasks|bins|result",
            "---|---:|---:|---:|---:|---:|---|---"]

    def compare(name):
        print(f"RN-17 frame={name}", flush=True)
        start = len(descriptors)
        lib.s3_lvgl_self_compare()
        result = lib.s3_lvgl_comparison().contents
        good = lib.s3_compare_passes(C.byref(result))
        rows.append(f"{name}|{result.full_max_lsb}|{result.edge_max_lsb}|{result.over1}|"
                    f"{result.over1 * 100 / result.pixels:.6f}|"
                    f"{result.rnd_tasks}/{result.sw_tasks}|{list(result.histogram)}|"
                    f"{'PASS' if good else 'FAIL'}")
        if not good:
            failures.append(name)
        ppm(OUT / f"{name}-sw.ppm", lib.s3_lvgl_reference_pixels())
        ppm(OUT / f"{name}-rnd.ppm", lib.s3_lvgl_rendered_pixels())
        (OUT / f"{name}.commands.bin").write_bytes(descriptors[start:])

    now = 0
    lib.s3_lvgl_start_widgets()
    for now in (16, 176, 656):
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        compare(f"widgets-{now}")
    lib.s3_lvgl_stop_demo()
    lib.s3_lvgl_start_benchmark()
    selected = {0: "empty", 2: "rectangle", 4: "rgb-images", 5: "argb-images",
                6: "rotated-images", 7: "labels", 10: "containers", 13: "opa-layer"}
    # Actual lv_demo_benchmark scene timer advances its own scene list. The
    # runner does not synthesize or replace any scene's objects/draw tasks.
    for scene in range(14):
        now += 32 if scene == 0 else (5032 if scene == 9 else 3032)
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        if scene in selected:
            compare(f"benchmark-{scene:02d}-{selected[scene]}")
    # Finish the original scrolling/widgets scenes and exercise the real end
    # callback. These synthetic host-clock FPS values are not board measurements.
    for duration in (3032, 5032, 20032):
        now += duration
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
    for repeat in range(2):
        lib.s3_lvgl_stop_demo()
        lib.s3_host_menu()
        now += 16
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        before = C.string_at(lib.s3_lvgl_rendered_pixels(), 1280 * 720 * 2)
        now += 3500
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        # The sysmon label may update; the menu's central text must survive.
        after = C.string_at(lib.s3_lvgl_rendered_pixels(), 1280 * 720 * 2)
        for y in range(300, 420):
            assert before[y * 2560 + 640:y * 2560 + 1920] == after[y * 2560 + 640:y * 2560 + 1920]
        print(f"PASS benchmark stop -> menu survives next scene deadline, repeat={repeat + 1}")
        lib.s3_lvgl_start_benchmark()
    lib.s3_lvgl_stop_demo()
    report = "\n".join(rows) + f"\n\nReal rnd_ref execution: {totals}\n"
    (OUT / "rn17-results.md").write_text(report)
    print(report)
    print(f"RN-17 {'FAIL' if failures else 'PASS'}; tolerance unchanged; failed frames={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
