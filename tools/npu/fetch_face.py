#!/usr/bin/env python3
"""fetch_face.py — NPU spec 2.5: fetch the specified face checkpoint and data.

Download the README weight and only sampled WIDER validation ZIP members.
Clock domain: offline host tool; downloads stay outside the repository.
"""
import io
import struct
import subprocess
from concurrent.futures import ThreadPoolExecutor
import zipfile
import zlib

import numpy as np

from model_data import DATA, dataset_root

BASE = "https://huggingface.co/datasets/CUHK-CSE/wider_face/resolve/main/data/"
WEIGHT_URL = ("https://drive.usercontent.google.com/download?"
              "id=1qcr9DbgsX3ryrz2uU8w4Xm3cOrRywXqb&export=download&confirm=t")
VAL_ZIP_BYTES = 362752168


def main():
    root = dataset_root("face")
    root.mkdir(parents=True, exist_ok=True)
    subprocess.run(["curl", "-L", "--fail", "-s", WEIGHT_URL, "-o",
                    str(DATA / "yolov8n-face.pt")], check=True)
    annotation = subprocess.check_output(["curl", "-L", "--fail", "-s",
                                          BASE + "wider_face_split.zip"])
    with zipfile.ZipFile(io.BytesIO(annotation)) as archive:
        (root / "wider_face_val_bbx_gt.txt").write_bytes(
            archive.read("wider_face_split/wider_face_val_bbx_gt.txt"))

    def fetch(start, end):
        return subprocess.check_output([
            "curl", "-L", "--fail", "-s", "-H", f"Range: bytes={start}-{end}",
            BASE + f"WIDER_val.zip?range={start}-{end}"])

    end_record = fetch(VAL_ZIP_BYTES - 22, VAL_ZIP_BYTES - 1)
    central_size, central_start = struct.unpack_from("<II", end_record, 12)
    central = fetch(central_start, central_start + central_size - 1)
    # Sparse ZIP metadata enables standard-library indexing without fetching image bodies.
    directory = root / "directory.zip"
    with directory.open("wb") as output:
        output.seek(central_start)
        output.write(central)
        output.write(end_record)
    with zipfile.ZipFile(directory) as archive:
        entries = sorted((x for x in archive.infolist() if x.filename.endswith(".jpg")),
                         key=lambda x: x.filename)
    selected = set(np.random.default_rng(0).choice(len(entries), 96, replace=False))
    selected.update(np.random.default_rng(0).choice(len(entries), 300, replace=False))

    def download(index):
        entry = entries[index]
        header = fetch(entry.header_offset, entry.header_offset + 29)
        name_len, extra_len = struct.unpack_from("<HH", header, 26)
        start = entry.header_offset + 30 + name_len + extra_len
        compressed = fetch(start, start + entry.compress_size - 1)
        data = zlib.decompress(compressed, -15) if entry.compress_type == 8 else compressed
        destination = root / "images" / entry.filename.split("images/", 1)[1]
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return len(data)

    with ThreadPoolExecutor(max_workers=8) as pool:
        sizes = list(pool.map(download, sorted(selected)))
    directory.unlink()
    print(f"Downloaded {len(sizes)} images / {sum(sizes)} bytes from {len(entries)} val images")


if __name__ == "__main__":
    main()
