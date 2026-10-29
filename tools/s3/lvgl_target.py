#!/usr/bin/env python3
# File: lvgl_target.py
# Spec: CLAUDE 9.3; SoC 1.2 S3; Task B3-3b.
# Description: Compile the LVGL fragment as RV32 C11 without a second application entry point.
# Clock domain: host tool, generated objects target clk_sys.
"""Compile the LVGL fragment with the S3 freestanding target flags, one compiler at a time."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/s3/lvgl-rv32"


def main():
    sources = sorted(str(p.relative_to(ROOT)) for directory in
                     ("third_party/lvgl/src", "third_party/lvgl/demos/widgets",
                      "third_party/lvgl/demos/benchmark")
                     for p in (ROOT / directory).rglob("*.c"))
    sources += ["third_party/lvgl/demos/lv_demos.c", "sw/apps/s3/lvgl/draw_rnd.c",
                "sw/apps/s3/lvgl/s3_lvgl.c", "sw/apps/s3/lvgl/rn17_compare.c",
                "sw/apps/s3/lvgl/freestanding.c",
                "build/s3/lvgl_assets.c"]
    subprocess.run(["python3", "tools/s3/lvgl_assets.py", "build/s3/lvgl_assets.c"],
                   cwd=ROOT, check=True)
    objects = []
    flags = ["-march=rv32im_zicsr", "-mabi=ilp32", "-std=c11", "-Wall", "-Wextra", "-Werror",
             "-O2", "-g", "-ffreestanding", "-fno-builtin", "-ffunction-sections",
             "-fdata-sections", "-DLV_CONF_INCLUDE_SIMPLE", "-Ithird_party/lvgl",
             "-Isw/apps/s3/lvgl", "-Isw/apps/s3", "-Isw/bsp/include", "-Isw/drivers/include"]
    config_time = (ROOT / "sw/apps/s3/lvgl/lv_conf.h").stat().st_mtime
    for source in sources:
        obj = OUT / (source + ".o")
        objects.append(str(obj))
        if obj.exists() and obj.stat().st_mtime > max(config_time,
                                                     (ROOT / source).stat().st_mtime):
            continue
        obj.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["riscv-none-elf-gcc", *flags, "-c", source, "-o", str(obj)],
                       cwd=ROOT, check=True)
    output = OUT / "lvgl.o"
    subprocess.run(["riscv-none-elf-ld", "-melf32lriscv", "-r", *objects, "-o", str(output)],
                   cwd=ROOT, check=True)
    result = subprocess.run(["riscv-none-elf-nm", "-u", str(output)],
                            check=True, capture_output=True, text=True)
    (OUT / "undefined.txt").write_text(result.stdout)
    print(f"PASS RV32 C11 -Wall -Wextra -Werror: {len(sources)} sources")
    print(result.stdout)


if __name__ == "__main__":
    main()
