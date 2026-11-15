# 简笔画检测训练数据

数据来自 Google Quick, Draw! simplified ndjson，仅使用 `recognized: true` 的记录。
类别号固定为 cat、dog、fish、bird、rabbit、butterfly、sun、moon、star、cloud、lightning、
rainbow、tree、flower、house、car、airplane、sailboat、apple、smiley face（0–19）。

在仓库根目录下载完整的 20 类数据到本机缓存（不入库）：

```sh
python3 - <<'PY'
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen
import shutil

names = ('cat,dog,fish,bird,rabbit,butterfly,sun,moon,star,cloud,lightning,'
         'rainbow,tree,flower,house,car,airplane,sailboat,apple,smiley face').split(',')
cache = Path.home() / '.local/share/edrv32/quickdraw'
cache.mkdir(parents=True, exist_ok=True)
for name in names:
    url = 'https://storage.googleapis.com/quickdraw_dataset/full/simplified/'
    with urlopen(url + quote(name) + '.ndjson', timeout=120) as source:
        with (cache / (name + '.ndjson')).open('wb') as target:
            shutil.copyfileobj(source, target)
    print(name)
PY
```

依赖为 Python 3、numpy 和 OpenCV（版本见 `tools/requirements.txt`）。使用项目 Python 环境合成：

```sh
~/.local/opt/edrv32-py/bin/python tools/train/quickdraw_synth.py
```

所有随机抽样共用 `numpy.random.default_rng(0)`。每类 recognized 记录先按数值 `key_id`
排序并去重，再随机选择 3,300 个不同的原始涂鸦，前 3,000 个用于训练，后 300 个用于验证。
每个选中的原始涂鸦使用一次，两组 `key_id` 不相交。

每张 1280×720 灰度图放置 1–4 个涂鸦；随机分配 640×360 区域，在各区域内随机定位，
保证外接框不重叠。旋转为 ±15°，线宽为 3–12 px，长边为 80–400 px；
接近竖直的大图形按区域高度限制上限。背景灰度为 235–255，加少量黑色噪点，
以及 0–3 个小污点或纸边阴影残留。框由旋转、缩放并绘制后的笔画像素计算，含线宽。
每张图分别编码 PNG 和质量 95 的 JPEG，仅保存体积较小者。

生成物均不入库：

- `build/doodle/yolo/{images,labels}/{train,val}/`：图片及归一化 YOLO 检测标签。
- `build/doodle/yolo/doodle.yaml`：20 类配置，图片路径相对于此配置文件。
- `build/doodle/doodle-yolo.tar`：包含 `yolo/` 目录，可解包后使用 `yolo/doodle.yaml`。
- `build/doodle/samples/`：8 张带类别和框的样例，训练和验证各 4 张。

脚本标准输出给出每类实例数、每组图片数与图片字节数，以及 tar 字节数。
完整合成只运行一次；输出目录应为新建的 `build/doodle/`。

数据许可证：Google Quick, Draw! Dataset，**CC BY 4.0**。
原始绘画由 Quick, Draw! 玩家贡献，数据集由 Google 发布；合成数据基于原笔画进行旋转、
缩放、加粗、拼图及背景增强。分发合成数据时请保留此来源、许可证链接及修改说明。

- 数据集与署名来源：<https://github.com/googlecreativelab/quickdraw-dataset>
- 下载来源：<https://storage.googleapis.com/quickdraw_dataset/full/simplified/>
- 许可证：<https://creativecommons.org/licenses/by/4.0/>

本次合成统计：训练 24,015 张、验证 2,394 张，共 26,409 张图、66,000 个实例；
每类训练 3,000 个、验证 300 个。图片合计 303,486,245 字节，
`doodle-yolo.tar` 为 404,920,320 字节。逐类统计见本机 `build/doodle/statistics.txt`，
合成日志见 `build/doodle/synth.log`。8 张带框样例位于 `build/doodle/samples/`。

在有命令执行时间限制的终端中，可将相同合成命令放入独立后台进程：

```sh
nohup setsid ~/.local/opt/edrv32-py/bin/python tools/train/quickdraw_synth.py \
  > build/doodle/synth.log 2>&1 < /dev/null &
```

执行此命令前需先创建日志目录：`mkdir -p build/doodle`。

## 安全帽检测：Hard Hat Workers（T-HELMET-DATA）

原始来源为 andrewmvd 的 [Kaggle Hard Hat Workers](https://www.kaggle.com/datasets/andrewmvd/hard-hat-detection/data)，
实际下载自免登录的 [Voxel51 Hugging Face 镜像](https://huggingface.co/datasets/Voxel51/hard-hat-detection)。
镜像的 [数据卡](https://huggingface.co/datasets/Voxel51/hard-hat-detection/blob/main/README.md)
和 `fiftyone.yml` 均声明许可证为 **CC0 1.0 Universal（CC0 1.0）Public Domain Dedication**，
条款见 [Creative Commons](https://creativecommons.org/publicdomain/zero/1.0/)。
镜像包含 5,000 张 PNG，实际标注为 FiftyOne `samples.json`，不是 VOC XML；
原始框为归一化的左上角 `x, y, width, height`。

曾核实 [SHWD LICENSE](https://github.com/njvisionpower/Safety-Helmet-Wearing-Dataset/blob/master/LICENSE)
为 **MIT License**（Copyright 2019 njvisionpower）；
但 README 的官方 Google Drive 下载返回 `Quota exceeded`，因此未使用 SHWD。
经协调者确认，改用上述 CC0 镜像，并直接转换其 JSON 标注。

在仓库根目录下载并转换：

```sh
python3 tools/train/hardhat_download.py
python3 tools/train/hardhat_to_yolo.py
~/.local/opt/edrv32-py/bin/python tools/train/hardhat_samples.py
```

下载目录为 `~/.local/share/edrv32/hardhat/`，不入库。
下载脚本从同一镜像读取元数据，通过系统 `curl` 最多四个并发下载，
跳过已存在的 PNG，不含重试循环；
网络失败会直接报错，可手动重新运行同一条命令继续下载。
下载结束核对 PNG 数量与 `samples.json` 的样本数一致。
转换脚本仅使用 Python 标准库；可用唯一的位置参数指定其他本机源目录。
样例脚本使用 `tools/requirements.txt` 已列出的 OpenCV。

镜像没有官方 train/test 划分，样本 `tags` 均为空。
先按 `filepath` 字典序排序，再用 `random.Random(0)` 打乱，前 90% 为 train，余下为 val。
类别映射为 `helmet → 0`、`head → 1`，丢弃 `person` 框，保留图片。
YOLO 框为归一化中心点 `x + width/2, y + height/2, width, height`。

产物均不入库：

- `build/helmet/yolo/{images,labels}/{train,val}/`。
- `build/helmet/yolo/helmet.yaml`，图像路径相对该 YAML，便于解包后训练。
- `build/helmet/helmet-yolo.tar`，内含完整 `yolo/` 目录。
- `build/helmet/samples/` 中六张带类别名和框的 PNG，各取 train/val 字典序前三张。
  绿色表示 helmet，红色表示 head，画框读取转换后的 YOLO 标签。

统计（2026-11-15，固定种子 0）：

| 划分 | 图片 | helmet 目标 | head 目标 | 丢弃 person 框 |
|---|---:|---:|---:|---:|
| train | 4,500 | 17,219 | 5,207 | 671 |
| val | 500 | 1,747 | 578 | 80 |
| 合计 | 5,000 | 18,966 | 5,785 | 751 |
