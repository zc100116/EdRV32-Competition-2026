#!/usr/bin/env python3
"""pose_eval.py — npu-spec 2.6: fixed YOLOv8n-pose offline evaluation.

Compare descriptor INT8 inference with Ultralytics FP32 using COCO OKS.
Clock domain: offline host; downloaded data stays outside the repository.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
from time import perf_counter
import urllib.request

import cv2
import numpy as np
from PIL import Image
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval
import torch
from ultralytics import YOLO

from fixed_plan import build_plan, descriptors
from format import BASES, pack_c4
from quantize import DATA, load_quantized, prepare_image
from ref.npu_ref import Memory, execute
from yolo_post_ref import decode_candidates, integer_sort, make_heads, STAT_KEYS, suppresses

ANNOTATIONS = DATA / "annotations/person_keypoints_val2017.json"
IMAGES = DATA / "val2017"
UPPER = [0, 5, 6, 7, 8, 9, 10]
SKELETON = [(0, 5), (0, 6), (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),
            (5, 11), (6, 12), (11, 12), (11, 13), (13, 15), (12, 14), (14, 16)]


def selected_images():
    data = json.loads(ANNOTATIONS.read_text())
    people = {a["image_id"] for a in data["annotations"]}
    return sorted((x for x in data["images"] if x["id"] in people),
                  key=lambda x: x["id"])[:300]


def download_images(images):
    IMAGES.mkdir(parents=True, exist_ok=True)

    def fetch(row):
        urllib.request.urlretrieve(
            "http://images.cocodataset.org/val2017/" + row["file_name"],
            IMAGES / row["file_name"])

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(fetch, images))
    print(f"downloaded {len(images)} person images to {IMAGES}")


def geometry(row, size):
    width, height = size
    ratio = min(width / row["width"], height / row["height"])
    padding = np.array([(width - round(row["width"] * ratio)) // 2,
                        (height - round(row["height"] * ratio)) // 2])
    return ratio, padding


def restore(boxes, points, row, size):
    ratio, padding = geometry(row, size)
    boxes = (boxes - np.tile(padding, 2)) / ratio
    boxes[:, [0, 2]] = boxes[:, [0, 2]].clip(0, row["width"])
    boxes[:, [1, 3]] = boxes[:, [1, 3]].clip(0, row["height"])
    points = points.copy()
    points[:, :, :2] = (points[:, :, :2] - padding) / ratio
    points[:, :, 0] = points[:, :, 0].clip(0, row["width"])
    points[:, :, 1] = points[:, :, 1].clip(0, row["height"])
    return boxes, points


def iou(box, others):
    intersection = np.maximum(0, np.minimum(box[2:], others[:, 2:]) -
                              np.maximum(box[:2], others[:, :2])).prod(axis=1)
    area = np.maximum(0, box[2:] - box[:2]).prod()
    areas = np.maximum(0, others[:, 2:] - others[:, :2]).prod(axis=1)
    return intersection / (area + areas - intersection)


def fp32(network, path, row, square=False):
    if square:
        image = cv2.imread(str(path))
        ratio, padding = geometry(row, (640, 640))
        image = cv2.resize(image, (round(row["width"] * ratio), round(row["height"] * ratio)))
        left, top = padding.tolist()
        image = cv2.copyMakeBorder(image, top, 640 - image.shape[0] - top,
                                  left, 640 - image.shape[1] - left,
                                  cv2.BORDER_CONSTANT, value=(114, 114, 114))
        tensor = torch.from_numpy(np.ascontiguousarray(image[:, :, ::-1].transpose(2, 0, 1)))
        tensor = tensor[None].float() / 255
    else:
        tensor = prepare_image(path)
    with torch.inference_mode():
        prediction = network(tensor)[0][0].T.cpu().numpy()
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
    points = values[keep, 5:].reshape(-1, 17, 3)
    boxes, points = restore(boxes[keep], points, row, (640, 640 if square else 384))
    return boxes, values[keep, 4], points


def integer_keep(candidates):
    stats = dict.fromkeys(STAT_KEYS, 0)
    integer_sort(candidates, stats)
    kept = []
    for candidate in candidates:
        if any(suppresses(previous[0], candidate[0]) for previous in kept):
            continue
        kept.append(candidate)
        if len(kept) == 100:
            break
    return kept


def int8(memory, registers, plan, rows, heads, path, row):
    tensor = torch.round(prepare_image(path) * 127).to(torch.int8)
    memory.write(BASES["INPUT_BASE"], pack_c4(tensor[0].permute(1, 2, 0).numpy()))
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
        raw = raw.reshape(-1, 64)[:, :51].astype(np.float64)
        quant = lookup[f"D{scale}.kpt.out"]
        points = ((raw - quant["output_zero_point"]) * quant["output_scale"]).reshape(-1, 17, 3)
        cells = np.indices((t["height"], t["width"])).reshape(2, -1).T[:, ::-1]
        points[:, :, :2] = (points[:, :, :2] * 2 + cells[:, None, :]) * stride
        points[:, :, 2] = 1 / (1 + np.exp(-points[:, :, 2]))
        raw_points.append(points)
    points = np.concatenate(raw_points)[[x[3] for x in kept]]
    boxes = np.asarray([x[0] for x in kept], dtype=float).reshape(-1, 4) / 256
    boxes, points = restore(boxes, points, row, (640, 384))
    return boxes, np.asarray([x[1] / (1 << 24) for x in kept]), points


def output_bytes(plan):
    return max(t["base"] + t["bytes"] - BASES["OUTPUT_BASE"]
               for name, t in plan["tensors"].items() if name.startswith("D"))


def records(result, image_id):
    boxes, scores, points = result
    return [dict(image_id=image_id, category_id=1, score=float(score),
                 bbox=[float(box[0]), float(box[1]),
                       float(box[2] - box[0]), float(box[3] - box[1])],
                 keypoints=keypoints.flatten().tolist())
            for box, score, keypoints in zip(boxes, scores, points)]


def compare(reference, integer, row):
    ref_boxes, _, ref_points = reference
    boxes, _, points = integer
    available = list(range(len(boxes)))
    errors = []
    invisible = visible = matched = 0
    for box, keypoints in zip(ref_boxes, ref_points):
        if not available:
            break
        overlaps = iou(box, boxes[available])
        best = int(overlaps.argmax())
        if overlaps[best] < .5:
            continue
        index = available.pop(best)
        matched += 1
        mask = keypoints[UPPER, 2] > .5
        difference = (points[index, UPPER, :2] - keypoints[UPPER, :2])
        difference *= np.array([1280 / row["width"], 720 / row["height"]])
        errors.extend(np.linalg.norm(difference[mask], axis=1).tolist())
        visible += int(mask.sum())
        invisible += int((mask & (points[index, UPPER, 2] <= .5)).sum())
    return dict(errors=errors, visible=visible, invisible=invisible, matched=matched,
                fp_people=len(ref_boxes), int8_people=len(boxes))


def illustrate(row, reference, integer, destination):
    original = cv2.imread(str(IMAGES / row["file_name"]))
    panels = []
    for title, result in (("FP32 640x384", reference), ("INT8 640x384", integer)):
        panel = cv2.resize(original, (400, 300))
        factor = np.array([400 / row["width"], 300 / row["height"]])
        for points in result[2]:
            coords = np.rint(points[:, :2] * factor).astype(int)
            for a, b in SKELETON:
                if min(points[a, 2], points[b, 2]) > .5:
                    cv2.line(panel, tuple(coords[a]), tuple(coords[b]), (50, 240, 60), 1)
            for coord, confidence in zip(coords, points[:, 2]):
                if confidence > .5:
                    cv2.circle(panel, tuple(coord), 2, (30, 70, 255), -1)
        cv2.rectangle(panel, (0, 0), (400, 23), (0, 0, 0), -1)
        cv2.putText(panel, title, (8, 16), cv2.FONT_HERSHEY_SIMPLEX, .5, (255, 255, 255), 1)
        panels.append(panel)
    rgb = cv2.cvtColor(np.concatenate(panels, axis=1), cv2.COLOR_BGR2RGB)
    Image.fromarray(rgb).quantize(colors=128).save(destination, optimize=True)


def resources(plan, rows):
    desc = descriptors(plan, rows)
    # Same MAC calendar formula as eval/npu_model.py: C32 blocks include half tails.
    cycles = sum(d.cout_blocks * d.out_h * (d.out_w // 2) * d.k_count
                 for d in desc if d.op == 0)
    return dict(model_bytes=plan["image_bytes"], work_bytes=plan["work_bytes"],
                output_bytes=output_bytes(plan), descriptors=len(desc), mac_cycles=cycles)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download-images", action="store_true")
    parser.add_argument("--out", type=Path, default=Path("build/npu/pose_eval"))
    args = parser.parse_args()
    images = selected_images()
    if args.download_images:
        download_images(images)
        return
    torch.set_num_threads(1)
    started = perf_counter()
    args.out.mkdir(parents=True, exist_ok=True)
    plan = build_plan("pose")
    model, rows = load_quantized(plan)
    memory = Memory()
    memory.write(BASES["MODEL_BASE"], model)
    encoded = descriptors(plan, rows)
    memory.write(BASES["DESC_BASE"], b"".join(d.encode() for d in encoded))
    registers = BASES | {"DESC_COUNT": len(encoded)}
    heads = make_heads({"convolutions": rows})
    network = YOLO(str(DATA / "yolov8n-pose.pt")).model.eval().fuse(verbose=False)
    predictions = {name: [] for name in ("fp32_384", "int8_384", "fp32_640")}
    comparisons = []
    asset_dir = Path("docs/reports/assets")
    asset_dir.mkdir(parents=True, exist_ok=True)
    for n, row in enumerate(images):
        path = IMAGES / row["file_name"]
        reference = fp32(network, path, row)
        integer = int8(memory, registers, plan, rows, heads, path, row)
        square = fp32(network, path, row, square=True)
        for name, result in zip(predictions, (reference, integer, square)):
            predictions[name].extend(records(result, row["id"]))
        comparisons.append(dict(image_id=row["id"], **compare(reference, integer, row)))
        if n < 4:
            illustrate(row, reference, integer, asset_dir / f"pose-eval-{row['id']:012d}.png")
        if (n + 1) % 25 == 0:
            print(f"{n + 1}/300 elapsed={perf_counter() - started:.1f}s", flush=True)
    metrics = {}
    coco = COCO(str(ANNOTATIONS))
    for name, results in predictions.items():
        (args.out / f"{name}.json").write_text(json.dumps(results) + "\n")
        prediction = coco.loadRes(results)
        metrics[name] = {}
        for kind in ("keypoints", "bbox"):
            evaluator = COCOeval(coco, prediction, kind)
            evaluator.params.imgIds = [x["id"] for x in images]
            evaluator.params.catIds = [1]
            evaluator.evaluate()
            evaluator.accumulate()
            evaluator.summarize()
            metrics[name][kind] = dict(map50_95=float(evaluator.stats[0]),
                                       map50=float(evaluator.stats[1]))
    errors = [e for c in comparisons for e in c["errors"]]
    visible = sum(c["visible"] for c in comparisons)
    invisible = sum(c["invisible"] for c in comparisons)
    _, detect_rows = load_quantized(build_plan())
    sizes = {"pose": resources(plan, rows), "detect": resources(build_plan(), detect_rows)}
    ratio = sizes["pose"]["mac_cycles"] / sizes["detect"]["mac_cycles"]
    summary = dict(commit=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                   images=len(images), image_ids=[x["id"] for x in images], metrics=metrics,
                   upper_body=dict(mean_pixels=float(np.mean(errors)),
                                   p95_pixels=float(np.percentile(errors, 95)),
                                   invisible_fraction=invisible / visible, visible_points=visible,
                                   invisible_points=invisible,
                                   matched_people=sum(c["matched"] for c in comparisons),
                                   fp_people=sum(c["fp_people"] for c in comparisons),
                                   int8_people=sum(c["int8_people"] for c in comparisons)),
                   resources=sizes, cycle_ratio=ratio, estimated_ms_180=35.0 * ratio,
                   estimated_ms_150=41.2 * ratio, elapsed_s=perf_counter() - started)
    (args.out / "comparisons.json").write_text(json.dumps(comparisons) + "\n")
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
