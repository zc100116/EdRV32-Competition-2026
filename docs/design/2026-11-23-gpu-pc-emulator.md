# GPU 游戏软件的 PC 开发环境

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-23 |
| 状态 | 已决定（用户 2026-11-23 选方案 A） |
| 关联 | `gpu-spec.md` v0.3、`aud-spec.md` v0.2、`disp_gpu` 寄存器、`tools/gpu/model/`、`gpu-plan.md` S-0、G-1 |

## 1. 背景和问题

游戏和测试软件要与硬件联调并行开发。SoC 仿真太慢（ST-08 只启动就要约 10 分钟），而上板要等 B-1。因此需要一个在 PC 上看画面、操作和听声音的环境。

## 2. 约束

- 游戏代码和驱动只有一份，同一份源码既编译成板上程序，也编译成 PC 程序。
- PC 上的画面必须与 GPU 规格一致，以 `tools/gpu/model/`（Python，逐位精确）为准。
- 用户在 Windows 上操作；Linux 主机没有图形界面，也没有 root 权限。可用的交叉编译器是 `~/.local/opt/zig-0.17.0`（`zig cc -target x86_64-windows-gnu`）。
- 不引入第三方库（不用 SDL 等），只用 Win32 API（GDI 窗口、键盘、winmm 音频）和 C 标准库。

## 3. 可选方案

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A C 版 GPU 模拟器** | 把 Python 参考模型移植成 C，在 PC 上实时执行命令列表 | 能交互，可在 PC 上调手感和难度；以后上板出问题，可用它区分软件错和硬件错 | 多一个工作包；要靠场景对照保证与 Python 模型一致 |
| B 只用 Python 模型离线出帧 | 用脚本输入跑若干帧，渲染成图片 | 不写新代码 | 每帧数秒以上，不能交互 |

## 4. 决策

采用 A，结构如下：

1. **寄存器级虚拟 SoC**：
   - 驱动（gpu、aud、disp 及它们用到的 plic 访问）的寄存器读写统一经过现有的 `sw/drivers/include/mmio.h`（`mmio_read32/mmio_write32`），CPU 地址到 DDR 物理地址的换算统一经过其中新增的 `ddr_physical()`。板上实现是 volatile 访问和地址减基址；PC 构建用同名替换头文件（沿用 `sw/apps/demo/host_mmio.h` 的做法，占用同一个 include guard），转给模拟器按地址分发。
   - GPU、DISP、AUD 三个寄存器块在 PC 上按规格模拟。驱动代码在 PC 和板上完全相同。
2. **GPU 模拟器核心** `tools/gpu/emu/`：
   - Python 模型的 C11 移植，纯库，不依赖平台。
   - 写 DOORBELL 时同步执行整个命令列表。
   - 与 Python 模型逐位一致：用 GT 场景和模型自测场景对照 DDR 结果、PERF、OBJ 计数和错误码。
   - 只模拟功能，不模拟周期。
3. **PC 平台**：
   - `sw/bsp/pc/`：PC 版 BSP。包括替换的 `mmio.h` 和地址分发；DDR 用一块连续主机内存，`ddr_physical()` 换算为它的偏移；cache 维护为空操作。
   - DISP 模拟：L0/L1 合成和 `L0_X2`，按帧节拍切换缓冲并报告释放。
   - AUD 模拟：按 48 kHz 实时消耗环形缓冲，按规格更新水位、LOW 中断和欠载计数。
   - 中断：模拟器在主循环中检查各块的中断，调用已注册的处理函数。
4. **游戏平台层** `sw/lib/plat/`：
   - 驱动以外的平台差异只放在这里：帧计时、输入（板上为按键和 ETH 虚拟手柄，PC 上为键盘）、日志（板上走 UART，PC 上走 stdout）、DMA 可见内存的分配。
   - 按键位为 UP、DOWN、LEFT、RIGHT、A、B、START、SELECT，与 `sw/lib/virtual_input.h` 的同名位一一对应。PC 上 Z/X 对应 A/B，Enter 对应 START，Esc 对应 SELECT；板上 4 个按键固定对应 RIGHT/LEFT/A/START。
   - 有 `board.c`、`pc.c` 两个实现。游戏只调用平台层、驱动和 C 标准库。
5. **前端**：
   - Windows 交互前端：GDI 窗口，按整数倍放大，键盘输入，winmm 出声。在 Linux 上用 zig 交叉编译成单个 `.exe`，不依赖其他文件。
   - Linux 无界面前端：从文件读入按帧的输入脚本，输出指定帧的 PNG（自带无压缩 PNG 编码，不用第三方库）和每帧的 PERF 计数。用于自动测试，以及协调者查看画面。

## 5. 影响

- `sw/drivers/{gpu,aud}.c`：直接的 volatile 访问改为 `mmio_read32/mmio_write32`，地址换算改用 `ddr_physical()`（`disp.c`、`plic.c` 已经使用 mmio.h）；行为不变，视觉项目的构建不受影响。
- 新目录：`tools/gpu/emu/`、`sw/bsp/pc/`、`sw/lib/plat/`。
- `gpu-plan.md`：新增 S-0a（模拟器核心）、S-0b（PC 平台和前端）、S-0c（驱动 mmio 改造）；G-1 依赖 S-0。

## 6. 状态

已决定（用户 2026-11-23）。

## 7. v0.6 算术同步（2026-11-27，E-1）

