# YOLOv8n-pose snapshot

Generated at `3a9a36a72994dfa5d6096abd2607275e09a484ab` (compiler/evaluation code
`8cbabba6d10cdad45d79ff39a48872e816705575`), with the fixed COCO128 calibration:

```sh
PYTHONPATH=third_party/ultralytics OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py --task pose \
  --image ~/.local/share/edrv32/npu/val2017/000000000139.jpg --out build/npu/pose_board/compiled
```

`mem_model.hex` comes from that output; `quantization.json` comes from
`build/npu/quantized_pose/`. Rebuilding descriptors, postprocessing tables and ELF
from these two files uses standard-library Python and does not require torch.
