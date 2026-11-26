# GPU 上板小游戏

`gpu_test.elf` 含两个原创测试场景：Prism Patrol（俯视弹幕射击）与 Candy Canyon
（低多边形峡谷飞行）。没有关卡、存档或成长系统。代码和素材生成器位于
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
| next / 向右 | GPIO 按键 bit0 | → / VI_RIGHT |
| prev / 向左 | GPIO 按键 bit1 | ← / VI_LEFT |
| enter / 确认 | GPIO 按键 bit2 | Enter 或 Z / VI_A |
| esc / 返回开机菜单 | GPIO 按键 bit3 | Esc / VI_START 或 VI_SELECT |
| 上下移动 | ETH 输入 | ↑↓ / VI_UP、VI_DOWN |

开机 next/prev 选 2D/3D，enter 开始；场景内左右移动，2D 自动射击，3D 穿过光环得分。
只有板上四键时仍可横向游玩；ETH 提供完整四向移动。不使用 UART 输入。
场景内 enter 打开控制菜单，next/prev 选择条目，enter 应用：

1. 模式依次为正常、压测、CPU 对比（2D）或纹理测试（3D）。切模式回到场景。
2. 增加负载档，最高档后回到第一档。切档回到场景。
3. AA 开关，应用后选择 RESUME 返回。
4. 2D 在当前场景状态上切 CPU/GPU；3D 切最近邻、双线性、三线性。选择 RESUME 返回。
5. RESUME 恢复场景；控制菜单期间冻结游戏。

2D 正常/CPU 对比 1500 个对象；压测档 1000、2000、5000、10000、20000、50000、100000。
100000 是协调者确认的应用 DDR 预算上限，**不是硬件对象上限**；COUNT 编码为 24 位。
Boss 每 240 帧在放射、螺旋、波浪弹幕间循环，旋转缩放部件走三角形路径。
玩家受击短暂无敌，HP 归零后原地补满；Boss 被打空后补满并加分，便于连续上板观测。
子弹/敌人由 OBJ_STEP 推进、碰撞和释放，CPU 消费命中/释放列表后补槽。
8 个碰撞目标为玩家、Boss 和编队最前排 6 个敌人；其余编队对象仍走对象硬件运动。
粒子走加色混合，子弹走 Alpha 混合，HUD/飘字走四边形。

3D 正常为 240 个二十面体 + 地形 + 实体环 + 飞行器，约 7100 三角形。
压测岩石档 420、600、900、1200、1600、2100、2600，约 1.1 万至 5.4 万三角形。
地形是连续三角网格；岩石旋转、环有实体管壁、飞行器为三角网格，均不是公告板。
顶点法线光照、RGB565 顶点色远雾、七级 mipmap 与透视投影均由 GPU 路径执行。
错过环扣 5 HP，穿环加 100 分；不实现岩石碰撞或任务流程。

## 渲染与测量

固定 640×360、两个 640×180 条带，同一 L0 Surface，DISP L0_X2 放大。
HUD 始终由 GPU 绘制。CPU 对比保留同一场景对象状态，CPU 用整数软件精灵/三角形绘制与
同算法后处理 AA 写入同一对 RGB565 Surface；GPU 只覆盖顶端 52 行与底端 24 行的 HUD。
软件三角形边界和颜色舍入与参考 GPU 可能相差少量像素，不是逐像素等价回归。

FPS 是相邻帧开始的实际时间差；CPU ms 为 CPU 更新、命令构造和软件渲染耗时，
扣除 GPU 批次提交与等待（PC 的提交调用内同步执行参考模型，板端提交内含 cache 维护）；GPU µs 为所有本帧批次的 PERF[0] 差值 / 180 MHz（向上取整）。
HUD 显示前一帧耗时；第一帧没有 FPS 样本。模拟器周期计数为 0 时 GPU 显示 n/a。
GPU 频率上板若变更，应同步修改运行时的 180 周期/µs 换算。
CPU 模式的 GPU 耗时/像素只计 HUD，CPU 场景时间计入 CPU ms。
CPU 与 Windows 时钟分辨率为 µs，板端使用 CLINT。

## 资源预算

| 纹理 RAM 项 | 字节 | 装入时机 |
|---|---:|---|
| I8 256×256：原创精灵、星空、字体、纯色区 | 65536 | 启动一次 |
| RGB565 64×64、七级 mip、2×2 块补齐 | 10928 | 启动一次 |
| 尾部对齐填充 | 16 | 启动一次 |
| 合计 | 76480 / 196608 | 每帧 TEX_LOAD = 0 B |

调色板 16×256×4 = 16384 B，PAL_LOAD 仅启动时；不计入纹理 RAM。
纹理交织与尺寸计算按 gpu-spec 2.6，全部 Python 标准库程序生成。
字体复用 `sw/lib/font8x16.h`，其来源为 public-domain console-setup 字体。
没有下载素材，没有第三方美术许可依赖。四种短音效为整数方波包络，通过 AUD/ES8156 播放。

| DDR 动态分配项 | 字节 |
|---|---:|
| GPU 命令（512×32） | 16384 |
| 四边形（8192×16） | 131072 |
| 三角形顶点（60000×3×16） | 2880000 |
| 对象表（100000×32） | 3200000 |
| 命中 / 释放列表（各100000×4） | 800000 |
| 两个 RGB565 Surface | 921600 |
| CPU AA 原图 | 460800 |
| 纹理源、调色板、矩阵 | 92992 |
| AUD 环 | 32768 |
| 合计（不含分配对齐空洞） | 8535616 |

平台 board.c 静态保留 64 MiB DMA pool；本应用实际申请约 8.15 MiB，另有只读生成纹理、
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
