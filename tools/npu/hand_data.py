"""hand_data.py — npu-spec 2.5: fixed hand calibration/evaluation inputs.

Transform labeled hand images and composite distance scenes with seed zero.
Clock domain: offline host tool.
"""
from pathlib import Path

import cv2
import numpy as np
import torch
from ultralytics.data.utils import verify_image_label

ROOT = Path(__file__).resolve().parents[2]
DATA = Path.home() / ".local/share/edrv32/npu"
HANDS = DATA / "hand-keypoints"
WEIGHTS = ROOT / "tasks/win/20261115-80-hand-pose-train/artifacts/best.pt"
SIZES = (45, 60, 90, 180)


def selected(split, count):
    rows, skipped = [], []
    for path in sorted((HANDS / "images" / split).glob("*.jpg")):
        label = HANDS / "labels" / split / (path.stem + ".txt")
        result = verify_image_label((str(path), str(label), "", True, 1, 21, 3, False))
        if result[0] is None:
            skipped.append(result[-1])
            continue
        _, labels, (height, width), _, points, *_ = result
        xywh = labels[:, 1:5] * [width, height, width, height]
        boxes = np.column_stack((xywh[:, :2] - xywh[:, 2:] / 2,
                                 xywh[:, :2] + xywh[:, 2:] / 2))
        points = points.astype(float)
        points[:, :, :2] *= [width, height]
        rows.append(dict(path=path, boxes=boxes, points=points))
    indices = np.random.default_rng(0).choice(len(rows), size=count, replace=False)
    return [rows[i] for i in indices], skipped


def tensor(image):
    rgb = np.ascontiguousarray(image[:, :, ::-1].transpose(2, 0, 1))
    return torch.from_numpy(rgb)[None].float() / 255


def letterbox(image, boxes, points, height=384):
    h, w = image.shape[:2]
    ratio = min(640 / w, height / h)
    resized = cv2.resize(image, (round(w * ratio), round(h * ratio)))
    left, top = (640 - resized.shape[1]) // 2, (height - resized.shape[0]) // 2
    image = cv2.copyMakeBorder(resized, top, height - resized.shape[0] - top,
                               left, 640 - resized.shape[1] - left,
                               cv2.BORDER_CONSTANT, value=(114, 114, 114))
    boxes = boxes * ratio + [left, top, left, top]
    points = points.copy()
    points[:, :, :2] = points[:, :, :2] * ratio + [left, top]
    return image, boxes, points


def composite(row, size, rng, backgrounds):
    image = cv2.imread(str(row["path"]))
    box = row["boxes"][0]
    scale = size * 2 / max(box[2:] - box[:2])
    h, w = image.shape[:2]
    resized = cv2.resize(image, (round(w * scale), round(h * scale)))
    # Place the annotated box completely inside the 1280x720 frame; clip only
    # surrounding source-image pixels when they extend beyond the frame.
    offset = np.array([rng.integers(int(np.ceil(-box[0] * scale)),
                                    int(np.floor(1280 - box[2] * scale)) + 1),
                       rng.integers(int(np.ceil(-box[1] * scale)),
                                    int(np.floor(720 - box[3] * scale)) + 1)])
    background = cv2.imread(str(backgrounds[int(rng.integers(len(backgrounds)))]))
    bh, bw = background.shape[:2]
    factor = max(1280 / bw, 720 / bh)
    background = cv2.resize(background, (round(bw * factor), round(bh * factor)))
    y, x = (background.shape[0] - 720) // 2, (background.shape[1] - 1280) // 2
    frame = background[y:y + 720, x:x + 1280].copy()
    x, y = offset
    rh, rw = resized.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(1280, x + rw), min(720, y + rh)
    frame[y0:y1, x0:x1] = resized[y0 - y:y1 - y, x0 - x:x1 - x]
    boxes = row["boxes"] * scale + np.tile(offset, 2)
    points = row["points"].copy()
    points[:, :, :2] = points[:, :, :2] * scale + offset
    return letterbox(frame, boxes, points)


def calibration_samples():
    rows, _ = selected("train", 96)
    rng = np.random.default_rng(0)
    backgrounds = sorted((DATA / "val2017").glob("*.jpg"))
    return [r["path"] for r in rows], [
        tensor(composite(row, SIZES[i % 4], rng, backgrounds)[0])
        for i, row in enumerate(rows)]
