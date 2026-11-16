# 卡 87：安全帽 v2

完成50轮重训与三项新旧评估。普通场景改善：COCO 40图的head检出数13→41、helmet
26→4；CrowdHuman head检出率0.804375→0.901557。Hard Hat helmet mAP50
0.964681→0.961716，下降幅度小。权重、训练记录、评估与过滤原始输出已回传。

## 数据准备

执行基线为 `ce76bf65`，模型为 YOLOv8n 检测，类别保持 `0 helmet`、`1 head`。
服务器 Python 3.12.16、torch 2.14.1+cu130、ultralytics 8.4.160，使用卡 83 的源码环境。
所有下载与解压只在训练机执行，数据准备使用 `nice -n 19`，单进程。

CrowdHuman 来源：[官方说明与条款](https://www.crowdhuman.org/download.html)、
[作者发布的数据](https://huggingface.co/datasets/sshao0516/CrowdHuman)。
官方 Google Drive 的训练标注链接被 gdown 报告公开下载不可用，协调者批准改用作者本人
的 HuggingFace 发布版本；实际使用 HuggingFace 直连。许可限非商业研究和教育用途，
作者发布页标注 CC BY-NC 4.0，官方条款禁止再分发图片。本提交不包含 CrowdHuman 原图或联系图。

下表直接取自 `artifacts/filter-stats.json`。规则命中数可重叠；“顺序丢弃”按表中顺序
仅计算首次命中，因此各行可相加。安全帽重叠仅在前五条规则过滤后的候选图上检查，
使用 v1、640 输入、conf=0.5，任一 helmet 与任一 hbox IoU≥0.3 即丢弃整图。

| 规则 | train 命中 | val 命中 | train 顺序丢弃 | val 顺序丢弃 |
|---|---:|---:|---:|---:|
| extra.ignore=1 | 12125 | 3495 | 12125 | 3495 |
| head_attr.ignore=1 | 4244 | 1147 | 285 | 85 |
| tag=mask | 12021 | 3460 | 0 | 0 |
| 人头数超过15 | 7713 | 2265 | 485 | 153 |
| 640输入下人头长边小于8px | 6521 | 1887 | 104 | 31 |
| v1安全帽重叠 | 979 | 299 | 979 | 299 |

| 阶段 | train | val |
|---|---:|---:|
| 原始图片 | 15000 | 4370 |
| 前四条标注规则并集过滤后 | 2105 | 637 |
| 再过滤小人头后 | 2001 | 606 |
| 再过滤安全帽后 | 1022 | 307 |
| 最终采用图片 | 1022 | 307 |
| 最终人头框 | 7768 | 2377 |

由于严格过滤后数量不足原定 6000/600，协调者批准训练用全部合格图、不重复采样、不加权，
验证最多600图、不足全用。验证用 `default_rng(0)` 无放回抽样；本次即全部307张。
Hard Hat 原训练/验证集分别为4500/500张，因此合并清单为5522/807张。

联系图位于本机 `build/helmet-v2/sheets/crowdhuman-heads.jpg`（24张）和
`hardhat-heads.jpg`（12张），由 `src/contact_sheets.py` 生成，不入库。
协调者逐张审阅24张 CrowdHuman 图并放大检查其中5张，确认整头框包含头发，
背面和远处人头亦有标注，与 Hard Hat 松紧一致，随后批准训练。
原始 hbox 有44张train/11张val的归一化值越界；协调者批准保持原始框，
接受 Ultralytics 默认超出1%容差时整图作 corrupt 跳过，未添加裁剪或额外过滤。

协调者随后明确 GPU 可在空闲时立即开训，无需等待尚未开训的手部任务。
2026-11-16 08:21:36 UTC 的 nvidia-smi 显示无GPU进程，之后启动训练。

## 训练

从卡83 v1 best.pt 开始，50轮、imgsz640、batch128、workers16、cache=False、seed0、
deterministic=True，其余默认。模型日志确认355/355项预训练权重转入。
2026-11-16 08:21:50–08:30:21 UTC完成50轮，Bash `time -p` 原文
real=510.91秒，user=3911.35秒，sys=969.31秒；起止时间见 `artifacts/train-times.txt`。
`results.csv` 首轮累计时间26.8186秒（含验证），已通过 ask 报告协调者，训练未等待回复。
训练清单5522张中默认跳过32张corrupt，实际5490张，即4500张 Hard Hat 加990张
CrowdHuman；验证清单807张中跳过6张，实际801张，即500加301。
原始扫描统计与逐图corrupt原因见 `artifacts/data-loading.txt`。
自定义 CrowdHuman 对比评估仍使用全部307张、2377个人头框，包括原始越界框，
不沿用训练器的corrupt跳过。
CrowdHuman 验证图经过 v1 安全帽检测器筛选，helmet误判指标受该筛选条件影响；
独立的 COCO 对比保留相同40张普通人物照，不经过此过滤。

## 新旧模型评估

服务器原始输出见 `artifacts/evaluation.json` 和 `evaluation.log`，指标取0–1。
Hard Hat 使用原始500张验证图，imgsz640、batch128、workers4、其他验证参数默认。

| 类别 | 模型 | P | R | mAP50 |
|---|---|---:|---:|---:|
| helmet | v1 | 0.953388 | 0.913222 | 0.964681 |
| helmet | v2 | 0.939132 | 0.908414 | 0.961716 |
| head | v1 | 0.888039 | 0.877163 | 0.894362 |
| head | v2 | 0.891099 | 0.873702 | 0.890711 |

helmet mAP50变化幅度小，head 在 Hard Hat 上也略降；普通场景改善见以下两组评估。

CrowdHuman 使用全部307张、2377个hbox，conf=0.5、imgsz640。
预测按置信度顺序在每个类别内与hbox一对一匹配，IoU≥0.5算检出；
head检出率和helmet误判率均以2377个真值头框为分母。helmet总检出数额外列出，
其中不与hbox匹配的检测不计入“人头误判”分子。

| 模型 | head匹配数 | head检出率 | helmet匹配数 | helmet误判率 | head总检出 | helmet总检出 |
|---|---:|---:|---:|---:|---:|---:|
| v1 | 1912 | 0.804375 | 0 | 0 | 1968 | 16 |
| v2 | 2143 | 0.901557 | 0 | 0 | 2182 | 1 |

COCO 选图从本机 `person_keypoints_val2017.json` 的images原始顺序出发，仅取本机
val2017存在、人数1–3、最高人身高占图高0.25–0.8的图，`random.Random(0)`
打乱后取40张。符合条件101张，所选40张共59人。
本机 Python3.12.3、torch2.14.1+cpu、ultralytics8.4.160，逐图CPU推理，
imgsz640、conf=0.5、NMS IoU=0.7。输出见 `artifacts/coco-evaluation.json`，
包含每图文件名、人数及检出数；以下数字是检测框数，不是带人头真值的召回率。

| 模型 | head检出数 | helmet检出数 |
|---|---:|---:|
| v1 | 13 | 26 |
| v2 | 41 | 4 |

协调者此前参考值为15/25；由于脚本不同，协调者明确批准采用本次统一脚本所得13/26
作为基线。新旧均使用相同40张图、相同输入和阈值，未对v2另调参数。

## 复现

服务器设置 `PYTHONPATH=/root/edrv32/repo/third_party/ultralytics`，
使用 `/root/edrv32/venv/bin/python`，工作目录 `/root/edrv32/helmet-v2`。
以下脚本与本提交的 `src/` 相同；`R=/root/edrv32/helmet-v2`。

```sh
mkdir -p "$R/raw"
nice -n 19 python src/download.py "$R/raw"
nice -n 19 python - "$R/raw" <<'PY'
from pathlib import Path
import sys
from zipfile import ZipFile
root = Path(sys.argv[1])
for name in ("CrowdHuman_train01.zip", "CrowdHuman_train02.zip",
             "CrowdHuman_train03.zip", "CrowdHuman_val.zip"):
    with ZipFile(root / name) as archive:
        archive.extractall(root)
PY
nice -n 19 env OMP_NUM_THREADS=4 python src/crowdhuman_heads.py "$R"
nice -n 19 python src/contact_sheets.py "$R" "$R/sheets"
# 联系图批准、手部训练结束且 nvidia-smi 无训练进程后：
python -u src/train.py "$R"
python -u src/evaluate_server.py "$R"
```

本机 CPU 比较（`T=tasks/win/20261116-87-helmet-v2-train`）：

```sh
OMP_NUM_THREADS=2 /home/workspace/.local/opt/edrv32-py/bin/python \
  "$T/src/evaluate_coco.py" "$T/artifacts/coco-evaluation.json" \
  tasks/win/20261115-83-hagrid-train/artifacts/extra/helmet/best.pt \
  "$T/artifacts/best.pt"
```

## 执行记录

- 首次转换未设置卡83的 PYTHONPATH，导入 ultralytics 失败；按原运行环境设置后重启。
- 首次过滤推理误将全部候选图片列表作为一次 predict 输入；该接口将列表视为一个批次，
  `batch=32` 没有拆分输入，触发 CUDA OOM。已将输入显式分为32张一组并成功完成过滤。
  原始失败日志保留在服务器 `conversion-first.log`，未修改训练参数。
- Python 语法检查、`git diff --check`、标注规则与 IoU=0.3 边界夹具通过；本任务无RTL，
  Verilator lint 不适用。
- `artifacts/best.pt` 为6249962 bytes，约6MB；它是验收要求的可运行模型权重，故保留。
  全部训练产物与原始日志仍在服务器 `/root/edrv32/helmet-v2/`，服务器未关机或释放，
  未修改手部任务的数据或运行目录。
