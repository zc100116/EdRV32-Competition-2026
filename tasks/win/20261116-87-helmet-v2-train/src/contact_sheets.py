"""contact_sheets.py — T-HELMET-V2 step 3, head box visual comparison.

Draw 24 converted CrowdHuman and 12 original Hard Hat images.
Clock domain: not applicable. Generated images must not enter git.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps


root = Path(sys.argv[1])
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(0)
datasets = [("crowdhuman", root / "crowdhuman", 24, ".jpg"),
            ("hardhat", root.parent / "extra/helmet/yolo", 12, ".png")]
for name, data, count, suffix in datasets:
    candidates = []
    for label in sorted((data / "labels/train").glob("*.txt")):
        heads = [list(map(float, line.split()[1:])) for line in label.read_text().splitlines()
                 if line.split()[0] == "1"]
        if heads:
            candidates.append((label.stem, heads))
    sheet = Image.new("RGB", (4 * 480, ((count + 3) // 4) * 390), "white")
    for index, selected in enumerate(rng.choice(len(candidates), count, replace=False)):
        stem, heads = candidates[selected]
        with Image.open(data / "images/train" / f"{stem}{suffix}") as source:
            image = source.convert("RGB")
        width, height = image.size
        draw = ImageDraw.Draw(image)
        for x, y, w, h in heads:
            draw.rectangle(((x - w / 2) * width, (y - h / 2) * height,
                            (x + w / 2) * width, (y + h / 2) * height),
                           outline="lime", width=3)
        tile = ImageOps.contain(image, (480, 360))
        x, y = (index % 4) * 480, (index // 4) * 390
        sheet.paste(tile, (x + (480 - tile.width) // 2, y))
        ImageDraw.Draw(sheet).text((x + 4, y + 362), f"{stem} / {len(heads)} heads",
                                   fill="black")
    sheet.save(output / f"{name}-heads.jpg", quality=95)
    print(name, count, output / f"{name}-heads.jpg", flush=True)
