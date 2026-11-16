# 卡 86：新模型否决，保留卡 83 模型

已按用户批准的最终方案完成 30 轮训练与新旧模型评估。FreiHAND 原图上，手背与侧面检出率严重退化，协调者否决新模型；本次仅交付失败实验记录，不提交新的 best.pt，也不替换卡 83 权重。服务器未关机、未释放，等待用户决定。

## 新旧模型比较

FreiHAND 使用最终过滤后的同一套 1624 张原图验证集；类别未知，不计算分类正确率。检出条件为 conf=0.25、IoU≥0.5，不论类别，一对一匹配；PCK@0.1 为误差小于 GT 手框长边 10% 的可见点比例，漏检手的点计为零命中。

| FreiHAND 朝向 | 手数 | 旧模型检出率 | 新模型检出率 | 旧 PCK | 新 PCK |
|---|---:|---:|---:|---:|---:|
| 全部 | 1624 | 64.901478% (1054) | 2.278325% (37) | 28.210767% | 2.196223% |
| 手心 | 438 | 71.917808% (315) | 5.022831% (22) | 34.431398% | 4.935856% |
| 手背 | 434 | 75.345622% (327) | 1.382488% (6) | 42.198815% | 1.327628% |
| 侧面 | 752 | 54.787234% (412) | 1.196809% (9) | 16.514691% | 1.101824% |

括号为检出手数。原始计数与完整精度见 `artifacts/old_freihand_final.json`、`artifacts/new_freihand.json`。新模型共检出 37 只手，关键点命中 749/34104；这 37 只已检出手中的命中比例为 749/(37×21)=96.396396%，总体 PCK 仍按全部 GT 点计算。

| HaGRID val 指标 | 卡 83 | 本次新模型 |
|---|---:|---:|
| 检出率 | 99.358345% | 99.501774% |
| 检出手中类别正确率 | 99.711290% | 99.620666% |
| PCK@0.1 | 96.140280% | 95.881070% |
| Ultralytics Box mAP50 | 99.433025% | 99.414790% |
| Ultralytics Pose mAP50 | 93.338843% | 93.086123% |

Box/Pose mAP50 分别变化 -0.018235 / -0.252720 个百分点。自定义评估的 13247 只 GT 手：旧检出/分类正确为 13162/13124，新为 13181/13131；关键点旧命中 257032/267351、新命中 256339/267351。见 `old-hagrid.json`、`new_hagrid.json`。原生评估沿用默认越界标签忽略，10600 图中实际评估 10503 图；自定义指标读取完整标注，两模型口径一致。

### HaGRID 各类别 mAP50

| 类别 | 旧 Box | 新 Box | 旧 Pose | 新 Pose |
|---|---:|---:|---:|---:|
| palm | 99.389293% | 99.334874% | 98.200143% | 98.184247% |
| fist | 99.500000% | 99.498728% | 93.954508% | 93.920459% |
| peace | 99.498721% | 99.482122% | 96.755637% | 96.634649% |
| point | 99.483465% | 99.414318% | 79.342978% | 76.893338% |
| grabbing | 99.500000% | 99.498734% | 90.447559% | 90.630342% |
| grip | 99.500000% | 99.500000% | 93.359248% | 93.321813% |
| thumb_index | 99.500000% | 99.498739% | 99.483464% | 99.482131% |
| ok | 99.500000% | 99.500000% | 98.479202% | 98.433163% |
| like | 99.412287% | 99.442328% | 96.210477% | 95.850822% |
| dislike | 99.500000% | 99.500000% | 94.694366% | 94.812943% |
| three | 99.484782% | 99.489927% | 98.267483% | 98.323874% |
| four | 99.498734% | 99.489818% | 99.364591% | 99.307351% |
| call | 99.500000% | 99.476101% | 97.200513% | 97.083682% |
| no_gesture | 98.795067% | 98.681370% | 70.983630% | 70.326909% |

完整原始值见 `artifacts/old-map.json`、`artifacts/new_map.json`。原生独立评估的结果与训练中验证略有不同，以上使用独立评估值。

