# 上板实测实施方案

| 项 | 内容 |
|---|---|
| 版本 | v0.4（B2 已确认 2026-10-29；B3 按 RND/DISP 设计记录拆分） |
| 日期 | 2026-10-29 |
| 关联 | SoC 规格 v0.15 第 3、7.5、9 节；设计记录 `docs/design/2026-10-29-b2-software.md`；`plan/cpu-plan.md`、`plan/sys-subsys-plan.md`、`plan/mem-subsys-plan.md`、`plan/vision-plan.md`、`plan/npu-plan.md` |

阶段编号用 B1–B3，避免与 SoC 规格中的演示场景 S1–S3 混淆。

## 1. 目标和完成标准

| 阶段 | 内容 | 完成标准 |
|---|---|---|
| B1 | CPU 最小系统：CPU、I$/D$、系统子系统（ROM、SRAM、UART、GPIO、CLINT、PLIC、I2C、SYSCTRL），clk_sys 100 MHz（用户 2026-10-28 指定，C-S1 前的临时值） | 上板打印启动 logo 和启动信息；监控程序 CoreMark CRC 正确，输出分数、CoreMark/MHz、HPM；PDS 资源和时序报告 |
| B2 | 完整 SoC（CPU、系统、存储、VIN + PIX + CH2、GEO、DISP、NPU、ETH；RND 未开发不接）：DDR3、HDMI 输出、两路 OV5640、千兆网口；clk_mem 125 MHz、clk_npu 150 MHz、clk_sys 100 MHz | S2：摄像头 → PIX →（GEO）→ HDMI 显示正确；S1：摄像头/网口图像 → CH2 → NPU → CPU 后处理 → 画框显示，网口回传的 NPU 输出与参考模型逐字节一致；调试工具实时显示各端口 DDR 读写带宽；BIOS 烧录、经 BIOS 运行 tuned CoreMark；PDS 时序和资源 |
| B3 | B2 + RND（2D 绘制、图层合成）+ S3 图形界面（LVGL） | RND 规格和开发完成后细化 |

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
| B1-7 | Windows：生成 PLL 和 7 个已有 IP（ROM/SRAM 带初始化文件），综合、布局布线、bitstream，上板，采集串口日志（启动信息、CoreMark O2 和 tuned）和资源时序报告 | 用户 + Windows Codex | B1-1–B1-6 | 串口日志、报告 | `tasks/win/<日期>-board-b1/` | [x] 2026-10-28：第一次上板启动信息正确、100 MHz 满足（+0.674 ns）（`docs/reports/2026-10-28-board-b1.md`）；第二次（07 卡 B 部分）5000 次正式成绩 O2 **3.603**、tuned **4.310** CoreMark/MHz，CRC PASS，按键 PASS（`docs/reports/2026-10-28-perf-board-b1-coremark.md`）；LED 用户确认正常 |
| B1-8 | BIOS（SoC v0.14 7.5 第 3、3a 条：按住 KEY1 复位进入，烧录 SRAM 程序，按复位运行）；SRAM 应用每次启动恢复 `.data`、清零 `.bss`（第 3b 条）；uart_tool 和板级/sys_cpu 测试改为 BIOS 流程 | Codex · GPT-6.1 Sol | B1-7 | 板级仿真覆盖烧录、复位运行两次结果一致；sys_cpu、sys_subsys smoke | task-boot-bios | [x] 2026-10-29：BIOS（KEY1 100 ms 窗口、SCRATCH0、烧录后写回 D$）、`.data` LMA 恢复，板级/sys_cpu 两次复位一致，52 个目录通过（`docs/debug/2026-10-28-boot-bios.md`）；上板验证按用户要求并入 B2-4 |
| B1-9 | EdRV32 调试工具 `tools/debug_tool/`（用户串口工具改名入库）：BIOS 选择文件烧录、网口文件收发（eth-spec 2.3–2.6） | Codex · GPT-6.1 Sol | — | unittest：烧录字节流、应用头逐字节、本机回环 | task-debug-tool | [x] 2026-10-28：`tools/debug_tool/`（用户工具 a7b8cf2 导入改名）；BIOS 烧录（GUI/CLI/REST）、UDP 网口收发；14 项 unittest、本机回环通过；待 Windows 上确认 GUI 和烧录 |

