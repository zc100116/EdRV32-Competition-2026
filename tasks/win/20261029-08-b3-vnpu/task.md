# 任务卡 20261029-08-b3-vnpu：B3VN 图像 + NPU 工程（不含 RND），综合实现与点亮

## 1. 目标

用户 2026-10-29 要求按四个口径建 FPGA 工程：图像（B3V）、图像 + NPU（本卡 B3VN）、渲染器（B3R）、全部（B3F）。B3V、B3R、B3F 在 20261029-07 中，本卡是第四个，可以与卡 07 的三个工程同时布局布线。

| 口径 | 工程 | 顶层 | 内容 |
|---|---|---|---|
| 图像 + NPU | **B3VN** | `edrv32_fpga_board_vnpu_top` | CPU、系统外设、DDR、VIN（两路摄像头）、PIX、GEO、DISP 两层、NPU、ETH。不含 RND |

- 板级端口、引脚和约束与 B2 完全相同（约束内容与 `edrv32_fpga_board_b2_top.fdc` 一致，17 个时钟定义）。
- RND 的 APB 槽按空槽处理，访问返回总线错误；PLIC 源 11 接 0。
- 包含卡 07 第 1 节列出的全部修复（TMDS、DISP clk_pix 流水、PERF_MON、DDR 异步时钟组）。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261029-08-b3-vnpu`，在 `result.md` 中记录完整哈希。
- 板级顶层 `fpga/rtl/edrv32_fpga_board_vnpu_top.v`；端口、接死清单见 `fpga/rtl/README.md` 的“B3 图像 + NPU 板级顶层（B3-10）”一节，IP 清单见 `verif/soc/board_vnpu/README.md`。
- 约束 `fpga/constraints/edrv32_fpga_board_vnpu_top.fdc`；导入脚本 `fpga/scripts/import_board_vnpu_top.tcl`，预期 `edrv32: added 144 sources`。
- 本卡 `src/`：在 Linux 端从 9510c64 构建，与 20261029-03/05 的 `src/` 相同（BIOS 和监控程序此后没有改动）。

  | 文件 | 内容 |
  |---|---|
  | `ip_rom_boot.dat` | bootloader + 新 BIOS（菜单 `1=Program SRAM 2=Load 3=Run 4=Baud`），2048 行 × 16 HEX 字符 |
  | `ip_ram_sram.dat` | 监控程序，8192 行 × 16 HEX 字符 |

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676，JTAG，USB 串口。
- 新建工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3VN\`。
- 使用 `zc100116/b3` 检出，先 `git fetch` 并切到包含本卡的提交。旧工程不用动，也不用继续跑。
- 与卡 07 同时布局布线内存不够时，排在 B3V 之后、B3F 之前，在 `result.md` 中记下实际怎么跑的。

## 4. 需要的 IP


共 29 种 IP，全部从旧工程复制，不需要新生成。各 IP 的选项见 `fpga/ip/<IP 名>.md`。

| IP | 来源 |
|---|---|
| `ip_pll_sys`、`ip_pll_video`、`ip_pll_eth`、`ip_pll_npu`、`ip_ddr3` | B2 工程 |
| CPU/SYS 5 个（I$/D$ tag/data、`ip_mul_s33x33`）、`ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w`、`ip_ram_disp_scan`（例化两次，同一个 IP） | B2 工程 |
| `ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、`ip_ram_eth_buf`、`ip_ram_eth_fifo` | B2 工程 |
| NPU 的 9 个（`ip_ram_npu_line/weight/quant/lut/residual/result/scratch`、`ip_mul_npu_quant_low/high`） | B2 工程 |
| `ip_rom_boot`、`ip_ram_sram`（新 BIOS） | 卡 07 的任一工程；没有时用本卡 `src/` 的 `.dat` 生成。**不能从 B2 复制** |
| RND 的 IP | 不需要 |

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 在 b3 检出中 `git fetch origin`，`git switch -c win/20261029-08-b3-vnpu origin/zc100116/b3`，`git submodule update --init`。阅读本卡和 `fpga/rtl/README.md` 的 B3 各节，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 新建 B3VN 工程（PG2L200H-6 / FBB676），按第 4 节复制 IP，告诉 Codex IP 目录。 |
| 2 | Windows Codex（C） | 检查 ROM/SRAM `.idf` 的初始化文件是新 BIOS 版本（与本卡 `src/` 一致）。不一致时停下，写进 `result.md`。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 在 PDS Tcl 控制台，当前目录为工程目录（`G:\codex_project\EdRV32-FPGA\EdRV32-B3VN`），执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_vnpu_top.tcl`，把 N 告诉 Codex（预期 144）。脚本按工程目录定位仓库，不需要手动改脚本。编译报错就停下，把报错原文交给 Codex。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录每一步的耗时。任何一步报错就停下，回传报错原文和第 6 节中已经取得的产物。 |
| 5 | Windows Codex（C） | **确认约束生效**：clk_sys 10 ns、clk_mem 8 ns、clk_pix 13.468 ns、clk_serial、clk_npu 6.667 ns、cam0/1、clk_eth、DDR IP 内部时钟；时钟组中有 `rst_clk`、`phy_dq_clk_0`、`phy_dq_clk_1`。`create_generated_clock` 不能报找不到对象。setup 违例照常继续，写明即可。 |
| 6 | 用户（U） | 接好 HDMI、串口、两路摄像头和网线，下载 bitstream，告诉 Codex COM 口号。 |
| 7 | Windows Codex（C） | **启动**：打开串口记录 `build/board/b3vn_boot.log`，请用户按一下复位键（不按 KEY1）。应出现 EdRV32 logo、启动信息（`CLK_SYS_HZ 100000000`）和监控程序菜单。没有输出时请用户报告 LED 状态。 |
| 8 | Windows Codex（C） | **监控程序**：菜单 3（系统信息）运行一次，日志 `b3vn_sysinfo.log`。 |
| 9 | Windows Codex（C） | **新 BIOS**：按住 KEY1 并复位，日志 `b3vn_bios.log` 应出现 `BIOS: EdRV32` 和 `BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud`。输入 `4` 回车、`2000000` 回车，应打印 `Baud result: 2000000`；串口改为 2000000 后按回车，应看到 BIOS 菜单。复位退出。 |
| 10 | 用户（U） | 告诉 Codex HDMI 显示器是否检测到信号（监控程序下 DISP 未使能，“无信号”属正常，如实记录）。 |
| 11 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-08-b3-vnpu results`，推送 `win/20261029-08-b3-vnpu`，告诉用户完成并给出分支名。中途停下时，已完成部分照常回传，写明停在哪一步和现象。 |