## 退化原因分析（推测）

YOLOv8 的类别得分同时决定检出置信度。FreiHAND 未知手的已分配正锚点没有分类目标、整行分类损失为零，但其余锚点仍作为分类负例；模型可能因此学会压低这类手的类别得分，导致 conf0.25 下大部分手消失。检出后的点定位较好、HaGRID 检出仍稳定，与这个解释一致；尚未通过额外对照实验确认因果。未修改阈值、未调参、未再次训练。协调者据此否决新模型，保留卡 83。

## 最终数据与训练

| 数据 | train | val | 类别监督 |
|---|---:|---:|---|
| HaGRID | 57182 | 10600 | 原 14 类 |
| FreiHAND 原图 | 30853 | 1624 | 标签 14 为实例忽略标志 |

HaGRID 0–12 类各抽样 4286 张，no_gesture 全部 1464 张；palm 中 stop_inverted 2143 张，peace 中 peace_inverted 1068、two_up_inverted 1075 张。随机抽样使用 default_rng(0)，补转换原图 7705 张。见 `hagrid-counts.json`、`training-data-counts.json`。训练清单合计 88035 张；原生扫描默认跳过 558 张 HaGRID 越界标签，实际训练 87477 张，FreiHAND 全部接纳。

FreiHAND 仅使用前 32560 张绿幕原图，不抠图、不贴图；最后 5% 连续编号为 val，其余合格样本全部训练。21 点投影到图外、落在膨胀 5 px 掩码外、源框长宽比>3 的样本丢弃。框由关键点外接框加 HaGRID 的四边中位数边距，图像边界处截断。两数据集点序均为腕、拇指、食指、中指、无名指、小指，每指四点，与 HaGRID/MediaPipe 一致；参考 [FreiHAND 工具](https://github.com/lmb-freiburg/freihand/blob/master/utils/fh_utils.py)、[DexYCB 工具](https://github.com/NVlabs/dex-ycb-toolkit/blob/master/dex_ycb_toolkit/dex_ycb.py)。

| FreiHAND 最终过滤 | train | val |
|---|---:|---:|
| 输入 | 30932 | 1628 |
| 点出图 | 6 | 1 |
| 点在膨胀掩码外 | 0 | 0 |
| 源框长宽比>3 | 73 | 3 |
| 保留 | 30853 | 1624 |

| FreiHAND 最终类别/朝向 | train | val |
|---|---:|---:|
| 不计类别/手心 | 7870 | 438 |
| 不计类别/手背 | 8060 | 434 |
| 不计类别/侧面 | 14923 | 752 |

完整计数见 `freihand-raw-counts.json`。朝向由右手掌心法线与指向相机的向量夹角决定：余弦>0.5 为手心、<−0.5 为手背，其余侧面，仅用于统计。

模型仍为 YOLOv8n-pose，类别号/名字与卡 83 相同、nc=14、关键点为21×3。数据标签14不增加输出类别：其已分配锚点分类目标与分类损失整行归零，参加框/DFL/关键点及可见性损失；分配对齐分数取各类别得分最大值。分类按已知目标权重归一化，框/DFL按全部目标权重归一化。

从 `/root/edrv32/runs/hagrid-v8n-r2/weights/best.pt` 开始，30轮、imgsz640、batch128、workers16、cache=False、seed0、deterministic=True，其他参数默认，包括 mosaic=1、close_mosaic=10；参数原文为 `artifacts/args.yaml`。训练内验证只用 HaGRID，FreiHAND 独立评估。

训练起止 `2026-11-16T10:22:45.139930+00:00` 至 `2026-11-16T11:53:50.141935+00:00`，总耗时 **5465.002005 秒**；30 轮训练/验证 CSV 累计 5363.29 秒（原始最后一行以 results.csv 为准）。首轮 194.452 秒，已按要求 ask 报告并继续。实际 best 检查点最后记录 epoch30。权重仍在服务器 `/root/edrv32/runs/hand-orient-v8n/weights/best.pt`；被否决后已从本机待提交目录删除。

### 训练实现自检

正式训练前的64图、1轮自检通过：ignored_anchors386、known_anchors385；忽略目标和分类损失均0、正常分类损失152.56921768188477，所有损失有限。分配器专项检查通过。自检时间15.701776秒，见 `masked-self-check.json`、`masked-assigner-check.txt`。最终权重在仅提供原生 Ultralytics 的 `/tmp` 环境独立加载成功，PoseModel、nc14、kpt_shape[21,3]、输出[1,81,8400]，无需导入训练模块；见 `final-model-check.txt`。模型结构验证通过不代表模型效果获准。

## 两次合成失败与放弃原因

第一版1500图、1782只手，手心76/478=15.89958159%、手背104/491=21.18126273%、侧面54/813=6.64206642%检出。原始 FreiHAND 对照手心315/438=71.91780822%；合成显著降低检出，停止生成训练图。原始 JSON 为 `old-freihand.json`、`old-freihand-raw.json`。这套原图对照含1627图，早于长宽比过滤，与最终1624图对照分开保存。

初版将约3px羽化误作sigma3，10%–90%过渡实测8px；修正为7×7/sigma1后为2px。同几何/颜色100图对照的105只手心检出仅由20/105变为21/105，说明羽化不能解释主要差距；见 `feather-check.txt`、`old_sigma3.json`、`old_edge3.json`。尺寸诊断见 `detection-size-diagnostic.json`，诊断低阈值未用于正式结果。

第二版按协调者要求去绿限掩码边缘3px、腐蚀1px后羽化、只改亮度±10%和饱和度±5%、不改色相；长边为图高8%–30%、放大≤1.5倍、框长宽比≤3。1500图、2210只手，手心71/607=11.69686985%、手背127/592=21.45270270%、侧面81/1011=8.01186944%，仍未达到60%门槛。内部8335071像素平均BGR从[115.84070790,117.66990131,156.68256095]变为[114.78491653,116.59360982,155.63791406]；平均颜色色相偏差0.03083801°、逐像素绝对偏差均值0.31223077°/P95=2°，已符合≤5°要求。最大放大1.49984361、最大长宽比2.94552847、轴向拉伸比1.000000000011。见 `old_freihand_v2.json`、`colour_v2.json`、`freihand-v2-counts.json`、`composite-colour-check.txt`。

两版合成均未用于正式训练；用户最终批准改用原图。联系图和审查图只保留在本机 `build/hand-orient/sheets/` 与 `build/hand-orient/committed-sheets/`；FreiHAND 仅限研究用途，不提交任何数据集图片或由其合成的图片。

## 原始自动手势方案的审查记录

DexYCB 整体被排除：候选 fist 有拿剪刀、手指未弯、关键点错位，four 多数拇指张开；FreiHAND 收紧规则后的候选仍有持物、关键点错位和手型误判，也被否决。公开数据最终只使用 FreiHAND 的框与关键点，不给它标 no_gesture。

| 原始过滤步骤 | Dex train | Dex val | Frei train | Frei val |
|---|---:|---:|---:|---:|
| 输入/每10帧抽样 | 12688 | 6328 | 30932 | 1628 |
| 非接近阶段 | 9656 | 5088 | — | — |
| 无手 | 848 | 1104 | — | — |
| 点出图 | 588 | 32 | 6 | 1 |
| 进入判断 | 1596 | 104 | 30926 | 1627 |
| 不确定 | 1540 | 86 | 30286 | 1580 |
| 检出额外未标手 | 6 | 0 | — | — |
| 最终候选（全部否决） | 50 | 18 | 640 | 47 |

不确定占参与判断：Dex train96.49122807%/val82.69230769%，Frei train97.93054388%/val97.11124770%。掩码外Frei为零。逐split统计在 `dexycb-counts.json`、`freihand-source-counts.json`。

| 被否决候选 | 类别 | 手心 | 手背 | 侧面 |
|---|---|---:|---:|---:|
| DexYCB | fist | 2 | 11 | 27 |
| DexYCB | four | 1 | 11 | 9 |
| DexYCB | palm | 0 | 3 | 4 |
| FreiHAND | dislike | 0 | 0 | 1 |
| FreiHAND | fist | 16 | 17 | 31 |
| FreiHAND | grip | 164 | 139 | 258 |
| FreiHAND | like | 13 | 13 | 27 |
| FreiHAND | thumb_index | 2 | 4 | 2 |

## 环境、数据获取与复现

起始代码 `b32048b0b48f131b28cd7cb5ed283068b8f2b245`。RTX4090、Python3.12.16、PyTorch2.14.1+cu130、Ultralytics8.4.160，使用 `/root/edrv32/venv/bin/python`，PYTHONPATH指向服务器仓库的Ultralytics子模块。初查GPU1MiB/0%，磁盘总290GiB、已用217GiB、可用74GiB；HaGRID train图/标签各105464、val各10600。经ask批准，核对已使用22个来源类数量一致后删除原始 `hagridv2_512.zip`（128252037404bytes），保留annotations.zip，剩余180GiB。原包1086167图，解压692846图，差额为未使用来源类及检查点目录。

DexYCB 官方GoogleDrive经批准用gdown下载subject01/02/03及calibration，subject03实测50–85MB/s。FreiHAND服务器常规下载及本机上传过慢，经批准改用官方ZIP的HTTP Range，只提取绿幕RGB、mask、xyz/K/scale，共65123成员；请求60秒超时、异常直接报错、按缺失文件名续取，无哈希校验或自动重试。本机临时zip/原图/掩码/JSON已删除，数据保留服务器。完整数据位于 `/root/edrv32/hand-orient/`，训练输出在 `/root/edrv32/runs/hand-orient-v8n/`。

复现命令（服务器）：

```sh
export PYTHONPATH=/root/edrv32/repo/third_party/ultralytics
python_exec=/root/edrv32/venv/bin/python
task_root=/root/edrv32/hand-orient
"$python_exec" "$task_root/freihand_raw.py" "$task_root/freihand-range" \
    "$task_root/freihand_raw_yolo" "$task_root/margins.json"
"$python_exec" "$task_root/assemble_data.py" mix \
    "$task_root/freihand_raw_yolo" "$task_root/mixed"
"$python_exec" "$task_root/train_masked.py"
bash "$task_root/evaluate_models.sh"
```

上述组装命令用于新的输出目录；现存目录已完整保留。原生旧模型评估命令见 `src/ultralytics_eval.py`，旧HaGRID自定义指标由 `src/hand_orient_eval.py` 计算。参数和原始输出以 artifacts 中JSON/CSV/YAML为准。提交前Python全文件py_compile、shell bash -n、git diff --check通过；本Task没有RTL修改，Verilog风格检查无目标文件，Verilator lint不适用。

本机检查命令均通过；Verilog风格检查输出 `Style: 0 files, 0 warnings`：

```sh
PYTHONPYCACHEPREFIX=build/hand-orient/pycache python3 -m py_compile tasks/win/20261116-86-hand-orient-train/src/*.py
bash -n tasks/win/20261116-86-hand-orient-train/src/evaluate_models.sh
python3 tools/check/verilog_style.py tasks/win/20261116-86-hand-orient-train
git diff --check
```

## 出处与许可

[FreiHAND](https://lmb.informatik.uni-freiburg.de/resources/datasets/FreihandDataset.en.html)：Zimmermann等，ICCV2019，*FreiHAND: A Dataset for Markerless Capture of Hand Pose and Shape from Single RGB Images*；仅限研究用途、禁止商业使用。[DexYCB](https://dex-ycb.github.io/)：Chao等，CVPR2021，*DexYCB: A Benchmark for Capturing Hand Grasping of Objects*；CC BY-NC4.0。下载与实验遵守上述许可，新权重已否决且未入库。
