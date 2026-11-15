# 卡 83 交接

本次从 Windows 完成了实例登录和环境检查。训练、验证及结果回传改由 Claude 调度 VPS 上的 Codex 接手。后续按 [任务卡](task.md) 执行，完成后在本分支提交 `result.md` 和产物。

## 已实测的环境

| 项目 | 结果 |
|---|---|
| 任务卡基线 | `5d08d092c727c903a3a7de9cb055823a8e2e8ce5` |
| Ultralytics 子模块 | 仓库锁定 `9d25f80daa5b3af71c16521eba353cb6e7fb66e2`，任务要求版本 8.4.160 |
| 访问 | Windows 以 ED25519 公钥免密登录验证通过。配置时将实例 `/root` 的权限从 0777 改为 0755，使服务端的 SSH 权限检查通过。 |
| 系统 | Ubuntu 20.04.6 LTS |
| GPU | NVIDIA GeForce RTX 4090，49,140 MiB 显存 |
| NVIDIA 驱动 | 590.48.01，`nvidia-smi` 显示 CUDA 13.1 |
| CPU 和内存配额 | `cpu.max = 2200000 100000`，即 22 核；`memory.max = 128849018880`，即 120 GiB |
| 工作盘 | `/root` 所在的实例系统盘为 290 GiB，检查时几乎全空。训练目录可设在该盘。 |
| Python | `/root/miniconda3/bin/python` 为 3.12.12，Conda 为 25.11.1 |
| 工具 | `wget`、`unzip` 可用；`tmux` 未在 PATH 中找到。 |

采集命令为 `nvidia-smi`、`cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max`、`df -hT /root`、`/root/miniconda3/bin/python --version` 和 `/root/miniconda3/bin/conda --version`。实例未做实际关机和恢复测试。

## VPS 上接手

1. 在 VPS 的现有仓库中检出本交接分支，执行 `git submodule update --init third_party/ultralytics`。卡 80 的初始权重 [best.pt](../20261115-80-hand-pose-train/artifacts/best.pt) 已随任务基线入库，复制到卡内指定的 `$D/init/best.pt`。
2. 用现有 Miniconda 创建 Python 3.12 训练环境，准备 `tmux`。PyTorch 官方 CUDA 13.0 索引同时提供 Python 3.12 的 `torch==2.14.1` 和 `torchvision==0.29.1` Linux x86-64 安装包。实际安装后按卡验证 `torch.cuda.is_available()` 和 Ultralytics 版本。[Torch 索引](https://download.pytorch.org/whl/cu130/torch/) · [TorchVision 索引](https://download.pytorch.org/whl/cu130/torchvision/)
3. 先按卡做约 60 秒的下载测速。正式下载后，按第 7 步提取 10 个既定类别和 `thumb_index`、`thumb_index2`、`grip` 三个候选类别的样例。由用户确认最终类别后，再转换数据并开始 80 轮训练。

VPS 训练环境尚未安装，HaGRIDv2 尚未测速或下载，训练尚未开始。
