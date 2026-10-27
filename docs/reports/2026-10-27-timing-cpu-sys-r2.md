# CPU + 系统子系统测量顶层时序与资源（C-W3，第二轮）

日期：2026-10-27。来源：Windows 任务 `20261027-02-cpu-npu-synth` A 部分，结果分支 `origin/win/20261027-02-cpu-npu-synth`（提交 `1c3eda6`），原始报告在该分支 `tasks/win/20261027-02-cpu-npu-synth/artifacts/cpu/`。产物含大量原始日志，与上一轮一样不合入 main。

## 测量条件

| 项 | 内容 |
|---|---|
| 设计输入 commit | `335bb0fddc9f3f31eb8486390ece1a584d52c9e5`（SRAM 64 KiB，C-R5/C-R6 之后） |
| 顶层 | `edrv32_fpga_cpu_sys_top`，`RVC_EN` = 1 |
| 工具 | PDS 2022.2-SP6.1（build 138931） |
| 器件 | PG2L200H-6 FBB676，Pre-silicon 时序模型，多角分析 |
| 约束 | `fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`：`clk_i` 6.667 ns（150 MHz）；8 个 IO 没有 input/output delay |
| 流程 | compile → synthesize -ads → dev_map → pnr → report_timing（max_path=200、nworst=1） |

## 时序

| 角 | WNS | TNS | setup 违例端点 | WHS | hold 违例 |
|---|---|---|---|---|---|
| slow | −3.920 ns | −19583.569 ns | 12645 / 43021 | +0.143 ns | 0 |
| fast | −0.069 ns | −0.201 ns | 7 / 43021 | +0.100 ns | 0 |

估计频率 **94.46 MHz**（上一轮 69.57 MHz，WNS −7.708 ns，19008/46871 端点违例）。Recovery/Removal 无违例。

slow setup 前 200 条（全局导出，每对起终点寄存器取最差一条）按起终点分组：

| 最差裕量 | 级数 | 起点 → 终点 | 路径内容（据逐级明细） |
|---|---|---|---|
| −3.920 ns | 24 | `u_dcache/addr_r` → `u_csr/counter_r` | D$ 标签比较得 `hit0_w`（扇出 74）→ 读数据选择和装载对齐 → core 写回结果前递到 `e_operand_a_r` 旁的 LUT → CSR 写数据 `write_data_w`（扇出 25）→ 64 位 HPM 计数器写入/加法进位链 |
| −3.233 ns | 17 | `u_core/e_operand_a_r` → `u_predictor/ras_data_r` | EX 操作数 → 跳转目标 → RAS 更新 |
| −3.102 ns | 9 | `u_frontend/f2_pc_r` → `u_predictor/ras_data_r` | 级数少，以连线和扇出为主 |
| −3.085 ns | 17 | `u_core/e_operand_a_r` → `u_frontend/f1_pc_r` | EX 重定向 → 取指 PC |
| −2.947 ns | 16 | `u_core/e_operand_a_r` → I$ 标签 RAM `CEB` | EX 重定向 → I$ 读使能 |
| −2.892 ns | 10 | `u_frontend/f2_pc_r` → `u_ib/entries_r` | 前端 F2 → 指令缓冲写入 |

结论：第一轮最差的"D$ 命中 → M 级停顿 → 前端"链已消失；现在的瓶颈是两类：(1) D$ 装载结果在同一拍内经前递进入 CSR 写数据并写 64 位计数器；(2) EX 级的跳转/重定向在同一拍内到达前端 PC、RAS 和 I$ 读使能。

## 资源（布局布线后，逻辑层次）

| 层次 | LUT | FF | 分布式 RAM | APM | DRM36K 等效 |
|---|---|---|---|---|---|
| 顶层合计 | 14879 | 8319 | 231 | 4 | 26 |
| `u_cpu_subsys` | 13428 | 7154 | 223 | 4 | 6 |
| ├ `u_core` | 10479 | 5411 | 223 | 4 | 0 |
| │ ├ `u_frontend` | 4027 | 2306 | 223 | 0 | 0 |
| │ └ `u_csr` | 1427 | 870 | 0 | 0 | 0 |
| ├ `u_dcache` | 2210 | 1120 | 0 | 0 | 3 |
| └ `u_icache` | 694 | 462 | 0 | 0 | 3 |
| `u_sys_subsys` | 1450 | 1165 | 8 | 0 | 20 |
| ├ `u_sram` | 138 | 37 | 0 | 0 | 16 |
| └ `u_rom` | 60 | 30 | 0 | 0 | 4 |

上一轮：24441 LUT、9121 FF、39 分布式 RAM、4 APM、74 DRM。DRM 减少来自 SRAM 256 KiB → 64 KiB；LUT 减少主要在 `u_frontend`（12776 → 4027）。

## 原始数据

结果分支 `artifacts/cpu/`：`timing_summary.txt`、`setup_top200.txt`、`setup_top20_detail.txt`、`hold_top200.txt`、`high_fanout.txt`、`resource_hier.txt`、`dangerous_paths.md`、`native_reports/`。
