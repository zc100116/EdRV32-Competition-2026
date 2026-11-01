# 任务卡 20261101-31-b3f-map：全系统顶层 B3F（含 CPU ILA）跑到 Device Map，评估资源、扇出和逻辑级数

## 1. 目标

用最新 RTL 建立全系统顶层 `edrv32_fpga_board_full_top`（CPU + DDR + VIN/PIX/GEO + RND + 两层 DISP + NPU + ETH），按 `fpga/ip/ila_cpu.md` 插入 CPU ILA（A 组为性能计数器 mcycle/minstret/HPM3–10，B 组为流水线观察向量 `debug_o`），**只跑到 Device Map**。取得以下数据，用来评估整体优化方向（`docs/design/2026-11-01-fanout-audit.md`）：
- 整个系统的资源，以及按模块的分布；
- 高扇出网络；
- 各时钟域的路径和逻辑级数。

本卡不布局布线、不生成 bitstream、不上板。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261101-31-b3f-map`，在 result.md 中记录完整哈希。
- **新增文件**：
  - `fpga/rtl/edrv32_fpga_board_full_top.v`：以 B3VN 顶层为基础，接入 RND（P4、APB 槽 4、PLIC 源 11），`debug_o` 寄存为 `ila_cpu_r`；
  - `fpga/constraints/edrv32_fpga_board_full_top.fdc`：B3VN 约束加上 RGMII RX 输入延迟和 PLL 位置约束；
  - `fpga/scripts/import_board_full_top.tcl`；
  - `fpga/ip/ila_cpu.md`。
- **ROM/SRAM 初始化**：`tasks/win/20261101-24-b3-rnv/src/ip_rom_boot.dat`、`ip_ram_sram.dat`。本卡不上板，内容不影响结果，只要求 IP 能生成。

## 3. 环境

- PDS 2022.2-SP6.1；PG2L200H-6 FBB676。
- **开始时间**：现在就可以开始，不用等卡 24（用户 2026-11-01）。本卡只跑综合和 Device Map。如果卡 24 的 B3R 布局布线还在运行，在两张卡的 result.md 中各记一笔两者重叠的起止时间，作为卡 24 耗时对比的备注。
- 工程目录：`G:\codex_project\EdRV32-FPGA\EdRV32-B3F`（新建），顶层 `edrv32_fpga_board_full_top`。
- 本地 Verilator lint 0 告警；导入脚本预计输出 `added 165 sources`。

## 4. 需要的 IP

逐个按 `fpga/ip/<IP>.md` 生成，模块名和端口名必须与说明一致：

| 来源 | IP |
|---|---|
| 与 B3V 相同 | `ip_pll_sys`、`ip_pll_video`、`ip_pll_eth`（卡 30 外部反馈版）、`ip_ddr3`、`ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`（20 位）、`ip_ram_dcache_data`、`ip_mul_s33x33`、`ip_rom_boot`、`ip_ram_sram`、`ip_ram_mem_xbar_r`、`ip_lutram_mem_xbar_w`、`ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、`ip_ram_eth_buf`、`ip_ram_eth_fifo`、`ip_ram_disp_scan` |
| 与 B3N 相同 | `ip_pll_npu`、`ip_ram_npu_line`、`ip_ram_npu_weight`、`ip_lutram_npu_quant`、`ip_ram_npu_lut`、`ip_lutram_npu_residual`、`ip_lutram_npu_result`、`ip_ram_npu_scratch`、`ip_mul_npu_quant_low`、`ip_mul_npu_quant_high` |
| 与 B3R 相同 | `ip_ram_rnd_line`、`ip_ram_rnd_palette`、`ip_ram_rnd_window` |
| 本卡新增 | `ila_cpu`：调试核，综合之后插入，见第 5 节第 3 步 |

