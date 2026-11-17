#!/usr/bin/env python3
"""Replay recorded INT8 detections through the compiled board draw.c.

Writes each original detection plus the C rule result, and event intervals.
Host clock: milliseconds from video; no inference in this stage.
"""
import argparse
import bisect
import csv
import io
import json
import math
from pathlib import Path
import subprocess


def run(executable, frames):
    lines = []
    for frame in frames:
        hands = frame["hands"]
        lines.append(f'{frame["f"]} {frame["ms"]} {len(hands)}')
        for hand in hands:
            lines.append(" ".join(map(str, hand["box"] + [hand["cls"]])))
            lines.append(" ".join(str(v) for p in hand["points"] for v in p[:2]))
    result = subprocess.run([str(executable)], input="\n".join(lines) + "\n",
                            text=True, capture_output=True, check=True)
    return [{k: v if k == "why" else float(v) if k in ("x", "y") else int(v)
             for k, v in row.items()}
            for row in csv.DictReader(io.StringIO(result.stdout))]


def events(rows):
    # A V is a >60 px perpendicular excursion from the before/after chord,
    # returning within 300 ms. Adjacent detections belong to one excursion.
    candidates = []
    for i in range(1, len(rows)-1):
        b = rows[i]
        if not b["pen"]:
            continue
        found = False
        for left in range(i-1, -1, -1):
            a = rows[left]
            if b["ms"] - a["ms"] > 300 or not a["pen"]:
                break
            for right in range(i+1, len(rows)):
                c = rows[right]
                if c["ms"] - a["ms"] > 300 or not c["pen"]:
                    break
                dx, dy = c["x"]-a["x"], c["y"]-a["y"]
                length = math.hypot(dx, dy)
                if length:
                    distance = abs(dx*(b["y"]-a["y"])-dy*(b["x"]-a["x"]))/length
                else:
                    distance = math.hypot(b["x"]-a["x"], b["y"]-a["y"])
                # The recorded failure is a downward-and-back V during a
                # horizontal sweep. Require return to the original height.
                if distance > 60 and abs(c["y"]-a["y"]) <= 60 and \
                        (b["y"]-a["y"])*(b["y"]-c["y"]) > 0:
                    candidates.append(b["f"])
                    found = True
                    break
            if found:
                break
    jumps = []
    for f in candidates:
        if not jumps or f-jumps[-1][-1] > 9:
            jumps.append([f])
        else:
            jumps[-1].append(f)
    breaks = [b["f"] for a, b in zip(rows, rows[1:]) if a["pen"] and not b["pen"]]
    pauses = [b["f"] for a, b in zip(rows, rows[1:]) if not a["pause"] and b["pause"]]
    return dict(jumps=[[g[0], g[-1]] for g in jumps], breaks=breaks, pauses=pauses)


def latency(frames, rows):
    """Best time shift of actual emitted endpoints against tips in the clean sweep.

    f60..119 precedes the collapsed landmarks. This measures draw processing,
    excluding camera/NPU/display time already present in the recorded video.
    """
    times = [frame["ms"] for frame in frames]
    scores = []
    for lag in range(201):
        squared = []
        for frame, row in zip(frames, rows):
            if not 60 <= frame["f"] < 120:
                continue
            t = frame["ms"]-lag
            i = bisect.bisect_right(times, t)-1
            weight = (t-times[i])/(times[i+1]-times[i])
            a = frames[i]["hands"][0]["points"][8]
            b = frames[i+1]["hands"][0]["points"][8]
            squared.append(sum((row[key] - (a[axis]*(1-weight)+b[axis]*weight))**2
                               for axis, key in enumerate(("out_x", "out_y"))))
        scores.append((math.sqrt(sum(squared)/len(squared)), lag))
    rmse, lag = min(scores)
    return dict(draw_lag_ms=lag, fit_rmse_px=round(rmse, 3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    frames = [json.loads(line) for line in args.input.read_text().splitlines()]
    rows = run(args.executable.resolve(), frames)
    with args.output.open("w") as output:
        for frame, row in zip(frames, rows):
            output.write(json.dumps(frame | dict(draw=row), separators=(",", ":")) + "\n")
    print(json.dumps(events(rows) | latency(frames, rows), indent=2))


if __name__ == "__main__":
    main()
