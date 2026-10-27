# 任务卡 20261027-01-cpu-sys-synth-r2：CPU 时序优化后的第二轮综合与布局布线

## 1. 目标

SRAM 改为 64 KiB、CPU 完成时序优化（C-R5、C-R6）后，重新取得 CPU + 系统子系统测量顶层的 clk_sys Fmax、关键路径和资源分布，与上一轮（20261025-01，估计 69.6 MHz、WNS −7.708 ns）对比。

## 2. 输入

- commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录实际使用的完整哈希）。
- 顶层、导入脚本、约束与上一轮相同：`fpga/rtl/edrv32_fpga_cpu_sys_top.v`（`RVC_EN` 默认 1）、`fpga/scripts/import_cpu_sys_top.tcl`、`fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`（`clk_i` 按 150 MHz 约束）。文件列表没有增删文件，导入脚本应仍打印 `edrv32: added 42 sources`。
- 相对上一轮的 RTL 变化：SRAM 包装模块和 SRAM 桥改为 13 位字地址（64 KiB）；`rtl/cpu/` 的 core、frontend、ib、csr 和 `rtl/cache/edrv32_dcache.v` 的时序优化。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- 工程：沿用上一轮的 `G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`。

## 4. 需要的 IP

- **重新生成 `ip_ram_sram`**：按 `fpga/ip/ip_ram_sram.md` 的当前版本，深度改为 **8192**（地址 13 位），其余选项不变（64 位、8 位字节写使能、时钟使能、无输出寄存器、读延迟 1）。生成后核对端口：`addr` 应为 13 位，其他端口与该文件"实际端口"表一致；有差异写进 `result.md`。
- 其他 6 个 IP 不变，不重新生成。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261027-01-cpu-sys-synth-r2 origin/main`。阅读本任务卡，把用户步骤整理成清单交给用户。 |
| 2 | 用户（U） | 在 PDS IP Compiler 中按第 4 节重新生成 `ip_ram_sram`（覆盖旧的 32768 深度版本）。完成后告诉 Codex 生成目录，Codex 核对端口位宽。 |
| 3 | 用户（U） | 在 PDS Tcl 控制台执行：`source <仓库路径>/fpga/scripts/import_cpu_sys_top.tcl`（路径用 `/`），确认打印 `edrv32: added 42 sources`。编译报错就停下，把报错原文交给 Codex。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。 |
| 5 | Windows Codex（C） | 从工程目录收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261027-01-cpu-sys-synth-r2 results`，推送 `win/20261027-01-cpu-sys-synth-r2`，告诉用户完成并给出分支名。 |

本轮不做 `RVC_EN = 0` 对照，也不做多种子运行。

## 6. 产物

放在 `tasks/win/20261027-01-cpu-sys-synth-r2/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `ip_sram_ports.md` | 重新生成的 `ip_ram_sram` 端口名、方向、位宽 |
| 2 | `timing_summary.txt` | 每个时钟的 WNS/TNS/WHS/THS；推算 Fmax = `1000 / (6.667 − WNS)` MHz |
| 3 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM、APM、分布式 RAM、IO、PLL）；按层次至少到 `u_cpu_subsys` 下的 core（及 core 内的 frontend、csr）、icache、dcache，`u_sys_subsys` 下的 xbar、ROM、SRAM、各外设 |
| 4 | `setup_top200.txt` | 最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 5 | `setup_top20_detail.txt` | 最差 20 条 setup 路径的逐级明细（含每级单元和扇出） |
| 6 | `hold_top20.txt` | 最差 20 条 hold 路径 |
| 7 | `high_fanout.txt` | 扇出最大的 100 个网络（网络名、扇出） |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。单个产物超过几 MB 时，在 `result.md` 里说明原因。

## 7. 通过判据

- SRAM IP 按 8192 深度生成，端口与包装模块一致。
- 综合、布局布线完成，没有未解析的模块或黑盒（IP 除外）。
- 第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261027-01-cpu-sys-synth-r2 结果

| 项 | 内容 |
|---|---|
| commit | <完整哈希> |
| PDS 版本 | |
| 器件 | PG2L200H-6 FBB676 |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## SRAM IP
（深度、端口与包装模块是否一致；差异）

## 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

上一轮（20261025-01）：WNS −7.708 ns，估计 69.6 MHz，19008/46871 个端点违例。

最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

上一轮：24.4K LUT、9.1K FF、74 DRM、4 APM。

按层次（主要模块）：

## 完整报告在 Windows 本地的路径

## 备注
```
