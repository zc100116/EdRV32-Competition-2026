"""model_data.py — NPU spec 2.5: four demonstration model inputs.

Select sorted dataset filenames with default_rng(0) for calibration/evaluation.
Clock domain: offline host tool.
"""
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DATA = Path.home() / ".local/share/edrv32/npu"
MODELS = ROOT / "sw/apps/showcase/models"
WORKSPACES = ROOT.parent


def weights_for(name):
    if name == "face":
        return DATA / "yolov8n-face.pt"
    return MODELS / name / "best.pt"


def dataset_root(name):
    if name == "gesture":
        return DATA / "hagrid-val600"
    if name == "face":
        return DATA / "wider-face"
    return WORKSPACES / f"task-{name}-data/build/{name}/yolo"


def wider_annotations():
    lines = iter((dataset_root("face") / "wider_face_val_bbx_gt.txt").read_text().splitlines())
    rows = {}
    for name in lines:
        count = int(next(lines))
        boxes = [list(map(int, next(lines).split())) for _ in range(max(1, count))]
        rows[name] = [b[:4] for b in boxes if b[2] > 0 and b[3] > 0 and b[7] == 0]
    return rows


def sample(paths, count):
    indices = np.random.default_rng(0).choice(len(paths), count, replace=False)
    return [paths[i] for i in indices]


def calibration_paths(name):
    root = dataset_root(name)
    if name == "face":
        paths = [root / "images" / p for p in sorted(wider_annotations())]
    else:
        split = "val" if name == "gesture" else "train"
        paths = sorted(p for p in (root / "images" / split).rglob("*")
                       if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp"})
    return sample(paths, 96)


def evaluation_paths(name):
    root = dataset_root(name)
    if name == "face":
        return sample([root / "images" / p for p in sorted(wider_annotations())], 300)
    paths = sorted(p for p in (root / "images/val").rglob("*")
                   if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp"})
    if name == "gesture":
        calibration = set(calibration_paths(name))
        return [p for p in paths if p not in calibration]
    return sample(paths, 600) if name == "doodle" else paths
