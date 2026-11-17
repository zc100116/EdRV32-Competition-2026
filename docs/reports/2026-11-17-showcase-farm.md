# Showcase 智慧农场 — 2026-11-17

- 代码：本报告所在提交；开始 rebase 到 `9c49ca420`，字形同步到 `5327b43f3`，交付前再次 rebase 到 `origin/zc100116/b3`（`d9d55d942`）。
- 环境：Linux x86_64 / GCC 13.3，目标 xPack GCC 15.2.0，仓库锁定 LVGL；主机 1280×720 ARGB8888，器件/速度等级不适用，无板上性能测量。
- `farm.c/h` 无 LVGL：底边中点分三栏、全量四类计数、盘点、走失 2 s / 串栏 1 s 连续计时与恢复；20 条带时间戳的出现/解除记录，10 s 采样、60 点环形曲线。
- 页号 19，复用 `UI_APP_CAMERA` 与 COCO-80；`main.c` 原有 CAMERA 分派直接适用，不新增 wire app 编号。
- 协调者批准的接口扩展：`ui_data.h` / `board/vision/vision.c` 增加全量后处理框只读接口，`showcase_lvgl.c` 增加农场逐帧分发和视觉页登记；不改 vision 调度或显示同步。
- 页面：48 px 顶栏、224 px 三行结果卡、细虚线与栏名徽章、3 s 告警横幅、默认收起的 320 px 曲线/时间线抽屉；只更新变化的框边缘与文本，徽章仅在告警状态切换时更新。
- 主机逻辑 PASS：`flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase farm`，覆盖分栏/边界、盘点、走失持续/中断/恢复、串栏、20 条记录上限和 60 点采样上限。
- 目标构建 PASS、0 告警：`flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`；日志 `build/farm/build.log`、`build/farm/build-final.log`。
- 主机 UI PASS：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 farm-shots`；日志 `build/farm/shots.log`，包含 9 框全量计数（关闭实时识别类别筛选）、盘点、恢复、四曲线像素、字形、抽屉及按键遍历检查。
- 遮挡实测：L1 非零 alpha 像素 / 921600；正常 `96024`（10.419%），走失横幅 `100098`（10.861%），默认收起均 ≤15%；展开抽屉为 33.794%。
- 截图：`outputs/farm/{normal,missing,dashboard,home-ai}.png`；街景背景叠加主机合成动物检测框，仅验证 UI 与统计，不代表模型动物识别实测。
- 串口：按 1 s 间隔打印 `farm counts=3,1,3,2 alerts=0` 等；出现/解除输出 `farm event=... time_ms=...`，时间线显示运行时长 HH:MM:SS。
- 图标：内置 imagegen 原创，96×96 RGBA；提示词见 `sw/apps/showcase/assets/icons/README.md`；粗体 24 字形沿用 T-GRAB-EXP 的统一补字。

## T-FARM-SIM：平板模拟与栏位对齐

- 代码：本报告所在提交；构建/逻辑/UI 验收基线 `7539e98c0`，交付 rebase 到 `4d4e5dfbd`；无 RTL 改动，Verilator lint 不适用。
- 主机 Chromium 1248 / playwright-core 1.65.1；2000×1200 渲染，投影四角 (220,100)/(1052,112)/(1044,614)/(228,603) 到 1280×720，宽 65%；σ=1 px、亮度 0.85、噪声 σ=2、种子 17。
- YOLOv8n COCO-80：`~/.local/share/edrv32/npu/yolov8n.pt` 的仓库 INT8 标定，640×384 描述符参考执行及整数后处理；全部可见动物正确检出（26/26），最低 0.449；走失羊离场不计。
| 动物（初始位置） | COCO 类 | 初始置信度 | 走失中置信度 | 串栏中置信度 |
|---|---|---:|---:|---:|
| 牛 1（左上） | cow/19 | 0.886 | 0.694 | 0.807 |
| 牛 2（左下） | cow/19 | 0.774 | 0.736 | 0.500 |
| 马（牛栏右上） | horse/17 | 0.921 | 0.863 | 0.905 |
| 羊 1（上，走失） | sheep/18 | 0.694 | 离场 | 0.774 |
| 羊 2（中） | sheep/18 | 0.736 | 0.694 | 0.837 |
| 羊 3（下，串栏） | sheep/18 | 0.694 | 0.736 | 0.886 |
| 鸡 1（上） | bird/14 | 0.774 | 0.449 | 0.601 |
| 鸡 2（中） | bird/14 | 0.863 | 0.774 | 0.807 |
| 鸭（下） | bird/14 | 0.837 | 0.774 | 0.863 |
- 素材调优：照片草地、牛 380/400 px、马 350 px、鸡 320 px/鸭 250 px；牛栏加宽，错开牲畜，避免头部遮挡。截图与框图 `outputs/farm-sim/{initial,missing,crossing}{,-camera,-detections}.png`，逐只数据 `build/farm-sim/detections.json`。
- 复现：`npm install --prefix build/farm-sim playwright-core@1.65.1 && node tools/demo/farm-sim/capture.mjs`；`PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/demo/farm-sim/validate.py`。
- PASS/0 告警：`flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`（先加载 env.sh）、`flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase farm`、`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 farm-shots FARM_OUTPUT="$PWD/outputs/farm-sim/board"`；日志 `build/farm-sim/{build,ui}.log`，覆盖百分比分栏、滑条重计数与本次开机保留；浏览器剧本/停止/复位/鼠标/触摸 PASS。

- T-FARM-SIM-FIT（本报告所在提交，基于 `5e1ebd7a3`）：2000×1200 舞台等比居中、黑边，竖屏旋转 90°；支持时显示全屏按钮，无 RTL 变更（Verilator/Verilog 风格检查不适用）。
- `node tools/demo/farm-sim/capture.mjs`：Chromium 1248 / Playwright 1.65.1，1080×1728 DPR 2.5、2400×1080、2560×1600、1280×800；三栏九只动物完整可见，鼠标/触摸拖动、旋转重排、全屏与不支持时隐藏 PASS；截图 `outputs/farm-sim/fit-*.png`，日志 `build/farm-sim/capture-fit.log`。
- `PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/demo/farm-sim/validate.py`：26/26 可见动物分类正确，最低置信度 0.500，识别通过结论不变；日志 `build/farm-sim/validate-fit.log`，未做微信/QQ/iPad 真机验证。

## T-FARM-AREA：单区域与闯入告警（R5-11）
- 实现为本节所在提交；起止 rebase origin/zc100116/b3，基线 b70f1a085；目标 xPack GCC 15.2.0、主机 GCC 13.3、LVGL 9.6.0，1280×720；无 RTL 改动，Verilator lint 不适用。
- 全画面牛/马/羊/鸟计数，删除分栏线、栏位滑块、栏名和串栏状态；盘点后少于基准持续 2000 ms 告警，恢复即时解除；person 持续 500 ms 触发、无人连续 1000 ms 解除，0.3 s 出现不告警。
- 看板显示四类当前/基准、今日走失/闯入次数、20 条最近事件和原 10 s/60 点四类曲线；时间沿用运行时长 HH:MM:SS，今日计数按该单调时钟的 24 h 日界复位。
- 固件 make -C sw -j2 PROGRAM=showcase、逻辑 make -C sw/tests/showcase farm、主机 make -C sw/apps/showcase/sim -j2 farm-shots 均用共用 flock 串行通过、0 告警；日志 build/farm-area/{build,host,shots}.log。
- 截图 /home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/farm/{normal,intrude,missing,dashboard}.png，另有 home-ai.png；为真实 LVGL 渲染加合成检测框，街景是主机占位相机背景，不是模型识别或上板测量。
- 正常 3/1/3/2 只，闯入红色人框且动物计数不变，走失羊 2/3；L1 覆盖正常 11.165%、闯入 11.856%、走失 11.455%、看板 34.484%；四曲线像素、事件/恢复、按键遍历和新文案字形检查通过。
- 串口按 1 s 输出 farm counts=... person=... alerts=...，四种出现/解除事件输出 farm event=missing|missing_clear|intrude|intrude_clear class=... amount=...；首页副标题为“动物盘点与闯入告警”，常规字库自动包含新字形，无需修改既有粗体字库。

- T-FARM-LAG-OK：本节所在提交，起止 rebase `origin/zc100116/b3`，基线 `c2b7638c6`（农场与 `e146915c1` 一致）；GCC 13.3.0 / xPack GCC 15.2.0、仓库锁定 LVGL，1280×720 ARGB8888 DIRECT、失效缓冲 128 项、每组 120 帧/16 ms，原始数据 `build/farm-lag/{before,after}.log`；无板上性能数据，无 RTL 改动。
- 主机确认的额外开销：相同 5 个静止框，计数页 405.5 px/帧、0 次背景设置，农场 7211.5→461.5 px/帧、背景设置 5→0、失效请求 10.03→0.03、对象 5.02→0.02；原 `ui_text` 已去重，框已复用，主要问题是每帧重复设置标签背景导致失效。
- 9 框静止：12611.5→461.5 px/帧，失效请求 18.03→0.03、对象 9.02→0.02；水平 0/1/2 px 移动：18484.2→18382.9 px/帧、请求 125.13→71.43、对象 10.01→9.93，沿用计数页的新旧边缘合并；静止标签实际更新均为 0.02 次/帧（顶栏指标），无常驻横幅重复重绘。
- 每帧推进 10 s 的采样压力：隐藏看板失效请求 243→2、对象 11→1，展开时 243→3、对象 11→2；隐藏时不刷新看板，展开补齐最新数据；四条曲线直接批量填数组后统一刷新，仍只在采样版本变化时更新，标签/横幅仍仅在文字变化时设置。
- `farm_frame` 未改：100 框移动时主机 2.429→2.616 µs/帧，整帧 2751.56→2644.12 µs（含软件绘制/测量开销），不是主要计算量；所有场景逐帧创建/删除对象均为 0；100 框移动仍为 913920 px/帧，不能据此宣称板上卡顿已经消失。
- 串口每秒新增实际 LVGL 渲染次数 `draw_fps=` 和本周期平均本页更新耗时 `ui_us=`（不含后续布局/绘制）；注册时记录所属显示对象用于退出注销；移动/消失与全屏重绘逐像素一致、红色人框消失后复用为青色动物标签、看板补齐、告警与 OK 进度环/字形均 PASS。
- 复现基线：`mkdir -p build/farm-lag; git show c2b7638c6:sw/apps/showcase/ui/page_farm.c > build/farm-lag/page_farm_before.c`，再 `flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 farm-bench FARM_PAGE_SOURCE="$PWD/build/farm-lag/page_farm_before.c"`；去掉变量即修复后；加载 `env.sh` 后固件 `make -C sw -j2 PROGRAM=showcase`、规则 `make -C sw/tests/showcase farm workshop`、主机 `make -C sw/apps/showcase/sim -j2 farm-shots workshop-shots` 均加同一 flock 通过、0 告警，日志 `build/farm-lag/{build-final,tests,after,shots}.log`。
