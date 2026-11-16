# T-HELMET-V2：普通场景人头补充与安全帽重训（卡 87）

## 目标和输入

卡 83 的 YOLOv8n 检测模型仅用 Hard Hat Workers 工地照片训练，在普通人物照上
漏检 head、误判 helmet。保持两类 `0 helmet`、`1 head`，加入 CrowdHuman hbox，
从 v1 best.pt 重训。Linux 执行，服务器已有环境与 Hard Hat 数据；不得记录连接信息。

归属：本目录、本机 `build/helmet-v2/`、训练机 `/root/edrv32/helmet-v2/`。
不修改 `sw/`、`rtl/`、`fpga/`、`tools/npu/`、`docs/spec/`；不访问仿真虚拟机。
遵守 CLAUDE.md 第 12 节，不增加防御性检查、回退、哈希校验或额外门禁。

## 数据与审批

1. 从 [CrowdHuman 官方下载页](https://www.crowdhuman.org/download.html) 的 Google Drive
   下载训练图片三包、验证图片和 `annotation_train.odgt`、`annotation_val.odgt`。
   数据只在服务器下载；下载受阻用 orchestration ask，不换来源。
2. `src/crowdhuman_heads.py` 仅使用 hbox，统一标为 head（1）。以下任一情况整图丢弃：
   任一 `extra.ignore=1`、`head_attr.ignore=1`、`tag=mask`；人头数超过 15；
   任一 hbox 在 640 输入下长边小于 8 px。用 v1 conf=0.5 检测候选图，
   任一 helmet 框与任一 hbox IoU≥0.3 时整图丢弃。统计各规则丢图数。
3. 用 `default_rng(0)` 抽取 CrowdHuman train 6000 图、val 600 图。
4. 随机 24 张 CrowdHuman 图画人头框，另取 12 张 Hard Hat 原数据 head 框作比较。
   联系图复制到本机 `build/helmet-v2/sheets/`，不入库。用 ask 通知协调者，
   **取得批准后才能训练**。

CrowdHuman 只允许非商业研究和教育用途，不能分发原图；result.md 必须注明出处。

## 训练

服务器与 T-HAND-ORIENT 共用 GPU。数据准备用 `nice -n 19`，加载进程不超过 4。
不得修改 hagrid、runs/hagrid-*、hand-orient* 目录。必须等手部训练结束，
用 nvidia-smi 确认没有训练进程后使用 GPU。

训练集为 Hard Hat 原训练集全部加 CrowdHuman 6000 图，验证为原验证集加 600 图。
从 `/root/edrv32/runs/helmet-v8n/weights/best.pt` 开始，50 epochs、imgsz=640、
batch=128、workers=16、cache=False、seed=0、deterministic=True，其他参数默认。
第 1 轮结束后用 ask 报告每轮耗时，不等回复。不发送心跳。

## 评估和回传

- Hard Hat 验证集：新旧模型各类 P、R、mAP50；helmet 不能明显下降。
- CrowdHuman 验证 600 图：head 检出率（IoU≥0.5）和误判 helmet 比例。
- 本机 COCO：从 `~/.local/share/edrv32/npu/annotations/person_keypoints_val2017.json`
  选本机 val2017 中存在、人数 1–3、最高人身高占图高 0.25–0.8 的图，
  用 `random.Random(0)` 打乱取 40 张；本机 CPU 跑新旧 best.pt，统计 head、helmet 数。
  协调者 v1 参考值为 head 15、helmet 25（59 人）。

artifacts 回传 best.pt、results.csv、args.yaml、评估原始结果和过滤统计；
result.md 数字全部取自原始输出，记录命令、commit 和数据出处。联系图不入库。
本任务不涉及 FPGA/PDS/IP。

提交格式 `<范围>: <做了什么>`，正文结尾
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`，rebase 到最新 `zc100116/b3`。
完成后立即 worker_done succeeded，报告提交号与三项新旧评估数字；不得关闭或释放服务器。

## 执行中批准的调整

- 官方 Google Drive 标注链接被 gdown 报告公开下载不可用后，协调者批准使用作者本人
  [sshao0516/CrowdHuman](https://huggingface.co/datasets/sshao0516/CrowdHuman)。
  允许直连慢时用 hf-mirror；实际下载使用 HuggingFace 直连。
- 标注四条规则的并集过滤后，train 仅剩 2105、val 仅剩 637，尚未检查小头和安全帽。
  协调者批准所有过滤规则不变，训练用最终合格图全量、不重复采样、不加权；
  验证最多 600 图，不足全用，仍用 default_rng(0)。result.md 必须记录原计划偏离。
- 协调者审阅联系图后批准训练：原始 hbox 不裁剪，接受 Ultralytics 超出1%容差时
  整图作 corrupt 跳过，并记录实际加载数；COCO 使用统一逐图640/conf=0.5脚本，
  以本次 v1 head13/helmet26 为基线，报告与此前脚本15/25的差异。
- GPU 时机调整为联系图批准后立即检查 nvidia-smi：无其他训练则开训，已有手部
  训练则等其结束。2026-11-16 08:21:36 UTC 确认无其他GPU进程后开始本次训练。
