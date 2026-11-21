#!/usr/bin/env python3
"""T-DRAW-FIX: measure 1 Hz UART samples and visible white-line spatial wiggle.

Usage: python3 sw/apps/showcase/sim/draw_measure.py build/draw-fix
Extract session.log / board.mp4 with git show from origin/win/20261117-96-r5-board.
Video wiggle is a spatial estimate, not unavailable raw per-frame keypoints.
"""
import collections
import math
import pathlib
import re
import subprocess
import sys

directory = pathlib.Path(sys.argv[1])
rows = []
for line in (directory / "session.log").read_text().splitlines():
    match = re.search(
        r"\[(15:1[01]:[0-5]\d\.\d+)\].*draw .*strokes=(\d+).*tool=(\w+) cls=(-?\d+)", line)
    if match and "15:10:53" <= match[1] <= "15:11:50":
        rows.append((match[1], int(match[2]), match[3], int(match[4])))
counts = collections.Counter(row[3] for row in rows)
print("UART 15:10:53..15:11:49:", len(rows), "samples; class counts", dict(counts))
print("point fraction:", counts[3], "/", len(rows), "=", 100*counts[3]/len(rows), "%")
runs = collections.Counter()
length = 0
for row in rows:
    if row[3] != 3:
        length += 1
    elif length:
        runs[length] += 1
        length = 0
if length:
    runs[length] += 1
print("non-point run lengths (1 Hz samples, includes intended lifts):", dict(sorted(runs.items())))
print("strokes:", rows[0][1], "->", rows[-1][1])
# Fixed ROI selects the visibly serrated white near-horizontal path at video t=10 s.
raw = subprocess.check_output([
    str(pathlib.Path.home() / ".local/opt/video/bin/ffmpeg"),
    "-v", "error", "-ss", "10", "-i", str(directory / "board.mp4"),
    "-vf", "scale=1280:720", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
centers = []
for x in range(490, 621):
    ys = []
    for y in range(240, 311):
        rgb = raw[(y*1280+x)*3:(y*1280+x)*3+3]
        if min(rgb) >= 225 and max(rgb)-min(rgb) <= 25:
            ys.append(y)
    assert ys, f"white-line ROI has no pixels at x={x}"
    centers.append(sum(ys)/len(ys))
residuals = []
for i in range(15, len(centers)-15):
    residuals.append(centers[i]-sum(centers[i-15:i+16])/31)
print("visible white centerline, ROI x490..620 y240..310, t=10 s:")
print("31 px moving-mean residual RMS %.3f px; peak-to-peak %.3f px" %
      (math.sqrt(sum(v*v for v in residuals)/len(residuals)), max(residuals)-min(residuals)))
print("This spatial wiggle includes intentional curvature; "
      "raw fingertip jitter is not identifiable.")
# Newly painted white pixels approximate the moving stroke endpoint at 25 Hz.
# Pixel quantization, the old alpha=.5 filter and deliberate motion remain in this proxy.
movie = subprocess.Popen([
    str(pathlib.Path.home() / ".local/opt/video/bin/ffmpeg"), "-v", "error",
    "-i", str(directory / "board.mp4"), "-t", "8",
    "-vf", "fps=25,scale=1280:720,crop=700:350:400:150",
    "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
seen = bytearray(700*350)
endpoints = []
for frame in range(200):
    raw = movie.stdout.read(700*350*3)
    assert len(raw) == 700*350*3, f"short video frame {frame}"
    xs = []
    ys = []
    for pixel in range(700*350):
        if seen[pixel]:
            continue
        r, g, b = raw[pixel*3:pixel*3+3]
        if min(r, g, b) >= 225 and max(r, g, b)-min(r, g, b) <= 25:
            seen[pixel] = 1
            xs.append(pixel%700)
            ys.append(pixel//700)
    if 12 <= len(xs) <= 300:
        endpoints.append((frame, sum(xs)/len(xs), sum(ys)/len(ys)))
assert movie.wait() == 0
differences = []
for a, b, c in zip(endpoints, endpoints[1:], endpoints[2:]):
    if b[0]-a[0] == c[0]-b[0] == 1:
        differences.append(((c[1]-2*b[1]+a[1])**2+(c[2]-2*b[2]+a[2])**2)/6)
assert differences, "no consecutive endpoint triples"
print("25 Hz white-endpoint proxy: %d observations, %d consecutive triples, "
      "second-difference/sqrt(6) radial RMS %.3f px" %
      (len(endpoints), len(differences), math.sqrt(sum(differences)/len(differences))))
