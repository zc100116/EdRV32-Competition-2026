# 物理积木验收（2026-11-17）

- 实现 commit：`e3608a516`；恢复源：`a1b6fd783`；前后两次 rebase 到 `origin/zc100116/b3`（`6346f5c18`），均无冲突。
- 工具：xPack RISC-V GCC 15.2.0、Ubuntu GCC 13.3.0、Python 3.12.3、仓库锁定 LVGL 9.6.0。
- 条件：原生主机固定 60 Hz、种子 42、全尺寸几何；板目标 PG2L200H，本次未上板、未访问仿真虚拟机。
- 恢复独立自由玩法与 36 种积木；点赞保持 18 步召唤，24 块时最老块淡出 18 步，确认键也可召唤。
- 根因：轻微倾斜使零分离裁剪丢失双点支撑，8 次求解不收敛，球的角速度休眠阈值过严。
- 修复：0.5 px 接触皮肤、32 次求解、接触岛同步休眠；移除支撑时唤醒邻居。
- 方形 / 长条三角 / 球场景分别在第 73 / 39 / 41 步全休眠（1.217 / 0.650 / 0.683 s）。
- 三场景第 1.5–4.5 s 的逐块像素位置、角度帧变化均为 0；原求解器方形场景有 364 个样本偏离第 90 步快照。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：PASS，0 告警。
- `flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase phys tower`：PASS，含静止、支撑删除、抓取旋转、玻璃、召唤淡出及循环测试。
- 图集：1632 帧、117165144 bytes；首次 36 批、主机 CPU 1532 ms，重进不生成；仅首次打印 atlas 事件。
- GEO 合成最大 RGB 误差 10、alpha 误差 5，p99.9 RGB 误差 8；固定种子 3600 次召唤中球为 1148 次。
- 截图命令：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 tower-shots TOWER_OUTPUT=/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/physblocks`：PASS，已目视检查。
- 截图目录：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/physblocks/`；`stacked.png`、`falling.png`、`rotated.png`。
- 原始日志：本 worktree 的 `build/sw/tests/showcase/{firmware,acceptance,shots,baseline-regression}.log`。
- 调试记录：`docs/debug/2026-11-17-showcase-phys-jitter.md`；`git diff --check` 无问题，C 使用 `-Wall -Wextra -Werror`，无 RTL 改动。
- 方块工坊及首页大卡片入口保持；板上实际 FPS、物理耗时与硬件 GEO 时间留待上板串口实测。

## T-GRAB-EXP（2026-11-17）

- 代码提交：`680e3f894`；开始/结束两次 rebase 到 `origin/zc100116/b3`（结束 `5327b43f3`）；GCC 15.2.0 / 主机 GCC 13.3.0。
- 入口与串口名：抓取实验 / `game name=grablab`；80 px 方块与球各六材质，初始 3+3 件静止摆放。
- A–D 共用设置页判定与阈值；当步抓起、运动学零误差跟手、钢块可推物、放开速度上限 1200 px/s。
- 卡 95 录像约 26–29 s 撞堆后弹飞；修复中间角冲量 Q16.16 溢出，方块零弹性、近直角休眠对齐，保留橡胶球弹性。
- 主机同场景两倍动能峰值：中间值回绕对照 927430987，修复后 1898438；录像缺物理日志，不能确认板上唯一根因。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：PASS，0 告警。
- `flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase phys tower grab`：PASS；初始 180 步无移动、当步抓起、钢块误差 0、召唤在平台内。
- 图集 96 帧 / 4091352 bytes / 6 批；球不生成角度帧；首次加载估算 `11068×96/1632 = 651.1 ms`，未再次上板实测。
- 截图：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 tower-shots TOWER_OUTPUT="$PWD/outputs/grablab"`；三图已目视检查，标题字形齐全。
- 日志：`build/grablab/{build-final,tests-final,shots-final,probe-before,probe-after}.log`；截图：`outputs/grablab/{initial,steel-held,mode-d}.png`。
- 细节：`docs/debug/2026-11-17-showcase-phys-jitter.md` §8；`git diff --check` 通过，无 RTL 改动。
