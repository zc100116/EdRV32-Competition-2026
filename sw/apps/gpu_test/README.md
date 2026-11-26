# GPU 上板小游戏

`gpu_test.elf` 包含四个原创场景：Prism Patrol、Candy Canyon、棱炉地宫、云脊漫游。
G-3 采用经用户确认的现代卡通像素画风：深色描边、2～3 阶明暗、白青主角、亮芯发光效果；
2D 用深蓝紫星云衬托敌机，3D 用暖橙岩壁、金色沙路与蓝紫天空。

```sh
. ~/.local/opt/edrv32/env.sh
PYTHONDONTWRITEBYTECODE=1 make -C sw/apps/gpu_test board linux windows -j1
make -C sw/apps/gpu_test hud-test -j1
python3 sw/apps/gpu_test_common/tools/controls_test.py
python3 sw/apps/gpu_test_common/tools/capture.py
```

三个目标输出到 `build/gpu_test/`：`gpu_test.elf`、`gpu_test`、`gpu_test.exe`。
预览和构建日志位于 `outputs/gpu-test-games-20261126/`，不入库。Windows 默认 1280×720，
`--half` 为 640×360。PC 使用功能参考模拟器，测量值不代表板端帧率；不运行 RTL / SoC 仿真。

## 操作

| 操作 | 板上按键 | Windows / ETH 虚拟手柄 |
|---|---|---|
| next / 向右 | GPIO bit0 | → / VI_RIGHT、VI_NEXT |
| prev / 向左 | GPIO bit1 | ← / VI_LEFT、VI_PREV |
| enter / 确认 | GPIO bit2 | Enter 或 Z / VI_A、VI_ENTER |
| esc / 返回开机菜单 | GPIO bit3 | Esc / VI_START、VI_SELECT、VI_ESC |
| 上下移动 | ETH 输入 | ↑↓ / VI_UP、VI_DOWN |

开机左右选 2D / 3D，enter 开始。场景中左右移动，ETH/Windows 支持四向；2D 自动开火，
3D 穿环和收集水晶加分。没有 UART 输入。

enter 打开控制菜单，左右选择、enter 应用；菜单冻结游戏：

1. 模式：正常 → 压测 → CPU 对比（2D）/ 纹理测试（3D）。
2. 负载：增加一档，最高档后回第一档。
3. AA：开关抗锯齿，选“继续”返回。
4. 2D 切 CPU/GPU，3D 切最近邻 / 双线性 / 三线性，选“继续”返回。
5. 2D 切散射 / 激光 / 追踪导弹；3D 切材质 / 棋盘；应用后返回。
6. 继续游戏。

## 画面与负载

2D 正常和 CPU 对比为 **310 对象：12 敌机、18 玩家弹、280 敌弹**。三种敌机轮廓、
颜色和运动各异，玩家 32×32，Boss 128×96，四个独立部件用三角形网格旋转并沿三角形路径移动。
每 240 tick 切换放射 / 螺旋 / 波浪弹幕，分别为珊瑚 / 紫 / 金色，切换时震动。
敌弹 8×8，白亮芯加彩色光晕；玩家散射是细长青色束，激光贯穿、导弹转向并拖尾。
四帧尾焰、八帧爆炸、碎片、火花、闪烁掉落物、透明护盾和彩色伤害字共用统一素材。
普通命中使用短火花，爆炸与伤害字保留清楚的层次；角色受击白闪。
背景包含大图星云、两层视差星点、带边缘光的行星和少量不透明描边陨石。

2D 压测档仍为 1000、2000、5000、10000、20000、50000、100000 对象，全部使用同一发光贴图，
随密度降低单弹 alpha。100000 是应用 DDR 预算上限，硬件 COUNT 为 24 位。
对象运动、碰撞、释放由 OBJ_STEP 执行；CPU 对比使用相同状态与算法。
碰撞目标为玩家、Boss 与前 6 个敌人。玩家/Boss HP 归零后补满，供连续观测。

