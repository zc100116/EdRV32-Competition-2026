# nofrendo DDR 移植（B3-4b 第 1 步）

实现依据：`docs/design/2026-10-29-rnd-disp.md` 5.2。
本步交付 CPU/PPU 软件模拟、I8 帧接口、主机 PPM、UART/KEY 输入和板上计时。
RND/DISP 在 B3-3a 合入后接入，当前板上不显示、不限速、无声音。
板上 CLINT 实测帧率**未取得**；协调者确认本卡按 Linux 验收交付，后续上板补测。

## 上游、许可与补丁

子模块：<https://github.com/espressif/esp32-nesemu.git>，锁定
`693e378643dd4810665e52c0ec02bd9f64559c50`；只使用 `components/nofrendo/`。
上游 README 将该目录声明为 GPLv2（部分历史文件头写 GNU Library GPL v2）；
本移植层按 GPL-2.0-only 分发，完整 GPLv2 文本见 `COPYING`。
子模块保持原样；未引入 ESP-IDF、FreeRTOS 或 ESP32 外设代码。

协调者批准的两个 RV32 移植补丁保存在 `patches/`：

- `6502-byte-reads.patch`：6502 两个 16 位读取函数改成字节组合，避免 RV32
  非对齐半字异常；零页地址及 16 位 CPU 地址按 NES 地址宽度环绕。
- `ppu-byte-storage.patch`：PPU 的 8 像素清除/保存/恢复使用 memset/memcpy，
  避免对字节缓冲直接作 uint32 指针解引用。

构建把这两个文件复制到对应输出目录的 `core/`，然后 `git apply`；应用失败立即退出。
其余核心文件直接从子模块编译。原版 `bitmap.c` 不编译：其中地址对齐把指针截成
uint32，不适合 Linux 64 位主机；`port.c` 自己提供静态位图和行指针。
原版 GUI、OSD、视频驱动、memguard 和应用主循环入口不编译，其必要回调由 `port.c`
提供；NES CPU、PPU、mapper、APU 寄存器处理和 `nes_emulate()` 仍来自上游。
未注册 mapper 由上游 `mmc_peek()` 检测，GUI_RED 回调打印 mapper 号后退出。
不提供存档文件系统；嵌入 ROM 不销毁，随应用退出一起回收，避免上游 rom_free
对直接指向嵌入映像的 PRG/CHR 指针调用 free。

## ROM

默认嵌入 `roms/nrom-template.nes`（NROM-128，mapper 0，16 KiB PRG + 8 KiB CHR）。
它是 Damian Yerrick 的自制演示，有人物运动、草地和木箱；无商业游戏内容。
源代码：<https://github.com/pinobatch/nrom-template>，使用提交
`d5ce5d898a32b8ef8b20b2d417f1f32b0530faa8` 的 `nrom-template.nes` 构建结果。
许可为上游 README 的 GNU All-Permissive 风格授权，允许免费复制、修改和分发；
完整声明见 `roms/LICENSE`（Copyright 2011–2024 Damian Yerrick）。
原 ROM 在 Linux 用 cc65 2.19、Python 3.12、Pillow 13.0.0，执行上游 `make all` 构建；
Pillow 仅在重建此公开 ROM 时需要，编译/运行本移植不需要它。
可另选该仓库的 NROM-256 版本；用相同许可和源码重新构建。

主机及板上都可通过 `NES_ROM=/绝对路径/公开授权.nes` 指定其他 ROM，`.incbin` 把
ROM 嵌进 ELF；运行时不从文件系统加载 ROM。许可不明或商业 ROM 不入库。

## 构建与主机验证

在仓库根目录执行（首次需 `git submodule update --init third_party/nofrendo`）：

```sh
make -C sw/apps/nes
mkdir -p build/nes/frames
build/sw/nes-host/nes-host 180 build/nes/frames > build/nes/host-run.log
build/sw/nes-host/nes-host 180 build/nes/frames skip > build/nes/host-skip.log
```