可以从卡 24 的 B3V、B3N、B3R 工程复制已生成的 IP，但必须是卡 24 的版本：`ip_pll_eth` 为外部反馈，`ip_rom_boot`、`ip_ram_sram` 用卡 24 的 dat。复制和重新生成都可以，在 result.md 中逐个写明每个 IP 的来源。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261101-31-b3f-map origin/zc100116/b3`。整理用户清单。在本机 PDS 安装目录的文档中，找到调试核插入工具（Inserter/Debugger）的用户指南，把插入 ILA 的 GUI 或 Tcl 步骤整理进清单，并在 result.md 中注明出处（文件名、页码）。找不到就停下告诉用户。 |
| 1 | 用户（U） | 新建 B3F 工程，按第 4 节准备 IP，在工程目录的 Tcl 控制台中执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`。源文件数和 FDC 与第 3 节不符就停下。 |
| 2 | U 或 C | `synthesize -ads`。完成后在综合网表中确认两组探针都存在，并记录实际实例名：<br>1. B 组：64 个 `ila_cpu_r` 寄存器；<br>2. A 组：`u_cpu/u_core/u_csr` 下的 `cycle_r`、`instret_r`、`counter_r[0]`–`counter_r[7]` 的低 40 位寄存器。<br>任何一组找不到（被优化或改名后无法对应），就停下回传原文。 |
| 3 | U（C 协助） | 按 `fpga/ip/ila_cpu.md` 插入 ILA：采样时钟 clk_sys，A 组 400 位加 B 组 64 位，按说明中的组名分组；触发探针为 `retire_pc` 和 `retire`；深度 1024，触发位置 10%。保存调试核配置文件并截图。 |
| 4 | U 或 C | `dev_map`（包含插入的调试核）。到此为止：**不跑 pnr**。任何阶段报错就停下，回传原文。 |
| 5 | C | 收集第 6 节的产物。 |

### 第 5 步要收集的内容

1. **资源**：
   - Device Map 的资源汇总；
   - `.snr` 中 "Device Utilization Summary Of Each Module" 整张表（按模块的 LUT/FF/DRM/APM/分布式 RAM），以及 DMR 中按层次的资源表（如有）；
   - 单独列出调试核占用的资源。
2. **高扇出**：
   - DMR 中的 Clock / Reset / CE / Other High Fanout 四张表全文，以及综合目录下的 `*_controlsets.txt`；
   - 检查 PDS 的综合或 Device Map 设置里，有没有控制高扇出报告条数的选项。有就设为 1000 以上重跑这一步，并在 result.md 中写明选项名；没有就写"未找到"。
3. **路径与逻辑级数**：
   - 先试在 Device Map 数据库上做时序分析：`report_timing -input_db_file {<工程>/device_map/<顶层>_map.adf} -delay_type max -max_path 200 -nworst 1 -input_pins TRUE -force_to_run`（数据库文件名以实际为准）。按时钟域导出每个时钟最差 200 条路径，一行一条，列出起点、终点、裕量、逻辑级数，以及最差 20 条的逐级明细（含每段走线的扇出）；
   - 如果 Device Map 数据库不支持，就对综合数据库做同样的导出；两者都不支持，就回传报错原文，只交 `.snr` 中的时序部分；
   - 另外统计每个时钟域逻辑级数 ≥ 8 的路径条数。
4. **警告**：各阶段警告按代码分组计数，以及 E 级原文。

## 6. 产物

放在 `tasks/win/20261101-31-b3f-map/artifacts/`：

| 产物 | 内容 |
|---|---|
| `ip_sources.txt` | 每个 IP 的来源（复制自哪个工程或重新生成） |
| `ila/` | 调试核配置文件、截图、插入步骤的出处 |
| `flow_summary.txt` | 各阶段耗时、峰值内存、警告数、错误数 |
| `resource_summary.txt`、`resource_hier.txt` | 第 5 步第 1 项 |
| `high_fanout.txt`、`controlsets.txt` | 第 5 步第 2 项 |
| `paths_<clock>.txt`、`paths_top20_detail.txt`、`levels_count.txt` | 第 5 步第 3 项 |
| `native_reports/` | CMR、SNR、DMR 原文 |

不提交：PDS 工程文件、IP 生成目录、网表、数据库。

## 7. 通过判据

- 综合和 Device Map 完成，0 错误；ILA 插入成功，探针为 A 组 400 位加 B 组 64 位。
- 交齐第 6 节的产物。资源、扇出和级数只记录，不设门槛。所有数字取自报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261101-31-b3f-map 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 源文件数 | |
| 综合 / Device Map 耗时 | |
| ILA | 插入方式、出处、A/B 组探针的实际实例名、深度、资源 |

## 资源
| 项 | LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|
| 全芯片 | | | | | | | |
| 调试核 | | | | | | | |

按模块（u_cpu、u_sys、u_mem、u_vin、u_pix、u_geo、u_rnd、u_disp、u_npu、u_eth、板级）：

## 高扇出
- 报告条数选项：
- 各表条目数，以及扇出 ≥ 300 的条目数（按模块）

## 路径与逻辑级数
| 时钟 | 数据来源（map/综合） | WNS | 最差路径级数 | 级数 ≥ 8 的路径条数 |
|---|---|---|---|---|

## 问题与偏离
```