3D 正常有 64 个侧路岩石/水晶，另有地形、光环、航道水晶、玩家和 3 架无人机，约 4500 三角形。
压测档为 420、600、900、1200、1600、2100、2600 个侧路物体，最高约 5.5 万三角形。
玩家飞船为项目自建 **176 三角形**模型：机身、双引擎、掠翼、驾驶舱和尾翼，带贴图与尾焰粒子；
无人机 48 三角形，开火有弹光。岩石为有扰动的多面体，水晶为尖顶五棱柱。
峡谷用大块岩层与沙地纹理、远处雾色、渐变天空和云层，光环有连续光晕和放射状发光粒子。
受击屏幕泛红并震动，高速有速度线。保留中文任务面板与方向框。

穿环 +100，收集航道水晶 +25，错过环 -5 HP，无人机命中 -8 HP。
纹理测试使用沙地材质，控制菜单可切棋盘，并比较三种过滤模式。
游戏 HUD 使用生成面板边框和图标，测试模式、对象/三角形数、FPS、CPU/GPU 耗时为左下角半透明一行。
GPU n/a 在参考模型中以 0 us 显示；不从 PC 墙钟推算板端性能。

## 共用素材和来源

关键素材均为 **Codex imagegen 生成，项目自有**；原始 PNG 入库，构建时统一处理。
玩家/敌机/Boss、四帧尾焰、盾、掉落物、弹光、激光、八帧爆炸、星云/行星、UI 边框/图标、
3D 沙地/岩层/矿岩/机体表面全部由这套素材派生。旧 Kenney 素材已替换。

- [共用 STYLE](../gpu_test_common/assets/STYLE.md)：画风、尺寸、处理参数与复用方法。
- [共用 72 色调色板](../gpu_test_common/assets/palette.json)。
- [2D STYLE / 提示词](../gpu_test2d/assets/STYLE.md)、[2D SOURCES](../gpu_test2d/assets/SOURCES.md)。
- [3D STYLE / 提示词](../gpu_test3d/assets/STYLE.md)、[3D SOURCES](../gpu_test3d/assets/SOURCES.md)。
- [字体 SOURCES](../gpu_test_common/assets/SOURCES.md)：Fusion Pixel 12px、63 字中文子集，SIL OFL 1.1；ASCII 为 BSP public-domain 字体。

`gpu_test_common/tools/art.py` 可供后续 demo import：PNG 读写、分格裁切、面积缩小、
alpha 加权、固定调色板、去孤立杂点、1 像素深色描边。只用 Python 标准库。
`assets.py` 使用同一套处理函数并打包 GPU atlas；所有处理产物仅在 `build/gpu_test/generated/`。

## 纹理 RAM / DDR 预算

固定 640×360，两个 640×180 条带，同一 L0 Surface，经 DISP L0_X2 放大；HUD 由 GPU 绘制。
纹理启动装入一次，**每帧 TEX_LOAD = 0 B**。

| 纹理（含硬件块对齐） | OFFSET | 字节 |
|---|---:|---:|
| I8 atlas 0：角色、8 帧爆炸、发光、UI、ASCII / 中文 | 0 | 65536 |
| I8 atlas 1：Boss、星云、行星、陨石、掉落物、云 | 65536 | 65536 |
| RGB565 沙地 64×64，7 级 mip，含 16 B 链间填充 | 131072 | 10944 |
| RGB565 暖橙岩层 64×64，7 级 mip，含填充 | 142016 | 10944 |
| RGB565 紫色矿岩 64×64，7 级 mip，含填充 | 152960 | 10944 |
| RGB565 棋盘 64×64，7 级 mip，含填充 | 163904 | 10944 |
| RGB565 机体/无人机/水晶 64×64，7 级 mip，含填充 | 174848 | 10944 |
| **合计 / 硬件容量** | | **185792 / 196608** |

余量 **10816 B**。每条实际 mip 链为 10928 B，按 `Σ 8×ceil(w/2)×ceil(h/2)` 计算，
最后 1×1 级占 8 B，额外 16 B 确保下一 OFFSET 按 32 B 对齐。
调色板 16×256×4 = 16384 B，独立于纹理 RAM，也只启动装载。

