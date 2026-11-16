# 卡 83 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD / ultralytics 子模块 | `4809fc62a928187dc883a854b7a67d14d26e0d3a` / `9d25f80daa5b3af71c16521eba353cb6e7fb66e2` |
| GPU / 驱动 / CUDA / CPU 核数 / 内存 | RTX 4090，49,140 MiB / 590.48.01 / 13.1 / 配额 22 核（`nproc` 显示宿主机 382）/ 120 GiB |
| torch / ultralytics 版本、PyTorch 索引 URL | `2.14.1+cu130`（CUDA 可用）/ `8.4.160`；`https://download.pytorch.org/whl/cu130` |
| 下载速度 / 下载耗时 | wget 约 60 秒测速为 1.99–2.13 MiB/s；经协调者批准改用同源 aria2 16 连接，约两分钟后为 24 MiB/s。图片包平均 36 MiB/s，2026-11-15 16:42:14–17:37:54 UTC，55 分 40 秒；标注包平均 27 MiB/s，17:37:54–17:38:21 UTC，27 秒。两包分别为 128252037404、719041314 bytes。path-style 地址返回 HTTP 403 `VirtualHostDomainRequired`，按协调者指示保留原地址。 |
| 最终手势清单（类别号：类名） | 0 palm；1 fist；2 peace；3 point；4 grabbing；5 grip；6 thumb_index；7 ok；8 like；9 dislike；10 three；11 four；12 call；13 no_gesture |
| 训练图数 / 验证图数 / 手数 / 无关键点的手数 | 转换结果 train：105464 图、130194 手、5380 手无关键点；val：10600 图、13247 手、516 手无关键点。Ultralytics 默认校验忽略 train 963 图、val 97 图，实际加载 train 104501 图、val 10503 图。各类转换原文见 `artifacts/data-stats.txt` |
| batch / workers / cache | 128 / 16 / False（原 ram 主机内存 OOM，经协调者批准修改） |
| 第 1 轮耗时、每秒图片数 | 最终运行 `results.csv`：`time=234.083` 秒（含验证），104501 / 234.083 ≈ 446.43 图/秒；首个 ram 运行为 265.03 秒、约 394.30 图/秒 |
| 训练起止时间 / 总耗时 | 最终运行：2026-11-15 18:51:44–23:11:04 UTC；Bash time -p 原文 real=15559.56 秒（4 小时 19 分 19.56 秒），results.csv 第 80 轮累计 time=15494.2 秒；首个运行启动：18:12:27 UTC，进程运行 419.68 秒后被杀 |
| 中断与续训 | 首个运行第 2 轮 318/817 batches 处主机 OOM，`memory.events`：oom=1、oom_kill=1。协调者指定不 resume，从卡 80 权重重新训练 80 轮，name 改为 hagrid-v8n-r2、cache=False，其余参数不变 |

## 精度（best.pt，val）

| 指标 | 值 |
|---|---|
| Box mAP50-95 / mAP50（总体） | 0.865506 / 0.994330 |
| Box P / R（总体，原文显示精度） | 0.994 / 0.993 |
| Pose mAP50-95 / mAP50 | 0.766683 / 0.933400 |
| best 所在轮次 | 80（results.csv 的 Box + Pose mAP50-95 合计最高；权重记录 fitness=1.63155） |

## 各类别

| 类别 | Box P | Box R | mAP50 | mAP50-95 |
|---|---|---|---|---|
| palm | 0.994961 | 0.996203 | 0.993893 | 0.902362 |
| fist | 0.999965 | 0.997472 | 0.995000 | 0.841759 |
| peace | 0.991278 | 0.993655 | 0.994987 | 0.860493 |
| point | 0.992432 | 0.990906 | 0.994835 | 0.852833 |
| grabbing | 0.999811 | 0.994975 | 0.995000 | 0.874577 |
| grip | 0.997349 | 0.998742 | 0.995000 | 0.855680 |
| thumb_index | 0.997954 | 0.997481 | 0.995000 | 0.893341 |
| ok | 0.995802 | 1.000000 | 0.995000 | 0.904671 |
| like | 0.992883 | 0.998741 | 0.994106 | 0.854366 |
| dislike | 0.999339 | 0.998734 | 0.995000 | 0.863631 |
| three | 0.993205 | 0.993711 | 0.994848 | 0.894261 |
| four | 0.996324 | 0.992453 | 0.994987 | 0.899344 |
| call | 0.998744 | 0.996219 | 0.995000 | 0.855635 |
| no_gesture | 0.965294 | 0.952110 | 0.987961 | 0.764126 |

指标为 0–1，取自 `artifacts/val.txt` 的独立 best.pt 验证（imgsz=640、batch=64）；完整精度见其中的 `METRICS_JSON`。

## 问题与偏离

