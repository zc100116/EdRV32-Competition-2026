"""train.py — T-HELMET-V2 step 4, fixed 50-epoch v1 fine-tuning.

Run only after coordinator approves sheets and hand training has ended.
Clock domain: not applicable. No automatic approval or GPU locking logic.
"""

import sys
from pathlib import Path

from ultralytics import YOLO


root = Path(sys.argv[1])
hardhat = root.parent / "extra/helmet/yolo"
for split in ("train", "val"):
    images = sorted((hardhat / "images" / split).glob("*.png"))
    images += sorted((root / "crowdhuman/images" / split).glob("*.jpg"))
    (root / f"{split}.txt").write_text("\n".join(map(str, images)) + "\n")
(root / "combined.yaml").write_text(
    f"path: {root}\ntrain: train.txt\nval: val.txt\n"
    "names:\n  0: helmet\n  1: head\n")
model = YOLO(root.parent / "runs/helmet-v8n/weights/best.pt")
model.train(data=str(root / "combined.yaml"), epochs=50, imgsz=640, batch=128,
            workers=16, cache=False, seed=0, deterministic=True,
            project=str(root), name="train")
