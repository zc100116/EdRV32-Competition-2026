"""labels.py — shared firmware COCO label table, Task T-UI1-R; host only.

Read the same literal table used by both board overlay implementations.
"""
from pathlib import Path
import re

SOURCE = Path(__file__).resolve().parents[3] / 'sw/lib/draw.c'
ARRAY = SOURCE.read_text(encoding='utf-8').split('class_names[80] = {', 1)[1].split('};', 1)[0]
COCO_NAMES = tuple(re.findall(r'"([^"]+)"', ARRAY))