- 执行环境改为 Linux，通过 SSH 操作 GPU 服务器；工作目录为 `/root/edrv32`。
- 下载测速后，经协调者批准用 aria2 多连接下载替代 wget，保留已有部分文件续传。
- 协调者确认 14 类：palm 合并 palm/stop/stop_inverted；peace 合并 peace/peace_inverted/two_up/two_up_inverted；point 合并 one/point；three 合并 three/three2/three3。其余类别与同名来源对应；类别 0–12 从合并合集整体抽样 train 8000、val 800，no_gesture 自身 train/val 全用。
- 转换夹具核对通过：22 个来源的类别映射、中心框、21 个可见关键点、缺失关键点全零及两种 split；20 个关键点按要求抛出 ValueError。`python3 -m py_compile` 与 `git diff --check` 通过；本卡没有 RTL 改动，Verilator lint 不适用。
- 初次启动脚本因服务器未安装 `/usr/bin/time` 在训练开始前退出，改用 Bash 内置 `time -p` 后重新启动，训练参数未变。
- HaGRID 原始关键点存在越界值，Ultralytics 默认忽略整图：train 963、val 97。协调者明确同意保持默认忽略、不重启；转换脚本没有裁剪坐标或增设过滤。
- 首次训练使用 cache=ram，在第 2 轮主机内存达到 120 GiB cgroup 限制，被 OOM killer 杀死；当时显存约 21.5 GiB。经协调者批准，仅改 cache=False、运行名 hagrid-v8n-r2，按其指示从卡 80 初始权重重新开始，不使用首轮检查点。
- 重训前 30 分钟每约 5 分钟检查，主机 used 26–27 GiB、available 92–93 GiB，未新增 OOM，随后恢复约 30 分钟检查间隔。
- 按协调者追加指令预上传附加数据，使用 `nice -n 19` 解压：doodle-yolo.tar 为 404920320 bytes，上传 2026-11-15 18:50:16.393055–18:50:57.068852 UTC，40.68 秒；helmet-yolo.tar 为 1330012160 bytes，上传 18:51:01.881629–19:01:02.679342 UTC，600.80 秒。两者均已解压到 `/root/edrv32/extra/` 下的同名目录，未启动其他模型训练。
- 模型结构为 YOLOv8n-pose，14 类、21×3 关键点；独立验证原文记录融合后 81 层、3,382,031 参数。`artifacts/best.pt` 约 6.7 MiB，为本卡要求回传的可运行模型权重。
- 环境原文见 `artifacts/env.txt`，目录与数据统计见 `artifacts/data-stats.txt`；训练、独立验证与六张预测已完成。原始训练日志保留在服务器 `/root/edrv32/train.log`，运行产物位于 `/root/edrv32/runs/hagrid-v8n-r2/`。服务器未关机或释放。


## 预测样例

六张 PNG 位于 `artifacts/predict/`，覆盖 palm、fist、peace、ok、grabbing；保留极小拳头的误分类案例。手框尺寸为原始标注按 640 / max(宽, 高) 缩放后的长边。

| 文件 | val 图片 UUID | 640 输入中的手框长边（px） |
|---|---|---|
| 01_palm_small.png | 00bc972f-955d-47bb-b88a-558bc267a283 | 42.42、34.74 |
| 02_fist_small.png | 00744dd6-4dbd-4fa5-9092-079ccff16290 | 20.54；模型误判为 like，置信度 0.49 |
| 03_peace.png | 0004c52a-6190-413c-bc23-1bcd24a69454 | 100.24 |
| 04_ok.png | 00301c2f-fb36-4915-b4b6-aa8f7a78dc87 | 51.21、47.54 |
| 05_grabbing.png | 058aff6b-c4eb-4016-afde-ce50ae219c54 | 81.67、87.67 |
| 06_fist.png | 06b1d373-0936-4564-b674-a6c6a130ab05 | 94.44；识别为 fist |

## 复现命令

服务器工作目录 `/root/edrv32`，Ultralytics 使用上述锁定子模块，通过 PYTHONPATH 引用；转换命令针对新建的输出目录运行。

```sh
/root/edrv32/venv/bin/python /root/edrv32/src/hagrid_to_yolo.py /root/edrv32/hagrid
export PYTHONPATH=/root/edrv32/repo/third_party/ultralytics
/root/edrv32/venv/bin/python -c "from ultralytics import YOLO; YOLO('/root/edrv32/init/best.pt').train(data='/root/edrv32/hagrid/yolo/hagrid.yaml', epochs=80, imgsz=640, batch=128, workers=16, cache=False, seed=0, deterministic=True, project='/root/edrv32/runs', name='hagrid-v8n-r2')"
/root/edrv32/venv/bin/python -c "from ultralytics import YOLO; YOLO('/root/edrv32/runs/hagrid-v8n-r2/weights/best.pt').val(data='/root/edrv32/hagrid/yolo/hagrid.yaml', imgsz=640, batch=64)"
```

预测使用同一 best.pt，对上表 val 图片执行 `model.predict(source=图片路径, imgsz=640)`，以 `result.plot()` 绘图并保存 PNG；未调整预测参数。

## 附加模型

