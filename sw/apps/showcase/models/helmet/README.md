# helmet model snapshot

Compiler/evaluation commit `88b390c9` (integrated in `94fc1cdb`), 2026-11-16.
Weights/data and calibration: `tools/npu/README.md`, four demonstration models.

```sh
PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 \
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py --task detect --weights tasks/win/20261115-83-hagrid-train/artifacts/extra/helmet/best.pt \
  --image <evaluation-image> --out build/npu/models_eval/helmet/compiled
cp build/npu/models_eval/helmet/compiled/{mem_model.hex,mem_desc.hex,regs.txt} sw/apps/showcase/models/helmet/
cp build/npu/quantized_helmet/quantization.json sw/apps/showcase/models/helmet/
```

Descriptors and weights are immutable compiler output; embedding requires only
standard-library Python. C80 padding supports hardware postprocessing.