### B2

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支或任务卡 | 状态 |
|---|---|---|---|---|---|---|
| B2-1a | `edrv32_soc_top`（全部子系统和引擎、APB 槽、PLIC 源、复位、GPIO 位分配）；reset_ctrl 增加 `rst_npu_n`；mem_xbar 统计读写拆分；`soc.f`；连接冒烟测试 `verif/soc/soc_connect` | Codex · GPT-6.1 Sol | — | lint 0 告警；soc_connect smoke；mem_xbar/mem_subsys/sys_subsys/sys_cpu 不回退 | task-soc-top | [x] 2026-10-29：5f311e2–07eeff1 已合入协调者分支；121 次验收 PASS，SoC lint 0 告警（expand_files 去重），GEO 空矩形描述符 DONE 经 PLIC 源 10 到 MEIP |
| B2-1b | VIN CH2 RTL（2×2 平均、量化、letterbox、INT8_C4） | Codex · GPT-6.1 Sol | — | lint 0 告警；`verif/unit/vin_ch2`；VIN 现有测试不回退 | task-vin-ch2 | [~] 2026-10-29 RTL 完成（Yosys 1523 LUT / 2049 FF）；与 B2-1c 测试合并后 VI-20 失败，联调 B2-1e 进行中 |
| B2-1c | VIN CH2 模块级验证 VI-19–VI-23（独立，与 `tools/npu` 预处理交叉核对） | Codex · GPT-6.1 Sol | 与 B2-1b 并行 | VIN block smoke/full 通过 | task-vin-ch2-verif | [~] 2026-10-29 测试已交付（abcd685，与 input_pack.py 交叉核对 983040 B 差异 0），待与 B2-1b 一起合入后对真实 RTL 回归 |
| B2-1f | 寄存器复位值与位域缺项整理（只读 RTL，报告 `docs/reports/2026-10-29-regs-reset-survey.md`），之后协调者起草规格回填交用户确认（第 4 节） | Codex · GPT-6 Luna | B2-1a | 报告覆盖全部 null 复位值和多位域 VALUE 字段 | task-regs-reset-survey | [~] 2026-10-29 派发（ctx_ce846f7cf53f） |
| B2-1d | SoC 级验证（`docs/testplan/soc-testplan.md`，待写）：S2 数据流、S1 数据流（小用例 NPU）、ETH 收发、并发流量下 DISP 不读空/VIN 不溢出、监控统计 | Codex · GPT-6.1 Sol | B2-1a、B2-1b、B2-1f 回填 | SoC 级 smoke/full | — | [ ] |
| B2-2 | 板级：DDR3 IP 创建说明（厂商 `6_IP_setup_packet`、`2_9_ddr3_test`）、DDR 适配器（已有，接入）、PLL（clk_mem 由 DDR IP 给出，clk_pix 74.25 MHz 与 5 倍串化时钟，clk_npu 150 MHz，clk_sys 100 MHz）、HDMI TMDS 串化、两路 DVP 摄像头 IO、RGMII ↔ 8 位 MAC 适配（厂商 `2_11_ethernet_test`）、B2 板级顶层、约束（引脚取自厂商例程和 `mini-base管脚映射.xlsx`）、导入脚本 | 协调者 + Codex | B2-1a | 板级仿真（DDR/TMDS/RGMII 模型）PASS；约束与引脚表逐项核对 | — | [ ] |
| B2-3a | 引擎寄存器 JSON 描述（`rtl/include/regs/`）和 C 头生成器 `tools/gen/regs.py` | Codex · GPT-6.1 Sol | — | 重复生成不变；`_Static_assert` 与规格数字对照 | task-regs-gen | [x] 2026-10-29：8 个模块 JSON 与头文件，142 条静态断言通过 |
| B2-3b | 引擎驱动（VIN/PIX/GEO/DISP/NPU/ETH/MEM_XBAR/PERF_MON）；OV5640 初始化（I2C0、GPIO bit12–15） | Codex · GPT-6.1 Sol | B2-1a、B2-3a | SoC 级仿真中驱动用例通过 | — | [ ] |
| B2-4 | 演示程序 `sw/apps/demo`：S2 图像处理（菜单/KEY2–4 切换 PIX、GEO）；S1 目标检测（CH2 → NPU → 后处理 → 画框）；网口加载 NPU 镜像、网口图像检查；输出选择 HDMI/网口/同时、网口 720p 视频 1–60 fps（设计记录 3.4a）；DDR 监控记录 100 Hz 经网口上报（设计记录 3.5） | Codex · GPT-6.1 Sol | B2-3 | 后处理 C 实现与 Python 参考逐项一致；SoC 级仿真跑通 S1 小用例和监控记录 | — | [ ] |
| B2-5a | 调试工具：DDR 监控页、场景控制、YOLO 数据发送与回传接收（设计记录 3.5、3.6） | Codex · GPT-6.1 Sol | 设计记录 3.5 记录格式 | unittest：记录解析、带宽换算、CSV、UDP 回环；合成数据截图 | task-debug-monitor | [x] 2026-10-29：DDR 监控页、场景控制、YOLO 发送/回传接收、`telemetry_sim.py`；33 项 unittest；截图 `tools/debug_tool/ddr-monitor.png`；场景命令待 B2-4 填写，Windows GUI 待 B2-6 确认 |
| B2-5b | 调试工具 YOLO 页：板上检测框显示、参考模型与后处理参考比对；视频页（网口视频接收、检测框叠加、输出选择，设计记录 3.4a、3.6） | Codex · GPT-6.1 Sol | B2-4 后处理参考 | 参考比对用例 | — | [ ] |
| B2-6 | Windows：生成 DDR3、PLL 等 IP，PDS 综合布局布线（完整 SoC 时序、资源）；上板 S2、S1、监控；B1-8 BIOS 烧录和经 BIOS 运行 tuned CoreMark；调试工具 GUI 确认 | 用户 + Windows Codex | B2-1–B2-5 | 串口日志、截图、监控 CSV、报告 | `tasks/win/<日期>-board-b2/` | [ ] |

