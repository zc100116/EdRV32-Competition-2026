# 任务卡 20261102-34-b1-ila：CPU + UART + ILA 单独实验，验证计数器 ILA 能不能用

## 1. 目标

在小工程 B1（CPU + 系统外设 + UART，片上 SRAM，没有 DDR 和媒体模块）上按 `fpga/ip/ila_cpu.md` 插入 ILA。上板跑 CoreMark，确认以下三点，通过后才在 B3F 整版（卡 33）插入同样的 ILA：
1. A 组计数器（mcycle、minstret、8 个 HPM）在综合网表里存在，能被选为探针；
2. 冻结后抓到的计数和串口打印的一致（核对跑分）；
3. 运行中按 `minstret` 数值触发能抓到 1024 周期的窗口，波形能用来分析流水线效率。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交，含 T-FANOUT-CPU，CPU RTL 与卡 33 相同）。拉出 `win/20261102-34-b1-ila`，在 result.md 中记录完整哈希。
- **工程**：新建 `G:\codex_project\EdRV32-FPGA\EdRV32-B1-ILA`，顶层 `edrv32_fpga_board_b1_top`，导入脚本 `fpga/scripts/import_board_b1_top.tcl`。预计输出 `added 43 sources`（本卡修正了脚本，`edrv32_reset_copy` 不再重复加入）。
- **IP**：8 个 IP 全部从卡 31 的 B3F 工程复制：`ip_pll_sys`、`ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`（20 位）、`ip_ram_dcache_data`、`ip_mul_s33x33`、`ip_rom_boot`、`ip_ram_sram`。其中 ROM/SRAM 的初始化内容是卡 24 的 `src/ip_rom_boot.dat`、`ip_ram_sram.dat`（BIOS + monitor）。Linux 端已用当前 b3 跑过 B1 板级仿真 `verif/soc/board_b1`，3/3 PASS。
- **约束**：`fpga/constraints/edrv32_fpga_board_b1_top.fdc`（导入脚本自动加入）。

## 3. 环境

PDS 2022.2-SP6.1；PG2L200H-6 FBB676。可以和卡 35 同时进行（卡 35 不需要综合）。卡 33 暂停，等本卡和卡 35 的结论。

## 4. 需要的 IP

见第 2 节，另加调试核 `ila_cpu`（Inserter 插入）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-34-b1-ila origin/zc100116/b3`。在本机 PDS 文档中找到 Inserter 的用户指南（卡 31 已找到：`Fabric_Inserter_User_Guide.pdf` 第 9–17 页），把插入步骤整理进用户清单。 |
| 1 | 用户（U） | 新建工程，复制 IP，执行导入脚本。源文件数不是 43 就停下。 |
| 2 | U 或 C | `synthesize -ads`。在综合网表中找出 `u_cpu_subsys/u_core/u_csr` 下 `cycle_r`、`instret_r`、`g_counter[2]`…`g_counter[9]` 的 `count_r` 的实际实例名，各取低 40 位，写进 `artifacts/probe_names.txt`。找不到就停下，回传网表中相关名字的原文。 |
| 3 | U（C 协助） | 按 `fpga/ip/ila_cpu.md` 插入 ILA：采样时钟 clk_sys，10 组探针共 400 位，按 `mcycle`、`minstret`、`hpm3`…`hpm10` 分组命名；触发探针 `minstret`、`mcycle`；深度 1024；触发位置 10%。保存 .fic 并截图。 |
| 4 | U 或 C | `dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。记录各阶段耗时，以及 ILA 占用的资源（LUT/FF/DRM）。 |
| 5 | U | 下载 bitstream，打开 PDS Debugger 连上 ILA。串口 115200 进入 monitor（复位后自动从 SRAM 启动；进不去就按卡 24 第 5.0 节进 BIOS 选 `3=Run`）。 |
| 6 | U | **核对跑分**：monitor 菜单输入 `1`（CoreMark），迭代次数 `5000`。每轮结束、串口打印出该轮 HPM 结果后，在 Debugger 中立即触发（Immediate/手动触发）抓一次。第 1、2 轮各抓一次。导出 CSV，截图。 |
| 7 | U | **流水线窗口**：再跑一次 CoreMark（5000 次）。用第 6 步第 1 轮的 `HPM round instructions` 除以 2 作为 `minstret` 的触发值（触发条件 `minstret == 该值`；Debugger 不支持相等比较就用 `≥`）。在串口打印第 1 轮开始后布防，抓 1024 周期，导出 CSV，截图。 |
| 8 | C | 用第 6、7 步的 CSV 计算并写进 result.md：(1) 冻结值和串口值逐项对比（mcycle、minstret、hpm3–10）；(2) 窗口内 `minstret` 每周期增量的分布（0/1/2 各多少拍）、IPC，各 HPM 计数器在窗口内的增量。只用 CSV 原始数据计算，在 result.md 中写出计算方法。 |

## 6. 产物

放在 `tasks/win/20261102-34-b1-ila/artifacts/`：

| 产物 | 内容 |
|---|---|
| `probe_names.txt` | 第 2 步 |
| `ila/` | .fic、插入截图、Debugger 截图、第 6/7 步的 CSV |
| `uart/coremark_*.log` | 两次 CoreMark 的串口全文 |
| `flow_summary.txt` | 各阶段耗时、峰值内存 |
| `timing_summary.txt`、`resource_summary.txt` | 每个时钟的 WNS/TNS/WHS/THS；资源汇总，单列 ILA 占用 |

不提交：工程文件、IP 目录、数据库、网表、bitstream。

## 7. 通过判据

- 10 组计数器都能选为探针，ILA 插入成功，时序不违例。
- 第 6 步两轮抓到的冻结值与串口打印**逐项相等**。
- 第 7 步按 `minstret` 触发成功，窗口内 `minstret` 的增量只有 0/1/2，IPC 与串口该轮的 IPC 在同一量级。
- 所有数字取自报告和 CSV 原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-34-b1-ila 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 源文件数 | |
| 探针实际实例名 | 见 probe_names.txt，摘要： |
| ILA 资源 | LUT / FF / DRM |
| 时序 | clk_sys WNS / WHS |
| 各阶段耗时 | |

## 核对跑分（第 6 步）
| 计数器 | 第 1 轮 串口 | 第 1 轮 ILA | 第 2 轮 串口 | 第 2 轮 ILA |
|---|---|---|---|---|

## 流水线窗口（第 7 步）
触发值、触发方式；minstret 增量分布（0/1/2 拍数）、IPC；各 HPM 增量。

## 问题与偏离
```
