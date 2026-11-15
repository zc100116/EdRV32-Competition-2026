#!/usr/bin/env python3
# hardhat_download.py — T-HELMET-DATA, approved public CC0 mirror.
# Download metadata and PNG images with four workers; existing images are skipped
# as authorized by the coordinator. Clock domain: not applicable (host tool).

import json
from pathlib import Path
import subprocess
from urllib.request import urlopen


def main():
    root = Path.home() / ".local/share/edrv32/hardhat"
    root.mkdir(parents=True, exist_ok=True)
    base = "https://huggingface.co/datasets/Voxel51/hard-hat-detection/resolve/main/"
    for name in ("README.md", "samples.json", "metadata.json", "fiftyone.yml"):
        (root / name).write_bytes(urlopen(base + name).read())
    samples = json.loads((root / "samples.json").read_text())["samples"]
    (root / "data").mkdir(exist_ok=True)

    config = []
    for sample in samples:
        name = sample["filepath"]
        destination = root / name
        if not destination.exists():
            config.extend([
                f"url = {json.dumps(base + name)}",
                f"output = {json.dumps(str(destination))}",
            ])
    # One curl process reuses connections across files, with at most four transfers.
    if config:
        subprocess.run(
            ["curl", "--parallel", "--parallel-max", "4", "--fail", "--fail-early", "--location",
             "--silent", "--show-error", "--remove-on-error", "--config", "-"],
            input="\n".join(config), text=True, check=True,
        )
    count = len(list((root / "data").glob("*.png")))
    if count != len(samples):
        raise RuntimeError(f"Downloaded {count} images; expected {len(samples)}")
    print(f"Downloaded {count} images to {root}")


if __name__ == "__main__":
    main()