### B3（设计记录 `2026-10-29-rnd-disp.md`；规格写好后细化为任务）

| 编号 | 内容 | 执行者 | 依赖 | 状态 |
|---|---|---|---|---|
| B3-0 | RND/DISP 设计决策：DISP 两层扫描叠加（L0 RGB565 带卷轴，L1 ARGB8888 非预乘）、RND 命令集 T2、游戏路线 G3、预算初值（VIN+PIX+DISP 12K、RND 10K，[待定]）、LVGL 子模块 | 协调者 + 用户 | — | [x] |
| B3-1 | 规格：`disp-spec.md` v0.3、`rnd-spec.md` v0.1、SoC v0.16；验证方案 `disp-testplan` v0.3、`rnd-testplan` v0.1；实施方案 `rnd-plan.md` | 协调者 | B3-0 | [x] 2026-10-29 |
| B3-2 | （`rnd-plan.md` D-R1–R-W1）DISP 两层 RTL 与验证；RND RTL 与验证（移植旧工程 alpha 流水线、圆角、字形、位图、模糊；新增 TILEMAP、索引色、混合模式、BORDER） | Codex | B3-1 | [~] 2026-10-29 D-R1、D-T1、R-R1、R-T1 派发；DISP 合入等 B2-6 PDS 之后 |
| B3-3 | 软件：LVGL 子模块和绘制单元驱动、DDR 资源段、S3 界面；S1 改为 RND 画框进 L1；网口发送帧按设计记录 3.6 | Codex | B3-2 | [ ] |
| B3-4 | 游戏：自制横版游戏（TILEMAP + L0 卷轴 + L1 精灵）；NES 模拟器纯软件移植并实测帧率（效果不好时另写设计记录评估硬件 PPU 辅助） | Codex | B3-2 | [ ] |
| B3-5 | Windows：PDS 时序资源（定稿预算）、上板 S1–S3 和游戏 | 用户 + Windows Codex | B3-2–B3-4 | [ ] |

