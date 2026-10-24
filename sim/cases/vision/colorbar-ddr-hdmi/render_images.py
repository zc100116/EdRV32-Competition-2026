#!/usr/bin/env python3
"""Render and compare DDR RGB565 decode and HDMI RGB888 scanout captures."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    output_dir = args.output_dir.resolve()
    ddr_image = Image.open(output_dir / "colorbar_ddr.ppm").convert("RGB")
    hdmi_image = Image.open(output_dir / "colorbar_hdmi.ppm").convert("RGB")

    if ddr_image.size != hdmi_image.size:
        raise SystemExit(
            f"image size mismatch: DDR={ddr_image.size} HDMI={hdmi_image.size}"
        )

    difference = ImageChops.difference(ddr_image, hdmi_image)
    if difference.getbbox() is not None:
        difference.save(output_dir / "colorbar_difference.png")
        raise SystemExit("DDR and HDMI images differ")

    resampling = getattr(Image, "Resampling", Image).NEAREST
    display_size = (1280, 720)
    ddr_scaled = ddr_image.resize(display_size, resampling)
    hdmi_scaled = hdmi_image.resize(display_size, resampling)
    ddr_scaled.save(output_dir / "colorbar_ddr.png")
    hdmi_scaled.save(output_dir / "colorbar_hdmi.png")

    sheet = Image.new("RGB", (display_size[0] * 2, display_size[1] + 28), "black")
    sheet.paste(ddr_scaled, (0, 28))
    sheet.paste(hdmi_scaled, (display_size[0], 28))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 8), "DDR RGB565 decode", fill="white")
    draw.text((display_size[0] + 8, 8), "HDMI RGB888 scanout", fill="white")
    sheet.save(output_dir / "colorbar_compare.png")

    print(
        "IMAGE_COMPARE_PASS "
        f"size={ddr_image.width}x{ddr_image.height} "
        f"pixels={ddr_image.width * ddr_image.height}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
