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

## 8. T-GRAB-EXP：卡 95 碰撞后弹飞与抓取实验

### 现象与复现条件

实现代码提交：`680e3f894`，起始基线 `efaf1fa40`；完成时再次 rebase 到 `origin/zc100116/b3`（`5327b43f3`）。录像来自 `origin/win/20261117-95-workshop-board`（`aa7229acf`）的 `tasks/win/20261117-95-workshop-board/artifacts/video/QQ20261117-134147.mp4`。约 26–29 s，金属长条撞到金属砖和冰砖形成的堆叠后，整堆向上弹飞；画面光标为张手。约 30–39 s 还能看到橡胶三角落地反弹。前一段是新碰撞触发，录像不足以确认此前刚体是否已经休眠，也没有刚体状态日志可唯一确定板上数值根因。

```sh
mkdir -p build/grablab
git show origin/win/20261117-95-workshop-board:tasks/win/20261117-95-workshop-board/artifacts/video/QQ20261117-134147.mp4 > build/grablab/board.mp4
~/.local/opt/video/bin/ffmpeg -ss 23 -i build/grablab/board.mp4 -t 6 \
  -vf 'fps=4,crop=1300:400:300:550,scale=520:-1,tile=6x4' \
  -frames:v 1 build/grablab/landing.png -y
flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase phys tower grab
```

主机为 GCC 13.3.0、60 Hz、重力 900 px/s²、种子 42。`tower.c:impact_energy()` 复现同类全尺寸重物撞堆：冰方块中心 (640,580)，钢方块中心 (634,40)，钢方块初角 3688/65536 rad，运行 360 步。恢复中间值回绕（保留本次除法舍入）的对照两倍动能峰值为 927430987（第 148 步）；修复后为 1898438（第 60 步），约差 488 倍。原始对照数据在 `build/grablab/probe-{before,after}.log`；前者只把 `angular_impulse()` 的返回式替回 `mul((phys_q)(torque/PHYS_ONE),inverse)`，其余代码相同。

单角接触回归 `heavy_corner()` 中，钢块以 1200 px/s 落下且仅右下角接触平台：中间值回绕对照得到竖直速度 −12295 px/s、角速度 +338 rad/s；修复后为 +707 px/s、−18 rad/s，右下角向上冲量产生正确的负角速度。替回中间值回绕运算运行同一规则测试会在该断言失败，日志为 `build/grablab/torque-before.log`。

### 根因与修复

确认的代码缺陷位于 `phys.c:impulse()`：旧代码先把 `r × impulse` 缩成 Q16.16 的 `phys_q`，再乘逆惯量。全尺寸钢物体的冲量乘力臂可超过该中间值的 ±32768 范围，回绕后改变角冲量方向，接触求解继续注入能量。现在保留 64 位扭矩到乘逆惯量之后才缩回 Q16.16；普通冲量、热启动和分离修正共用这一计算。主机对照确认了该缺陷；它与录像撞堆弹飞相符，但板上录像本身不能证明唯一因果。

方块弹性统一为 0；非橡胶球维持 0.02–0.05 的小弹性，橡胶球保留 0.8。休眠方块角度距 90° 整数倍小于 4° 时对齐，并同步更新碰撞几何。仍保留碰撞转动、整岛休眠和删除支撑时的唤醒。

抓取删除停留计数、进度环和弹簧：`grab_rule()` 导出设置页同一组 A/B/C/D 判定和阈值，实验页直接使用判定结果，不经过设置页的连续帧等待；设置页原有平滑、滞回和等待行为不变。命中形状外扩 12 px 的当步即转为运动学体，位置精确等于光标加抓取偏移，接触仍能推开其他动态体。放开恢复动态质量和逆惯量，继承光标移动速度，上限 1200 px/s；剪刀手在四种模式中均保留 90° 旋转。

### 防回归与同类排查

`tower` 新增初始 3 方块/3 球静止 180 步、当步拾取、钢块跟手零误差、推动睡眠邻居、抛出限速、4° 休眠角度边界、召唤全形状在平台内和钢块撞冰块能量上界测试；保留召唤保持、24 件淡出、旋转重新触发、移除支撑、玻璃高低落差和三场景稳定性检查。`grab` 同时验证导出的四种原始判定及设置页旧行为。球始终直接显示零度原图，物理角度继续积分；方块六种材质各生成 16 帧，共 96 帧，按卡 95 的 11068 ms / 1632 帧估算为 651.1 ms，尚未再次上板实测。

原生 LVGL 截图在 `outputs/grablab/{initial,steel-held,mode-d}.png`。截图发现粗体标题缺“实、验”，经协调器授权保留全部原字形并补充指定字符，检查四字标题均非占位字形；字形结果由协调器先提交为 `5327b43f3`，本分支在第二次 rebase 时直接复用；没有修改共享布局。构建、验收、截图日志分别在 `build/grablab/{build-final,tests-final,shots-final}.log`。