## 6. 产物

放在 `tasks/win/20261029-08-b3-vnpu/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/*_boot.log`、`*_sysinfo.log`、`*_bios.log` | 串口原始日志 |
| 2 | `timing_summary.txt` | 布线后每个时钟 slow/fast 角的 WNS/TNS/WHS/THS、违例端点数、推算 Fmax |
| 3 | `setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | CLAUDE.md 10.5 |
| 4 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM 18K/36K、APM、分布式 RAM、IO、PLL）；按层次展开到 cpu/sys/mem 子系统、VIN、PIX、GEO、DISP、NPU、ETH，以及板级适配 |
| 5 | `flow_summary.txt` | 各阶段耗时、峰值内存、W/C/E 行数；布线失败时附失败网络摘要 |
| 6 | `fdc_used.fdc` | 只有本地改过约束时才提交，内容为改后的全文 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 实现：完成布线和 bitstream；资源在器件容量内。
- 上板：串口打印 logo 和启动信息；监控程序菜单 3 有输出；能进入新 BIOS 菜单，切换到 2000000 后仍能交互。
- 时序：如实记录各时钟布线后的 WNS/TNS/WHS/THS，不作为停止条件。
- 所有数字来自 PDS 报告和串口日志原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261029-08-b3-vnpu 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | |
| PDS 版本 | |
| 工程路径 | |
| 导入源文件数 | |
| 各阶段耗时（综合/映射/布局布线） | |
| 运行方式（并行/排队） | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## IP
| IP | 来源 | 备注（初始化文件） |
|---|---|---|

## 约束
- 各时钟周期、时钟组：
- create_generated_clock 是否全部命中、有无本地修改：

## 时序（布线后）
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM 18K/36K | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

按层次：

## 上板
| 启动信息 | 监控菜单 3 | 新 BIOS 菜单 | 2000000 波特率交互 | HDMI 显示器 |
|---|---|---|---|---|

日志摘录：

## 完整报告在 Windows 本地的路径

## 备注
```
