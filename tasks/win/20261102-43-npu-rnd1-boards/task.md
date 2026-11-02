# 任务卡 20261102-43-npu-rnd1-boards：最新 NPU + RND v1，四种板级工程实现并上板

## 1. 目标

用户 2026-11-02 决定将原定 B3N 测试与三种整机候选一起下发，利用夜间完成布局布线。四种配置均使用最新已集成的 CPU、cache、mem_xbar、系统和 ETH，以及 Q6+OPT2 NPU；带 RND 的两种配置固定使用 RND v1。

| 标识 | 配置 | 用途 |
|---|---|---|
| N | B3N：CPU、DDR、NPU、ETH | NPU 独立功能、资源、时序和性能 |
| VN | B3VN：CPU、DDR、VIN、PIX、GEO、DISP、NPU、ETH | 最新 NPU 的视频识别整机，无 RND |
| F | B3F-RND1-N：完整 B3F，RND v1 + 最新 NPU | 完整整机候选 |
| VRN | B3F-VRN-RND1-N：F 去掉 PIX/GEO | 保留 VIN、DISP、RND v1、NPU 的整机候选 |

- **Q6**：重量化由 16 路 / 32 APM 改为 4 路分时 / 8 APM，激活表副本 16→4；输出算术不变。已合入 `7ccac3a8`，报告 `docs/reports/2026-11-02-npu-q6.md`。
- **OPT2**：POOL 连续每拍一个采样；输入行和模型读请求按消费顺序仲裁，保留残差优先级。集成后的 RTL `a7306e22`，报告提交 `92b38fd2`（报告中保留 worker 测量时的原提交 `eee575ed`）。
- Q6+OPT2 已有必要仿真通过：两单元、六个相关 block smoke、zero 整网 725760 B 逐字节一致；PERF0 从 Q6 的 6297548 降至 5987773。此次上板取得真实 DDR 条件下的结果，不把 zero 仿真的 4.919% 降幅作为实板承诺。

RND v1 采用 Claude 卡 39 的同一恢复改动 `bbd1abc1`：只将 `rtl/media/rnd/` 和 `rtl/filelists/rnd.f` 恢复到 `d14fb33c`，本分支对应提交 `95fcd376`，端口不变。实验分支不合入 b3；原卡 39 分支保持原输入。CPU 使用 b3 已集成版本，未纳入尚未验收的 task-cpu-v015。

本卡沿用卡 24 的 NPU 上板流程、卡 38 的 B3VN 工程和测试、卡 39 的 RND v1 配套、卡 37 的去 PIX/GEO 顶层。F/VRN 插入原 CPU 计数器 ILA；N/VN 不插 ILA。各配置只跑一个工程，采用现有对应 FDC，不新增布局区域变体。

## 2. 输入

- **代码**：`origin/zc100116/b3f-rnd1-npu-opt`（包含本卡的提交；下发时由协调者提供完整提交号）。从该提交拉出 `win/20261102-43-npu-rnd1-boards`，在 `result.md` 记录实际完整 commit。实验分支基于 NPU 集成及软件构建基线 `92b38fd2ae6013e192c419d51d150ae27172da01`。
- **四工程使用同一 checkout、同一提交**。N/VN 不引用 RND 文件，因此同一实验分支可供四种配置使用；导入和综合期间不要切换仓库分支。源文件路径、工程目录关系沿用 Claude 的 `codex_project/EdRV32-Competition-2026` 与 `codex_project/EdRV32-FPGA/<工程>` 布局。

