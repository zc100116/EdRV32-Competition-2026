#!/usr/bin/env python3
"""hand_eval.py — npu-spec 2.6: fixed 21-point hand offline evaluation.

Measure ground-truth detection, OKS, point errors and pinch at fixed distances.
Clock domain: offline host tool; all predictions stay in build/.
"""
import argparse
import json
from pathlib import Path
import subprocess
from time import perf_counter
from types import SimpleNamespace

import cv2
import numpy as np
from PIL import Image
import torch
from ultralytics import YOLO
from ultralytics.engine.validator import BaseValidator
from ultralytics.utils.metrics import ap_per_class, kpt_iou

from fixed_plan import build_plan, descriptors
from format import BASES, pack_c4
from hand_data import DATA, SIZES, WEIGHTS, composite, letterbox, selected, tensor
from pose_eval import integer_keep, iou, output_bytes, resources
from quantize import load_quantized
from ref.npu_ref import Memory, execute
from yolo_post_ref import decode_candidates, make_heads

GROUPS = dict(wrist=[0], thumb=[4], index=[8], other_tips=[12, 16, 20],
              bases=[5, 9, 13, 17], joints=[1, 2, 3, 6, 7, 10, 11, 14, 15, 18, 19])
SKELETON = [(0, i) for i in (1, 5, 9, 13, 17)] + [
    (i, i + 1) for start in (1, 5, 9, 13, 17) for i in range(start, start + 3)]


def fp32(network, image):
    with torch.inference_mode():
        prediction = network(tensor(image))[0][0].T.cpu().numpy()
    anchors = np.flatnonzero(prediction[:, 4] > .25)
    values = prediction[anchors]
    boxes = np.column_stack((values[:, :2] - values[:, 2:4] / 2,
                             values[:, :2] + values[:, 2:4] / 2))
    order = np.lexsort((anchors, -values[:, 4]))
    keep = []
    while len(order) and len(keep) < 100:
        index = order[0]
        keep.append(index)
        order = order[1:]
        order = order[iou(boxes[index], boxes[order]) <= .45]
    return boxes[keep], values[keep, 4], values[keep, 5:].reshape(-1, 21, 3)


def int8(memory, registers, plan, rows, heads, image):
    packed = torch.round(tensor(image) * 127).to(torch.int8)
    memory.write(BASES["INPUT_BASE"], pack_c4(packed[0].permute(1, 2, 0).numpy()))
    execute(memory, registers)
    size = output_bytes(plan)
    output = memory.read(BASES["OUTPUT_BASE"], size)
    kept = integer_keep(decode_candidates(output, heads))
    lookup = {x["name"]: x for x in rows}
    raw_points = []
    for scale, stride in enumerate((8, 16, 32)):
        t = plan["tensors"][f"D{scale}.kpt"]
        raw = np.frombuffer(memory.read(t["base"], t["bytes"]), dtype=np.int8)
        raw = raw.reshape(4, t["height"], t["width"], 16).transpose(1, 2, 0, 3)
        raw = raw.reshape(-1, 64)[:, :63].astype(np.float64)
        quant = lookup[f"D{scale}.kpt.out"]
        points = ((raw - quant["output_zero_point"]) * quant["output_scale"]).reshape(-1, 21, 3)
        cells = np.indices((t["height"], t["width"])).reshape(2, -1).T[:, ::-1]
        points[:, :, :2] = (points[:, :, :2] * 2 + cells[:, None, :]) * stride
        points[:, :, 2] = 1 / (1 + np.exp(-points[:, :, 2]))
        raw_points.append(points)
    points = np.concatenate(raw_points)[[x[3] for x in kept]]
    boxes = np.asarray([x[0] for x in kept], dtype=float).reshape(-1, 4) / 256
    return boxes, np.asarray([x[1] / (1 << 24) for x in kept]), points


def distribution(values):
    if not len(values):
        return dict(mean=None, p95=None)
    return dict(mean=float(np.mean(values)), p95=float(np.percentile(values, 95)))


def pinch(points):
    return np.linalg.norm(points[4, :2] - points[8, :2]) / np.linalg.norm(
        points[0, :2] - points[9, :2])


