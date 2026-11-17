# 物理积木叠放后抖动

## 1. 现象

卡 94 上板反馈：已经放在其他积木上的积木仍跳动。恢复 `a1b6fd783` 的物理后，完全对齐的主机场景可以休眠；加入实际放置会产生的 ±0.03 rad 倾角和 1–5 px 落差后，五块 80 px 方形塔持续摇摆。

## 2. 复现

恢复源 `a1b6fd783`，集成基线 `6346f5c18`，修复代码 `e3608a516`。Ubuntu GCC 13.3.0、Python 3.12.3，原生 C 主机测试，不使用 SoC 仿真器；固定种子 42，60 Hz，重力 900 px/s²。

```sh
flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase phys tower
```

`sw/tests/showcase/tower_scenes.h` 固定三组初始位置与倾角：五方形塔、三长条加两三角、两方形之间落下三球。`tower.c:stability()` 先运行 90 步，再比对后续 180 步逐块快照的整数 x/y 和角度帧。

替换为原求解器可复现失败（在已构建图像数据后执行）：

```sh
git show a1b6fd783:sw/apps/showcase/ui/phys.c > build/sw/tests/showcase/phys-old.c
flock /tmp/edrv32-sw-build.lock cc -std=c11 -O2 -Wall -Wextra -Werror -ffunction-sections -Wl,--gc-sections \
  -Isw/apps/showcase/ui -Isw/apps/showcase/board -Isw/drivers/include -Isw/bsp/include \
  sw/tests/showcase/tower.c sw/tests/showcase/tower_geo.c sw/apps/showcase/ui/tower.c \
  build/sw/tests/showcase/phys-old.c sw/apps/showcase/ui/sprite_rot.c sw/drivers/geo.c \
  -o build/sw/tests/showcase/tower-old
stdbuf -o0 build/sw/tests/showcase/tower-old build/sw/tests/showcase/tower-art.bin
```

## 3. 观察

原求解器：方形塔在第 90 和 270 步都还有 5 块醒着，第 91–270 步中有 364 个块显示样本与第 90 步快照不同，角度帧一直为 0；长条结构第 48 步休眠；球场景第 144 步才全部休眠。关节 ID 始终为 -1。

接触跟踪显示平台支撑面会从 2 点变为 1 点再回到 2 点；其中一个角点刚越过零分离时被删除。原代码已有近邻接触匹配和冲量热启动，不是缺少缓存。仅加入 0.5 px 接触皮肤、沿用 8 次迭代时，方形塔仍要 196 步才休眠；同一场景改为 32 次迭代后为 73 步。

| 场景 | 修复后全部休眠 | 1.5–4.5 s 显示变化 |
|---|---:|---:|
| 5 方形 | 73 步 / 1.217 s | 0 |
| 3 长条 + 2 三角 | 39 步 / 0.650 s | 0 |
| 3 球落入 2 方形之间 | 41 步 / 0.683 s | 0 |

原始输出在 `build/sw/tests/showcase/{baseline-regression.log,jitter-before-final-scenes.log,jitter-contacts-before.log,acceptance.log}`。接触跟踪的早期实验在添加倾角后首步更新几何；最终三场景在创建刚体时就使用正确的倾角和顶点，避免依赖过期 AABB。

## 4. 根因

`ui/phys.c:polygons()` 原先只接纳 separation ≤ 0 的角点，轻微摇摆便丢失双点支撑；8 次顺序冲量迭代不足以收敛全尺寸堆叠，使线速度、角速度振荡，持续重置休眠计数。球的 0.01 rad/s 角速度阈值又使不到 1 px/s 的低速滚动迟迟不能休眠；显示角度量化和光标关节不是此次复现的根因。

## 5. 修复

多边形 SAT、接触裁剪和宽相位使用同一 0.5 px 接触皮肤，保留亚像素分离时的双点支撑；保持原有接触缓存、热启动和分离冲量位置修正，速度求解改为 32 次迭代。连续 30 步的休眠阈值改为线速度 3 px/s（每步 0.05 px）、角速度 1638/65536 rad/s，整座接触岛一起休眠；睡眠期间不积分位置或角度。

删除支撑体时先唤醒接触邻居，防止玻璃破碎或最老积木淡出后上层悬空。没有增加显示位置锁定、角度帧滞回、特殊场景分支或关节兜底。

## 6. 防回归

`tower.c:stability()` 检查三场景 90 步以内全睡眠、后续 180 步逐块显示位置与角度帧不变，并检查移除底层支撑后上层会落下。保留 `phys` 的接触、十层塔、斜坡、弹性、抓取旋转、移动平台倒塌、拱形和确定性测试；规则测试检查召唤保持/重置、抓取时抑制、24 块淡出、玻璃破碎和所有 36 种几何。

## 7. 同类排查

检查了圆形与多边形、圆形与圆形、复合拱形接触、热启动匹配、抓取释放和接触岛唤醒路径。圆形采用解析接触，保留其原算法；修复后的球场景满足相同静止判据。未访问仿真虚拟机，板上实际帧率和物理耗时等待后续上板串口实测。
