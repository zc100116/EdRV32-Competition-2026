# 卡 80：在 Windows（RTX 3070 Ti）上训练手部 21 关键点模型 yolov8n-hand-pose

## 1. 目标

从 `yolov8n-pose.pt` 出发，用 Ultralytics 的手部关键点数据集（21 个点/手）微调出一个 YOLOv8n 手部关键点模型。训练结果交回 Linux 端，按人体姿态的流程做 INT8 编译和离线评估，判断能否在 NPU 上识别手指级的手势。

背景：
- 决赛演示方向是用手势操控自研游戏（`docs/design/2026-11-14-finals-demo-pose-game.md`）。人体 17 点姿态已完成离线评估，上板测试是卡 79。
- 手部模型必须保持 **YOLOv8n-pose 的结构**，只把关键点改成 21×3。这样 NPU（只支持标准 1×1/3×3 卷积，输入固定 640×384）和现有编译工具都能直接用。不要换成 YOLO11、YOLO26 或其他结构。
- 数据集：Ultralytics `hand-keypoints`，训练集 18,776 张、验证集 7,992 张，下载约 369 MB，配置在 `third_party/ultralytics/ultralytics/cfg/datasets/hand-keypoints.yaml`。
- Linux 端用 torch 2.14.1 和 ultralytics 8.4.160（子模块 `9d25f80d`）加载模型。为保证权重文件能在 Linux 上加载，训练必须使用**同样的 torch 版本（2.14.1，CUDA 版）和同一个 ultralytics 子模块**。

可以和卡 75 的 PnR、卡 79 的上板同时进行。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261115-80-hand-pose-train`，记录 HEAD |
| ultralytics | 仓库子模块 `third_party/ultralytics`（`9d25f80d`，8.4.160），通过 `PYTHONPATH` 使用，不要 `pip install ultralytics` |
| 初始权重 | `https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n-pose.pt`（与 Linux 端评估用的是同一文件） |
| 数据集 | 训练时由 ultralytics 按 `hand-keypoints.yaml` 自动下载 |
| 工作目录 | 仓库外，例如 `G:/codex_project/edrv32-train/`：虚拟环境、权重、数据集和 `runs/` 都放在这里，不放进仓库 |

## 3. 环境

Windows，NVIDIA RTX 3070 Ti（8 GB），Python 3.12。

## 4. 需要的 IP

无。

## 5. 操作步骤

全部由 Windows Codex（C）执行。命令以 PowerShell 为例，`$REPO` 为仓库路径，`$W` 为 `G:/codex_project/edrv32-train`。

| 步骤 | 内容 |
|---|---|
| 0 | `git fetch origin`，`git switch -c win/20261115-80-hand-pose-train origin/zc100116/b3`，记录 HEAD。`git submodule update --init third_party/ultralytics`，确认子模块为 `9d25f80d`。 |
| 1 | 执行 `nvidia-smi`，记录驱动版本、CUDA 版本、显卡型号和显存。 |
| 2 | 在 `$W/venv` 建立虚拟环境：<br>- 先从 PyTorch 官方索引安装与驱动匹配的 CUDA 版 `torch==2.14.1` 和 `torchvision==0.29.1`，记录使用的 index URL；<br>- 再执行 `pip install -r $REPO/tools/requirements.txt`。<br>**如果 2.14.1 没有可用的 CUDA 版本，停下回报，不要换其他版本。** |
| 3 | 设置 `$env:PYTHONPATH="$REPO/third_party/ultralytics"`，执行 `python -c "import torch, ultralytics; print(torch.__version__, torch.cuda.is_available(), ultralytics.__version__)"`，应输出 `2.14.1+cu…  True  8.4.160`。 |
| 4 | 把 `yolov8n-pose.pt` 下载到 `$W`。 |
| 5 | 在 `$W` 目录下训练，参数只设下面这些，其余保持默认，不调参：<br>`python -c "from ultralytics import YOLO; YOLO('yolov8n-pose.pt').train(data='hand-keypoints.yaml', epochs=100, imgsz=640, batch=32, workers=4, seed=0, deterministic=True, project='$W/runs', name='hand-v8n')"`<br>- batch 32 显存不足时改为 16，并在 result.md 中记录；<br>- 记录数据集下载到的路径、开始和结束时间、每轮耗时。 |
| 6 | 训练结束后，对 `best.pt` 再做一次验证：`YOLO('$W/runs/hand-v8n/weights/best.pt').val(data='hand-keypoints.yaml', imgsz=640, batch=32)`，记录 Pose 和 Box 的 mAP50-95、mAP50。 |
| 7 | 用 `best.pt` 对 4 张验证集图片做预测，各存一张带关键点的结果图（PNG）。挑选时覆盖张开手掌、握拳、单指，以及手较小（离镜头较远）的情况。 |
| 8 | 整理产物，填写 result.md，提交 `result.md` 和 `artifacts/`，推送 `win/20261115-80-hand-pose-train`。 |

## 6. 产物

放在 `tasks/win/20261115-80-hand-pose-train/artifacts/`：
- `best.pt`：约 6–7 MB。Linux 端编译和评估要用这个文件，所以需要入库；
- `results.csv`、`args.yaml`、`results.png`：训练曲线和完整参数；
- `val.txt`：第 6 步验证输出的原文；
- `predict/`：第 7 步的 4 张结果图；
- `env.txt`：`nvidia-smi`、`pip freeze` 和第 3 步的输出。

不提交 `last.pt`、数据集和 `runs/` 中的其他文件。

## 7. 通过判据

- 100 轮训练完成，并生成 `best.pt`；
- 第 3 步的版本与要求一致；
- result.md 中的数字都取自 `results.csv` 或验证输出原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 80 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD / ultralytics 子模块 | |
| GPU / 驱动 / CUDA | |
| torch / ultralytics 版本 | |
| PyTorch 索引 URL | |
| batch / workers | |
| 数据集路径 | |
| 训练起止时间 / 总耗时 / 平均每轮 | |

## 精度（best.pt，imgsz 640，验证集 7,992 张）
| 指标 | 值 |
|---|---|
| Pose mAP50-95 | |
| Pose mAP50 | |
| Box mAP50-95 | |
| Box mAP50 | |
| best 所在轮次 | |

## 问题与偏离
```
