# 方块工坊验收（2026-11-17）

- 版本：本报告所在提交；基线 `origin/zc100116/b3`（`a1b6fd783`），美术 `ddf7ce370`。
- 模块：`workshop.c/h` 负责整数网格、固定连通、整体/散粒下落、工具、场景和动物；
  `workshop_view.c` 负责共享边界与失效矩形；`page_workshop.c` 负责 LVGL 组件和绘制。
- 应用任务通过现有 `game_loop` 以 60 Hz 步进，三个调用方持有的缓冲发布值快照。
- 快照：方块种类/朝向/格坐标/组、下落位移、动物位置/动作/帧、粒子、光标、
  当前物品/天色、预览、抓持/滑回/挖掘裂纹状态、场景/物品栏、累计操作数。
- 静态层：48×48 ARGB8888 格子缓存（含周边光晕），只更新变化区域；下落结构和抓持物离开缓存。
  动态层使用新旧边界失效，物品栏为 LVGL 部件；顶栏复用 `ui_camera_layout`，48 px。
- 归位规则按协调者答复：原位被占则找同列上方最近空位，0.2 s 滑回；上方无位置则出碎屑。
- 动物固定种子；小兔/小鸭步幅 24/16 px，每 8 帧一循环，脚底 y=52；走/跑为 10/24 fps。
- 天色暗幕：白天黑色 alpha 89；黄昏 `#59351e` alpha 156；夜晚 `#081a3b` alpha 208。

主机每次发布一帧的失效区域并集（1280×720 裁剪，`workshop_dirty` 与 GUI 共用）：

| 操作与条件 | 像素 |
|---|---:|
| 单只小兔走路，前进一帧 3 px | 3752 |
| 拖动 1×1 方块，光标位移 (8,4) px | 4896 |
| 30 格矩形连通块，最大速度下落 16 px | 76800 |
| 打开物品栏，世界静止 | 344160 |

验收命令均经 `flock /tmp/edrv32-sw-build.lock` 串行运行：
- `make -C sw -j2 PROGRAM=showcase`：通过，0 告警。
- `make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`：通过，0 告警。
- `make -C sw/tests/showcase workshop grab games`：全部通过，0 告警。
- `make -C sw/apps/showcase/sim -j2 workshop-shots WORKSHOP_OUTPUT=<截图目录>`：12 张通过。
- 日志：`build/workshop-acceptance/{showcase,showcase-cpu,host,screenshots}.log`；GCC 15.2.0 / host GCC 13.3.0。
- 截图：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/workshop/`。

删除清单：`ui/{phys.c/h,sprite_rot.c/h,tower.c/h,page_tower.c}`；
`sim/{main_tower_shots.c,geo_host.c}`；`assets/tower/` 全部；`tools/sw/compose_tower_blocks.py`；
`sw/tests/showcase/{phys.c,tower.c,tower_loop.c,tower_geo.c,tower_art.py,geo_model.h}`。
同时删除 GEO 角度帧辅助函数、DDR 旋转/暂存区和构建/测试规则；首页卡片仍名“体感积木”。
