# 卡 83：在租用的 GPU 服务器上用 HaGRIDv2 训练手势 + 21 点手部模型

## 1. 目标

用 HaGRIDv2 数据集训练一个 YOLOv8n-pose 结构的手部模型，同时输出两样东西：
- 手势类别，共 10 类，见第 5 节的手势清单；
- 每只手 21 个关键点。

训练在用户租用的云服务器上进行，由 Windows Codex 通过 ssh 操作。

背景：
- 卡 82 实测，卡 80 的手部模型（Ultralytics hand-keypoints 数据集训练）效果差：
  - 剪刀手完全检测不到；
  - 握拳时关键点每帧乱跳；
  - 手背朝镜头时效果差。
- 原因是那个数据集几乎都是张开的手。
- HaGRIDv2 的情况：
  - 6.5 万多人，在 0.5–4 m 处对着摄像头拍摄，共 33 种手势；
  - 每只手有 MediaPipe 自动标注的关键点；
  - 许可证为 CC BY-SA 4.0。
  - 项目页：`https://github.com/hukenovs/hagrid`。
- 模型结构必须保持 **YOLOv8n-pose**，只改类别数和关键点数，不要换成 YOLO11、YOLO26 或其他结构。原因：NPU 只支持标准 1×1/3×3 卷积，输入固定 640×384；10 个类别远小于硬件后处理支持的 80 类。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261115-83-hagrid-train`，记录 HEAD |
| ultralytics | 仓库子模块 `third_party/ultralytics`（`9d25f80d`，8.4.160），从 Windows 本地仓库复制到服务器，通过 `PYTHONPATH` 使用，不要 `pip install ultralytics` |
| 初始权重 | 卡 80 的 `tasks/win/20261115-80-hand-pose-train/artifacts/best.pt`（仓库内） |
| 数据 | HaGRIDv2 512px 精简版：`https://rndml-team-cv.obs.ru-moscow-1.hc.sbercloud.ru/datasets/hagrid_v2/hagridv2_512.zip`（119.4 GB） |
| 标注 | `https://rndml-team-cv.obs.ru-moscow-1.hc.sbercloud.ru/datasets/hagrid_v2/annotations_with_landmarks/annotations.zip` |
| 服务器 | 用户租用：镜像"Miniconda 3.12 Ubuntu 20.04"，1×RTX 4090 48 GB、22 核、120 GB 内存，磁盘扩到 292 GB |

**保密**：服务器的 IP、端口、用户名、私钥和平台账号，一律**不写进仓库**，包括 result.md、日志和提交信息，只保存在 Windows 本地。

## 3. 环境

- Windows：OpenSSH 客户端（`ssh`、`scp`、`ssh-keygen`）。
- 服务器：Ubuntu 20.04，NVIDIA RTX 4090 48 GB。

## 4. 需要的 IP

无。

## 5. 手势清单（10 类，类别号按此顺序）

| 类别号 | HaGRID 类名 | 手势 | 演示中的用途 |
|---|---|---|---|
| 0 | `palm` | 张开手掌，五指分开 | 布；松开 |
| 1 | `fist` | 握拳 | 石头；抓住 |
| 2 | `peace` | 剪刀手（食指、中指伸出） | 剪刀 |
| 3 | `one` | 竖起食指 | 指点、光标 |
| 4 | `point` | 食指指向一侧 | 指点、光标 |
| 5 | `ok` | OK（拇指和食指成圈） | 捏合 |
| 6 | `grabbing` | 五指弯曲成爪 | 抓起 |
| 7 | `like` | 点赞 | 确认 |
| 8 | `stop` | 手掌立起，五指并拢 | 暂停 |
| 9 | `no_gesture` | 没有特定手势的手 | 保证画面中所有的手都能被检出 |

另有 3 个**候选**类：`thumb_index`、`thumb_index2`、`grip`。它们的具体手势需要看图才能确定，可能与捏合、抓取有关。第 7 步给用户看样例图，由用户决定是否加入。如果加入，类别号接在 9 之后。

## 6. 操作步骤