卡 83 完成后，在同一环境、同一 tmux 会话中依次训练 YOLOv8n 检测器 doodle（20 类，50 轮）和 helmet（helmet/head 两类，100 轮），无中断。均从本机 `~/.local/share/edrv32/npu/yolov8n.pt` 上传的官方 COCO 权重开始；batch=128、imgsz=640、workers=16、cache=False、seed=0、deterministic=True，其余参数默认，未调参。两个数据集 YAML 的 path 已指向 `/root/edrv32/extra/<模型>/yolo/`。

两个模型均以 best.pt 独立验证（imgsz=640、batch=64），下表为 Box 指标，范围 0–1；数字取自各自 `val.txt` 的 `TRAIN_TIMING_JSON`、`METRICS_JSON` 和 CSV 最佳轮次记录。完整运行耗时包含初始化、训练及训练末尾的自动验证，独立验证与预测另行执行。

| 模型 | 轮数 | 完整运行耗时（秒） | P | R | mAP50 | mAP50-95 | best 轮次 |
|---|---|---|---|---|---|---|---|
| doodle | 50 | 1782.73 | 0.974334 | 0.956647 | 0.984793 | 0.982096 | 48 |
| helmet | 100 | 734.88 | 0.920728 | 0.895216 | 0.929523 | 0.609224 | 94 |

- doodle：2026-11-15T23:22:57.290154+00:00 至 2026-11-15T23:52:40.021908+00:00（UTC）；原始日志为服务器 `/root/edrv32/extra-train.log`。
- helmet：2026-11-15T23:52:48.908356+00:00 至 2026-11-16T00:05:03.783383+00:00（UTC）；原始日志为服务器 `/root/edrv32/extra-train.log`。

### doodle 各类别

| 类别 | P | R | mAP50 | mAP50-95 |
|---|---|---|---|---|
| cat | 0.917135 | 0.890000 | 0.955705 | 0.954861 |
| dog | 0.921248 | 0.833333 | 0.946651 | 0.939236 |
| fish | 0.986299 | 0.959819 | 0.989006 | 0.986963 |
| bird | 0.954593 | 0.896667 | 0.960857 | 0.960857 |
| rabbit | 0.952667 | 0.939253 | 0.980473 | 0.980235 |
| butterfly | 0.993202 | 0.974011 | 0.994700 | 0.992108 |
| sun | 0.991892 | 0.983333 | 0.994490 | 0.992890 |
| moon | 0.971129 | 0.940000 | 0.979742 | 0.976010 |
| star | 0.979486 | 0.966667 | 0.990188 | 0.987182 |
| cloud | 0.983084 | 0.968598 | 0.990576 | 0.975775 |
| lightning | 0.973488 | 0.980000 | 0.991074 | 0.988369 |
| rainbow | 0.992084 | 0.986667 | 0.993217 | 0.991296 |
| tree | 0.989790 | 0.969409 | 0.986359 | 0.986201 |
| flower | 0.989878 | 0.977923 | 0.990265 | 0.988914 |
| house | 0.995051 | 0.983333 | 0.994543 | 0.991201 |
| car | 0.987574 | 0.976667 | 0.994281 | 0.993183 |
| airplane | 0.957121 | 0.967259 | 0.985650 | 0.985650 |
| sailboat | 0.989557 | 0.980000 | 0.992932 | 0.992932 |
| apple | 0.986690 | 0.990000 | 0.994669 | 0.994669 |
| smiley face | 0.974720 | 0.970000 | 0.990481 | 0.983382 |

### helmet 各类别

| 类别 | P | R | mAP50 | mAP50-95 |
|---|---|---|---|---|
| helmet | 0.953391 | 0.913269 | 0.964694 | 0.633696 |
| head | 0.888066 | 0.877163 | 0.894353 | 0.584751 |

每个模型的 `best.pt`、`results.csv`、`args.yaml`、`results.png`、独立验证混淆矩阵、`val.txt` 和四张预测 PNG 均在 `artifacts/extra/doodle/`、`artifacts/extra/helmet/`。两个 best.pt 各约 6 MiB，为要求回传的可运行模型权重；未提交 last.pt。预测选用各自有效 val 图片排序后的前四张，以默认参数 `model.predict(source=图片路径, imgsz=640)` 生成，并用 `result.plot()` 保存 PNG；图片路径记录在 val.txt 的 `PREDICT_INPUT` 行。服务器保持运行，未关机或释放。

复现训练时沿用上文 PYTHONPATH 和 Python 环境，将初始权重换为 `/root/edrv32/init/yolov8n.pt`、data 换为 `/root/edrv32/extra/doodle/yolo/doodle.yaml` 或 `/root/edrv32/extra/helmet/yolo/helmet.yaml`、epochs 分别为 50/100、name 分别为 doodle-v8n/helmet-v8n，其余训练参数与上文一致；独立验证使用各自 `/root/edrv32/runs/<模型>-v8n/weights/best.pt` 和对应 data。
