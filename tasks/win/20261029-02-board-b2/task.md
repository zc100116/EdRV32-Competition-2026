# 任务卡 20261029-02-board-b2：B2 完整 SoC 生成 IP、综合实现、点亮

## 1. 目标

把 B2 板级顶层 `edrv32_fpga_board_b2_top` 做完，并取得资源和时序报告（`docs/plan/board-plan.md` B2-6 第一部分）：
- 完整 SoC：CPU、系统、存储、VIN + PIX + CH2、GEO、DISP、NPU、ETH；
- 板上设备：DDR3、HDMI 直出 TMDS、两路 OV5640、RGMII 千兆网口；
- 流程：生成全部 IP，综合、布局布线、生成 bitstream，下载上板；
- 点亮：确认启动信息、监控程序和 I2C 摄像头应答。

演示程序（S1/S2、网口、监控）不在本卡。它经 BIOS 烧录到 SRAM 运行，**不需要重新生成 bitstream**，由后续任务卡提供。

## 2. 输入

- 任务卡 commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。
- 板级顶层 `fpga/rtl/edrv32_fpga_board_b2_top.v`，以及 `edrv32_fpga_ddr_adapter.v`、`edrv32_fpga_tmds.v`、`edrv32_fpga_rgmii.v`。
  - 端口和引脚逐位见 `fpga/rtl/README.md` 的 B2 一节，共 48 个端口、137 个引脚。
  - 摄像头 PWDN 不引出（模块固定），两路复位接 T22、AC26。
- 约束 `fpga/constraints/edrv32_fpga_board_b2_top.fdc`：17 个时钟定义。
  - DDR IP 内部时钟的层次名取自厂商 `2_9_ddr3_test`；PLL 输出引脚名需要在 PDS 中确认（步骤 7）。
- 导入脚本 `fpga/scripts/import_board_b2_top.tcl`：展开 `rtl/filelists/soc.f`（去重）加 4 个板级文件，定义 `FPGA_MODE`，结束时打印 `edrv32: added <N> sources`。
- 本卡 `src/`：在 Linux 端用本任务卡 commit 构建，GCC 15.2.0。

  | 文件 | 内容 |
  |---|---|
  | `ip_rom_boot.dat` | bootloader + BIOS（5348 字节），ROM 初始化文件，2048 行 × 16 HEX 字符 |
  | `ip_ram_sram.dat` | 监控程序（20392 字节 text），SRAM 初始化文件，8192 行 × 16 HEX 字符 |

- 串口工具：`tools/board/uart_tool.py` 或调试工具 `tools/debug_tool/`（B1 已用过）。

## 3. 环境

