#!/usr/bin/env python3
"""hand_edge_eval.py — T-HAND-EDGE; vin-spec 2.8, npu-spec 2.5–2.6.

Compare the board's gesture INT8 snapshot and FP384 at 17 positions and two sizes.
Clock domain: offline host; predictions in build/, examples in outputs/.
"""
import json
from pathlib import Path
import subprocess
from time import perf_counter

import cv2
import numpy as np
import torch
from ultralytics import YOLO, __version__ as ultralytics_version

from fixed_plan import build_plan
from hand_data import DATA, HANDS, ROOT, tensor, verify_image_label
from hand_eval import distribution, pinch
from model_data import weights_for
from models_eval import fp32, integer
from pose_eval import iou
from ref.npu_ref import Memory
from yolo_post_ref import make_heads

POSITIONS = ("center", "left", "right", "top", "bottom",
             "top_left", "top_right", "bottom_left", "bottom_right",
             "left_25", "right_25", "top_25", "bottom_25",
             "left_50", "right_50", "top_50", "bottom_50")
OUT = Path("build/npu/hand_edge_eval")
SNAPSHOT = ROOT / "sw/apps/showcase/models/gesture"


def sample_hands():
    # Reuse the existing verified loader, then sample the eligible pool rather
    # than taking the first filenames or filtering a preselected random subset.
    eligible, skipped = [], []
    for path in sorted((HANDS / "images/val").glob("*.jpg")):
        label = HANDS / "labels/val" / (path.stem + ".txt")
        result = verify_image_label((str(path), str(label), "", True, 1, 21, 3, False))
        if result[0] is None:
            skipped.append(result[-1])
            continue
        _, labels, (height, width), _, points, *_ = result
        if len(labels) != 1 or not np.all(points[0, :, 2] == 2):
            continue
        xywh = labels[0, 1:5] * [width, height, width, height]
        box = np.r_[xywh[:2] - xywh[2:] / 2, xywh[:2] + xywh[2:] / 2]
        points = points.astype(float)
        points[:, :, :2] *= [width, height]
        # A clear, complete source hand has its box inside the source image and
        # its visible landmarks inside that box (so a full edge placement is full).
        if (np.all(box[:2] >= 0) and np.all(box[2:] <= [width, height])
                and np.all(points[0, :, :2] >= box[:2])
                and np.all(points[0, :, :2] <= box[2:])):
            eligible.append(dict(path=path, boxes=box[None], points=points))
    indices = np.random.default_rng(0).choice(len(eligible), 40, replace=False)
    return [eligible[i] for i in indices], len(eligible), skipped


def background(path):
    image = cv2.imread(str(path))
    height, width = image.shape[:2]
    scale = max(1280 / width, 720 / height)
    image = cv2.resize(image, (round(width * scale), round(height * scale)))
    x, y = (image.shape[1] - 1280) // 2, (image.shape[0] - 720) // 2
    return image[y:y + 720, x:x + 1280].copy()


def origin(position, dimensions):
    width, height = dimensions
    x, y = (1280 - width) / 2, (720 - height) / 2
    sides = position.split("_")
    fraction = int(sides[-1]) / 100 if sides[-1].isdigit() else None
    if "left" in sides:
        x = -fraction * width if fraction else 4
    if "right" in sides:
        x = 1280 - (1 - fraction) * width if fraction else 1276 - width
    if "top" in sides:
        y = -fraction * height if fraction else 4
    if "bottom" in sides:
        y = 720 - (1 - fraction) * height if fraction else 716 - height
    return np.array([x, y])


def scene(row, source, backdrop, size, position):
    box = row["boxes"][0]
    dimensions = box[2:] - box[:2]
    scale = size / dimensions.max()
    # Keep approximately 15% of the box dimensions on each side, clipped only
    # by the source image; affine placement preserves the exact target box.
    lo = np.maximum(0, np.floor(box[:2] - dimensions * .15)).astype(int)
    hi = np.minimum(source.shape[1::-1], np.ceil(box[2:] + dimensions * .15)).astype(int)
    crop = source[lo[1]:hi[1], lo[0]:hi[0]]
    offset = origin(position, dimensions * scale) - box[:2] * scale
    transform = np.column_stack((np.eye(2) * scale, offset + lo * scale))
    frame = cv2.warpAffine(crop, transform, (1280, 720), dst=backdrop.copy(),
                           flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_TRANSPARENT)
    truth_box = box * scale + np.tile(offset, 2)
    points = row["points"][0].copy()
    points[:, :2] = points[:, :2] * scale + offset
    return frame, truth_box, points


def vin_input(frame):
    # vin-spec 2.8: half-up integer 2x2 averaging, then twelve gray rows per side.
    summed = frame.astype(np.uint16).reshape(360, 2, 640, 2, 3).sum(axis=(1, 3))
    half = ((summed + 2) >> 2).astype(np.uint8)
    return cv2.copyMakeBorder(half, 12, 12, 0, 0, cv2.BORDER_CONSTANT,
                              value=(114, 114, 114))


