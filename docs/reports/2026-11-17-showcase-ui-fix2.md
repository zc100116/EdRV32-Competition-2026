# Showcase 紧凑游戏与设置修复 — 2026-11-17

- 代码：起始基线 `efaf1fa40`，结果为本报告所在提交；开始、完成均 rebase 到 `origin/zc100116/b3`。
- 五游戏共用 48 px 顶栏：返回、游戏名、28 px 粗体分数、进度条、单行性能、关键点开关；删除右侧面板，隐藏系统顶底栏；游戏规则和串口行未改。
- 结算卡 480×300：24 px 标题、64 px 分数、星级、新纪录，实心主按钮与描边返回；结算隐藏顶栏分数和遮挡星级的光标。
- 全局 dropdown 列表增加不透明背景、边框，展开移至 top layer；原生检查覆盖处理设置、检测设置、串口调试。
- 处理设置减少组内/组间间距，读数改为 16 px 深色；该页指标只显示 CPU、GUI FPS。
- 简笔画删除文件：`sw/apps/showcase/models/doodle/{README.md,mem_desc.hex,mem_model.hex,quantization.json,regs.txt}`、`sw/apps/showcase/assets/icons/doodle.png`、`docs/reports/assets/demo-doodle.png`。
- 同时删除共享页面、类别名、主机数据/截图、模型测试/夹具与构建规则中的简笔画部分；保留其他应用原协议编号和页面编号。
- 经协调者批准，在 `main.c`、`board/vision_hooks.h`、`board/vision/{vision.c,model.h,pose.h,memory.h}` 仅删除简笔画专用分支、注册、声明和 DDR 区域，其余调度/显示同步不变。
- 环境：Linux x86_64，目标 xPack GCC 15.2.0，主机 GCC 13.3.0、锁定 LVGL 9.6.0；1280×720 原生截图使用固定输入，非上板性能测量。
- PASS、0 告警：`flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`；日志 `build/ui-fix2/build.log`。
- PASS：`flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase -j2 games`；5 组规则/大厅测试，日志 `build/ui-fix2/games.log`。
- PASS：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 games-shots GAMES_OUTPUT="$PWD/outputs/ui-fix2"`；日志 `build/ui-fix2/shots.log`，另通过 `git diff --check`。
- 指定截图：`outputs/ui-fix2/{sling-playing,sling-result,process-s1-open,home-ai}.png`；另有五游戏开始/进行/结算截图，共 17 张 PNG。
- 截图绝对目录：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-ui-fix2/outputs/ui-fix2/`。
