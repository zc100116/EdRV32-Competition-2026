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
