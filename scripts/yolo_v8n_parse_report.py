"""Summarize YOLOv8n board UART profiling and Detection META lines.

Accepts a Serial Console 2 saved log. Per-command read waits can overlap MAC
beats, so the columns describe activity and cannot be summed as time slices.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / "out/board/yolo_v8n_fixed_plan.json"
CLOCK_HZ = 150_000_000
STATUS = re.compile(r"YV8 (PASS|FAIL) STEP=([0-9A-F]{2}) CYC=([0-9A-F]{8})")
CORE = re.compile(r"YCORE CYC=([0-9A-F]{8})")
POST = re.compile(r"YPOST CYC=([0-9A-F]{8}) CAND=([0-9A-F]{4}) DET=([0-9A-F]{2})")
PHASE = re.compile(
    r"YPH LD=([0-9A-F]{8}) CL=([0-9A-F]{8}) DF=([0-9A-F]{8}) "
    r"NM=([0-9A-F]{8}) WR=([0-9A-F]{8})"
)
POST_IO = re.compile(
    r"YPIO RB=([0-9A-F]{8}) WB=([0-9A-F]{8}) AR=([0-9A-F]{8}) "
    r"RW=([0-9A-F]{8}) AW=([0-9A-F]{8}) WW=([0-9A-F]{8}) "
    r"BW=([0-9A-F]{8})"
)
STEP = re.compile(
    r"YS ([0-9A-F]{2}) CY=([0-9A-F]{8}) MC=([0-9A-F]{8}) "
    r"RB=([0-9A-F]{8}) WB=([0-9A-F]{8}) AR=([0-9A-F]{8}) "
    r"RW=([0-9A-F]{8}) AW=([0-9A-F]{8}) WW=([0-9A-F]{8}) "
    r"BW=([0-9A-F]{8})"
)
DETECTION = re.compile(
    r"YDET ([0-9A-F]{2}) CL=([0-9A-F]{2}) SC=([0-9A-F]{4}) "
    r"X1=([0-9A-F]{8}) Y1=([0-9A-F]{8}) "
    r"X2=([0-9A-F]{8}) Y2=([0-9A-F]{8})"
)


def parse(log: Path, geometry: Path | None) -> dict:
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    transform = json.loads(geometry.read_text(encoding="utf-8")) if geometry else None
    status = core = post = phases = post_io = None
    steps: dict[int, dict] = {}
    detections: dict[int, dict] = {}
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if match := STATUS.search(line):
            status = {"result": match[1], "last_step": int(match[2], 16),
                      "cycles": int(match[3], 16)}
        if match := CORE.search(line):
            core = {"cycles": int(match[1], 16)}
        if match := POST.search(line):
            post = {"cycles": int(match[1], 16),
                    "candidates": int(match[2], 16),
                    "detections": int(match[3], 16)}
        if match := PHASE.search(line):
            phases = dict(zip(
                ("load", "class_scan", "dfl_decode", "nms", "meta_write"),
                (int(value, 16) for value in match.groups()), strict=True))
        if match := POST_IO.search(line):
            post_io = dict(zip(
                ("read_beats", "write_beats", "ar_stall", "read_wait",
                 "aw_stall", "write_stall", "response_wait"),
                (int(value, 16) for value in match.groups()), strict=True))
        if match := STEP.search(line):
            index = int(match[1], 16)
            if index >= len(plan["commands"]):
                raise ValueError(f"unknown command index {index}")
            values = [int(value, 16) for value in match.groups()[1:]]
            steps[index] = {
                "index": index,
                "name": plan["commands"][index]["name"],
                "kind": plan["commands"][index]["kind"],
                **dict(zip(("cycles", "mac_beats", "read_beats",
                            "write_beats", "ar_stall", "read_wait",
                            "aw_stall", "write_stall", "response_wait"),
                           values, strict=True)),
            }
        if match := DETECTION.search(line):
            index, cls, score, x1, y1, x2, y2 = (
                int(value, 16) for value in match.groups())
            box = [value / 256.0 for value in (x1, y1, x2, y2)]
            item = {"index": index, "class": cls,
                    "confidence": score / 32768.0,
                    "box_model_xyxy": box}
            if transform:
                left, top = transform["pad_left"], transform["pad_top"]
                sx, sy = transform["scale_x"], transform["scale_y"]
                width, height = (transform["original_width"],
                                 transform["original_height"])
                item["box_source_xyxy"] = [
                    max(0.0, min(width, (box[0] - left) / sx)),
                    max(0.0, min(height, (box[1] - top) / sy)),
                    max(0.0, min(width, (box[2] - left) / sx)),
                    max(0.0, min(height, (box[3] - top) / sy)),
                ]
            detections[index] = item
    if status is None:
        raise ValueError("log has no YV8 status line")
    total_mac = sum(row["mac_beats"] for row in steps.values())
    result = {
        "log": str(log.resolve()),
        "clock_hz": CLOCK_HZ,
        "status": status,
        "core": core,
        "post": post,
        "post_phases": phases,
        "post_axi": post_io,
        "total_ms": status["cycles"] * 1000.0 / CLOCK_HZ,
        "core_ms": core["cycles"] * 1000.0 / CLOCK_HZ if core else None,
        "post_ms": post["cycles"] * 1000.0 / CLOCK_HZ if post else None,
        "mac_active_fraction": (total_mac / core["cycles"]
                                if core and core["cycles"] else None),
        "profiled_commands": len(steps),
        "steps": [steps[index] for index in sorted(steps)],
        "detections": [detections[index] for index in sorted(detections)],
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--geometry", type=Path,
                        help="input packer JSON for original-image coordinates")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = parse(args.log, args.geometry)
    print(f"{result['status']['result']}  total={result['total_ms']:.3f} ms "
          f"core={result['core_ms']} ms post={result['post_ms']} ms")
    print(f"commands={result['profiled_commands']} "
          f"MAC-active={result['mac_active_fraction']}")
    if result["post_phases"]:
        print("post phases (ms):", {
            key: round(value * 1000 / CLOCK_HZ, 3)
            for key, value in result["post_phases"].items()})
    if result["post_axi"]:
        print("post AXI:", result["post_axi"])
    for row in sorted(result["steps"], key=lambda item: item["cycles"],
                      reverse=True)[:10]:
        print(f"{row['index']:02d} {row['name']:<22} "
              f"{row['cycles'] * 1000 / CLOCK_HZ:8.3f} ms "
              f"MAC={row['mac_beats']:8d} RB={row['read_beats']:7d} "
              f"RW={row['read_wait']:7d}")
    for item in result["detections"]:
        print(f"det {item['index']:02d} class={item['class']} "
              f"score={item['confidence']:.4f} "
              f"model_box={item['box_model_xyxy']}")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n",
                               encoding="utf-8")
        print(f"report: {args.output.resolve()}")


if __name__ == "__main__":
    main()
