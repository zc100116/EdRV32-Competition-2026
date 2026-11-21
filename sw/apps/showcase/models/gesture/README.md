# gesture model snapshot

Compiler/evaluation commit `88b390c9` (integrated in `94fc1cdb`), 2026-11-16.
Weights/data and calibration: `tools/npu/README.md`, four demonstration models.

```sh
PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 \
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py --task gesture \
  --image <evaluation-image> --out build/npu/models_eval/gesture/compiled
cp build/npu/models_eval/gesture/compiled/{mem_model.hex,mem_desc.hex,regs.txt} sw/apps/showcase/models/gesture/
cp build/npu/quantized_gesture/quantization.json sw/apps/showcase/models/gesture/
```

Descriptors and weights are immutable compiler output; embedding requires only
standard-library Python. C80 padding supports hardware postprocessing.
