#!/usr/bin/env python3
# File: lvgl_host.py
# Spec: rnd-testplan RN-17(a); CLAUDE 9.3.
# Description: Single-process, single-job C11 host build of the unmodified LVGL submodule.
# Clock domain: host.
"""Build the LVGL RN-17 shared library with the board configuration."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/s3/lvgl"
FLAGS = ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-g", "-fPIC",
         "-ffreestanding", "-fno-builtin",
         "-DLV_CONF_INCLUDE_SIMPLE", "-Ithird_party/lvgl", "-Isw/apps/s3/lvgl",
         "-Isw/apps/s3", "-Isw/lib", "-Isw/drivers/include", "-Isw/bsp/include"]


def build(sanitize=False):
    output = OUT / "sanitized" if sanitize else OUT
    flags = FLAGS + (["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
                     if sanitize else [])
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run(["python3", "tools/s3/lvgl_assets.py", "build/s3/lvgl_assets.c"],
                   cwd=ROOT, check=True)
    sources = sorted(str(p.relative_to(ROOT)) for directory in
                     ("third_party/lvgl/src", "third_party/lvgl/demos/widgets",
                      "third_party/lvgl/demos/benchmark")
                     for p in (ROOT / directory).rglob("*.c"))
    sources += ["sw/lib/virtual_input.c","sw/apps/s3/lvgl/draw_rnd.c", "sw/apps/s3/lvgl/s3_lvgl.c",
                "sw/apps/s3/lvgl/rn17_compare.c",
                "sw/drivers/rnd.c", "sw/drivers/mem_xbar.c", "tools/s3/lvgl_host.c",
                "build/s3/lvgl_assets.c"]
    if sanitize:
        sources += ["sw/apps/s3/menu.c", "sw/apps/s3/host/layers_check.c"]
    objects = []
    sources.append("third_party/lvgl/demos/lv_demos.c")
    headers = [p for directory in ("sw/apps/s3/lvgl", "sw/drivers/include", "sw/bsp/include")
               for p in (ROOT / directory).rglob("*.h")]
    headers.append(ROOT / "sw/apps/s3/s3_platform.h")
    config_time = max(Path(__file__).stat().st_mtime, *(p.stat().st_mtime for p in headers))
    for source in sources:
        obj = output / "obj" / (source + ".o")
        objects.append(str(obj))
        if obj.exists() and obj.stat().st_mtime > max((ROOT / source).stat().st_mtime,
                                                     config_time):
            continue
        obj.parent.mkdir(parents=True, exist_ok=True)
        extra = (["-Drnd_physical=s3_host_unused_board_physical"]
                 if source == "sw/drivers/rnd.c" else [])
        subprocess.run(["cc", *flags, *extra, "-c", source, "-o", str(obj)],
                       cwd=ROOT, check=True)
    library = output / "lvgl_rn17.so"
    subprocess.run(["cc", *flags, "-shared", "-Wl,--no-undefined", "-Wl,--wrap=lv_draw_sw_blend",
                    "-Wl,--wrap=lv_draw_sw_init", "-Wl,--wrap=lv_draw_create_unit",
                    "-Wl,--wrap=lv_timer_create", "-Wl,--wrap=rnd_read_perf",
                    "-Wl,--wrap=mem_xbar_snapshot",
                    *objects, "-lm", "-o", str(library)],
                   cwd=ROOT, check=True)
    print(f"PASS C11 -Wall -Wextra -Werror host build: {len(sources)} sources; {library}")
    return library


if __name__ == "__main__":
    build()