| 标识 | 新工程示例（同一父目录下）/复制来源 | 顶层 | 导入脚本 | FDC | 源文件数 |
|---|---|---|---|---|---|
| N | `EdRV32-B3N-Q6-OPT2` / 已有 B3N | `edrv32_fpga_board_npu_top` | `import_board_npu_top.tcl` | `edrv32_fpga_board_npu_top.fdc` | 105 |
| VN | `EdRV32-B3VN-Q6-OPT2` / 卡 38 B3VN；尚未建立时按卡 38 从 B3F 复制所需 IP 新建 | `edrv32_fpga_board_vnpu_top` | `import_board_vnpu_top.tcl` | `edrv32_fpga_board_vnpu_top.fdc` | 144 |
| F | `EdRV32-B3F-RND1-N` / 卡 39 RND1，或卡 33 A 的 B3F | `edrv32_fpga_board_full_top` | `import_board_full_top.tcl` | `edrv32_fpga_board_full_top.fdc` | 159 |
| VRN | `EdRV32-B3F-VRN-RND1-N` / F 工程目录复制一份 | `edrv32_fpga_board_vrn_top` | `import_board_vrn_top.tcl` | `edrv32_fpga_board_full_top.fdc` | 142 |

导入脚本位于 `fpga/scripts/`，FDC 位于 `fpga/constraints/`，宏均为 `FPGA_MODE`。VRN 与卡 37 相同：VIN 像素流直接回接 VIN，PIX/GEO APB 槽返回 SLVERR，GEO DDR 口停用。原工程及旧 bitstream 保留。

- **本卡 `src/`**：下表标“本轮重建”的文件由 Linux 从 `92b38fd2` 用 xPack GCC 15.2.0 构建；RND v1 三件套与卡 39 一样采用卡 21 已有产物，复制并改名以区别 v2。Windows 统一使用本卡列出的文件。

| 文件 | 版本 / 用途 |
|---|---|
| `ip_rom_boot.dat` | 本轮重建；四工程 BIOS ROM 初始化，含切换波特率后等待 100 ms |
| `ip_ram_sram.dat` | 本轮重建；四工程 SRAM monitor 初始化，默认 O2 |
| `board_npu.elf` | 本轮重建；四工程 NPU 39 项测试，内含小用例、整网模型、输入和参考结果 |
| `demo_npu.bin` | 本轮重建；N 的网口送图识别，TX_GAP=2125；也可用于 F/VRN 的独立网口识别 |
| `eth_diag.bin` | 本轮重建；四工程网口诊断 |
| `demo_vnpu.bin` | 本轮重建；VN 视频+NPU，包含 `eed1c488` 的 CPU 画框清除优化及 TX_GAP |
| `demo_vision.bin` | 本轮重建；F 的 VIN/PIX/GEO/DISP 视频测试，含 TX_GAP；VRN 不运行此程序 |
| `rnd_v1_board.elf`、`rnd_v1_expected.log` | 原卡 21 `src/rnd_board.elf`、`rnd_expected.log`，构建基线 `6890ac7e`；F/VRN 的 RND v1 自检 |
| `s3_v1.elf` | 原卡 21 `src/s3.elf`，构建基线 `6890ac7e`；同卡 39 只测 benchmark、LAYERS 和可用的网口遥测 |

所有 `.bin` 的加载地址和入口为 `0x10000000`，`.elf` 按 ELF 段加载。**不要用卡 24 的 RND v2 自检/S3 或开发中的 showcase 替代 v1 程序**。卡 21 S3 有已知 WIDGETS store fault 和串口虚拟输入丢帧，本卡沿用卡 39 不测这两项；RND v1 通过不代表这两个旧软件问题已修复。网口硬件和 BIOS 的验收使用本轮 eth_diag/BIOS/PC 工具，不依赖旧 S3。

**软硬件版本配套**：

| 部分 | 本卡采用的版本和行为 |
|---|---|
| RGMII RTL / FDC / ETH PLL | 含 `31ef0617`：PLL External Feedback，反馈来自 `u_eth_clk` 全局缓冲，CLKOUT0 125 MHz / 0°；RX 不经过 IODELAY，TX 保留原设置；使用第 2 节各工程对应的当前 FDC |
| PHY | 沿用已确认的 strap RXDLY=1 / TXDLY=1；应用和 BIOS 不写 PHY 延迟寄存器，不使用卡 26 的临时 RXDLY=0 诊断设置 |
| BIOS / 新程序 | BIOS 含 `b4119b4a` 的波特率切换修复；demo 系列含 `d5d16c34` 的 TX_GAP；按上表从集成基线重建，RND v1 三件套单独沿用已知版本 |
| PC 工具 | 从本卡同一 checkout 启动 `tools/board/uart_tool.py`、`tools/debug_tool/main.py`；含 `17b7da29` / `0177990f` 等本机网卡就绪后发送，以及 `79d577f8` 应用自动建立连接；已有独立接收进程和 YOLO 超时后继续队列的修复均包含 |

- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`，与卡 24 相同。Q6/OPT2 不改描述符、权重镜像或量化算法。该目录供 `demo_npu` 上传；`board_npu.elf` 自带测试数据，无须另传模型。
- **旧板对照**：优先取 Windows 本地最近一次 B3N 的时序、资源和 C-YOLO 原文，并注明其 commit；仓库已记录卡 23 整网约 24.0 fps、clk_npu WNS −0.078 ns。没有同条件旧数据的项写“未取得”，不额外重跑旧工程。

Linux 构建命令：先 `. ~/.local/opt/edrv32/env.sh`，分别执行 `make -C sw PROGRAM=<bootloader|monitor|board_npu|demo_npu|eth_diag|demo_vnpu|demo_vision> -j 1`，再执行 `python3 tools/fpga/mem_init.py build/sw/bootloader/rom.hex build/sw/monitor/sram.hex`。构建日志在 Linux b3-int 的 `build/card43/`；没有追加 RTL 仿真。

本次七个程序均构建成功；除 monitor 的未修改第三方 CoreMark 有一条既有 `-Wmaybe-uninitialized`（与卡 24 相同）外，均为 0 warning。

组合分支 `95fcd376` 的 N/VN/F/VRN 四个顶层已使用现有板级 IP 行为模型完成 Verilator 5.020 `--lint-only --timing -Wall -DSIM_MODE`，均为 0 告警；日志在 Linux b3f-rnd1-npu-opt 的 `build/card43/{npu,vnpu,full,vrn}-lint.log`。未追加功能回归，功能和物理实现由本卡上板验证。

## 3. 环境

- PDS 2022.2-SP6.1，或原 B3N 工程已使用的兼容版本（记录实际版本）；PG2L200H-6 FBB676。
- clk_sys 100 MHz、clk_mem 125 MHz、clk_npu 150 MHz；各工程沿用第 2 节对应的引脚和时钟约束，视频时钟沿用原配置。
- JTAG、USB 串口、千兆有线网口；VN/F/VRN 另接 HDMI，VN/F 摄像头测试接 OV5640。PC 地址 `192.168.1.2/24`，板端 `192.168.1.10:5000`；放行 UDP 6000，PC 工具显式选择 `192.168.1.2`，关闭会接管该网段路由的 TUN。
- 实现期间不在该 Windows 电脑上运行仿真虚拟机；已有其他 PnR 按用户原安排运行，本卡不停止其他任务。

## 4. 需要的 IP

沿用对应工程的 IP 类型，完整清单见各导入脚本开头及 `fpga/ip/README.md`。本轮 Q6/OPT2 没有新增 IP 类型。F/VRN 的 RND v1 不使用 `ip_ram_rnd_window`，VRN 不使用 GEO 的 `ip_ram_geo_src`，保留在 PDS 工程中不用即可（同卡 37/39）。F/VRN 按 `fpga/ip/ila_cpu.md` 插入 CPU 计数器 ILA。

| 动作 | IP |
|---|---|
| 用本卡 `src/ip_rom_boot.dat`、`src/ip_ram_sram.dat` 重新生成初始化内容 | `ip_rom_boot`、`ip_ram_sram` |
| 使用外部反馈版本；原工程尚为内部反馈时，按 `fpga/ip/ip_pll_eth.md` 重新生成 | `ip_pll_eth`：须有 `clkfb` 端口，External Feedback / CLKOUT0 / 0°，反馈接全局缓冲 |
| 沿用 2048×8、读延迟 2 拍的类型；Q6 由 RTL 将实例数改成 4 | `ip_ram_npu_lut`，配置见 `fpga/ip/ip_ram_npu_lut.md`（该说明的旧“16 实例”使用者文字不作为本轮实例数） |
| 沿用其余已生成配置 | NPU 权重、行缓存、scratch、分布式参数/残差/结果 RAM、量化乘法、CPU/cache、DDR、ETH 等 |

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-43-npu-rnd1-boards <协调者提供的本卡提交>`；阅读本卡，整理用户操作清单。记录 `git rev-parse HEAD`。关闭旧调试工具，从该 checkout 重启。 |
| 1 | 用户（U），C 协助 | 按第 2 节复制/新建四工程，按第 4 节处理 IP 和本卡初始化文件。C 同卡 38 查看空闲内存、已有 PnR 占用和峰值，安排夜间并行数；三个整机候选优先在睡前启动，N 用于独立验证。记录启动安排，不停止其他卡已有任务。 |
| 2 | U 或 C 在 PDS 控制台 | 各工程执行 `source ../../EdRV32-Competition-2026/fpga/scripts/<本工程导入脚本>`；记录脚本输出、顶层和源文件数，使用对应 FDC、FPGA_MODE，然后 `synthesize -ads`。复制自 v2 工程时移除旧源文件列表中的 affine/filter/geometry/window 等 v2-only RND 源，以本轮导入列表为准，方法同卡 39。 |
| 2a | U（C 协助） | F/VRN 按 `fpga/ip/ila_cpu.md` 插入 ILA：clk_sys，A 组 400 位，深度 1024，触发位置 10%，探针 minstret/mcycle。记录实际实例名，保存 .fic 和截图。VRN 顶层不同，旧 .fic 不能直接套用时重新插入；N/VN 不插。 |
| 3 | U 或 C | Device Map 的 `Number of Nets To Report` 设为 1000；依次 `dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。N 沿用已有 B3N 设置，VN/F/VRN 沿用卡 38/39/37 的卡 33 A 设置（拥塞选项、Placement Decongestion Mode 2）。记录实际选项、线程数；每小时记录阶段、轮次、未布通数和过用数。工具阶段报错回传原文，不自行改 RTL、约束或 IP 参数。 |
| 3a | C | VN/F/VRN 沿用卡 38/39/37 已定止损：第 40 轮未布通 >18000 时停止该工程并回传进度、布局后时序；N 沿用原 B3N 流程。四工程分别记结果，一个失败不停止其他工程。 |
| 4 | C | 收集第 6 节时序、资源和实现耗时。重点比较 NPU 总资源以及量化/激活表资源，记录最差 NPU 路径落在量化、POOL、读仲裁还是其他模块。 |
| 5 | U + C | 先让已启动的工程继续实现；有可用 bitstream 后逐个上板，按下述项目矩阵执行。独立测试项失败保留原文，再做后续可执行项；`board_npu` 自身首错结束行为不改。 |

### 上板项目矩阵

| 项目 | N | VN | F | VRN |
|---|---|---|---|---|
| 5.0 BIOS、ETH 接收 5 次 | 做 | 做 | 做 | 做 |
| 5N NPU 自检 39 项及整网性能 | 做 | 做 | 做 | 做 |
| 5E 网口单张/批量识别 | 做 | 用 5VN 视频整机测试 | 做 | 做 |
| 5VN 视频 + NPU | — | 做 | — | — |
| 5F 图像/几何处理（S2） | — | 已由 5VN 覆盖 | 做 | 不做（无 PIX/GEO） |
| 5R RND v1 自检、benchmark、LAYERS | — | — | 做 | 做 |
| 5C CPU CoreMark + ILA | — | — | 做 | 做 |

### 5.0 BIOS 与网口接收

1. KEY1 复位进入 BIOS，菜单应为 `1=UART load 2=ETH load 3=Run 4=Baud`。用本卡 `eth_diag.bin` 做 2 Mbaud 串口加载，再用 CLI 网口加载一次、调试工具网口加载一次，记录加载及自动运行结果、耗时和“等待网卡”日志（未等待时可能没有该行）。方法沿用卡 24 第 5.0 节和卡 36 B。
2. 串口命令（仓库根目录，COM7 换为实际端口）：

   `python tools/board/uart_tool.py tasks/win/20261102-43-npu-rnd1-boards/src/eth_diag.bin --addr 0x10000000 --entry 0x10000000 --baud 2000000 --port COM7 --log tasks/win/20261102-43-npu-rnd1-boards/artifacts/N/uart/eth_diag.log`

   以上以 N 为例；其他工程将日志目录的 `N` 改为 `VN`、`F`、`VRN`。先创建对应 `artifacts/<标识>/uart/`。

3. 接收检查沿用卡 24 第 5.0 节第 4 步：另开终端运行 `python tools/board/eth_probe.py --local-ip 192.168.1.2 --listen 6000`；在 eth_diag 做 5 次 `r`，每次等 `link=1 speed=1000` 后输入 `s`，10 秒后再 `s`，PERF1 增加 ≥8 且 PERF3 不增加记为成功。不要执行修改 PHY 延迟的 `d` 命令。

### 5N：NPU 自检与整网

1. 用本卡 `board_npu.elf`：

   `python tools/board/uart_tool.py tasks/win/20261102-43-npu-rnd1-boards/src/board_npu.elf --elf --baud 2000000 --port COM7 --log tasks/win/20261102-43-npu-rnd1-boards/artifacts/N/uart/board_npu.log`

   其他工程替换日志目录标识，不覆盖 N 的日志。

2. 完整执行现有 39 项：A 寄存器 3 项、B 小用例 15 项、C 整网 1 项、D 连续整网 20 项。保存全部串口原文；不改测试程序或期望值。
3. B 中重点记录全负数 POOL、多输出块、半块、LUT、残差、stride2、C4 首层和 UPSAMPLE。C 对六个检测头的 725760 B 逐字节比较；D 使用现有 CRC32 连续比较 20 帧。
4. 记录 `NPU board: PASS 39/39`、C-YOLO 的 PERF0/MAC/ms/frame/fps/CRC32、全部 D 行，以及与旧 B3N 相同测试的周期差。没有旧小用例周期时只列本轮值。

### 5E：B3N 网口图片识别

1. 关闭占用串口的加载 CLI，运行本卡 checkout 的 `python tools/debug_tool/main.py`。选择 B3N，连接实际串口，使用烧录页加载本卡 `demo_npu.bin`，加载地址及入口 `0x10000000`；保存启动日志与应用 PEER/连接结果。
2. 上传第 2 节给定目录中的模型。单张识别 3 张，记录检测框是否落在目标上，并截图。
3. 文件夹连续识别至少 20 张，记录完成数、失败数及工具原始原因、平均往返时间、fps、每张 NPU 周期和 CPU 后处理周期。连续识别期间导出 `edtm_npu.csv`。
4. 将 NPU 核心 fps 与包含上传、回传和 CPU 后处理的端到端 fps 分别记录。网口异常时沿用卡 24 / `docs/debug/2026-11-01-bios-eth-load.md` 已有诊断步骤，保留串口及工具报错原文。

### 5VN：摄像头 + 最新 NPU

沿用卡 38 第 5VN 节和卡 21 第 5VN 节，程序替换为本卡 `src/demo_vnpu.bin`：

1. 启动日志应为 `demo_vnpu (B3VN vision + NPU)`；按 `sw/apps/demo/README.md` 上板检查清单执行，上传相同模型。
2. S1 连续运行，至少三次 `status`，记录 camera frames、推理次数、检测数、`Overlay CPU cycles`、NPU/后处理周期；拍摄目标检测框及移动后旧框清除情况。
3. S2 的 HDMI、ETH、both 输出，WIN0/1 图片输入及切回摄像头沿用卡 21 的 ETH 检查；记录帧率、丢帧、串口和画面。
4. 导出视频识别负载的 EDTM CSV。此处有真实 VIN/PIX/GEO/DISP 和 DDR 竞争，与 N 独立自检结果分别记录。

### 5F：完整 B3F 的图像/几何处理

仅 F 执行，沿用卡 24 第 5V / 5E 节，用本卡 `demo_vision.bin` 按 `sw/apps/demo/README.md` 的图像处理检查清单逐项测试：摄像头帧率、CH0 overflow、PIX/GEO 模式、HDMI、ETH 和 both。各模式截图，网口视频各约 60 秒记录帧率和丢失计数，并导出 EDTM。VRN 没有 PIX/GEO，沿用卡 37 不运行依赖它们的 demo_vision/demo_vnpu；本卡不为 VRN 新开发视频应用。

### 5R：RND v1

F/VRN 沿用卡 39：

1. 加载本卡 `rnd_v1_board.elf`，将串口各项 CRC 与本卡 `rnd_v1_expected.log` 对照，按卡 21 的画面清单观察 HDMI；不要用当前 v2 的期望生成器替代该日志。
2. 加载 `s3_v1.elf`，只跑 benchmark、LAYERS，记录各场景 fps、LAYERS 画面；可建立网口遥测并导出 EDTM。WIDGETS、串口虚拟输入按第 2 节已知限制不测试。
3. 两种顶层分别报告，不能用其中一种通过代替另一种。

### 5C：CPU 与 ILA

F/VRN 沿用卡 33 第 7 步第 2 项及 `fpga/ip/ila_cpu.md`：复位进入本卡 SRAM monitor，CoreMark 5000 次；记录编译信息、CRC、分数和 HPM。以该 monitor 串口实际 `HPM round instructions` 设置 minstret 触发值；值为 1441025033 时使用原 `0x0055E44C09`，否则使用实际值。两轮分别抓冻结计数并与串口对比，再抓一次运行中 1024 周期窗口。N/VN 不增加 ILA 测试。

## 6. 产物

C 将四工程结果汇总到本卡一个 `result.md`，精简产物分别放在 `tasks/win/20261102-43-npu-rnd1-boards/artifacts/<N|VN|F|VRN>/`。每个工程先创建自己的 `uart/` 再运行日志命令，完整报告和 bitstream 的 Windows 本地路径也分别记录。

| 产物 | 内容 |
|---|---|
| `flow_summary.txt`、`pnr_progress.txt` | 各阶段耗时、CPU 时间、峰值内存、线程数；每轮未布通/过用原文 |
| `timing_summary.txt` | 各时钟域 slow/fast WNS/TNS/WHS/THS、recovery/removal；RGMII 已知例外单列 |
| `timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 每时钟最差 200 条 setup 的起点/终点/裕量/逻辑级数，最差 20 条 setup 逐级明细、20 条 hold；导出方法同卡 32 第 2 步第 2 项 |
| `npu_weight_paths.txt` | 同卡 24：到 `g_weight_byte[*].weight_r` D 端及从其出发到 APM 的各最差 20 条，含位置/走线延迟/裕量 |
| `resource_summary.txt`、`resource_hier.txt`、`high_fanout.txt` | LUT/FF/DRM/APM/分布式 RAM/IO/PLL 汇总、模块层次资源；高扇出四张表（1000 条）；列出 NPU、result_quant、activation_lut、nonconv、conv 的已有统计 |
| `uart/*.log`、`uart/*.raw` | BIOS、eth_diag、board_npu、demo_npu 串口原文 |
| `edtm_npu.csv`、`photos/*` | 连续图片识别带宽、单张叠框截图 |
| `edtm_vision.csv`、`edtm_rnd.csv`（对应工程） | 视频/视频识别、RND/S3 负载；画面和 fps 对应到各自程序 |
| `ila/`（F/VRN） | .fic、插入截图、上板冻结值和窗口 CSV/截图 |
| `placement_by_module.txt`、`congestion.txt`（VN/F/VRN） | 同卡 37/39：一级模块放置范围、拥塞报告原文；与旧对应工程同轮次比较 |
| `native_reports/` | CMR、SNR、DMR、PRR、RTR 原文；大于几 MB 的文件在 result.md 说明用途 |

