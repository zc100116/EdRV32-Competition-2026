#!/usr/bin/env python3
"""compose_tower_blocks.py — showcase R4 design §6.3/6.7 tower block artwork.
Tile original material swatches through shared collision silhouettes, then add
an inward 2 px outline and directional bevel. Host tool; no clock domain.
"""
import argparse
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

# Display-space geometry: origin at top left, x right, y down, units in pixels.
# Arch is the upper half of an annulus centered at (80, 80), radii 80 and 40.
SHAPES = {
    "square": {"size": (80, 80), "vertices": ((0, 0), (80, 0), (80, 80), (0, 80))},
    "circle": {"size": (80, 80), "center": (40, 40), "radius": 40},
}
MATERIALS = {"wood": 255, "stone": 255, "ice": 179, "metal": 255,
             "rubber": 255, "glass": 179}
SCALE = 4


def shape_mask(geometry):
    """Rasterize exact geometric boundaries with 4x antialiasing."""
    width, height = geometry["size"]
    mask = Image.new("L", (width * SCALE, height * SCALE))
    draw = ImageDraw.Draw(mask)
    if "vertices" in geometry:
        draw.polygon([(x * SCALE, y * SCALE) for x, y in geometry["vertices"]], fill=255)
    else:
        cx, cy = geometry["center"]
        radius = geometry["radius"]
        draw.ellipse(((cx - radius) * SCALE, (cy - radius) * SCALE,
                      (cx + radius) * SCALE - 1, (cy + radius) * SCALE - 1), fill=255)
        if "cutout_radius" in geometry:
            radius = geometry["cutout_radius"]
            draw.ellipse(((cx - radius) * SCALE, (cy - radius) * SCALE,
                          (cx + radius) * SCALE - 1, (cy + radius) * SCALE - 1), fill=0)
    return mask


def erode(mask, pixels):
    # Transparent padding makes rectangular image boundaries real silhouette edges.
    padded = ImageOps.expand(mask, pixels, fill=0)
    return padded.filter(ImageFilter.MinFilter(2 * pixels + 1)).crop(
        (pixels, pixels, pixels + mask.width, pixels + mask.height))


def shifted(mask, dx, dy):
    result = Image.new("L", mask.size)
    result.paste(mask, (dx, dy))
    return result


def compose(texture, geometry, opacity):
    mask = shape_mask(geometry)
    width, height = geometry["size"]
    tiled = Image.new("RGB", (width, height))
    for y in range(0, height, texture.height):
        for x in range(0, width, texture.width):
            tiled.paste(texture, (x, y))
    result = tiled.resize(mask.size, Image.Resampling.NEAREST)
    inner = erode(mask, 2 * SCALE)
    outline = ImageChops.subtract(mask, inner)
    result.paste((23, 38, 52), mask=outline)
    light = ImageChops.subtract(inner, shifted(inner, 2 * SCALE, 2 * SCALE))
    dark = ImageChops.subtract(inner, shifted(inner, -2 * SCALE, -2 * SCALE))
    result.paste((245, 253, 255), mask=light.point(lambda a: round(a * 0.65)))
    result.paste((16, 36, 48), mask=dark.point(lambda a: round(a * 0.50)))
    result = result.convert("RGBA")
    result.putalpha(mask)
    result = result.resize((width, height), Image.Resampling.LANCZOS)
    result.putalpha(result.getchannel("A").point(lambda a: round(a * opacity / 255)))
    return result


def main():
    assets = Path(__file__).resolve().parents[2] / "sw/apps/showcase/assets/tower"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--textures", type=Path, default=assets / "textures")
    parser.add_argument("--output", type=Path, default=assets)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for material, opacity in MATERIALS.items():
        texture = Image.open(args.textures / f"{material}.png").convert("RGB")
        if material == "rubber":
            # Fine molded grain and a soft diagonal face highlight survive at 1:1 pixels.
            grain = random.Random(20261116)
            pixels = texture.load()
            for y in range(texture.height):
                for x in range(texture.width):
                    red, green, blue = pixels[x, y]
                    light = max(0, 32 - abs((x + y) % 128 - 40) // 2)
                    noise = grain.randrange(-20, 21)
                    pixels[x, y] = tuple(max(0, min(255, c + light + noise))
                                         for c in (red, green, blue))
        for shape, geometry in SHAPES.items():
            output = args.output / f"block-{material}-{shape}.png"
            compose(texture, geometry, opacity).save(output)
            print(output)


if __name__ == "__main__":
    main()
