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