基于 `2659df379`，按 gpu-spec v0.6 2.13 同步 C 模拟器：先按 d 舍入完整起点和
增量，再按 SC∩TGT 的原点重定位、计算并舍入 κ；系数和像素步进以 int64_t
保存规格规定的 W=[32,42,42,42,32,32,32] 位值，步进不舍入、不截断。
q 的倒数支持零和负数；LOD 改为屏幕对齐 2×2 组的四对相邻 U/V 差分，包含
未覆盖及 SC/TGT 外的辅助像素。深度和颜色的输出移位包含各属性的 κ。

并行绘制只划分像素覆盖行，所有线程保留命令原有 SC∩TGT 作为平面建立域，
避免线程分区改变原点和块指数。平面自测适配器同步 domain 参数和构造期间的
起点求值；`compare.py --demo <导出目录>` 逐提交回放 CPU 改写的 DDR 字节，
将每次 DOORBELL 后完整 DDR 和全部模型寄存器（含 PERF、OBJ、错误码）逐位比较。

构建命令（`-W` 强制重编译；原 Makefile 未把模拟器源列为目标依赖）：

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/gpu_test linux windows board -j1 -W "$PWD/sw/apps/gpu_test/Makefile"
```

三个目标均 0 告警，日志 `build/gpu-emu/v06/build.log`；单线程配置另经
`gcc -std=c11 -Wall -Wextra -Werror -O3 -pthread -DGPU_EMU_THREADS=1 -fsyntax-only tools/gpu/emu/gpu_emu.c`
检查通过。本次未改 RTL，Verilator lint 不适用；修改的 C/Python 文件无 Tab、
无超过 100 列的行，针对本次五个修改文件的 `git diff --check -- <文件列表>` 通过。

四个主截图使用原捕获参数重拍到 `outputs/gpu-test-games-20261126/`：

| 输出（均加 `-v06.png`） | headless 参数（另加 `--out <目录>`） |
|---|---|
| `2d-normal` | `--scene 1 --frames 26 --shot boss` |
| `3d-normal` | `--scene 2 --frames 20` |
| `rogue-combat` | `--scene 3 --frames 60 --shot combat` |
| `world-day` | `--scene 4 --frames 3 --shot day` |

四张均已与原图目视对照，构图、角色、地形及 HUD 无明显变化。FPS/CPU 耗时文字随
主机负载变化，不能用于推断板端性能。截图与导出脚本为
`build/gpu-emu/v06/capture.sh`，逐帧 CSV 在同目录 `shots/`；outputs/build 不提交。

逐位回归的标准入口为 `python3 tools/gpu/emu/compare.py`。本次为避开执行终端的
长命令超时，将入口中的同一组函数分三次串行调用；临时驱动
`build/gpu-emu/v06/suites.py` 设置 `Scene` 默认 base=0，`gt` 段调用 `build()`、
`cli_case()`、`object_writeback_case()`、`gt_cases()`，`selftest` 段调用
`selftests()`，`stress` 段调用 `run_case(lib,'stress',stress.scene(),11)`：

```sh
free -h  # 每次启动 Python 前确认 MemAvailable >= 2 GiB
python3 build/gpu-emu/v06/suites.py gt
free -h
python3 build/gpu-emu/v06/suites.py selftest
free -h
python3 build/gpu-emu/v06/suites.py stress
```

GT01–GT25 共 124 个功能场景 PASS；完整 DDR、全部模型寄存器、IRQ 以及
颜色/深度/模板缓冲逐位一致。另有 CLI 命名/数字寄存器地址和 OBJ 列表别名写回
场景 PASS。14 组模型自测 PASS，含 P-A 极端面积 1、平移条带、逐像素步进、
2×2 LOD 和零/负 q 倒数。GT21 的 4 个场景与自测中的 2 个操作需要注入 AXI
响应错误，沿用原适配器的跳过方式；GT22 只比较完整命令列表的功能结果，不模拟
命令中途 ABORT。日志与结果为 `build/gpu-emu/v06/{gt,selftest}.{log,json}`。
附加 stress 场景的完整 DDR、寄存器、IRQ 和渲染缓冲也逐位一致，C 回放 11 次；
结果在 `build/gpu-emu/v06/stress.{log,json}`。

真实帧沿用 `study_precision.py` 的四帧选择，全部重新由本次 C 模拟器导出。
每帧目录 D 为 `build/gpu-emu/v06/<帧名>`，先 `mkdir -p D`，再运行：

```sh
build/gpu_test/gpu_test --scene S --frames 1 --tick 150 --out D --export D [--shot SHOT]
free -h
python3 tools/gpu/emu/compare.py --demo D
```

| 帧名 | S | SHOT |
|---|---:|---|
| canyon | 2 | 不传 |
| world | 4 | 不传 |
| world-dusk | 4 | dusk |
| rogue-slash | 3 | slash |

四帧各 4 次提交、20 次寄存器写入全部 PASS；每次提交比较完整 67108864 字节
DDR 和所有模型寄存器，PERF、OBJ 计数逐位一致，ERR_CODE 均为 0。
四帧结束时的完整 DDR 和 PERF 再次比较也全部相同；Candy Canyon 原首差
`0x757e62` 已消除。日志为 `build/gpu-emu/v06/{canyon,world,world-dusk,rogue-slash}.log`，
对应目录保存每次提交的输入、输出和寄存器快照。全部 Python 验证串行执行，
每次启动前已确认可用内存至少 2 GiB；未改模型、规格、RTL 或 demo 源码。