主机只需 Linux gcc、GNU make 和 git；同一份 `port.c`、`profile.c`、核心及 ROM
用于 Linux/RV32。每 60 帧及最后一帧写一个 P6 PPM，尺寸 256×240；skip 模式不输出图像。
主机无交互控制，用于画面和性能参考；板上有下面的键盘/按键输入。
帧数必须大于零，输出目录须事先创建。

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=nes MEMORY=ddr_app
```

输出 `build/sw/nes/nes.elf`、`.bin`、`.map`、`.dis` 及地址分段 hex。
默认 `NES_OPT=-O2`；比较选项可传 `NES_OPT=-O3`，禁画可传 `NES_SKIP=1`。
板上默认无限运行；测量可传 `NES_FRAMES=180` 固定帧数。
所有程序段、ROM、位图、I8 帧、状态和 newlib 堆均在 DDR 应用区
CPU `0x90000000`（DDR 物理偏移 `0x10000000`）起的 64 MiB 内。
`syscalls.c` 的固定堆为 2 MiB bss，通过 `_sbrk` 给 newlib malloc 使用；
没有自定义分配器。状态由核心 malloc，帧缓冲和位图由移植层静态分配。

## BIOS 2 Load / 3 Run

需要支持 SoC v0.17 菜单的 BIOS；本卡基线的旧 BIOS 只有 1，须等 BIOS 更新合入。
按住 KEY1 并复位进入 BIOS，先可用 4 Baud 切换到 2000000 baud，再用
`tools/board/uart_tool.py` 加载 `build/sw/nes/nes.elf` 并运行；参数见
`tools/board/README.md` 的 ELF 加载用法（该功能由另一个 Task 交付）。
**BIOS 不解析 ELF，不能把 ELF 文件整体当作一个裸镜像发送。**

手动协议（由协调者提供，SoC v0.17 7.5 3a）：

1. 对 ELF 中每个 `p_filesz != 0` 的 PT_LOAD 段，发送 `2` 加 Enter，等待
   `UART load ready`；发 4 字节小端 `p_paddr`、4 字节小端 `p_filesz`，再发段数据。
   等 `Load bytes: <n> at 0x<addr>` 和 `Load result: PASS`，再处理下一段。
2. 发送 `3` 加 Enter，等 `Run address:`，发 `0x90000000` 加 Enter（本 ELF 的
   `e_entry`），BIOS 打印 `Run: 0x90000000` 后跳转。
3. `.data` 必须加载到 `p_paddr` 指定的初始值副本地址；应用 startup 会复制到 VMA、
   清零 bss 并建立栈，所以可重新选择 Run 重入。`p_filesz=0` 的 bss 不传输。

板上每 60 帧打印一行：

```text
NES fps=75.4 cpu=30% ppu=62%
```

上面只是格式示例，**不是上板实测**。计时用 `clint_time()`，单位为 clk_sys 周期，
频率读 SYSCTRL `CLK_SYS_HZ`；fps 不用写死的 100 MHz。
FPS 计入帧复制/接收端及输入处理，排除上一次的串口统计打印时间。
CPU/PPU 百分比的分母是模拟核心帧时间，排除帧复制/接收端、输入和统计打印。
CPU 计入 `nes6502_execute()` 内发生的 PPU 寄存器访问和 mapper 回调；
PPU 计入 `ppu_scanline()` 和 `ppu_endscanline()`，两项不重复计时。
计时包装和读计时器本身有开销，百分比不要求加到 100%。

## 输入

UART 使用单个小写字符，不要发送 Enter。每次接收延长对应按钮约 100 ms；
每模拟帧采样一次，释放精度受帧耗时限制。多个不同按钮可以同时保持。
使用 UART 驱动的非阻塞状态轮询；`uart_input` 的 Enter 行协议用于 BIOS 菜单，
不适用于游戏的单字符输入。

| NES 按钮 | UART 字符 | 板上按键（低有效） |
|---|---|---|
| A | j | KEY3（GPIO0 bit2） |
| B | k | — |
| Select | u | — |
| Start | i | KEY4（GPIO0 bit3） |
| Up | w | — |
| Down | s | — |
| Left | a | KEY1（GPIO0 bit0） |
| Right | d | KEY2（GPIO0 bit1） |

物理按键按住即保持，UART/物理输入合并后交给上游 controller 0。

## 帧与声音接口

`nes_port.h` 的 `nes_frame(pixels, palette, frame)` 每次同步接收一帧：
`pixels` 是行距 256 的 256×240 I8，`palette` 是 256 项 RGB888（每项 3 字节）。
两个指针至少到下一帧前有效，帧号从 1 开始。PPU 的左右各 8 像素 overdraw
留在独立的 272×240 工作面，交付前逐行复制出连续的 I8 帧；优先级位由调色板
的重复项解释，保留上游 I8 值。板上接收端本步只丢弃，供后续 RND 接收端替换。
第 2 步须在接收端按 BSP cache 契约准备 RND 源、调色板及 L0 目标，
用 I8 BLIT 最近邻 3 倍输出 768×720；本步没有 RND 命令或 DISP 操作。

`osd_setsound()` 不调用上游 APU process 函数，所以完全不生成音频采样，
仍保留 APU 寄存器状态；依赖音频采样时钟/DMC DMA 的 ROM 行为未验证。

禁画选项利用核心 `ppu_scanline(..., false)`，保持 CPU、扫描行、vblank 和
sprite-0 hit 所需 fake OAM 逻辑；不是停止整个 PPU。禁画帧不交付帧接口。
测量这一模式可以区分 PPU 像素绘制成本和其他模拟成本，不代表可显示的实际帧率。

## 验证记录

测量实现提交：`f93a9f9a82a468744a40839692f5133248e0751c`；
上游/ROM 提交见前文。Linux x86_64，AMD EPYC 7742（共享运行环境），gcc 13.3.0；
RV32 编译器 xPack GCC 15.2.0，`-march=rv32im_zicsr -mabi=ilp32`；
Spike `1.1.1-dev`，未开启时序/cache 模型。没有运行 SoC 仿真。

上面的主机 180 帧命令退出 0，生成 60/120/180 帧 PPM；
图像 `build/nes/frames/frame-000180.ppm`（184335 字节）已查看，人物、草地、左右木箱
和背景完整，与上游示例布局一致（采用 nofrendo 自己的 RGB 调色板）。
主机三个窗口分别为 1407.3 / 2054.4 / 1899.1 fps；最后窗口 CPU 21%、PPU 70%。
主机 skip 三个窗口为 9465.1 / 8896.5 / 8530.4 fps；最后窗口 CPU 51%、PPU 19%。
主机数字受调度和 PPM 写盘影响，只作参考；原始记录为
`build/nes/host-run.log`、`build/nes/host-skip.log`。
**6502 每帧指令数未统计**：协调者明确取消该参考项，不为此维护核心插桩补丁。

板上构建命令退出 0，编译/链接均零告警；记录 `build/nes/board-build.log`。
ELF text/data/bss 为 214944 / 4376 / 2242724 字节，入口 `0x90000000`；
所有三个 PT_LOAD 的地址均在 DDR 应用区内。真实上板帧率仍未取得。
`build/nes/host-build.log` 是主机构建记录，编译/链接同样零告警。
另用默认 ROM 的副本把 iNES mapper 改为 250，单独构建主机程序：
`build/nes/unsupported-run.log` 包含 `Mapper 250 not yet implemented`，退出状态 1。

串行复现四组 Spike 测量：

```sh
. ~/.local/opt/edrv32/env.sh
python3 sw/apps/nes/run_spike.py > build/nes/spike-comparison.log 2>&1
```

脚本分别以 `NES_SPIKE=1 NES_FRAMES=180 NES_OPT=-O2/-O3 NES_SKIP=0/1`
调用同一个 `make -C sw PROGRAM=nes MEMORY=ddr_app`，输出到
`build/sw/nes-spike-O{2,3}-skip{0,1}/`，其中 `build.log`、`console.log` 为原始记录。
运行命令为：

```sh
spike --isa=rv32im_zicsr_zifencei_zicntr_zihpm --priv=m --pmpregions=0 \
  --no-dm --disable-dtb -m0x90000000:0x04000000 --pc=0x90000000 \
  build/sw/nes-spike-O2-skip0/nes.elf
