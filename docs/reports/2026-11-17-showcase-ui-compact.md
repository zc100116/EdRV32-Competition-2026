# Showcase 摄像头紧凑叠加 — 2026-11-17

- 代码：基线 `844ba4048185976aba35da9585ab7a7588e6d034`；改后为本报告所在提交，开始与完成均 rebase 到 `origin/zc100116/b3`。
- 八页使用 48 px 顶栏、224 px 结果卡、默认收起的 320 px 侧抽屉；贴纸为缩略图套装与五个横向分段，保留全部原有 32 px 字形并追加原生 24 px 粗体标题。
- 主机：Linux x86_64、GCC 13.3、锁定 LVGL、1280×720 ARGB8888；目标 GCC 15.2.0；器件/速度等级不适用，以下不是板上实测。
- 绘制时间：同一程序/字体并集，每页 30 次整帧重绘平均 CPU 时间，从 `lv_refr_now` 扣除主机 L0/RGB565 软件合成；板上 L0 视频绕过 LVGL，主机整帧时间另列。
- 默认遮挡：L1 缓冲所有非零 alpha 像素并集 / 921600，含检测框、骨架、贴纸；姿态/手势/人脸各一人，贴纸预热八帧，调试叠加关闭，安全帽 1/未戴 0。

| 页面 | 绘制前 ms | 绘制后 ms | 变化 | 默认遮挡 | 主机整帧前/后 ms |
|---|---:|---:|---:|---:|---:|
| 目标检测计数 | 1.229 | 0.613 | -50.1% | 10.484% | 13.960 / 13.039 |
| 图片识别 | 1.119 | 0.822 | -26.6% | 13.812% | 13.768 / 13.709 |
| 图像处理 | 1.215 | 0.609 | -49.9% | 6.667% | 13.674 / 13.860 |
| 人体姿态 | 0.919 | 0.673 | -26.7% | 9.930% | 13.460 / 13.108 |
| 手势识别 | 0.904 | 0.516 | -42.9% | 8.018% | 13.517 / 13.007 |
| 人脸贴纸 | 1.539 | 0.834 | -45.8% | 7.910% | 13.656 / 13.489 |
| 简笔画 | 0.938 | 0.521 | -44.5% | 8.231% | 13.549 / 13.063 |
| 安全帽 | 0.906 | 0.725 | -20.0% | 11.875% | 13.018 / 13.950 |

- 八页 UI 绘制均更快，默认遮挡均 ≤15%；主机整帧约 12–13 ms 用于软件合成，合成波动不等于板端 UI 绘制成本。
- 截图/交互 PASS：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 compact-shots COMPACT_OUTPUT=/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/ui-compact`，16 张 PNG，默认/展开各八张，覆盖按键遍历、检测阈值/类别、贴纸套装和处理开关。
- 两种目标构建 PASS，0 告警：`flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`，以及追加 `SHOWCASE_POST=cpu`；串行运行。
- 单测 PASS（沿用前次已完成验收）：`flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase sticker grab`，日志 `build/ui-compact/tests.log`。
- 基线复现：将上述基线的 `sw/apps/showcase/ui/*.[ch]` 用 `git show` 提取到 `build/ui-compact-before/ui/`；删除 `build/sim/showcase_pages_shots`，构建该绝对路径目标时传 `UI="$(printf '%s ' "$PWD"/build/ui-compact-before/ui/*.c)" PAGES_FLAGS=-DPAGES_BASELINE`。
- 两版共用字体并集：`python3 tools/sw/gen_fonts.py --output-dir build/sim/fonts --sizes 14 16 20 28 40 --digit-sizes 40 -- build/ui-compact-before/ui/*.[ch] sw/apps/showcase/ui/*.[ch] sw/apps/showcase/sim/sim_data.c sw/apps/showcase/games/games.txt`。
- 新版测量：删除上述可执行文件后，`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 "$PWD/build/sim/showcase_pages_shots" PAGES_FLAGS=-DPAGES_BASELINE`；两版分别运行 `flock /tmp/edrv32-sw-build.lock build/sim/showcase_pages_shots build/ui-compact/paired-before` 与 `paired-after`。
- 原始记录：`build/ui-compact/render-{before,after}.log`（绘制/合成分项），`shots.log`（像素数与交互），`build-{hw,cpu}.log`（构建）；截图即上述 `COMPACT_OUTPUT` 目录。