| DDR 动态分配项 | 字节 |
|---|---:|
| 命令 512×32 | 16384 |
| 四边形 8192×16 | 131072 |
| 顶点 60000×3×16 | 2880000 |
| 对象表 100000×32 | 3200000 |
| 命中 / 释放列表 | 800000 |
| 两个 RGB565 Surface | 921600 |
| CPU AA 原图 | 460800 |
| 纹理源、调色板、矩阵 | 202304 |
| AUD 环 | 32768 |
| 合计（不含分配对齐空洞） | 8644928 |

平台静态保留 64 MiB DMA pool，应用实际申请约 8.24 MiB，另有只读素材、程序、栈与 heap。
每帧 Surface 共 460800 B；PERF[4] 为通过全部测试的像素数，不含 CLEAR/RESOLVE。
四种音效为项目整数方波包络，经 AUD/ES8156 播放。

## Headless 和截图复现

```sh
mkdir -p build/gpu_test/example
build/gpu_test/gpu_test --scene 1 --frames 26 --shot boss --out build/gpu_test/example
build/gpu_test/gpu_test --scene 1 --tick 240 --frames 36 --out build/gpu_test/example
build/gpu_test/gpu_test --scene 2 --frames 27 --shot ring --out build/gpu_test/example
```

`--scene`：0 菜单 / 1 2D / 2 3D；`--mode`：0 正常 / 1 压测 / 2 CPU 对比或纹理测试；
`--level 0..6`，`--filter 0..2`。`--frames N` 默认仅保存末帧，`--sequence 1` 保存每一帧。
输出目录须存在。CSV 包含负载、提交三角形、命令、像素计数、耗时和完整模式状态。

`--tick N` 从指定弹幕阶段开始，`--weapon 0..2` 直接选择三种武器。
`--shot boss|explosion|ring|hit|drone` 在第 20 帧触发实际场景的对应效果，截图保留其真实演变。
`--input file` 每行 `帧编号 按键十进制位图`：UP=1、DOWN=2、LEFT=4、RIGHT=8、ENTER=16、ESC=128。
捕获脚本使用固定、无随机状态的场景和输入；不会把同一帧复制成不同效果截图。

`capture.py` 重做 19 张截图：2D 正常、Boss、爆炸、螺旋、波浪、三种武器、最高压测、CPU；
3D 正常、无人机、穿环、受击、最高压测，以及最近邻、双线性、三线性、棋盘四种纹理视图。
2D / 3D 正常与 2D CPU 各有一份 **180 个连续游戏帧**、60 tick/s、3 秒 ZIP；序列不注入截图效果。
设定图 `style2-*.png` 保留为画风记录，验收截图来自修改后程序的真实渲染。

## G-4 新增 demo

开机菜单左右循环选择四项：Prism Patrol、Candy Canyon、棱炉地宫、云脊漫游。
新 demo 的操作和独立资源预算见 [肉鸽 README](../gpu_test_rogue/README.md) 与
[开放世界 README](../gpu_test_world/README.md)。新 demo 短按确认执行翻滚/停驻，
长按30个tick打开中文控制菜单；原两个 demo 保持短按确认开菜单。Esc统一回开机菜单。

公共诊断行现在用原生8×16 ASCII与12×12中文四边形绘制，取消3/4最近邻缩小造成的
笔画丢失，显示“正常 对象/三角形 … FPS … CPU … ms GPU … us”。原2D Boss弹幕名为
放射/螺旋/波浪。共享字形从54增至63；新场景使用独立75字子集。

```sh
make -C sw/apps/gpu_test_rogue state-test -j1
make -C sw/apps/gpu_test_world state-test -j1
python3 sw/apps/gpu_test_rogue/tools/controls_test.py
python3 sw/apps/gpu_test_rogue/tools/capture.py rogue
python3 sw/apps/gpu_test_rogue/tools/capture.py world
```

headless `--scene` 扩为0菜单/1原2D/2原3D/3肉鸽/4开放世界。
新shot为肉鸽combat/slash/boss/choice/minimap，世界day/dusk/coast/landmark/lod；
压测仍用`--mode 1 --level 0..2`。新场景每次进入会重新装载185792B公共布局，
之后每帧TEX_LOAD=0B；原两场景切入时恢复原纹理和中文子集。
