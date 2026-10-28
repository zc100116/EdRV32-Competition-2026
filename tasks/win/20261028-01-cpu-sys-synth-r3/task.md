# 任务卡 20261028-01-cpu-sys-synth-r3：CPU 第三轮综合（C-R7 之后）

## 1. 目标

取得 C-R7 周期等价时序优化后，CPU + 系统子系统测量顶层的 clk_sys Fmax、关键路径，以及**每一类路径的最差一条的逐级明细**（cpu-plan C-W4）。

## 2. 输入

- commit：分支 `zc100116/SOC系统设计` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录实际使用的完整哈希）。分支：`git fetch origin`，`git switch -c win/20261028-01-cpu-sys-synth-r3 origin/zc100116/SOC系统设计`。本轮 CPU RTL（C-R7）尚未合入 `main`。
- 测量顶层、导入脚本、约束与上一轮（20261027-02 A 部分）相同：`fpga/rtl/edrv32_fpga_cpu_sys_top.v`、`fpga/scripts/import_cpu_sys_top.tcl`（应打印 `edrv32: added 42 sources`）、`fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`（150 MHz）。
- 本轮 RTL 改动只在 `rtl/cpu/edrv32_cpu_core.v`、`edrv32_cpu_csr.v`、`edrv32_cpu_frontend.v`、`edrv32_cpu_predictor.v`（C-R7），源文件数量不变。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- 沿用 A 工程 `G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`。路径不同时写进 `result.md`。

## 4. 需要的 IP

无新增。沿用工程中已生成的 7 个 IP（含上一轮重新生成的 8192 深度 `ip_ram_sram`）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-01-cpu-sys-synth-r3 origin/zc100116/SOC系统设计`。阅读本卡，把用户步骤整理成清单交给用户。 |
| 2 | 用户（U） | 打开 A 工程，在 PDS Tcl 控制台执行 `source <仓库路径>/fpga/scripts/import_cpu_sys_top.tcl`（路径用 `/`），确认打印 `edrv32: added 42 sources`。编译报错就停下，把报错原文交给 Codex。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。 |
| 4 | Windows Codex（C） | 收集第 6 节产物 1–6。 |
| 5 | Windows Codex（C） | 生成第 6 节产物 7（分组明细）：把 `setup_top200.txt` 中的路径按"起点寄存器名去掉位下标、终点寄存器名去掉位下标"分组；对每一组（最多 30 组，按组内最差裕量排序），用 PDS `report_timing` 的起点/终点过滤导出该组最差一条路径的逐级明细。另外，下表 6 组无论是否出现在前 200 条里，都必须各导出最差一条的逐级明细（找不到满足过滤条件的路径时写"无此类路径"）。每次使用的 `report_timing` 命令原文写进产物开头。 |
| 6 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-01-cpu-sys-synth-r3 results`，推送 `win/20261028-01-cpu-sys-synth-r3`，告诉用户完成并给出分支名。 |

必须导出明细的 6 组（上一轮最差的六类，C-R7 针对它们修改）：

| # | 起点 | 终点 | 上一轮 WNS / 级数 |
|---|---|---|---|
| G1 | `u_dcache` 内的 `addr_r` | `u_csr` 内的 `counter_r` | −3.920 ns / 24 |
| G2 | core 内的 `e_operand_a_r` | predictor 内的 `ras_data_r` | −3.233 ns / 17 |
| G3 | frontend 内的 `f2_pc_r` | predictor 内的 `ras_data_r` | −3.102 ns / 9 |
| G4 | core 内的 `e_operand_a_r` | frontend 内的 `f1_pc_r` | −3.085 ns / 17 |
| G5 | frontend 内的 `f2_pc_r` | IB 内的 `entries_r` | −2.892 ns / 10 |
| G6 | 任意 | I$ 数据 RAM 的读使能 / 地址引脚（CEB、ADDR） | — |

PDS 打包后寄存器名可能带后缀或被合并；按名字主体匹配，实际使用的匹配字符串写进产物。

本轮不做 `RVC_EN = 0` 对照，不做多种子运行，不上板。

## 6. 产物

放在 `tasks/win/20261028-01-cpu-sys-synth-r3/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | 每个时钟的 WNS/TNS/WHS/THS、违例端点数；推算 Fmax = `1000 / (6.667 − WNS)` MHz |
| 2 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM、APM、分布式 RAM、IO、PLL）；按层次至少到 `u_cpu_subsys` 下的 core（及 core 内的 frontend、csr、predictor）、icache、dcache，`u_sys_subsys` 下的 xbar、ROM、SRAM、各外设 |
| 3 | `setup_top200.txt` | 最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 4 | `setup_top20_detail.txt` | 最差 20 条 setup 路径的逐级明细（每级单元、扇出、单元延迟和线延迟） |
| 5 | `hold_top20.txt` | 最差 20 条 hold 路径 |
| 6 | `high_fanout.txt` | 扇出最大的 100 个网络（网络名、扇出） |
| 7 | `setup_group_detail.txt` | 第 5 节步骤 5：每组一段，段首写组名（起点主体 → 终点主体）、组内路径数、最差裕量、所用命令，随后是该组最差路径的逐级明细；G1–G6 各一段 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。单个产物超过几 MB 时，在 `result.md` 里说明原因。

## 7. 通过判据

- 综合、布局布线完成，没有未解析的模块或黑盒（IP 除外）。
- 第 6 节产物齐全，G1–G6 各有明细或明确写"无此类路径"。
- 所有数字来自 PDS 报告原文，找不到的写"未取得"。

时序是否达到 150 MHz 不是本任务的通过条件。

## 8. result.md 模板

```markdown
# 20261028-01-cpu-sys-synth-r3 结果

| 项 | 内容 |
|---|---|
| commit | <完整哈希> |
| PDS 版本 | |
| 器件 | PG2L200H-6 FBB676 |
| 工程路径 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

上一轮（20261027-02 A）：slow WNS −3.920 ns，约 94.5 MHz，12645/43021 个端点违例。

最差路径前 10 条（起点 → 终点，裕量，级数）：

## 六类路径（G1–G6）
| 组 | 本轮最差裕量 | 级数 | 逻辑延迟 / 布线延迟 | 上一轮 |
|---|---|---|---|---|

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

上一轮：14879 LUT、8319 FF、26 DRM36K 当量。

按层次（主要模块）：

## 完整报告在 Windows 本地的路径

## 备注
```
