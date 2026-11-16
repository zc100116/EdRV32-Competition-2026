#!/usr/bin/env python3
"""ultralytics_eval.py: card 86 step 8, HaGRID Box/Pose mAP50 and class values.
Clock domain: not applicable (GPU validation).
"""
import json
from pathlib import Path
import sys
from ultralytics import YOLO

model = YOLO(sys.argv[1])
metrics = model.val(data='/root/edrv32/hagrid/yolo/hagrid.yaml', imgsz=640, batch=128,
                    project='/root/edrv32/hand-orient/eval', name=sys.argv[2])
result = dict(box_map50=float(metrics.box.map50), pose_map50=float(metrics.pose.map50),
              per_class={})
for index, class_id in enumerate(metrics.box.ap_class_index):
    result['per_class'][model.names[int(class_id)]] = dict(
        box_map50=float(metrics.box.ap50[index]), pose_map50=float(metrics.pose.ap50[index]))
Path(sys.argv[3]).write_text(json.dumps(result, indent=2) + '\n')
print('METRICS_JSON', json.dumps(result), flush=True)