def measure(boxes, points, result):
    predicted, scores, keypoints = result
    available = list(range(len(predicted)))
    matches = {}
    # Match by descending detection confidence, as in the pose evaluation.
    for i in np.argsort(-scores, kind="stable"):
        remaining = [j for j in range(len(boxes)) if j not in matches]
        if not remaining:
            break
        overlaps = iou(predicted[i], boxes[remaining])
        best = int(overlaps.argmax())
        if overlaps[best] >= .5:
            matches[remaining[best]] = int(i)
            available.remove(i)
    errors = {name: [] for name in GROUPS}
    relative = {name: [] for name in GROUPS}
    counts = dict(pinched=0, open=0)
    correct = dict(pinched=0, open=0)
    detected = dict(pinched=0, open=0)
    d_errors = []
    for j, truth in enumerate(points):
        d = pinch(truth)
        state = "pinched" if d < .25 else "open" if d > .6 else None
        if state:
            counts[state] += 1
        if j not in matches:
            continue
        prediction = keypoints[matches[j]]
        difference = np.linalg.norm(prediction[:, :2] - truth[:, :2], axis=1)
        size = max(boxes[j, 2:] - boxes[j, :2])
        for name, indices in GROUPS.items():
            visible = [i for i in indices if truth[i, 2] > 0]
            errors[name].extend(difference[visible].tolist())
            relative[name].extend((difference[visible] / size * 100).tolist())
        if state:
            predicted_d = pinch(prediction)
            detected[state] += 1
            correct[state] += int((predicted_d < .4) == (state == "pinched"))
            d_errors.append(float(abs(predicted_d - d)))
    return dict(hands=len(boxes), matched=len(matches), extra=len(available), errors=errors,
                relative=relative, pinch_counts=counts, pinch_detected=detected,
                pinch_correct=correct, d_errors=d_errors)


def oks_stats(boxes, points, result):
    _, scores, predicted = result
    area = (boxes[:, 2:] - boxes[:, :2]).prod(1) * .53
    oks = kpt_iou(torch.tensor(points), torch.tensor(predicted), torch.tensor(area),
                  sigma=np.ones(21) / 21)
    validator = SimpleNamespace(iouv=torch.linspace(.5, .95, 10))
    correct = BaseValidator.match_predictions(
        validator, torch.zeros(len(predicted)), torch.zeros(len(points)), oks).numpy()
    return dict(tp=correct.tolist(), scores=scores.tolist(), targets=len(points))


def aggregate(rows, ap_rows):
    total = sum(r["hands"] for r in rows)
    matched = sum(r["matched"] for r in rows)
    summary = dict(hands=total, matched=matched, detection_rate=matched / total,
                   extra=sum(r["extra"] for r in rows))
    summary["points"] = {name: dict(
        pixels=distribution([v for r in rows for v in r["errors"][name]]),
        percent=distribution([v for r in rows for v in r["relative"][name]])) for name in GROUPS}
    summary["pinch"] = {}
    for state in ("pinched", "open"):
        count = sum(r["pinch_counts"][state] for r in rows)
        correct = sum(r["pinch_correct"][state] for r in rows)
        summary["pinch"][state] = dict(samples=count, correct=correct,
            detected=sum(r["pinch_detected"][state] for r in rows),
            accuracy=correct / count if count else None)
    summary["pinch"]["d_error"] = distribution([v for r in rows for v in r["d_errors"]])
    if ap_rows:
        tp = np.concatenate([np.array(r["tp"], dtype=bool).reshape(-1, 10) for r in ap_rows])
        scores = np.concatenate([r["scores"] for r in ap_rows])
        ap = ap_per_class(tp, scores, np.zeros(len(scores)),
                          np.zeros(sum(r["targets"] for r in ap_rows)))[5]
        summary["oks"] = dict(map50_95=float(ap.mean()), map50=float(ap[:, 0].mean()))
    return summary


