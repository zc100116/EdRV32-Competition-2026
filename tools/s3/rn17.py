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


# Mirrors draw_rnd.h and s3_platform.h for the per-frame maintenance delta.
class Timing(C.Structure):
    _fields_ = [("clean_ticks", C.c_uint64), ("wait_ticks", C.c_uint64),
                ("finish_ticks", C.c_uint64), ("cache_ops", C.c_uint32)]


class Measurement(C.Structure):
    _fields_ = [("ticks", C.c_uint64), ("perf", C.c_uint64 * 6),
                ("commands", C.c_uint32), ("doorbells", C.c_uint32)]


class DrawStats(C.Structure):
    _fields_ = [("claimed", C.c_uint32 * 16), ("unclaimed", C.c_uint32 * 16),
                ("executed", C.c_uint32), ("software", C.c_uint32),
                ("commands", C.c_uint32), ("doorbells", C.c_uint32),
                ("rnd_ticks", C.c_uint64), ("sw_ticks", C.c_uint64),
                ("perf", C.c_uint64 * 6), ("copy", Measurement),
                ("timing", Timing), ("glyph_cpu_ticks", C.c_uint64)]


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



def mask_alpha_check(lib):
    width, height = 33, 23
    count = width * height
    lib.s3_host_mask_reference.argtypes = [C.POINTER(C.c_uint32), *([C.c_int32] * 7), C.c_bool]
    cases = 0
    worst = 0
    for left in (-2, 3):
        mask = (left, 2, 29, 20)
        for radius in (0, 1, 7, 30):
            opaque = (C.c_uint32 * count)(*([0xff113355] * count))
            lib.s3_host_mask_reference(opaque, width, height, *mask, radius, False)
            sw_cov = [value >> 24 for value in opaque]
            hw_cov = [REF.rectangle_coverage(mask, radius, x, y)
                      for y in range(height) for x in range(width)]
            edge = set()
            for y in range(height):
                for x in range(width):
                    index = y * width + x
                    for cov in (sw_cov, hw_cov):
                        if 0 < cov[index] < 255 or any(
                                bool(cov[index]) != bool(cov[ny * width + nx])
                                for ny in range(max(0, y - 1), min(height, y + 2))
                                for nx in range(max(0, x - 1), min(width, x + 2))):
                            edge.add(index)
            for keep in (False, True):
                initial = [((0, 1, 128, 255)[i % 4] << 24) | (i * 7919 & 0xffffff)
                           for i in range(count)]
                native = (C.c_uint32 * count)(*initial)
                lib.s3_host_mask_reference(native, width, height, *mask, radius, keep)
                memory = bytearray(struct.pack('<' + 'I' * count, *initial))
                command = REF.Command(12, dst_fmt=1, dst_base=0, dst_stride=width * 4,
                    clip=(0, 0, width - 1, height - 1), rect=(0, 0, width - 1, height - 1),
                    flags=int(keep), args=(radius, REF.xy(*mask[:2]), REF.xy(*mask[2:]), 0, 0, 0, 0, 0))
                REF.execute(memory, [command])
                actual = struct.unpack('<' + 'I' * count, memory)
                maximum = max((abs((a >> 24) - (b >> 24))
                               for i, (a, b) in enumerate(zip(actual, native)) if i not in edge),
                              default=0)
                assert maximum <= 1, (mask, radius, keep, maximum)
                worst = max(worst, maximum)
                cases += 1
    print(f"PASS MASK_RECT native LVGL alpha: {cases} cases, outside-band max={worst}/255")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()
    library = OUT / "lvgl_rn17.so" if args.no_build else build()
    lib = C.CDLL(str(library))
    lib.s3_draw_rnd_stats.restype = C.POINTER(DrawStats)
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
    mask_alpha_check(lib)
    lib.s3_lvgl_set_rnd(False)
    lib.s3_lvgl_input(0)
    rows = ["frame|full max LSB|edge max LSB|>1 LSB pixels|>1 LSB %|RND/SW tasks|bins|result",
            "---|---:|---:|---:|---:|---:|---|---"]

    def compare(name):
        print(f"RN-17 frame={name}", flush=True)
        start = len(descriptors)
        previous = lib.s3_draw_rnd_stats().contents.timing.cache_ops
        commands_before = totals["commands"]
        lib.s3_lvgl_self_compare()
        cache_ops = lib.s3_draw_rnd_stats().contents.timing.cache_ops - previous
        commands = totals["commands"] - commands_before
        print(f"CACHE frame={name} ops={cache_ops} commands={commands}", flush=True)
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
    for now in (16, 176, 656, 1136):
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        compare(f"widgets-{now}")
    lib.s3_lvgl_stop_demo()
    lib.s3_lvgl_start_benchmark()
    selected = {0: "empty", 2: "rectangle", 4: "rgb-images", 5: "argb-images",
                6: "rotated-images", 7: "labels", 9: "arcs", 10: "containers",
                12: "opa-containers", 13: "opa-layer"}
    # Actual lv_demo_benchmark scene timer advances its own scene list. The
    # runner does not synthesize or replace any scene's objects/draw tasks.
    for scene in range(14):
        now += 32 if scene == 0 else (5032 if scene == 9 else 3032)
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        if scene in selected:
            compare(f"benchmark-{scene:02d}-{selected[scene]}")
            if scene == 6:
                now += 160
                lib.s3_host_time(now)
                lib.s3_lvgl_step()
                compare("benchmark-06-rotated-images-later")
    # Finish the original scrolling/widgets scenes and exercise the real end
    # callback. These synthetic host-clock FPS values are not board measurements.
    for index, duration in enumerate((3032, 5032, 20032)):
        now += duration
        lib.s3_host_time(now)
        lib.s3_lvgl_step()
        if index == 1:
            compare("benchmark-15-widgets")
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
