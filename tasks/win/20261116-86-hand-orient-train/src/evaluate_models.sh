#!/bin/bash
# Card 86: compare the final checkpoint and card 83 on the approved validation data.
set -e
export PYTHONPATH=/root/edrv32/repo/third_party/ultralytics
task_root=/root/edrv32/hand-orient
python_exec=/root/edrv32/venv/bin/python
old_weights=/root/edrv32/runs/hagrid-v8n-r2/weights/best.pt
new_weights=/root/edrv32/runs/hand-orient-v8n/weights/best.pt
"$python_exec" "$task_root/hand_orient_eval.py" "$old_weights" \
    "$task_root/freihand_raw_yolo" freihand "$task_root/eval/old_freihand_final.json"
"$python_exec" "$task_root/hand_orient_eval.py" "$new_weights" \
    "$task_root/freihand_raw_yolo" freihand "$task_root/eval/new_freihand.json"
"$python_exec" "$task_root/hand_orient_eval.py" "$new_weights" \
    /root/edrv32/hagrid/yolo hagrid "$task_root/eval/new_hagrid.json"
"$python_exec" "$task_root/ultralytics_eval.py" "$new_weights" \
    new-map "$task_root/eval/new_map.json"
