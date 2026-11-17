#!/usr/bin/env python3
"""T-DRAW-FIX3: real HDMI sequence, manual pen-up annotation and jump regression.

Frames 0..239 of card 98; INT8 model outputs, not synthetic hand positions.
Host clock follows the recording's timestamps.
"""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/demo/draw-replay"))
from replay import events, latency, run

frames = json.loads((Path(__file__).parent / "draw-real.json").read_text())
rows = run(Path(sys.argv[1]).resolve(), frames)
result = events(rows)
paint = events([r | dict(x=r["out_x"], y=r["out_y"], pen=1)
                for r in rows if r["emitted"]])
# Manual video annotation: the user opens the hand at 5.7 s and points again
# around 7.0 s. This is the only intended pen-up in this 8 s clip.
unintended = [f for f in result["breaks"] if not 171 <= f <= 209]
assert not result["jumps"], result
assert not paint["jumps"], paint
assert not unintended, result
assert len(result["breaks"]) == 1, result
assert not result["pauses"], result
for row in rows:
    if 41 <= row["f"] <= 170 or 219 <= row["f"] <= 239:
        assert row["pen"], row
assert rows[-1]["strokes"] == 2, rows[-1]
delay = latency(frames, rows)
assert delay["draw_lag_ms"] <= 60, delay
print(f"PASS draw real: {len(rows)} frames, V=0 (cursor and stamps), "
      f"unintended breaks=0, intended={result['breaks']}, strokes=2, {delay}")
