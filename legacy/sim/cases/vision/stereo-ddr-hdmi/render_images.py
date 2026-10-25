from pathlib import Path
import sys

from PIL import Image


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
    expected = {
        "stereo_left_hdmi": (255, 0, 0),
        "stereo_right_hdmi": (0, 255, 0),
        "stereo_pixel_gray_hdmi": (148, 150, 148),
    }
    for stem, color in expected.items():
        image = read_ppm(output_dir / f"{stem}.ppm")
        if image.tobytes() != bytes(color) * (image.width * image.height):
            raise SystemExit(f"IMAGE_COMPARE_FAIL {stem} expected={color}")
        image.save(output_dir / f"{stem}.png")
    sobel = read_ppm(output_dir / "stereo_spatial_sobel_hdmi.ppm")
    for y in range(sobel.height):
        for x in range(sobel.width):
            expected_pixel = (255, 255, 255) if (
                x == 0 or x == sobel.width - 1 or
                y == 0 or y == sobel.height - 1
            ) else (0, 0, 0)
            if sobel.getpixel((x, y)) != expected_pixel:
                raise SystemExit(
                    f"IMAGE_COMPARE_FAIL stereo_spatial_sobel_hdmi "
                    f"x={x} y={y} expected={expected_pixel}"
                )
    sobel.save(output_dir / "stereo_spatial_sobel_hdmi.png")
    print("STEREO_IMAGE_COMPARE_PASS")


if __name__ == "__main__":
    main()
