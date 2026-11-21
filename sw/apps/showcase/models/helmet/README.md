# helmet model snapshot

Helmet v2 weights commit `171fbd59`, 2026-11-16.
Compiler/evaluation: this update on base `171fbd59`;
results: `docs/reports/2026-11-16-helmet-v2-int8-eval.md`.
Weights/data and calibration: `tools/npu/README.md`, four demonstration models.

```sh
PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 \
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py --task detect --weights tasks/win/20261116-87-helmet-v2-train/artifacts/best.pt \
  --image <evaluation-image> --out build/npu/models_eval/helmet/compiled
cp build/npu/models_eval/helmet/compiled/{mem_model.hex,mem_desc.hex,regs.txt} sw/apps/showcase/models/helmet/
cp build/npu/quantized_helmet/quantization.json sw/apps/showcase/models/helmet/
```

Descriptors and weights are immutable compiler output; embedding requires only
standard-library Python. C80 padding supports hardware postprocessing.
