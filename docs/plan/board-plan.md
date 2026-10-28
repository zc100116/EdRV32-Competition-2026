# 上板实测实施方案

| 项 | 内容 |
|---|---|
| 版本 | v0.1（草案，待用户确认） |
| 日期 | 2026-10-28 |
| 关联 | SoC 规格 v0.13 第 3、7.5、9 节；`plan/cpu-plan.md`、`plan/sys-subsys-plan.md`、`plan/mem-subsys-plan.md`、`plan/vision-plan.md`、`plan/npu-plan.md` |

阶段编号用 B1–B3，避免与 SoC 规格中的演示场景 S1–S3 混淆。

## 1. 目标和完成标准

| 阶段 | 内容 | 完成标准 |
|---|---|---|
| B1 | CPU 最小系统：CPU、I$/D$、系统子系统（ROM、SRAM、UART、GPIO、CLINT、PLIC、I2C、SYSCTRL），clk_sys 100 MHz（用户 2026-10-28 指定，C-S1 前的临时值） | 上板打印启动 logo 和启动信息；监控程序 CoreMark CRC 正确，输出分数、CoreMark/MHz、HPM；PDS 资源和时序报告 |
| B2 | B1 + DDR3 + 图像通路：VIN（OV5640）、PIX、GEO、DISP（HDMI 输出），clk_mem 125 MHz | 摄像头 → PIX → DDR → DISP 显示正确；GEO 对 DDR 中的帧做变换并显示；PERF_MON 输出各主设备 DDR 带宽 |
| B3 | B2 + NPU + ETH：PC 经网口下载权重和图像，NPU 跑通 YOLO | 检测结果与参考模型一致；帧率、DDR 带宽 |

## 2. 前置条件

- B1：CPU、cache、系统子系统 RTL 已合入 main；bootloader（`sw/boot/`）、监控程序（`sw/apps/monitor/`）已有。C 扩展按 cpu-spec v0.13 去掉：B1 先用已验证的 P1 配置（`15d21f8`：`RVC_EN` 默认 0、软件 rv32im），C-R9 再删除代码。
- B2：存储子系统已合入 main；VIN/PIX/GEO/DISP 模块级验证通过（PIX 流水化 V-R6 已完成，待 PDS 复测）；`edrv32_soc_top` 和媒体子系统顶层**尚未编写**。
- B3：NPU 模块级和整网逐字节一致已完成，ETH 模块级完成；YOLO 驱动和应用软件**尚未编写**。

## 3. 待办清单

### B1

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支或任务卡 | 状态 |
|---|---|---|---|---|---|---|
| B1-1 | P1 配置并入：`RVC_EN` 默认 0，`sw/Makefile`、`sw/boot/program.mk`、`verif/block/sys_cpu/run.py` 改为 rv32im | 协调者 | — | cpu_b2 smoke、sys_cpu smoke 通过 | 协调者分支 | [x] 2026-10-28：P1 并入，生产软件 rv32im，`tools/cpu/` 的 C 验证保留到 C-R9 |
| B1-2 | 时钟 IP：`ip_pll_sys` 创建说明（27 MHz 板钟 D18 → clk_sys 100 MHz，locked）和仿真模型 | 协调者 | — | `fpga/ip/ip_pll_sys.md`、`verif/models/` | — | [x] 2026-10-28：`fpga/ip/ip_pll_sys.md`；仿真模型随 task-board-b1 |
| B1-3 | 存储初始化文件：确认 PDS 初始化文件格式（厂商 demo `2_6_ram_rom_fifo` 的 `init_param_*_exmp.dat`），写 `rom.hex`/`sram.hex` → PDS 初始化文件的转换脚本 | Codex · GPT-6.1 Sol | — | 转换结果与 demo 格式一致；ROM/SRAM 创建说明更新 | task-board-b1 | [x] 2026-10-28：`tools/fpga/mem_init.py`，HEX 每行 16 字符、补满深度（依据厂商 2_6 demo），待上板确认 |
| B1-4 | B1 板级顶层 `fpga/rtl/edrv32_fpga_board_b1_top.v`（PLL、按键复位与 locked、CPU 子系统 + 系统子系统、UART、按键、LED）和板级仿真：从 ROM 启动，打印 logo，跑监控程序菜单中的 CoreMark（小迭代） | Codex · GPT-6.1 Sol | B1-1、B1-2 | 板级仿真 PASS，lint 0 告警 | task-board-b1 | [x] 2026-10-28：`edrv32_fpga_board_b1_top`，`verif/soc/board_b1` 两项 smoke PASS；clk_sys 100 MHz（`clk_sys_hz`） |
| B1-5 | PC 端 UART 下载工具（按 bootloader 的下载协议，Python 标准库 + pyserial），用于不重新生成 bitstream 换 CoreMark 编译选项 | Codex · GPT-6.1 Sol | — | 与 bootloader 协议的仿真或回环测试通过 | task-board-b1 | [x] 2026-10-28：`tools/board/uart_tool.py`（下载、日志、菜单和迭代次数），仿真端到端通过 |
| B1-6 | 约束 `edrv32_fpga_board_b1_top.fdc`（引脚取自厂商 demo）和导入脚本 | 协调者 | B1-4 | — | — | [x] 2026-10-28：`edrv32_fpga_board_b1_top.fdc`（PLL 输出显式 generated clock，依据厂商 DDR3 demo）、`import_board_b1_top.tcl` |
| B1-7 | Windows：生成 PLL 和 7 个已有 IP（ROM/SRAM 带初始化文件），综合、布局布线、bitstream，上板，采集串口日志（启动信息、CoreMark O2 和 tuned）和资源时序报告 | 用户 + Windows Codex | B1-1–B1-6 | 串口日志、报告 | `tasks/win/<日期>-board-b1/` | [~] 2026-10-28 第一次上板：启动信息正确，O2 短诊断 3.600 CoreMark/MHz、CRC PASS，100 MHz 满足（+0.674 ns）（`docs/reports/2026-10-28-board-b1.md`）；监控程序修正输入和按键测试（207b05a）后，5000 次 O2/tuned 和按键补测随 `tasks/win/20261028-07-media-r3-b1/` B 部分下发 |