完整工程、IP 目录、数据库、网表、bitstream 和完整构建日志留在 Windows 本地；在 result.md 写本地路径，不入库。

## 7. 通过判据

- 实现完成，0 未布通网络；各时钟域 setup/hold 不违例。沿用卡 24 已确认的 `clk_rgmii_ref → clk_eth` 慢角 hold 例外，单列实际值；其他违例照实报告。存在时序违例但已生成 bitstream 时，沿用卡 24 继续上板并分别报告时序和功能结果。
- NPU `PASS 39/39`，整网输出一致，20 次连续整网全部通过。性能报告实测值及旧板对比，不新增周期阈值。
- 网口接收 5/5 成功；BIOS 串口及网口加载能自动运行；单张识别结果正确，批量队列能继续，取得完成/失败数及原因。
- VN 摄像头识别及检测框显示正常；F 的图像/几何处理检查逐项有结果；F/VRN 的 RND v1 自检匹配本卡期望日志、benchmark/LAYERS 可运行、CPU CoreMark CRC 正确且 ILA 冻结计数与串口一致。沿用上述旧 S3 已知限制。
- 所有数字来自报告和日志原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261102-43-npu-rnd1-boards 结果（N / VN / F / VRN）

| 项 | 内容 |
|---|---|
| 代码 commit / PC 工具 commit | |
| 程序来源 | 本卡 src；新程序 92b38fd2，RND v1 三件套 6890ac7e |
| 工程路径、PDS 版本、器件 | |
| 源文件数 / 时钟数 | |
| ROM/SRAM 初始化文件、ETH PLL 配置 | |
| PnR 设置、线程数、各阶段耗时、轮数、峰值内存 | |
| 完整报告及 bitstream 本地路径 | |
| 旧板对照 commit / 结果出处 | |

