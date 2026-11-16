# 安全帽 v2 INT8 离线评估（2026-11-16）

- 基线/权重 commit `171fbd59`（卡 87）；编译/评估代码为本提交，v2 权重 `tasks/win/20261116-87-helmet-v2-train/artifacts/best.pt`。
- Linux CPU，Python 3.12.3、torch 2.14.1+cpu、numpy 2.5.2、OpenCV 5.0.0、Ultralytics 8.4.160；torch/BLAS 单线程。
- Hard Hat train 原抽样 96 张标定，percentile 95、margin 1.05；val 全 500 张，仅完整评估一次；640×384 letterbox/114，conf>0.25、同类 NMS IoU>0.45、最多 100 框。
- `compile_yolo.py` 按已登记权重 resolve 路径选择 doodle/helmet，避免 v2 的 `artifacts/` 父目录被误当数据集；不带权重的 detect 保持原流程。

```sh
export PYTHONPATH="$PWD/tools/npu:$PWD/third_party/ultralytics" OPENBLAS_NUM_THREADS=1
P="$HOME/.local/opt/edrv32-py/bin/python"
$P tools/npu/compile_yolo.py --task detect --weights tasks/win/20261116-87-helmet-v2-train/artifacts/best.pt --image ../task-helmet-data/build/helmet/yolo/images/val/hard_hat_workers0.png --out build/npu/models_eval/helmet/compiled
$P tools/npu/models_eval.py helmet --out build/npu/models_eval
$P tasks/win/20261116-87-helmet-v2-train/src/coco_int8.py
$P -m unittest discover -s tools/npu -p 'test_compile.py'
make -C sw -j2 PROGRAM=showcase
make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu
```

| Hard Hat / 版本 | FP32 mAP50 | INT8 mAP50 | FP32 mAP50-95 | INT8 mAP50-95 | FP32 AP50 helmet/head | INT8 AP50 helmet/head |
|---|---:|---:|---:|---:|---:|---:|
| v1 | 85.38% | 84.21% | 55.66% | 54.78% | — | — |
| v2 | 84.88% | 84.06% | 55.52% | 53.41% | 88.69% / 81.07% | 88.53% / 79.59% |

v1 数字引用 [原报告](2026-11-16-npu-models-int8-eval.md) `88b390c9`，其中未列 helmet/head 单类 AP50；未重跑 v1 全集。此处固定板端输入和阈值，与卡 87 的 640 方形 FP32 评估条件不同。

| COCO 40 图 / INT8 | conf>0.25 head | conf>0.25 helmet | conf>0.5 head | conf>0.5 helmet |
|---|---:|---:|---:|---:|
| v1 | 20 | 31 | 13 | 18 |
| v2 | 40 | 10 | 33 | 8 |

图片严格采用卡 87 `artifacts/coco-evaluation.json` 的同一列表（59 人）；v1 取 `171fbd59` 当前快照，保存在 `build/npu/helmet_v2/v1/`。两版均调用 `models_eval.integer()`（`npu_ref`、硬件整数后处理、排序/NMS），单次推理结果统计两档阈值；检出数不表示与人头真值一对一匹配。

| 资源 | v1 | v2 |
|---|---:|---:|
| 模型镜像 / OUTPUT / B | 3,115,264 / 725,760 | 3,115,264 / 725,760 |
| 描述符条数 | 68 | 68 |

结构相同，镜像、OUTPUT、描述符条数均相同；WORK 均 5,867,520 B。原始数据为 `build/npu/models_eval/helmet/{predictions,summary}.json`、`build/npu/helmet_v2/{compile,eval,coco,unittest,build-hw,build-cpu}.log`、`coco-int8.json`；脚本已移入 `tasks/win/20261116-87-helmet-v2-train/src/coco_int8.py`；评估耗时 396.10 s。

验证：unittest 单次 16/16 通过（386.55 s）；两次构建按上述顺序各运行一次、均通过且无警告；CPU ELF 为 `build/sw/showcase-cpupost/showcase.elf`（29,593,568 B）。`py_compile`、`git diff --check` 通过；Verilog 风格 0 文件/0 告警，未改 RTL，lint 不适用。
