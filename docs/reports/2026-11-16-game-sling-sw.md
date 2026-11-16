# T-GAME-SLING 软件原型（2026-11-16）

代码提交：本报告所在提交（`git log -1 --format=%H -- docs/reports/2026-11-16-game-sling-sw.md`）。
入口：首页顶栏「体感弹弓」；返回按钮或 Esc 回首页。
平台：rv32im / GCC 15.2.0，卡 75 硬件后处理目标；板上效果由协调者验证。

| 参数 | 初值 |
|---|---|
| 叉口 / 抓取半径 / 最大拉距 | (260,470) / 90 px / 180 px |
| 物理步长 / 定点单位 | 30 Hz / 1/256 px |
| 发射系数 / 重力 | 9 s⁻¹ / 900 px/s² |
| 预测轨迹 / 失手取消 | 18 步（0.6 s） / 15 个推理帧 |
| 弹丸 / 靶子 / 平台 | 5 / 6（木箱、气球各 3） / 3 |
| 碎片 / 消退 | 每靶 8 块、不旋转 / 24 步（0.8 s） |
| 木箱 / 气球得分 | 100（弹丸消失） / 50（穿透） |
| 星级 / 重开 | ≥400 三星、≥200 二星、其余一星 / 握拳 1 s 或按钮 |

| 精灵 | 尺寸 | ARGB8888 字节 |
|---|---|---|
| slingshot | 110×190 | 83,600 |
| ball | 56×56 | 12,544 |
| crate | 88×88 | 30,976 |
| balloon-coral / balloon-blue | 各 72×100 | 各 28,800 |
| platform | 180×28 | 20,160 |
| wood-chip / balloon-chip | 各 18×18 | 各 1,296 |
| star | 48×48 | 9,216 |

共 216,688 字节（不含小型描述符），小于 2 MB；均为原创 imagegen、8-bit RGBA 非隔行透明 PNG。
提示词与裁边、缩放命令见 `sw/apps/showcase/assets/sling/README.md`。

验证命令（先 `. ~/.local/opt/edrv32/env.sh`）：
- `make -C sw/tests/showcase sling grab`：PASS，抛物线相对解析解误差 0 px。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：PASS。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`：PASS。
日志：`build/sling-hw-build.log`、`build/sling-cpu-build.log`；硬件版 ELF：`build/sw/showcase/showcase.elf`。

局部刷新：静止平台/靶子为独立 `lv_image`，不在定时器中主动失效；只在击中/重开时切换可见性。
移动精灵刷新新旧矩形并集；皮筋只刷新包围区域，预测点/光标/调试点只刷新各自小区域。
碎片按物理步更新位置/透明度，禁止旋转；绘制 fps 按实际含游戏绘制的 LVGL 刷新完成事件计数。
复用 PAGE_GRAB 手势会话和原有模式 C 平滑输入（独立状态）；强制镜像，退出沿用其镜像恢复流程。