### B2（B1 上板后细化）

| 编号 | 内容 | 执行者 | 依赖 | 状态 |
|---|---|---|---|---|
| B2-1 | 媒体子系统顶层（媒体 APB、VIN + PIX、GEO、DISP 到 mem_xbar 端口）和 `edrv32_soc_top`（本阶段不含 NPU、ETH、RND）；SoC 级测试 | Codex | — | [ ] |
| B2-2 | 板级：DDR3 IP 创建说明（厂商 `6_IP_setup_packet/DDR3`、demo `2_9_ddr3_test`）、DDR 适配器、HDMI 输出串化、摄像头接口、各 PLL；约束 | 协调者 + Codex | B2-1 | [ ] |
| B2-3 | 软件：VIN/PIX/GEO/DISP/PERF_MON 驱动、OV5640 初始化、演示程序（UART 菜单切换 PIX 运算和 GEO 变换，打印 DDR 带宽） | Codex | B2-1 | [ ] |
| B2-4 | Windows：上板 | 用户 + Windows Codex | B2-1–B2-3 | [ ] |

### B3（B2 上板后细化）

| 编号 | 内容 | 执行者 | 依赖 | 状态 |
|---|---|---|---|---|
| B3-1 | `edrv32_soc_top` 加入 NPU（clk_npu）和 ETH；板级 RGMII 适配和 PHY 约束 | Codex + 协调者 | B2 | [ ] |
| B3-2 | 软件：ETH、NPU 驱动；YOLO 应用（权重和图像经网口下载到 DDR、NPU 推理、CPU 后处理、结果经 UART/网口输出）；PC 端 UDP 发送工具 | Codex | B3-1 | [ ] |
| B3-3 | Windows：上板，与参考模型比对检测结果，测帧率和 DDR 带宽 | 用户 + Windows Codex | B3-1、B3-2 | [ ] |

## 4. 规格定稿项

- clk_sys 频率：B1 用 100 MHz；正式值在 C-S1 依据完整 SoC 的 PDS 结果和布局优化调研（`docs/guides/pds-floorplan.md`）确定。
- 监控程序外设测试项（SoC 7.5 第 4 条 [待定]）：B1 上板时按实际结果由用户确认。

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| PDS 存储初始化文件格式未实测（`fpga/ip/README.md`） | B1-3 先按厂商 demo 确认，B1-7 上板前用 ROM 打印 logo 验证 |
| B2 需要的 SoC 顶层和媒体子系统顶层尚未编写，工作量最大 | B1 进行期间并行开始 B2-1 |
| 完整 SoC 的时序（PIX 修改后未复测，NPU、媒体同片） | B2 的 PDS 先单独看 clk_mem 和 clk_sys |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-28 | v0.1 | 初稿：用户要求开始上板，B1–B3 三个阶段，clk_sys 暂用 100 MHz |
