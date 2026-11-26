# GPU 上板小游戏

`gpu_test.elf` 含两个原创测试场景：Prism Patrol（俯视弹幕射击）与 Candy Canyon
（低多边形峡谷飞行）。保留正常、压测及 CPU/纹理对比三种模式。代码和素材生成器位于
`gpu_test_common/`、`gpu_test2d/`、`gpu_test3d/`，不链接 ember_isles。

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/gpu_test board linux windows -j1
python3 sw/apps/gpu_test_common/tools/capture.py
```

构建产物：`build/gpu_test/gpu_test.elf`、`gpu_test`、`gpu_test.exe`。
预览与测量：`outputs/gpu-test-games-20261126/README.md`。Windows 可直接运行预览目录中的 exe；
`--half` 开 640×360 窗口，默认 1280×720。PC 使用功能参考模拟器，帧率低属正常，不能用作板端性能结论。
不运行 RTL 或 SoC 仿真。

## 操作

| 操作 | 板上按键 | Windows / ETH 虚拟手柄 |
|---|---|---|
| next / 向右 | GPIO 按键 bit0 | → / VI_RIGHT、VI_NEXT |
| prev / 向左 | GPIO 按键 bit1 | ← / VI_LEFT、VI_PREV |
| enter / 确认 | GPIO 按键 bit2 | Enter 或 Z / VI_A、VI_ENTER |
| esc / 返回开机菜单 | GPIO 按键 bit3 | Esc / VI_START、VI_SELECT、VI_ESC |
| 上下移动 | ETH 输入 | ↑↓ / VI_UP、VI_DOWN |

开机 next/prev 选 2D/3D，enter 开始；场景内左右移动，2D 自动射击，3D 穿过光环得分。
只有板上四键时仍可横向游玩；ETH 提供完整四向移动。不使用 UART 输入。
场景内 enter 打开控制菜单，next/prev 选择条目，enter 应用：

1. 模式依次为正常、压测、CPU 对比（2D）或纹理测试（3D）。切模式回到场景。
2. 增加负载档，最高档后回到第一档。切档回到场景。
3. AA 开关，应用后选择 RESUME 返回。
4. 2D 在当前场景状态上切 CPU/GPU；3D 切最近邻、双线性、三线性。选择 RESUME 返回。
5. 武器切换 / 棋盘切换：2D 循环散射、激光、追踪导弹；3D 在纹理测试视图中切换草地与棋盘。应用后回到场景。
6. 继续：恢复场景；控制菜单期间冻结游戏。

2D 正常/CPU 对比 1500 个对象；压测档 1000、2000、5000、10000、20000、50000、100000。
100000 是协调者确认的应用 DDR 预算上限，**不是硬件对象上限**；COUNT 编码为 24 位。
Boss 每 240 帧在放射、螺旋、波浪弹幕间循环，四个旋转缩放部件走三角形路径。
玩家飞船、三种敌机、Boss、尾焰三帧、护盾和掉落物均为 CC0 贴图；敌机分别做正弦、
折返、快速侧摆运动。散射弹分叉、激光有贯穿画面的束光，追踪导弹转向 Boss 并带粒子拖尾。
对象运动、碰撞与释放仍由 OBJ_STEP 执行；CPU 对比使用相同状态和运动算法。
敌机用 Alpha 混合，所有子弹（含 100k 压测）用有透明渐变的 I8 发光核与加色混合。
压测随档位降低单弹透明度，保留密集叠加的层次，子弹尺寸和对象数量不变。
背景为滚动星空、Alpha 星云、远景行星和近景陨石；不会每帧装载纹理。

命中产生四帧爆炸、径向碎片、彩色伤害飘字（放大后回弹），受击机体白闪及画面震动。
击破敌机掉落加分星或回血胶囊，靠近拾取；玩家有护盾光环。中文 HUD 含武器名、得分、
血量条、赤焰核心名称与 Boss 血条；小字继续显示对象数、FPS、CPU/GPU 耗时。
玩家受击短暂无敌，HP 归零后原地补满；Boss 被打空后补满并加分，便于连续上板观测。
8 个碰撞目标为玩家、Boss 和编队前 6 个敌人；其余编队仍由对象硬件运动。

3D 正常为 240 个漂浮岩石/五棱水晶，加地形、实体环、飞行器、无人机及光效，约 7600 三角形。
压测数量仍为 420、600、900、1200、1600、2100、2600，最高约 5.5 万三角形。
草地、岩石、沙地使用真实 CC0 纹理和七级 mipmap；GPU 执行透视纹理、顶点法线光照，
远景通过顶点色混入雾色。天空为阶梯渐变加半透明云层，峡谷中央为 Alpha 水面光带。
岩石是旋转二十面体；水晶为尖顶五棱柱，飞行器和移动无人机为带 UV 的真实三角形网格。
引擎尾焰、光环发光、水晶闪光、收集与穿环爆发、速度线均走 GPU 加色纹理/三角形路径。
无人机发射可躲避弹体，命中扣血、屏幕泛红及震动；中文任务提示显示下一个环、距离、
速度，右上方向框显示玩家与目标的相对位置。

穿环加 100 分，收集航道水晶加 25 分；错过环扣 5 HP，无人机命中扣 8 HP。
纹理测试默认真实草地，通过控制菜单第五项切换棋盘；最近邻、双线性、三线性仍由第四项切换。

## 渲染与测量

固定 640×360、两个 640×180 条带，同一 L0 Surface，DISP L0_X2 放大。
HUD 始终由 GPU 绘制。CPU 对比保留同一场景对象状态，CPU 用整数软件精灵/三角形绘制与
同算法后处理 AA 写入同一对 RGB565 Surface；GPU 只覆盖顶端 52 行与底端 24 行的 HUD。
软件三角形边界和颜色舍入与参考 GPU 可能相差少量像素，不是逐像素等价回归。

FPS 是相邻帧开始的实际时间差；CPU ms 为 CPU 更新、命令构造、cache 维护和软件渲染耗时，
板端扣除等待 GPU 完成的时间；PC 另扣除同步执行 GPU 参考模型的提交调用；GPU µs 为所有本帧批次的 PERF[0] 差值 / 180 MHz（向上取整）。
HUD 显示前一帧耗时；第一帧没有 FPS 样本。模拟器周期计数为 0 时 GPU 显示 n/a。
GPU 频率上板若变更，应同步修改运行时的 180 周期/µs 换算。
CPU 模式的 GPU 耗时/像素只计 HUD，CPU 场景时间计入 CPU ms。
CPU 与 Windows 时钟分辨率为 µs，板端使用 CLINT。

## 资源预算

纹理预算在出图前按两个 256×256 I8 图集及五条 RGB565 mip 链固定，所有模式共驻留：

| 纹理 RAM 项 | 偏移 | 字节 | 装入时机 |
|---|---:|---:|---|
| I8 256×256：角色、三敌机、Boss、尾焰、爆炸、发光、ASCII/中文 HUD | 0 | 65536 | 启动一次 |
| I8 256×256：行星、星云、陨石、云、掉落物 | 65536 | 65536 | 启动一次 |
| RGB565 草地 64×64，七级 mip | 131072 | 10928 | 启动一次 |
| RGB565 岩石 64×64，七级 mip | 142016 | 10928 | 启动一次 |
| RGB565 沙地 64×64，七级 mip | 152960 | 10928 | 启动一次 |
| RGB565 棋盘 64×64，七级 mip | 163904 | 10928 | 启动一次 |
| RGB565 飞行器/无人机/水晶表面 64×64，七级 mip | 174848 | 10928 | 启动一次 |
| 尾部对齐填充 | 185542 | 16 | 启动一次 |
| 合计 | | **185792 / 196608** | **每帧 TEX_LOAD = 0 B** |

余量 10816 B；调色板 16×256×4 = 16384 B，不计入纹理 RAM，PAL_LOAD 仅启动时。
每条 mip 链按 `Σ 8×ceil(w/2)×ceil(h/2)` 计入 2×2 块补齐，最后 1×1 级占 8 B；每链额外补 16 B，确保下一个 OFFSET 按 32 B 对齐。
`gpu_test_common/tools/assets.py` 用 Python 标准库解 PNG（含过滤器）、解析 BDF、最近邻缩小、
I8 固定调色板量化、RGB565 转换及 2×2 平均 mipmap，输出只在 `build/gpu_test/generated/`。

外部源素材与许可分别记录于：

- [2D SOURCES](../gpu_test2d/assets/SOURCES.md)：Kenney Space Shooter Remastered 和 Planets，CC0。
- [3D SOURCES](../gpu_test3d/assets/SOURCES.md)：Kenney Retro Textures Fantasy，CC0。
- [字体 SOURCES](../gpu_test_common/assets/SOURCES.md)：Fusion Pixel 12px、54 字中文子集，SIL OFL 1.1。

仅保留实际使用的源 PNG/BDF 与许可，合计小于 0.5 MiB；未入库下载脚本。
ASCII 复用 `sw/lib/font8x16.h` 的 public-domain console-setup 字体。
星云、云、发光、爆炸帧及棋盘由脚本生成。四种短音效为整数方波包络，通过 AUD/ES8156 播放。

| DDR 动态分配项 | 字节 |
|---|---:|
| GPU 命令（512×32） | 16384 |
| 四边形（8192×16） | 131072 |
| 三角形顶点（60000×3×16） | 2880000 |
| 对象表（100000×32） | 3200000 |
| 命中 / 释放列表（各100000×4） | 800000 |
| 两个 RGB565 Surface | 921600 |
| CPU AA 原图 | 460800 |
| 纹理源、调色板、矩阵 | 202304 |
| AUD 环 | 32768 |
| 合计（不含分配对齐空洞） | 8644928 |

平台 board.c 静态保留 64 MiB DMA pool；本应用实际申请约 8.24 MiB，另有只读生成纹理、
程序、栈和 newlib heap。目标实际使用量见 ELF size；不把整个平台保留池说成已使用纹理。
每帧写出 RGB565 共 460800 B；对象表每次 STEP 读写，条带绘制再读表。
模型中逐像素计数为 PERF[4]（通过全部测试的像素，不含 CLEAR/RESOLVE）；不换算成板端带宽。

## Headless 复现

```sh
mkdir -p build/gpu_test/example
build/gpu_test/gpu_test --scene 2 --mode 1 --level 6 --filter 2 \
  --frames 180 --sequence 1 --out build/gpu_test/example
```

scene：0 菜单 / 1 2D / 2 3D；mode：0 正常 / 1 压测 / 2 CPU 对比或纹理测试。
`--sequence 1` 保存全部帧，默认只保存最后一帧。输出目录须已存在。
CSV 包含对象、提交三角形、GPU 命令、通过测试像素、CPU/GPU 时间及模式状态。
`--input file` 接受每行 `帧编号 按键十进制位图`，按键沿触发菜单，零位图释放全部键。
位图按 `plat.h`：UP=1、DOWN=2、LEFT=4、RIGHT=8、ENTER=16、ESC=128。

## G-2 验收

```sh
make -C sw/apps/gpu_test board linux windows -j1
make -C sw/apps/gpu_test hud-test -j1
python3 sw/apps/gpu_test_common/tools/controls_test.py
python3 sw/apps/gpu_test_common/tools/capture.py
```

截图覆盖全部模式、三种武器、爆炸/Boss 血条、无人机及穿环特效；正常模式各 180 连续帧 ZIP。
截图与构建日志放在 `outputs/gpu-test-games-20261126/`，不提交。
PC 截图为功能参考模型的确定性游戏 tick，不代表板端帧率；板上实测仍需硬件。