```

Spike 使用 RV32 `instret` 作为计量单位（不是周期），通过同一套 CPU/PPU 包装采样。
HTIF 输出代替 UART，输入固定未按下，帧接收端和板上一样丢弃。
每 60 帧读取一次 `instret` 差值，除以 60 后向下取整；不包含 ROM 初始化或统计打印。
丢弃首个启动窗口，下表使用第 121–180 帧窗口：

| 优化 | PPU 绘制 | RV32 指令/模拟帧 | CPU 指令占比 | PPU 指令占比 | 100 MHz、IPC=1 估算 fps | 理想双发射上限估算 fps |
|---|---|---:|---:|---:|---:|---:|
| O2 | 开 | 1325190 | 30% | 62% | 75.46 | 150.92 |
| O3 | 开 | 1325758 | 30% | 62% | 75.43 | 150.86 |
| O2 | 关 | 506077 | 77% | 4% | 197.60 | 395.20 |
| O3 | 关 | 506645 | 77% | 4% | 197.38 | 394.75 |

估算公式：若每帧 RV32 指令数为 I，则 `fps = 100000000 × IPC / I`。
取 IPC=1 是单指令每周期的参考估算；EdRV32 双发射最多 IPC=2，理想上限估算为
`2 × 100000000 / I`。这些值均不是上板实测，也不能用 Spike 的运行墙钟时间
推算板上速度；实际 DDR/cache 停顿、相关性、分支及多周期指令会降低 IPC，
CLINT/UART 后端与 Spike 的 CSR/HTIF 后端也有开销差异。

最终选择 **O2**：这个 ROM 中 O3 的绘制指令数反而增加约 0.043%，没有收益；
保持较小代码更合适，不能据此宣称所有 ROM 都是同样结果。
O2 禁画比完整绘制少约 61.81% 指令，理想吞吐比约 2.62 倍。
这说明 PPU 像素绘制值得在第 2 步结合真实板上帧率评估；禁画不产生可显示新帧。


## 第三方告警放宽

移植层始终 C11、`-Wall -Wextra -Werror`；核心同样保留这些选项，仅以下对象
追加局部禁告警选项（Linux gcc 13.3 / xPack gcc 15.2 均零告警）：

| 上游源文件 | 局部选项 | 原因 |
|---|---|---|
| `nes/nes_ppu.c` | `-Wno-implicit-fallthrough -Wno-maybe-uninitialized` | 有意连续 case；保存/恢复受同一 mask 控制，编译器保守判断 |
| `nes/nes_rom.c` | `-Wno-unused-parameter -Wno-unused-result -Wno-unused-function -Wno-stringop-truncation -Wno-unused-but-set-variable -Wno-misleading-indentation` | 上游裁去文件读取路径后遗留的变量、函数、缩进和字符串处理 |
| `mappers/map005.c` | `-Wno-unused-but-set-variable` | 上游 MMC5 遗留局部变量 |

`-fno-strict-aliasing` 用于上游按字节/字读写 PPU 工作面及 bitmap 存储的别名约定。
没有全局 `-w` 或全局移除 `-Werror`。

## 上板检查清单（本步只看串口）

- BIOS 已支持 2/3；DDR MEM_READY，ELF 两个有文件数据的 PT_LOAD 都加载成功。
- Run 后出现 ROM loaded / mapper 0 / NES powered on；每 60 帧持续打印 fps/cpu/ppu。
- 记录默认 O2 的至少三个 60 帧窗口，丢弃首次启动窗口；保存完整 UART 日志和提交号。
- 同样 ROM 用 `NES_SKIP=1` 重建并重载，记录禁画结果；恢复普通构建。
- 接入显示后再验证 UART 八键及 KEY1–4；本步无画面，不能仅靠帧率验证按键效果。
- 重复 Run 能重新初始化状态；记录真实频率、cache 配置与 BIOS 版本。
