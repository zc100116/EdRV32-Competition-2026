# face model snapshot

Compiler/evaluation commit `88b390c9` (integrated in `94fc1cdb`), 2026-11-16.
Weights/data and calibration: `tools/npu/README.md`, four demonstration models.

```sh
PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 \
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py --task face \
  --image <evaluation-image> --out build/npu/models_eval/face/compiled
cp build/npu/models_eval/face/compiled/{mem_model.hex,mem_desc.hex,regs.txt} sw/apps/showcase/models/face/
cp build/npu/quantized_face/quantization.json sw/apps/showcase/models/face/
```

Descriptors and weights are immutable compiler output; embedding requires only
standard-library Python. C80 padding supports hardware postprocessing.