## 4. 规格定稿项

- 寄存器描述缺项回填（B2-3a 列出，生成头中暂为"未规定"、不产生复位值宏）：SoC 7.1 公共寄存器（CTRL、STATUS、IRQ_EN、IRQ_STAT、ERR_CODE、DESC_BASE/COUNT、DONE_COUNT、PERF）在 VIN/PIX/GEO/DISP/ETH/PERF_MON/MEM_XBAR 规格中的复位值；MEM_XBAR `WEIGHT[P2]`、`RATE[P0/1/3/4/5]` 复位值；各模块只有取值范围、没有位宽或位域名的寄存器（以 `VALUE` 命名）；npu-spec 第 4 节"STATUS.FRAME 不使用"应为 IRQ_STAT.FRAME、"公共寄存器复位全 0"与 ID = 0x00060001 的矛盾。依据 RTL 实际复位值整理后经用户确认写入规格（B2-1d 前完成）。

- clk_sys 频率：B1 用 100 MHz；正式值在 C-S1 依据完整 SoC 的 PDS 结果和布局优化调研（`docs/guides/pds-floorplan.md`）确定。
- 监控程序外设测试项（SoC 7.5 第 4 条 [待定]）：B1 上板时按实际结果由用户确认。

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| PDS 存储初始化文件格式 | B1 已上板确认（HEX 每行 16 字符、补满深度） |
| 完整 SoC 的时序：NPU 单独测量只有 +0.214 ns（150 MHz），clk_mem 第三轮 +0.388 ns，同片后布线更拥挤 | V-R8 提升媒体余量，V-W5 复测；B2-6 先看各域时序，不满足时按域单独处理（布局约束见 `guides/pds-floorplan.md`） |
| 完整 SoC 的资源：器件约 160K LUT、415 DRM、740 APM；NPU 157 DRM / 290 APM，媒体 46 DRM / 141 APM | B2-1a 后用 Yosys 估计，B2-6 以 PDS 为准 |
| 演示程序超出 SRAM 64 KiB | 设计记录 3.1 估算 40 KiB；超出时讨论 BIOS 增加烧录 DDR 程序 |
| DDR3 IP、HDMI、RGMII、OV5640 板级部分没有在本项目中验证过 | B2-2 依据厂商例程逐项移植，先做板级仿真；B2-6 上板按"DDR → HDMI → 摄像头 → 网口 → NPU"顺序逐项确认 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-28 | v0.1 | 初稿：用户要求开始上板，B1–B3 三个阶段，clk_sys 暂用 100 MHz |
| 2026-10-28 | v0.2 | 用户上板反馈：监控程序输入按行读取、按键测试改为 10 s 内等待按下松开；增加 B1-8 BIOS、B1-9 调试工具（SoC v0.14） |
| 2026-10-29 | v0.3 | 用户要求：B2 用完整 SoC（含 NPU、ETH），跑通 YOLO，DDR 带宽经网口实时监控并在调试工具可视化，BIOS 上板验证并入 B2；B2 拆为 B2-1a–B2-6（设计记录 `2026-10-29-b2-software.md`）；原 B3 内容并入 B2，B3 改为 RND 与 S3 |
| 2026-10-29 | v0.4 | B3 按 RND/DISP 设计记录（`2026-10-29-rnd-disp.md`，用户决定 Q1–Q4）拆为 B3-0–B3-5 |
