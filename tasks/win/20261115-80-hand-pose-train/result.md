# 卡 80 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | `369293262c96b4eedb42184b4ad857f8868a3ad4` |
| Ultralytics 子模块 | `9d25f80daa5b3af71c16521eba353cb6e7fb66e2` |
| GPU / 驱动 / 显存 | NVIDIA GeForce RTX 3070 Ti Laptop GPU, 610.74, 8192 MiB |
| CUDA / PyTorch / TorchVision / Ultralytics | 13.2 / 2.14.1+cu132 / 0.29.1+cu132 / 8.4.160 |
| PyTorch 索引 | [官方 CUDA 13.2](https://download.pytorch.org/whl/cu132/) |
| 训练 | 100 轮，imgsz 640，batch 32，workers 4，seed 0，deterministic True |
| 数据集路径 | `G:/codex_project/edrv32-train/datasets/hand-keypoints` |
| 训练起止 | 2026-11-15T10:47:29.7707542+08:00 至 2026-11-15T16:17:56+08:00（进程启动至最后一轮 CSV 写入） |
| 训练耗时 | 19790.6 s，平均 197.91 s/轮（按训练 CSV 累计时间） |

## best.pt 独立验证

以 imgsz 640、batch 32 在验证集重跑。Ultralytics 实际验证 7847 张图。指标下表单位为百分比。

| 指标 | 值 |
|---|---:|
| Pose mAP50–95 | 73.50 |
| Pose mAP50 | 88.01 |
| Box mAP50–95 | 89.31 |
| Box mAP50 | 99.17 |
| best 所在轮次 | 100 |

best 轮次取 `best.pt` 中的训练验证指标与 `results.csv` 中的对应行。模型为 YOLOv8n-pose，输出 21×3 手部关键点。

[best.pt](artifacts/best.pt) · [训练参数](artifacts/args.yaml) · [训练 CSV](artifacts/results.csv) · [逐轮耗时](artifacts/epoch-times.csv) · [训练曲线](artifacts/results.png) · [验证原文](artifacts/val.txt) · [环境](artifacts/env.txt)

## 验证集样例

| 样例 | 验证集原图 | 检出的手 |
|---|---|---:|
| [open-palm](artifacts/predict/open-palm.png) | IMG_00028696.jpg | 1 |
| [fist](artifacts/predict/fist.png) | IMG_00000827.jpg | 1 |
| [single-finger](artifacts/predict/single-finger.png) | IMG_00000338.jpg | 1 |
| [small-hand](artifacts/predict/small-hand.png) | IMG_00018121.jpg | 1 |

## 数据扫描

原始训练集 18,776 张、验证集 7,992 张。Ultralytics 默认数据扫描标记训练集 384 个、验证集 145 个图像或标注为损坏并跳过。完整训练日志保存在 `G:/codex_project/edrv32-train/train-batch32.stdout.log`。