- PDS 2022.2-SP6.1，器件 PG2L200H-6 FBB676，JTAG 下载，USB 串口接 UART。
- 工程：新建 `G:\codex_project\EdRV32-FPGA\EdRV32-B2\`（与 B1、MEDIA 工程同级）。B1、MEDIA、NPU 工程保留不动。路径不同时写进 `result.md`。

## 4. 需要的 IP

各 IP 的选项见 `fpga/ip/<IP 名>.md`，总表和 B2 生成顺序见 `fpga/ip/README.md`"B2 Windows 用户 IP 生成顺序"。

| IP | 操作 |
|---|---|
| `ip_pll_sys` | 从 B1 工程复制（`ip_pll_sys.md`，27 → 100 MHz） |
| `ip_pll_npu`、`ip_pll_video`、`ip_pll_eth` | **新生成**。IP Compiler 显示的实际频率与说明不一致时停下，把实际频率和分频参数告诉 Codex 写进 result.md |
| `ip_ddr3` | **新生成**（`ip_ddr3.md`，按厂商 `2_9_ddr3_test` 的设置）。生成后把实际端口列表、`core_clk` 频率交给 Codex 核对 |
| `ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w` | **新生成**（512 深，分别只用 128、16 项） |
| `ip_rom_boot`、`ip_ram_sram` | **重新生成**，初始化文件选本卡 `src/` 中的两个 `.dat`（HEX） |
| CPU/SYS 其余 5 个（I$/D$ tag/data、`ip_mul_s33x33`） | 从 B1 工程复制 |
| VIN/PIX/GEO/DISP/ETH 的 6 个（`ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、`ip_ram_disp_scan`、`ip_ram_eth_buf`、`ip_ram_eth_fifo`） | 从 MEDIA 工程复制 |
| NPU 的 9 个（`ip_ram_npu_*` 7 个、`ip_mul_npu_quant_low/high`） | 从 NPU 工程复制 |

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261029-02-board-b2 origin/main`；阅读本卡和 `fpga/ip/README.md`，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 新建 B2 工程（PG2L200H-6 / FBB676）；按第 4 节复制已有 IP。 |
| 2 | 用户（U） | 按第 4 节生成 3 个 PLL、`ip_ddr3`、两个 mem_xbar RAM，重新生成 ROM/SRAM（选本卡 `src/` 的初始化文件）。告诉 Codex IP 目录。 |
| 3 | Windows Codex（C） | 逐个核对 IP 的模块名和端口与 `rtl/tech/` 包装模块、板级顶层的例化一致（`fpga/ip/*.md` 末尾的期望端口），并检查 ROM/SRAM `.idf` 的初始化选项。不一致时停下，写进 result.md（不改生成文件，也不改 RTL）。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | 执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_b2_top.tcl`，把打印的 `edrv32: added <N> sources` 告诉 Codex（预期 145：SoC 141 + 板级 4）。编译报错就停下，把报错原文交给 Codex。 |
| 5 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。任何一步报错就停下，把报错原文交给 Codex。 |
| 6 | Windows Codex（C） | 资源超出器件容量时（`dev_map` 或 `pnr` 报错），按层次导出资源分布后停下，回传。 |
| 7 | Windows Codex（C） | **确认约束生效**：时序报告中应有 clk_sys 10 ns、clk_mem 8 ns、clk_npu 6.667 ns、clk_pix 13.468 ns、clk_serial、clk_eth，以及 DDR IP 内部时钟。`create_generated_clock` 不能报找不到对象。**引脚名不对时**：从网表中找到实际层次名，只在本地 `.fdc` 中改正后从步骤 4 重跑，把改后的行写进 result.md（协调者改仓库）。各时钟 setup 违例照常继续上板，但写明。 |
| 8 | 用户（U） | 接好 HDMI 显示器、两路摄像头、网线（另一端接 PC），下载 bitstream；告诉 Codex COM 口号。 |
| 9 | Windows Codex（C） | **启动信息**：打开串口记录 `build/board/b2_boot.log`，请用户按一下复位键（不按 KEY1）。日志应出现 EdRV32 logo、启动信息（`CLK_SYS_HZ 100000000`）和监控程序菜单。没有输出时，请用户报告 LED 状态。DDR 初始化未完成时 SoC 保持复位（`mem_ready`），串口不会有任何输出，记下这一现象。 |
| 10 | Windows Codex（C） | **系统信息和外设测试**：菜单 3、菜单 2 各运行一次，日志 `b2_sysinfo.log`、`b2_periph.log`。记录 I2C 扫描到的地址。监控程序不释放摄像头复位（GPIO bit13/15 复位后为 0），扫不到 OV5640 的 0x3C 属正常；摄像头在演示程序任务卡中检查。 |
| 11 | Windows Codex（C） | **BIOS**：按住 KEY1 并复位，确认进入 BIOS 菜单（日志 `b2_bios.log`），然后复位退出。 |
| 12 | 用户（U） | 观察并告诉 Codex：HDMI 显示器是否检测到信号（DISP 在监控程序下未使能，黑屏或"无信号"都如实记录）；网口 PHY 指示灯状态。 |
| 13 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-02-board-b2 results`，推送 `win/20261029-02-board-b2`，告诉用户完成并给出分支名。中途停下时，已完成部分照常回传，并写明停在哪一步和现象。 |

## 6. 产物

放在 `tasks/win/20261029-02-board-b2/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/b2_boot.log`、`b2_sysinfo.log`、`b2_periph.log`、`b2_bios.log` | 串口原始日志（文本） |
| 2 | `ip/` | 新生成 IP 的实际端口、PLL 实际频率和参数、DDR3 选项截图；ROM/SRAM 的初始化选项（`.idf` 中相关行） |
| 3 | `timing_summary.txt` | 每个时钟 slow/fast 角的 WNS/TNS/WHS/THS、违例端点数、推算 Fmax |
| 4 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM 18K/36K、APM、分布式 RAM、IO、PLL）；按层次到 `u_soc` 下一级（CPU 子系统、系统子系统、存储子系统、各媒体引擎、NPU、ETH）和板级适配 |
| 5 | `setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | 每个时钟域最差 200 条 setup（一行一条）、最差 20 条 setup 逐级明细、最差 20 条 hold（CLAUDE.md 10.5） |
| 6 | `fdc_used.fdc` | 仅在步骤 7 本地改过约束时提交改后的全文 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 实现：综合、布局布线、bitstream 完成；资源在器件容量内。
- 上板：串口打印 logo 和启动信息（说明 DDR 初始化完成、`mem_ready` 释放了复位）；监控程序菜单 2、3 有输出；能进入 BIOS。
- 报告：第 6 节产物齐全；所有数字来自 PDS 报告和串口日志原文，找不到的写"未取得"。时序是否满足不作为停止条件，但必须写明。

## 8. result.md 模板

```markdown
# 20261029-02-board-b2 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | <完整哈希> |
| PDS 版本 | |
| 工程路径 | |
| 导入源文件数 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## IP
| IP | 模块名 | 端口与包装/顶层一致 | 备注（实际频率、参数；初始化文件） |
|---|---|---|---|

## 约束
- 各时钟周期：
- create_generated_clock 是否全部命中、有无本地修改（改后的行）：

## 时序
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| | LUT | FF | DRM 18K/36K | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|

按层次：

## 上板
- 启动信息（日志摘录）：
- 系统信息、外设测试（I2C 扫描地址）：
- BIOS：
- HDMI 显示器、网口指示灯（用户观察）：

## 完整报告在 Windows 本地的路径

## 备注
```
