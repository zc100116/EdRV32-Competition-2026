# YOLOv8n hand snapshot

Generated at `e1bcb880` (2026-11-15) from card 80
`tasks/win/20261115-80-hand-pose-train/artifacts/best.pt`:

```sh
PYTHONPATH=third_party/ultralytics OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py --task hand \
  --image ~/.local/share/edrv32/npu/hand-keypoints/images/val/IMG_00000002.jpg \
  --out build/npu/hand_board/compiled
cp build/npu/hand_board/compiled/mem_model.hex sw/apps/showcase/models/yolov8n-hand/
cp build/npu/quantized_hand/quantization.json sw/apps/showcase/models/yolov8n-hand/
```

Calibration uses `hand_data.calibration_samples`: valid training images sorted by name,
`default_rng(0)` selects 96 without replacement, independently seeded composites cycle
45/60/90/180 NPU px over COCO val2017 backgrounds; percentile 95, margin 1.05.
The snapshot rebuild (`--task hand --model-source` plus `--hand-quantization` embedding)
uses standard-library Python only. Model 3,505,408 B; 77 descriptors; OUTPUT 1,048,320 B.