def illustrate(image, truth, result, size, destination):
    panels = []
    for title, points in (("Ground truth", truth), ("INT8", result[2])):
        panel = image.copy()
        for hand in points:
            coords = np.rint(hand[:, :2]).astype(int)
            for a, b in SKELETON:
                cv2.line(panel, tuple(coords[a]), tuple(coords[b]), (30, 230, 50), 1)
            for xy in coords:
                cv2.circle(panel, tuple(xy), 2, (30, 50, 255), -1)
        cv2.rectangle(panel, (0, 0), (640, 24), (0, 0, 0), -1)
        cv2.putText(panel, f"{title} / S={size}", (8, 17),
                    cv2.FONT_HERSHEY_SIMPLEX, .5, (255, 255, 255), 1)
        panels.append(panel)
    rgb = cv2.cvtColor(np.concatenate(panels, axis=1), cv2.COLOR_BGR2RGB)
    Image.fromarray(rgb).quantize(colors=96).save(destination, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("build/npu/hand_eval"))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    started = perf_counter()
    torch.set_num_threads(1)
    rows, skipped = selected("val", 300)
    plan = build_plan("hand")
    model, quant = load_quantized(plan)
    memory = Memory()
    memory.write(BASES["MODEL_BASE"], model)
    desc = descriptors(plan, quant)
    memory.write(BASES["DESC_BASE"], b"".join(d.encode() for d in desc))
    registers = BASES | {"DESC_COUNT": len(desc)}
    heads = make_heads({"convolutions": quant})
    network = YOLO(str(WEIGHTS)).model.eval().fuse(verbose=False)
    rng = np.random.default_rng(0)
    backgrounds = sorted((DATA / "val2017").glob("*.jpg"))
    names = ("fp32_384", "int8_384", "fp32_640")
    groups = ("A",) + tuple(f"B{s}" for s in (45, 60, 90, 120, 180))
    raw = {g: {n: [] for n in (names if g == "A" else names[:2])} for g in groups}
    ap = {n: [] for n in names}
    predictions = []
    assets = Path("docs/reports/assets")
    assets.mkdir(parents=True, exist_ok=True)
    for index, row in enumerate(rows):
        source = cv2.imread(str(row["path"]))
        for group in groups:
            size = int(group[1:]) if group != "A" else None
            image, boxes, points = (composite(row, size, rng, backgrounds) if size else
                                     letterbox(source, row["boxes"], row["points"]))
            results = dict(fp32_384=fp32(network, image),
                           int8_384=int8(memory, registers, plan, quant, heads, image))
            if group == "A":
                square, _, _ = letterbox(
                    source, row["boxes"], row["points"], 640)
                result = fp32(network, square)
                # All pixel metrics, including the square reference, use 640x384 coordinates.
                ratio384 = min(640 / source.shape[1], 384 / source.shape[0])
                ratio640 = min(640 / source.shape[1], 640 / source.shape[0])
                pad384 = np.array([(640 - round(source.shape[1] * ratio384)) // 2,
                                    (384 - round(source.shape[0] * ratio384)) // 2])
                pad640 = np.array([(640 - round(source.shape[1] * ratio640)) // 2,
                                    (640 - round(source.shape[0] * ratio640)) // 2])
                b, scores, p = result
                b = (b - np.tile(pad640, 2)) * ratio384 / ratio640 + np.tile(pad384, 2)
                p[:, :, :2] = (p[:, :, :2] - pad640) * ratio384 / ratio640 + pad384
                results["fp32_640"] = b, scores, p
            for name, result in results.items():
                raw[group][name].append(dict(
                    file=row["path"].name, **measure(boxes, points, result)))
                if group == "A":
                    ap[name].append(oks_stats(boxes, points, result))
                predictions.append(dict(file=row["path"].name, group=group, path=name,
                    truth_boxes=boxes.tolist(), truth_points=points.tolist(),
                    boxes=result[0].tolist(), scores=result[1].tolist(), points=result[2].tolist()))
            if index == 0 and size in SIZES:
                illustrate(image, points, results["int8_384"], size,
                           assets / f"hand-eval-{size}.png")
        if (index + 1) % 25 == 0:
            print(f"{index + 1}/{len(rows)} elapsed={perf_counter() - started:.1f}s", flush=True)
    metrics = {g: {n: aggregate(v, ap[n] if g == "A" else [])
                   for n, v in paths.items()} for g, paths in raw.items()}
    sizes = {}
    for task in ("detect", "pose", "hand"):
        p = build_plan(task)
        _, q = load_quantized(p)
        sizes[task] = resources(p, q)
    ratio = sizes["hand"]["mac_cycles"] / sizes["detect"]["mac_cycles"]
    summary = dict(commit=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        images=len(rows), skipped=skipped, metrics=metrics, resources=sizes, cycle_ratio=ratio,
        estimated_ms_180=35 * ratio, estimated_ms_150=41.2 * ratio,
        elapsed_s=perf_counter() - started)
    for filename, value in (("predictions", predictions), ("measurements", raw),
                             ("oks", ap), ("summary", summary)):
        (args.out / f"{filename}.json").write_text(json.dumps(value, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
