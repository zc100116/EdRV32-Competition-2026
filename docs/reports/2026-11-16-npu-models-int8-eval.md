# 四个新模型 INT8 离线评估（2026-11-16）

- 代码 commit：`88b390c9a9371aa5f321542cbf4190ee9610e2a2`；字节基线 `0f009a21`；Linux / AMD EPYC 7742，Python 3.12.3、torch 2.14.1+cpu、numpy 2.5.2、OpenCV 5.0.0、Ultralytics 8.4.160。
- 配置：640×384 居中 letterbox/114；各自数据 96 图标定，percentile=95、margin=1.05、torch/BLAS 单线程；所有新抽样均对排序文件名用 `default_rng(0)` 无放回抽取。
- 数据：HaGRID 从服务器复制 600 图/600 标签/YAML 后不再访问服务器，扣除标定 96 图评估 504 图；简笔画本机 val 抽 600 图，安全帽 val 全 500 图。
- 人脸：[derronqi README](https://github.com/derronqi/yolov8-face) 的 yolov8n-face，锁定版本加载及标准卷积/头形状审计通过；[WIDER 官方 HF 镜像](https://huggingface.co/datasets/CUHK-CSE/wider_face)验证集 3226 图中抽 300 图评估、96 图标定（重叠 10 图），Range 仅下载并集 386 图/44,138,279 B；评估有效、正面积框。
- 流程：FP32 浮点头与 INT8 `npu_ref` 全描述符执行、硬件整数后处理参考、排序、同类 NMS、anchor 关键点解码；两者均 confidence>0.25、NMS IoU>0.45、最多 100 框，未训练、未调阈值。
- 命令：`export PYTHONPATH="$PWD/tools/npu:$PWD/third_party/ultralytics" OPENBLAS_NUM_THREADS=1`；`P=~/.local/opt/edrv32-py/bin/python`；`$P tools/npu/models_eval.py --out build/npu/models_eval > build/npu/models_eval/eval.log 2>&1`；下载及四项编译命令见 [README](../../tools/npu/README.md#四个演示模型t-npu-models)。
- 验证：`$P -m unittest discover -s tools/npu -p test_compile.py` 15/15 通过，实际重标定/导出 detect、pose、hand 与基线逐字节相同，四模型编译/OUTPUT/补类常量通过；首次测试因旧 hand 测试夹具相对路径失效报错，修正夹具后完整通过；完整模型评估仅一轮。py_compile、diff --check、Verilog 风格 0 文件/0 告警，未改 RTL，lint 不适用。

| 模型 / 图数 | FP32 mAP50 | INT8 mAP50 | FP32 mAP50-95 | INT8 mAP50-95 |
|---|---:|---:|---:|---:|
| 手势 / 504 | 98.69% | 98.11% | 84.20% | 82.32% |
| 简笔画 / 600 | 97.13% | 96.41% | 96.76% | 95.96% |
| 安全帽 / 500 | 85.38% | 84.21% | 55.66% | 54.78% |
| 人脸 / 300 | 42.84% | 41.34% | 23.91% | 20.82% |

关键点 INT8 对 FP32 平均/P95（1280×720）：手势 3.39/8.43 px（636 框/12479 点）；人脸 1.91/6.33 px（1702 框/7103 点）；按同类框 IoU≥0.5 配对，仅计 FP32 confidence>0.5 点，未配对框不计。

| 模型 | 镜像 / B | OUTPUT / B | 描述符 | MAC 周期 | 对 detect 周期比 | 估算 ms@180/150 MHz |
|---|---:|---:|---:|---:|---:|---:|
| 手势 | 3,505,408 | 1,048,320 | 77 | 6,045,120 | 1.054509 | 36.91/43.45 |
| 简笔画 | 3,115,264 | 725,760 | 68 | 5,158,080 | 0.899774 | 31.49/37.07 |
| 安全帽 | 3,115,264 | 725,760 | 68 | 5,158,080 | 0.899774 | 31.49/37.07 |
| 人脸 | 3,192,064 | 806,400 | 77 | 5,450,400 | 0.950766 | 33.28/39.17 |

所有 OUTPUT <1 MiB，手势余 256 B；类别补 C80 的权重为 0、偏置使输出恒 −128；关键点 C63→C64、C15→C16，WORK 均 5,867,520 B。周期沿用 [pose 报告](2026-11-15-pose-int8-eval.md) `Σ(C32块×高×像素对×K_COUNT)`，含半块/补齐计算，不含 DMA、控制、后处理；以 detect 5,732,640 周期及实测 35.0/41.2 ms 按比值估算，非新模型上板实测。原始结果：`build/npu/models_eval/<model>/{predictions,summary}.json`、`eval.log`、`compile.log`、`unittest.log`（首次失败 `unittest-fixture-error.log`）；镜像/量化 `build/npu/quantized_<model>/`，导出 `<model>/compiled/`；数据 `~/.local/share/edrv32/npu/{hagrid-val600,wider-face}/` 及相邻数据 worktree；总评估耗时 1374.88 s。

| ID | 手势类 AP50/% | FP32 | INT8 | 简笔画类 AP50/% | FP32 | INT8 |
|---:|---|---:|---:|---|---:|---:|
| 0 | palm | 99.50 | 99.50 | cat | 88.39 | 86.28 |
| 1 | fist | 95.50 | 95.50 | dog | 89.35 | 89.66 |
| 2 | peace | 99.50 | 96.50 | fish | 97.74 | 96.64 |
| 3 | point | 97.50 | 95.43 | bird | 92.60 | 92.65 |
| 4 | grabbing | 99.50 | 99.50 | rabbit | 97.15 | 95.64 |
| 5 | grip | 99.50 | 99.50 | butterfly | 99.50 | 98.50 |
| 6 | thumb_index | 99.50 | 99.50 | sun | 99.49 | 99.49 |
| 7 | ok | 99.50 | 99.50 | moon | 98.49 | 97.40 |
| 8 | like | 99.44 | 99.39 | star | 99.49 | 98.50 |
| 9 | dislike | 99.50 | 99.50 | cloud | 96.40 | 96.50 |
| 10 | three | 99.50 | 97.50 | lightning | 98.50 | 98.50 |
| 11 | four | 99.50 | 99.50 | rainbow | 98.50 | 97.50 |
| 12 | call | 99.50 | 99.50 | tree | 96.74 | 94.94 |
| 13 | no_gesture | 94.24 | 93.18 | flower | 95.50 | 95.50 |
| 14 | — | — | — | house | 99.50 | 99.44 |
| 15 | — | — | — | car | 99.41 | 98.47 |
| 16 | — | — | — | airplane | 99.46 | 99.06 |
| 17 | — | — | — | sailboat | 97.44 | 95.49 |
| 18 | — | — | — | apple | 99.50 | 99.50 |
| 19 | — | — | — | smiley face | 99.50 | 98.49 |

手势 INT8 混淆矩阵（行=真值，列=预测；BG=background；配对框 IoU≥0.5，末行误检、末列漏检）：
```csv
truth/pred,palm,fist,peace,point,grabbing,grip,thumb_index,ok,like,dislike,three,four,call,no_gesture,BG
palm,40,0,0,0,0,0,0,0,0,0,0,0,0,0,0
fist,0,39,0,0,0,0,0,0,0,0,0,0,0,0,2
peace,0,0,28,0,0,0,0,0,0,0,0,0,0,0,1
point,0,0,0,39,0,0,0,0,1,0,0,0,0,0,1
grabbing,0,0,0,0,33,0,0,0,0,0,0,0,0,0,0
grip,0,0,0,0,0,42,0,0,0,0,0,0,0,0,0
thumb_index,0,0,0,0,0,0,37,0,0,0,0,0,0,0,0
ok,0,0,0,0,0,0,0,29,0,0,0,0,0,0,0
like,0,0,0,0,0,0,0,0,34,0,0,0,0,0,0
dislike,0,0,0,0,0,0,0,0,0,49,0,0,0,0,0
three,0,0,0,0,0,0,0,0,0,0,38,1,0,0,0
four,0,0,0,0,0,0,0,0,0,0,0,37,0,0,0
call,0,0,0,0,0,0,0,0,0,0,0,0,41,0,0
no_gesture,0,0,0,0,0,0,0,0,1,0,0,0,0,128,5
BG,0,0,0,1,0,0,0,0,0,0,0,0,0,22,0
```
