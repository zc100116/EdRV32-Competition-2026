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
