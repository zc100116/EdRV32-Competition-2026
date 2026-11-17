# 真实 HDMI 录像回放（T-DRAW-FIX3）

本工具使用 ELF 同源的 `sw/apps/showcase/models/gesture/` 不可变 INT8 镜像，
复用 `models_eval.integer` 的描述符执行、解码和按类别 NMS；同时得到类别和 21 点，
没有另跑一个手部检测模型，也不重新标定。画板只调用 `draw.c`，
`grab.c` 的抓取规则不参与画板；`page_draw.c` 原有最大面积选手在 `replay.c` 原样执行。

先从结果分支取录像（不入库）：

```sh
mkdir -p build/draw-fix3
git show origin/win/20261117-98-farm-draw-board:tasks/win/20261117-98-farm-draw-board/artifacts/video/QQ20261117-185928.mp4 > build/draw-fix3/98.mp4
flock /tmp/edrv32-sw-build.lock env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  PYTHONPATH="$PWD/third_party/ultralytics" ~/.local/opt/edrv32-py/bin/python \
  tools/demo/draw-replay/infer.py build/draw-fix3/98.mp4 \
  build/draw-fix3/98-immutable.jsonl --stop 240
```

依赖为 `tools/requirements.txt`，Ultralytics 使用锁定子模块。
选择前 240 帧（0–7.963 s）：包含首次 V 形、侧指误分类、张掌和短时漏检，
比后半段的白线遮挡少。先缩放 1280×720，再缩放 640×360、上下补 12 px，
保留工具栏、暗色遮罩和原有白线；没有遮盖或修补相机像素。
HDMI 是有损且已叠加 UI 的视频，因此这不是板上逐帧原始输入的逐位重建。

每行 JSONL 包含帧号、毫秒、所有框/置信度/类别/21 点及各点置信度。
规则回放另外输出选手、类别/几何结果、提笔原因、外推、暂停、滤波坐标、
笔画数、本帧写出的点数和最后笔迹点。修复前后命令：

```sh
mkdir -p build/draw-fix3/before-ui
git show b0f257989:sw/apps/showcase/ui/draw.c > build/draw-fix3/before-ui/draw.c
git show b0f257989:sw/apps/showcase/ui/draw.h > build/draw-fix3/before-ui/draw.h
flock /tmp/edrv32-sw-build.lock cc -std=c11 -Wall -Wextra -Werror \
  -Ibuild/draw-fix3/before-ui tools/demo/draw-replay/replay.c \
  build/draw-fix3/before-ui/draw.c -lm -o build/draw-fix3/before
flock /tmp/edrv32-sw-build.lock cc -std=c11 -Wall -Wextra -Werror \
  -Isw/apps/showcase/ui tools/demo/draw-replay/replay.c \
  sw/apps/showcase/ui/draw.c -lm -o build/draw-fix3/after
python3 tools/demo/draw-replay/replay.py build/draw-fix3/before \
  build/draw-fix3/98-immutable.jsonl build/draw-fix3/before.jsonl
python3 tools/demo/draw-replay/replay.py build/draw-fix3/after \
  build/draw-fix3/98-immutable.jsonl build/draw-fix3/after.jsonl
flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase draw grab
```

`draw-real.json` 就是这 240 帧的模型输出（121379 B）；测试不需要录像、模型或 Python 第三方库。
人工提笔标注：f171–209（约 5.7–7.0 s）张掌，其他位置没有有意提笔。
跳点定义：300 ms 内的前后轨迹弦线法向偏离 >60 px，并回到前高度 ±60 px；
本片段的错误是横向移动时向下再返回，按相邻 9 帧合并同一事件。
光标和实际最后写出笔迹均检查；断线统计 `down` 从真变假，另统计跟踪暂停。
延迟使用未遮挡的 f60–119，将实际笔迹端点与输入 tip8 作 0–200 ms 的时间平移，
线性插值并最小化二维 RMSE；这是画板处理延迟，不含相机/NPU/传输。
调试记录中另给出串口流水线时间和端到端估计，不能代替修复后的实板测量。
