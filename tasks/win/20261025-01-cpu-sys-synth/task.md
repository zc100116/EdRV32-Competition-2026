# 任务卡 20261025-01-cpu-sys-synth：CPU + 系统子系统综合与布局布线

## 1. 目标

对 CPU 子系统 + 系统子系统的测量顶层做综合和布局布线，取得 clk_sys 的 Fmax、关键路径和资源分布（cpu-plan C-W2、sys-subsys-plan S-P1）。

> 第二版（2026-10-26）。分工调整：约束文件和导入脚本由协调者在 Linux 端写好入库，Windows 端只负责建工程、生成 IP、执行脚本、跑流程、整理报告，不编写约束和导入脚本。第一阶段（7 个 IP 生成与包装模块适配）已完成，结果见 `result.md` 和 `artifacts/ip_ports.md`，包装模块适配已并入 `main`。

## 2. 输入

- commit：`main` 上包含本任务卡第二版的提交（Windows Codex 在 `result.md` 中记录实际使用的完整哈希）。
- 顶层：`fpga/rtl/edrv32_fpga_cpu_sys_top.v`（模块 `edrv32_fpga_cpu_sys_top`，参数 `RVC_EN` 默认 1）。
- 导入脚本：`fpga/scripts/import_cpu_sys_top.tcl`。按 `rtl/filelists/cpu_subsys.f`、`sys_subsys.f` 展开全部源文件（41 个）并加入顶层，共 42 个，导入约束文件，然后以头文件目录 `rtl/include`、宏 `FPGA_MODE` 编译（`compile -include_path -compiler_directives`）。PDS Tcl 当前目录必须为 `EdRV32-FPGA/<工程名>`；源码仓库按 `../../EdRV32-Competition-2026` 解析，不依赖 `info script`。器件沿用工程设置。IP 已在工程中，脚本不重复添加。
- 约束：`fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`。`clk_i` 按 150 MHz（6.667 ns）约束；引脚取自厂商 demo：`clk_i` D18（板载 27 MHz）、`rst_n_i` C22、`key_n_i` C23、`uart_rx_i` B24、`uart_tx_o` C24、`led_o[0..3]` A20/C18/C19/E18。本任务只测时序和资源，不上板运行。
- 头文件目录 `rtl/include` 和宏 `FPGA_MODE`（只定义这一个，不定义 `SIM_MODE`）由导入脚本在编译命令中设置，不需要在工程设置里填。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- 工程：沿用第一阶段的 `G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`（已含 7 个 IP）。

## 4. 需要的 IP

第一阶段已生成的 7 个 IP（`fpga/ip/README.md`），不需要重新生成。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch origin`，然后 `git switch -C win/20261025-01-cpu-sys-synth origin/main`（第一阶段的提交已并入 main，旧分支直接覆盖）。阅读本任务卡，把用户步骤整理成清单交给用户。 |
| 2 | 用户（U） | 打开第一阶段工程，将 PDS Tcl 当前目录设为 `G:/codex_project/EdRV32-FPGA/EdRV32`，执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_cpu_sys_top.tcl`。脚本导入源文件和约束并完成编译，最后打印 `edrv32: added 42 sources` 和顶层、头文件目录、宏。编译报错就停下，把报错原文交给 Codex 写进 `result.md`。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（与厂商 demo 的 `impl.tcl` 相同的流程，不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex 写进 `result.md`。 |
| 4 | Windows Codex（C） | 从工程目录收集第 6 节产物。 |
| 5 | 用户（U）+ Codex（C） | 把顶层文件中 `RVC_EN` 默认值本地改为 0（只改这一处，不提交），在控制台重新执行 `compile -top_module edrv32_fpga_cpu_sys_top -include_path <仓库路径>/rtl/include -compiler_directives FPGA_MODE`（文件已在工程中，不再 source 脚本），再执行步骤 3；Codex 只收集第 6 节第 2、3 项的汇总数字，写入 `rvc0_summary.txt`。完成后把这处改动撤销。 |
| 6 | Windows Codex（C） | 填写 `result.md`（在第一阶段内容基础上补全），提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261025-01-cpu-sys-synth results`，推送 `win/20261025-01-cpu-sys-synth`（需 `--force`，因为步骤 1 重建了分支），告诉用户完成并给出分支名。 |

## 6. 产物

放在 `tasks/win/20261025-01-cpu-sys-synth/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `ip_ports.md` | 已回传（第一阶段）；IP 若重新生成再更新 |
| 2 | `timing_summary.txt` | 每个时钟的 WNS/TNS/WHS/THS；由 150 MHz 约束和 WNS 推算的 Fmax（`1000 / (6.667 − WNS)` MHz，WNS 为负时同样适用） |
| 3 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM、APM、分布式 RAM、IO、PLL）；按模块层次的资源分布，至少到 `u_cpu_subsys` 下的 core、icache、dcache 和 `u_sys_subsys` 下的 xbar、ROM、SRAM、各外设 |
| 4 | `setup_top200.txt` | 最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 5 | `setup_top20_detail.txt` | 最差 20 条 setup 路径的逐级明细 |
| 6 | `hold_top20.txt` | 最差 20 条 hold 路径 |
| 7 | `rvc0_summary.txt` | 第 5 节步骤 5 `RVC_EN`=0 的时序汇总（同第 2 项）和资源汇总（同第 3 项的汇总表） |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 导入脚本和约束无需修改即可使用；若报错，在报错的步骤停止并回传报错原文，也算完成。
- 综合、布局布线完成，没有未解析的模块或黑盒（IP 除外）。
- 第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261025-01-cpu-sys-synth 结果

| 项 | 内容 |
|---|---|
| commit | <完整哈希> |
| PDS 版本 | |
| 器件 | PG2L200H-6 FBB676 |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## IP 端口差异
（第一阶段已回传；无新差异写“无”）

## 导入与约束
（导入脚本、约束是否原样可用；不可用时的报错原文）

## 时序（RVC_EN=1）
| 时钟 | WNS | TNS | WHS | THS | Fmax（推算） |
|---|---|---|---|---|---|

最差路径前 5 条（起点 → 终点，裕量，级数）：

## 资源（RVC_EN=1）
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

按层次（主要模块）：

## RVC_EN=0 对照
| 项 | RVC_EN=1 | RVC_EN=0 |
|---|---|---|
| WNS / Fmax | | |
| LUT / FF | | |

## 完整报告在 Windows 本地的路径

## 备注
```