全部命令由 Windows Codex（C）执行，需要用户（U）操作的步骤另行标明。下文的 `$D` 指服务器上数据盘的工作目录，由第 3 步确定。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | `git fetch origin`，`git switch -c win/20261115-83-hagrid-train origin/zc100116/b3`，记录 HEAD。`git submodule update --init third_party/ultralytics`，确认子模块为 `9d25f80d`。 |
| 1 | C | **生成 SSH 密钥**：<br>- `ssh-keygen -t ed25519 -f $HOME/.ssh/edrv32_train -N "" -C edrv32-train`；<br>- 把 `$HOME/.ssh/edrv32_train.pub` 的**公钥内容**显示给用户；<br>- 私钥不离开 Windows，不入库。 |
| 2 | U | **部署服务器**：<br>- 镜像选"Miniconda 3.12 Ubuntu 20.04"，1×RTX 4090 48 GB，磁盘扩到最大 292 GB；<br>- 在"SSH 密钥"中填入第 1 步的公钥；<br>- 部署后把地址、端口、用户名告诉 Codex；<br>- 向平台确认：**关机后数据盘里的数据是否保留**，告诉 Codex。 |
| 3 | C | **连接和检查**：<br>- 在 Windows 的 `$HOME/.ssh/config` 中添加 `Host edrv32-train`，指向用户给的地址，使用 `edrv32_train` 私钥。此文件只在本地；<br>- `ssh edrv32-train` 后记录：`nvidia-smi`（驱动版本、CUDA 版本、显卡、显存）、`nproc`、`free -g`、`df -h`；<br>- 确定数据盘的挂载目录，作为 `$D`。 |
| 4 | C | **环境**：<br>- 在 `$D/venv` 用 conda 建 Python 3.12 环境；<br>- 从 PyTorch 官方索引安装 `torch==2.14.1`、`torchvision==0.29.1` 的 CUDA 版，选与驱动匹配的 CUDA 版本，记录 index URL。**2.14.1 没有能在这个驱动上运行的 CUDA 版本时，停下回报**，不要换其他 torch 版本，也不要用镜像自带的 2.8.0；<br>- 用 `scp -r` 把 Windows 本地的 `third_party/ultralytics` 和 `tools/requirements.txt` 复制到 `$D/repo/`，再 `pip install -r $D/repo/tools/requirements.txt`；<br>- `PYTHONPATH=$D/repo/third_party/ultralytics python -c "import torch, ultralytics; print(torch.__version__, torch.cuda.is_available(), ultralytics.__version__)"`，应输出 `2.14.1+cu…  True  8.4.160`。 |
| 5 | C | **测下载速度**：用 `wget` 下载 512px 压缩包约 60 s 后中断，记录平均速度并告诉用户，再删除这个部分文件。 |
| 6 | C | **下载**：<br>- 在 `tmux` 会话中用 `wget -c` 下载 512px 压缩包和标注压缩包到 `$D/hagrid/`，ssh 断开也不影响；<br>- 下载完成后记录两个文件的大小和耗时。 |
| 7 | C + U | **确认手势清单**：<br>- 用 `unzip -l` 查看压缩包内的目录结构，记录下来；<br>- 只解压标注，以及第 5 节 10 类和 3 个候选类的各 2 张样例图；<br>- 把样例图复制到 Windows 给用户看；<br>- 用户确认手势清单，并决定候选类是否加入。**用户确认前不要开始第 8 步。** |
| 8 | C | **解压和转换**：<br>- 用 `unzip` 按目录名只解压确认后的类别；<br>- 在本卡 `src/` 中写转换脚本 `hagrid_to_yolo.py`，只用 Python 标准库加 numpy，复制到服务器运行，要求如下：<br>  - **抽样**：每个类别从 HaGRID 的 train 标注中用 `numpy.random.default_rng(0)` 不放回抽取 **8,000 张**图，不足 8,000 张的全部使用；从 val 标注中按同样方法抽取 **800 张**。`no_gesture` 自己的图全部使用。<br>  - **标签**：每只手一行 `类别号 cx cy w h` 加 21 组 `x y 2`。HaGRID 的框是归一化的"左上角 x、y、宽、高"，要换算成中心点。图中其他手的标签是 `no_gesture`，按类别 9 写入。<br>  - **没有关键点的手**：21 组都写 `0 0 0`。<br>  - **关键点数不是 21 时，停下回报**。<br>  - **数据集配置** `hagrid.yaml`：`kpt_shape: [21, 3]`，`flip_idx` 为 `[0, 1, …, 20]`（左右翻转不改变手指编号），`names` 按第 5 节的顺序。<br>- 记录每个类别的图数、手数、没有关键点的手数。 |
| 9 | C | **训练**：在 `tmux` 会话中，于 `$D` 目录下执行：<br>`python -c "from ultralytics import YOLO; YOLO('$D/init/best.pt').train(data='$D/hagrid/yolo/hagrid.yaml', epochs=80, imgsz=640, batch=128, workers=16, cache='ram', seed=0, deterministic=True, project='$D/runs', name='hagrid-v8n')"`<br>- `$D/init/best.pt` 是从仓库复制过去的卡 80 权重；其余参数保持默认，不调参；<br>- batch 128 显存不足时改为 64，并记录；<br>- 第 1 轮结束后，记录每轮耗时和每秒处理的图片数，告诉用户预计结束时间；<br>- 训练中断时用 `resume=True` 接着训，记录中断原因和时间；<br>- 训练期间不需要频繁查看，每 1–2 小时看一次即可。 |
| 10 | C | **验证**：执行 `YOLO('$D/runs/hagrid-v8n/weights/best.pt').val(data=…, imgsz=640, batch=64)`，记录：<br>- 总体和各类的 Box P、R、mAP50、mAP50-95；<br>- Pose mAP50-95 和 mAP50；<br>- 保存混淆矩阵图。 |
| 11 | C | **预测样例**：用 `best.pt` 对 val 中 6 张图做预测，各存一张结果图（PNG）。至少覆盖 palm、fist、peace、ok、grabbing，并且至少有 2 张图中手较小：手框长边在 640 输入中小于 80 px。 |
| 12 | C | **回传**：用 `scp` 把产物复制回 Windows，整理后填写 result.md，提交并推送 `win/20261115-83-hagrid-train`。完成后告诉用户可以关机或释放服务器，由用户决定。 |

