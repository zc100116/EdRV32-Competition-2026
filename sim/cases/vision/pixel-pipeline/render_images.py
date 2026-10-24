from pathlib import Path
import sys

from PIL import Image


STEMS = (
    "pixel_grayscale",
    "pixel_threshold",
    "pixel_sobel",
    "pixel_mean",
    "pixel_gaussian",
    "pixel_sharpen",
    "pixel_erode",
    "pixel_dilate",
)


def read_ppm(path: Path) -> Image.Image:
    tokens = path.read_text(encoding="ascii").split()
    if tokens[0] != "P3":
        raise ValueError(f"{path}: expected P3")
    width, height, maximum = map(int, tokens[1:4])
    if maximum != 255:
        raise ValueError(f"{path}: expected maximum 255")
    values = list(map(int, tokens[4:]))
    if len(values) != width * height * 3:
        raise ValueError(f"{path}: pixel payload length mismatch")
    image = Image.new("RGB", (width, height))
    image.putdata(list(zip(values[0::3], values[1::3], values[2::3])))
    return image


def main() -> None:
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    for stem in STEMS:
        image = read_ppm(output_dir / f"{stem}.ppm")
        if image.size != (32, 8):
            raise SystemExit(f"IMAGE_SIZE_FAIL {stem} size={image.size}")
        image.save(output_dir / f"{stem}.png")
    print(f"PIXEL_IMAGE_PARSE_PASS images={len(STEMS)}")


if __name__ == "__main__":
    main()
