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


## T-WS-POLISH（本节所在提交，基线 c52cbe2b6）
- 环境亮度 100/70/40%；光源半径 144 px，以距离平方的二次衰减逐像素恢复亮度，灯窗全亮，光晕叠在墙面上。
- 天色切换整体重建；方块变化只更新相应格子，光源增删/移动更新新旧半径内格子，同次更新去重。
- 光标 48 px，指尖/镐尖对齐原判定位置，目标浅色框；手旁 24 px 物品图标；预览 alpha 153、四边 2 px 绿/红框。
- 贴纸摘要仅保留“套装：名称”，两个原生截图断言同步修改；未改世界规则或输入判定。
- 主机 GCC 13.3.0、O2、clock() 单次整层重建：小屋夜晚 4.055 ms，城堡夜晚 5.940 ms（均包含光晕）。
- 城堡夜晚像素计数：着色 N=244224，光源采样 S=976896，半径内采样 I=211732；清屏 C=658944、光晕预算 G=82944。
- RV32 估算基本操作数 O=32N+12S+24I+40G+C=28596192；假定平均 3 周期/操作，光晕每像素额外三次 33 周期除法。
- 像素循环估算 (3O+99G)/100MHz=0.940 s，计入格子遍历约 1 s；仅为模型估算，不含 DDR 等待，频率变化按 100MHz/f 缩放。
- 验收：两种 showcase 构建、workshop/sticker 主机测试全部通过，0 告警；日志 `build/workshop-polish/`；原生 workshop 13 张、compact 16 张；截图位于上述 workshop 目录和同级 `ui-compact/`。

- T-WS-LIGHT-PERF：K=6；8 px 粗亮度图分帧生成，普通 GUI 更新估算预算 380000 周期，单格编辑优先。
- 前轮主机记录：小屋黄昏25帧、小屋夜晚19帧、城堡夜晚29帧；最终构建/测试/截图按协调者要求停止，由协调者构建上板。
- 与旧 ARGB8888 格子缓存比较，RGB 最大误差5、alpha误差0，协调者已接受；当前代码直接提交，未宣称最终验收通过。

- T-FARM-LAG-OK（本节所在提交）：物品栏开关恢复为 OK（class 7），保持 48 个 60 Hz 逻辑帧即 0.8 s；保留进度环、换手势取消和单次保持只触发一次，顶栏共用提示同步为“OK 保持 0.8 s”。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase` 与 `flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase farm workshop` 通过、0 告警；日志 `build/farm-lag/{build,tests}.log`，覆盖点赞不触发、OK 24/47/48 帧、取消、持续保持和再次开关。