## 7. 产物

放在 `tasks/win/20261115-83-hagrid-train/`：
- `src/hagrid_to_yolo.py`：转换脚本；`src/hagrid.yaml`：数据集配置；
- `artifacts/best.pt`；
- `artifacts/results.csv`、`args.yaml`、`results.png`、`confusion_matrix.png`；
- `artifacts/val.txt`：第 10 步的验证输出原文；
- `artifacts/predict/`：第 11 步的 6 张结果图；
- `artifacts/data-stats.txt`：第 8 步各类别的统计、压缩包目录结构摘要；
- `artifacts/env.txt`：`nvidia-smi`、`nproc`、`free -g`、`df -h`、`pip freeze`、第 4 步的输出，**去掉 IP 和主机名**。

不提交：`last.pt`、数据集、`runs/` 中的其他文件，以及任何服务器访问信息。

## 8. 通过判据

- 训练完成，生成 `best.pt`；
- 第 4 步的版本与要求一致；
- 仓库中没有服务器的 IP、端口、密钥；
- result.md 中的数字都取自 `results.csv` 或验证输出原文，找不到的写"未取得"。

## 9. result.md 模板

```markdown
# 卡 83 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD / ultralytics 子模块 | |
| GPU / 驱动 / CUDA / CPU 核数 / 内存 | |
| torch / ultralytics 版本、PyTorch 索引 URL | |
| 下载速度 / 下载耗时 | |
| 最终手势清单（类别号：类名） | |
| 训练图数 / 验证图数 / 手数 / 无关键点的手数 | |
| batch / workers / cache | |
| 第 1 轮耗时、每秒图片数 | |
| 训练起止时间 / 总耗时 | |
| 中断与续训 | |

## 精度（best.pt，val）
| 指标 | 值 |
|---|---|
| Box mAP50-95 / mAP50（总体） | |
| Pose mAP50-95 / mAP50 | |
| best 所在轮次 | |

## 各类别
| 类别 | Box P | Box R | mAP50 | mAP50-95 |
|---|---|---|---|---|

## 问题与偏离
```