def measure(box, truth, result):
    boxes, scores, classes, points = result
    boxes = (boxes - [0, 12, 0, 12]) * 2
    points = points.copy()
    points[:, :, :2] = (points[:, :, :2] - [0, 12]) * 2
    clipped = np.clip(box, [0, 0, 0, 0], [1280, 720, 1280, 720])
    visible = np.all((truth[:, :2] >= 0) & (truth[:, :2] < [1280, 720]), axis=1)
    outside = int((~visible[[0, 4, 8, 9]]).sum())
    matches = np.flatnonzero(iou(clipped, boxes) >= .5)
    errors, d_error = [], None
    matched = None
    if len(matches):
        matched = int(matches[np.argmax(scores[matches])])
        prediction = points[matched]
        errors = np.linalg.norm(prediction[visible, :2] - truth[visible, :2], axis=1).tolist()
        if outside == 0:
            d_error = float(abs(pinch(prediction) - pinch(truth)))
    return dict(matched=matched, errors=errors, outside=outside, d_error=d_error,
                matched_class=int(classes[matched]) if matched is not None else None,
                boxes=boxes.tolist(), scores=scores.tolist(), classes=classes.tolist(),
                points=points.tolist())


def aggregate(rows):
    consistency = [r["class_consistent"] for r in rows if r["class_consistent"] is not None]
    return dict(samples=len(rows), detected=sum(r["matched"] is not None for r in rows),
                points=distribution([v for r in rows for v in r["errors"]]),
                outside_total=sum(r["outside"] for r in rows),
                outside_mean=float(np.mean([r["outside"] for r in rows])),
                outside_counts=np.bincount([r["outside"] for r in rows], minlength=5).tolist(),
                d_samples=sum(r["d_error"] is not None for r in rows),
                d_error=distribution([r["d_error"] for r in rows if r["d_error"] is not None]),
                class_samples=len(consistency),
                class_consistency=float(np.mean(consistency)) if consistency else None)


def main():
    started = perf_counter()
    torch.set_num_threads(1)
    cv2.setNumThreads(1)
    rows, eligible, skipped = sample_hands()
    backgrounds = sorted((DATA / "val2017").glob("*.jpg"))
    background_indices = np.random.default_rng(1).choice(len(backgrounds), 40, replace=False)
    plan = build_plan("gesture", 14, 63)
    quant = json.loads((SNAPSHOT / "quantization.json").read_text())["convolutions"]
    memory = Memory()
    memory.load_hex(SNAPSHOT / "mem_model.hex")
    memory.load_hex(SNAPSHOT / "mem_desc.hex")
    registers = {name: int(value, 16) for name, value in
                 (line.split() for line in (SNAPSHOT / "regs.txt").read_text().splitlines())}
    heads = make_heads({"convolutions": quant})
    network = YOLO(str(weights_for("gesture"))).model.eval().fuse(verbose=False)
    OUT.mkdir(parents=True, exist_ok=True)
    examples = Path("outputs/hand-edge")
    examples.mkdir(parents=True, exist_ok=True)
    predictions = []
    for index, row in enumerate(rows):
        source = cv2.imread(str(row["path"]))
        background_path = backgrounds[background_indices[index]]
        backdrop = background(background_path)
        for size in (120, 180):
            for position in POSITIONS:
                frame, box, truth = scene(row, source, backdrop, size, position)
                image = tensor(vin_input(frame))
                results = dict(int8=integer(memory, registers, plan, quant, heads, image),
                               fp384=fp32(network, image, 14, 63))
                for name, result in results.items():
                    predictions.append(dict(file=row["path"].name,
                        background=background_path.name, size=size, position=position, path=name,
                        truth_box=box.tolist(), truth_points=truth.tolist(),
                        **measure(box, truth, result)))
                if index == 0 and position in ("center", "left", "left_50"):
                    cv2.imwrite(str(examples / f"{size}-{position}.jpg"), frame)
        print(f"{index + 1}/40 elapsed={perf_counter() - started:.1f}s", flush=True)
    centers = {(r["file"], r["size"], r["path"]): r["matched_class"]
               for r in predictions if r["position"] == "center"}
    for row in predictions:
        center_class = centers[row["file"], row["size"], row["path"]]
        row["center_class"] = center_class
        row["class_consistent"] = (row["matched_class"] == center_class
            if row["matched_class"] is not None and center_class is not None else None)
    metrics = {f"{size}/{position}": {name: aggregate([
        r for r in predictions if r["size"] == size and r["position"] == position
        and r["path"] == name]) for name in ("int8", "fp384")}
        for size in (120, 180) for position in POSITIONS}
    summary = dict(commit=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        eligible=eligible, skipped=skipped, hand_seed=0, background_seed=1,
        model_snapshot=str(SNAPSHOT.relative_to(ROOT)), classes=network.names,
        elapsed_s=perf_counter() - started, metrics=metrics,
        versions=dict(torch=torch.__version__, numpy=np.__version__, opencv=cv2.__version__,
                      ultralytics=ultralytics_version))
    (OUT / "predictions.json").write_text(json.dumps(predictions) + "\n")
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"results={OUT} elapsed={summary['elapsed_s']:.1f}s", flush=True)


if __name__ == "__main__":
    main()
