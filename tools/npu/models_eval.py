#!/usr/bin/env python3
"""models_eval.py — NPU spec 2.5–2.6: four model FP32/INT8 evaluation.

Execute 640x384 descriptors and hardware postprocessing, then measure boxes/points.
Clock domain: offline host tool; predictions and measurements remain in build/.
"""
import argparse
import json
from pathlib import Path
import subprocess
from time import perf_counter
from types import SimpleNamespace

import cv2
import numpy as np
import torch
from ultralytics import YOLO
from ultralytics.engine.validator import BaseValidator
from ultralytics.utils.metrics import ap_per_class, box_iou

from fixed_plan import build_plan, descriptors
from format import BASES, pack_c4
from model_data import dataset_root, evaluation_paths, weights_for, wider_annotations
from pose_eval import iou, output_bytes, resources
from quantize import load_quantized, prepare_image
from ref.npu_ref import Memory, execute
from yolo_post_ref import STAT_KEYS, decode_candidates, integer_sort, make_heads, suppresses


def fp32(network, image, nc, nk):
    with torch.inference_mode():
        values = network(image)[0][0].T.cpu().numpy()
    classes = values[:, 4:4 + nc].argmax(1)
    scores = values[np.arange(len(values)), 4 + classes]
    anchors = np.flatnonzero(scores > .25)
    xywh = values[:, :4]
    boxes = np.column_stack((xywh[:, :2] - xywh[:, 2:] / 2,
                             xywh[:, :2] + xywh[:, 2:] / 2))
    order = anchors[np.lexsort((anchors, -scores[anchors]))]
    keep = []
    while len(order) and len(keep) < 100:
        index = order[0]
        keep.append(index)
        order = order[1:]
        order = order[(classes[order] != classes[index]) |
                      (iou(boxes[index], boxes[order]) <= .45)]
    points = values[keep, 4 + nc:].reshape(len(keep), nk // 3, 3)
    return boxes[keep], scores[keep], classes[keep], points


def integer(memory, registers, plan, rows, heads, image):
    packed = torch.round(image * 127).to(torch.int8)
    memory.write(BASES["INPUT_BASE"], pack_c4(packed[0].permute(1, 2, 0).numpy()))
    execute(memory, registers)
    candidates = decode_candidates(memory.read(BASES["OUTPUT_BASE"], output_bytes(plan)), heads)
    integer_sort(candidates, dict.fromkeys(STAT_KEYS, 0))
    kept = []
    for candidate in candidates:
        if any(previous[2] == candidate[2] and suppresses(previous[0], candidate[0])
               for previous in kept):
            continue
        kept.append(candidate)
        if len(kept) == 100:
            break
    nk = plan["nk"]
    points = np.empty((len(kept), 0, 3))
    if nk:
        lookup = {row["name"]: row for row in rows}
        decoded = []
        for scale, stride in enumerate((8, 16, 32)):
            t = plan["tensors"][f"D{scale}.kpt"]
            raw = np.frombuffer(memory.read(t["base"], t["bytes"]), dtype=np.int8)
            raw = raw.reshape(t["channels"] // 16, t["height"], t["width"], 16)
            raw = raw.transpose(1, 2, 0, 3).reshape(-1, t["channels"])[:, :nk].astype(float)
            q = lookup[f"D{scale}.kpt.out"]
            p = ((raw - q["output_zero_point"]) * q["output_scale"]).reshape(-1, nk // 3, 3)
            cells = np.indices((t["height"], t["width"])).reshape(2, -1).T[:, ::-1]
            p[:, :, :2] = (p[:, :, :2] * 2 + cells[:, None, :]) * stride
            p[:, :, 2] = 1 / (1 + np.exp(-p[:, :, 2]))
            decoded.append(p)
        points = np.concatenate(decoded)[[c[3] for c in kept]]
    return (np.array([c[0] for c in kept], dtype=float).reshape(-1, 4) / 256,
            np.array([c[1] / (1 << 24) for c in kept]), np.array([c[2] for c in kept]), points)


def truth(name, path, wider):
    source = cv2.imread(str(path))
    height, width = source.shape[:2]
    if name == "face":
        key = str(path.relative_to(dataset_root(name) / "images"))
        xywh = np.array(wider[key], dtype=float).reshape(-1, 4)
        classes = np.zeros(len(xywh))
        boxes = np.column_stack((xywh[:, :2], xywh[:, :2] + xywh[:, 2:]))
    else:
        label = dataset_root(name) / "labels/val" / (path.stem + ".txt")
        labels = np.array([list(map(float, line.split()[:5]))
                           for line in label.read_text().splitlines()]).reshape(-1, 5)
        classes = labels[:, 0]
        xywh = labels[:, 1:] * [width, height, width, height]
        boxes = np.column_stack((xywh[:, :2] - xywh[:, 2:] / 2,
                                 xywh[:, :2] + xywh[:, 2:] / 2))
    ratio = min(640 / width, 384 / height)
    pad = np.array([(640 - round(width * ratio)) // 2, (384 - round(height * ratio)) // 2])
    return boxes * ratio + np.tile(pad, 2), classes, ratio, pad, width, height


def detection_stats(boxes, classes, result):
    predicted, scores, ids, _ = result
    overlaps = box_iou(torch.tensor(boxes), torch.tensor(predicted))
    validator = SimpleNamespace(iouv=torch.linspace(.5, .95, 10))
    correct = BaseValidator.match_predictions(
        validator, torch.tensor(ids), torch.tensor(classes), overlaps).numpy()
    return correct, scores, ids, classes


def aggregate(rows, names):
    tp, scores, ids, targets = [np.concatenate([r[i] for r in rows]) for i in range(4)]
    values = ap_per_class(tp, scores, ids, targets)
    ap, classes = values[5:7]
    return dict(map50=float(ap[:, 0].mean()), map50_95=float(ap.mean()),
                ap50={names[int(c)]: float(a) for c, a in zip(classes, ap[:, 0])})


def match(boxes, predicted, scores):
    used = set()
    pairs = []
    for i in np.argsort(-scores, kind="stable"):
        remaining = [j for j in range(len(boxes)) if j not in used]
        if not remaining:
            break
        overlaps = iou(predicted[i], boxes[remaining])
        best = int(overlaps.argmax())
        if overlaps[best] >= .5:
            used.add(remaining[best])
            pairs.append((remaining[best], int(i)))
    return pairs


def evaluate(name, out):
    started = perf_counter()
    network = YOLO(str(weights_for(name))).model.eval().fuse(verbose=False)
    head = network.model[-1]
    shape = getattr(head, "kpt_shape", (0, 3))
    task = "detect" if name in ("doodle", "helmet") else name
    plan = build_plan(task, head.nc, shape[0] * shape[1])
    plan.update(weights=str(weights_for(name).resolve()), dataset=name)
    model, rows = load_quantized(plan)
    desc = descriptors(plan, rows)
    memory = Memory()
    memory.write(BASES["MODEL_BASE"], model)
    memory.write(BASES["DESC_BASE"], b"".join(d.encode() for d in desc))
    registers = BASES | {"DESC_COUNT": len(desc)}
    heads = make_heads({"convolutions": rows})
    paths = evaluation_paths(name)
    wider = wider_annotations() if name == "face" else None
    stats = {key: [] for key in ("fp32", "int8")}
    errors, predictions = [], []
    matched = 0
    confusion = np.zeros((head.nc + 1, head.nc + 1), dtype=int)
    for index, path in enumerate(paths):
        boxes, classes, ratio, pad, width, height = truth(name, path, wider)
        image = prepare_image(path)
        results = dict(fp32=fp32(network, image, plan["nc"], plan["nk"]),
                       int8=integer(memory, registers, plan, rows, heads, image))
        for key, result in results.items():
            stats[key].append(detection_stats(boxes, classes, result))
        a, b = results["fp32"], results["int8"]
        if plan["nk"]:
            for j, i in match(a[0], b[0], b[1]):
                if a[2][j] != b[2][i]:
                    continue
                matched += 1
                visible = a[3][j, :, 2] > .5
                difference = (a[3][j, visible, :2] - b[3][i, visible, :2])
                difference *= np.array([1280 / width, 720 / height]) / ratio
                errors.extend(np.linalg.norm(difference, axis=1).tolist())
        if name == "gesture":
            pairs = match(boxes, b[0], b[1])
            for j, i in pairs:
                confusion[int(classes[j]), int(b[2][i])] += 1
            for j in set(range(len(boxes))) - {j for j, _ in pairs}:
                confusion[int(classes[j]), head.nc] += 1
            for i in set(range(len(b[0]))) - {i for _, i in pairs}:
                confusion[head.nc, int(b[2][i])] += 1
        predictions.append(dict(file=str(path), truth_boxes=boxes.tolist(),
            truth_classes=classes.tolist(), **{key: dict(zip(
                ("boxes", "scores", "classes", "points"), [v.tolist() for v in result]))
                for key, result in results.items()}))
        if (index + 1) % 50 == 0:
            elapsed = perf_counter() - started
            print(f"{name} {index + 1}/{len(paths)} elapsed_s={elapsed:.1f}", flush=True)
    resource = resources(plan, rows)
    baseline = resources(build_plan(), [{"index": c["index"], "output_zero_point": 0}
        for c in build_plan()["commands"] if c["kind"] == "conv"])["mac_cycles"]
    cycle_ratio = resource["mac_cycles"] / baseline
    summary = dict(images=len(paths), classes=network.names,
        metrics={key: aggregate(value, network.names) for key, value in stats.items()},
        resources=resource, cycle_ratio=cycle_ratio, estimated_ms_180=35 * cycle_ratio,
        estimated_ms_150=41.2 * cycle_ratio, elapsed_s=perf_counter()-started)
    if plan["nk"]:
        summary["points"] = dict(matched_boxes=matched, visible_points=len(errors),
                                mean_px=float(np.mean(errors)),
                                p95_px=float(np.percentile(errors, 95)))
    if name == "gesture":
        summary["confusion"] = dict(labels=list(network.names.values()) + ["background"],
                                    rows_truth_columns_prediction=confusion.tolist())
    out.mkdir(parents=True, exist_ok=True)
    (out / "predictions.json").write_text(json.dumps(predictions) + "\n")
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2), flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("build/npu/models_eval"))
    args = parser.parse_args()
    torch.set_num_threads(1)
    summary = {name: evaluate(name, args.out / name)
               for name in ("gesture", "doodle", "helmet", "face")}
    summary["commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