## 四工程执行状态
| 工程 | 工程路径 | 顶层 | 源文件数 | 开始/结束时间 | 阶段/轮次 | 未布通/过用 | bitstream 路径 |
|---|---|---|---|---|---|---|---|

## 时序
| 工程 | 时钟 | WNS | TNS | WHS | THS | 最差路径起终点/级数 |
|---|---|---|---|---|---|---|
RGMII 例外、recovery/removal、NPU 权重 D 端/输出路径：

## 资源
| 工程/模块 | LUT | FF | DRM | APM | 分布式 RAM | 旧板对比 |
|---|---|---|---|---|---|---|

## NPU 功能与性能
每工程的 39 项结果、C-YOLO 原文、D-01 至 D-20 原文位置；失败首个地址/期望/实际值。
| 工程/测试 | 旧板 PERF0 / fps | 本轮 PERF0 / fps | MAC | 说明 |
|---|---|---|---|---|

## BIOS / ETH
串口与两种网口加载的耗时和结果；PHY 复位接收 5 次各自的 PERF1/PERF3 增量。

## 图片识别
单张 3 张的结果和截图；批量完成/失败数、原因、平均往返时间、端到端 fps、NPU/后处理周期；EDTM 文件。

## VN 视频识别 / F 图像几何处理
摄像头 fps、推理与检测计数、Overlay CPU cycles、画面、视频网络输出及 EDTM。

## F/VRN RND v1
CRC 对照、benchmark、LAYERS、遥测结果；标明使用本卡 v1 程序。

## F/VRN CoreMark + ILA
CoreMark CRC/分数/HPM，实际触发值，两轮冻结值对照，窗口 CSV/截图。

## 问题与偏离
```

完成后 C 提交本卡 `result.md` 与 `artifacts/`，提交信息 `win: 20261102-43-npu-rnd1-boards results`，推送 `win/20261102-43-npu-rnd1-boards`，告知用户结果分支；不直接提交到 b3/main。
