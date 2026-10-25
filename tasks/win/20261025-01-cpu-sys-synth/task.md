# 任务卡 20261025-01-cpu-sys-synth：生成 IP，CPU + 系统子系统综合与布局布线

## 1. 目标

在 PG2L200H 上生成 7 个 IP，对 CPU 子系统 + 系统子系统的测量顶层做综合和布局布线，取得 clk_sys 的 Fmax、关键路径和资源分布（cpu-plan C-W2、sys-subsys-plan S-P1）。

## 2. 输入

- commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录实际使用的完整哈希）。本任务卡之前的代码提交即为被测 RTL。
- 顶层：`fpga/rtl/edrv32_fpga_cpu_sys_top.v`（模块 `edrv32_fpga_cpu_sys_top`，参数 `RVC_EN` 默认 1）。
- 源文件：`rtl/filelists/cpu_subsys.f` 与 `rtl/filelists/sys_subsys.f` 列出的全部文件（路径相对 `rtl/filelists/`，`-f` 表示递归包含另一个列表，`+incdir+` 表示头文件目录），加上顶层文件本身。不要导入 `rtl/tech/` 以外的仿真模型，也不要导入 `verif/`、`legacy/`。
- 头文件目录：`rtl/include`。
- 宏定义：`FPGA_MODE`（只定义这一个；不要定义 `SIM_MODE`）。
- IP：见第 4 节，由用户在 PDS 工程中生成；RTL 中的 `rtl/tech/` 包装模块在 `FPGA_MODE` 下例化这些 IP。

## 3. 环境

- PDS：用户现有版本（在 `result.md` 记录版本号）。
- 器件：PG2L200H，速度等级 -6，封装 FBB676（与厂商 demo 工程一致）。

## 4. 需要的 IP

按 `fpga/ip/README.md` 和各创建说明生成，模块名必须与说明一致：

| IP | 创建说明 |
|---|---|
| `ip_ram_icache_tag` | `fpga/ip/ip_ram_icache_tag.md` |
| `ip_ram_icache_data` | `fpga/ip/ip_ram_icache_data.md` |
| `ip_ram_dcache_tag` | `fpga/ip/ip_ram_dcache_tag.md` |
| `ip_ram_dcache_data` | `fpga/ip/ip_ram_dcache_data.md` |
| `ip_mul_s33x33` | `fpga/ip/ip_mul_s33x33.md` |
| `ip_rom_boot` | `fpga/ip/ip_rom_boot.md` |
| `ip_ram_sram` | `fpga/ip/ip_ram_sram.md` |

ROM、SRAM 的初始化内容不影响本任务的时序和资源；初始化文件暂按创建说明中的要求随意给一个合法文件（或不初始化，如果 IP Compiler 允许），但要记录 PDS 接受的初始化文件格式（扩展名、每行格式、位宽和地址顺序），协调者据此写转换脚本。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch`，从第 2 节 commit 拉出分支 `win/20261025-01-cpu-sys-synth`。完整阅读本任务卡和第 4 节的 7 份创建说明，检查 PDS 版本和器件；不满足时停下告诉用户。 |
| 2 | 用户（U） | 在仓库外新建 PDS 工程（器件见第 3 节），告诉 Codex 工程路径。 |
| 3 | 用户（U） | 先只生成 `ip_ram_icache_tag` 和 `ip_rom_boot`，把生成的模块端口列表（或生成的 `.v` 模块头）交给 Codex。 |
| 4 | Windows Codex（C） | 对照 `rtl/tech/edrv32_ram_icache_tag.v`、`rtl/tech/edrv32_rom_boot.v` 中 `FPGA_MODE` 分支例化的端口名，逐个核对。**不一致时停下**，把差异写进 `result.md` 的"IP 端口差异"一节并告诉用户；不要自行修改 RTL（`rtl/tech/` 由协调者修改）。一致时继续。 |
| 5 | 用户（U） | 生成其余 5 个 IP，同样交给 Codex 核对端口（步骤 4 的规则）。 |
| 6 | Windows Codex（C） | 写 PDS 导入 Tcl `artifacts/import_cpu_sys_top.tcl`：按第 2 节导入源文件、头文件目录、宏 `FPGA_MODE`，顶层设为 `edrv32_fpga_cpu_sys_top`，导入第 7 步的约束。Tcl 命令以本机 PDS 版本的文档为准，不确定的命令先在 PDS 中试运行。 |
| 7 | Windows Codex（C） | 写约束 `artifacts/edrv32_fpga_cpu_sys_top.fdc`：`clk_i` 时钟周期 6.667 ns（150 MHz，clk_sys 目标）；引脚 `clk_i`、`rst_n_i`（按键，低有效）、`uart_rx_i`、`uart_tx_o`、`key_n_i`（另一个按键）、`led_o[3:0]` 按厂商 demo 工程的约束文件选择板上的时钟、按键、串口和 LED 引脚，在 `result.md` 中逐个列出引脚号和出处（demo 文件名和行）。如果板载时钟不是 150 MHz，仍然按 150 MHz 约束（本任务只做时序测量，不上板运行）。 |
| 8 | 用户（U） | 在 PDS 中运行步骤 6 的 Tcl（或由 Codex 用 PDS 命令行运行），执行综合、布局布线、时序分析。 |
| 9 | Windows Codex（C） | 按第 6 节收集产物。 |
| 10 | 用户（U）+ Codex（C） | 把顶层文件中 `RVC_EN` 的默认值本地改为 0（只改这一处，不提交），重新综合、布局布线；Codex 只收集第 6 节第 3、4 项的汇总数字（不需要路径明细）。 |
| 11 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261025-01-cpu-sys-synth results`，推送 `win/20261025-01-cpu-sys-synth`，告诉用户完成并给出分支名。 |

## 6. 产物

放在 `tasks/win/20261025-01-cpu-sys-synth/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `import_cpu_sys_top.tcl`、`edrv32_fpga_cpu_sys_top.fdc` | 第 6、7 步实际使用的版本 |
| 2 | `ip_ports.md` | 7 个 IP 生成后的模块名和端口列表（名称、方向、位宽），以及 ROM/SRAM 初始化文件格式说明 |
| 3 | `timing_summary.txt` | 每个时钟的 WNS/TNS/WHS/THS；由 150 MHz 约束和 WNS 推算的 Fmax（`1000 / (6.667 − WNS)` MHz，WNS 为负时同样适用） |
| 4 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM、APM、分布式 RAM、IO、PLL）；按模块层次的资源分布，至少到 `u_cpu_subsys` 下的 core、icache、dcache 和 `u_sys_subsys` 下的 xbar、ROM、SRAM、各外设 |
| 5 | `setup_top200.txt` | 最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 6 | `setup_top20_detail.txt` | 最差 20 条 setup 路径的逐级明细 |
| 7 | `hold_top20.txt` | 最差 20 条 hold 路径 |
| 8 | `rvc0_summary.txt` | 第 10 步 `RVC_EN`=0 的时序汇总（同第 3 项）和资源汇总（同第 4 项的汇总表） |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 7 个 IP 全部生成，端口与包装模块一致（不一致则本任务在步骤 4 停止并回传差异，也算完成）。
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
（无，或逐项列出：IP、包装模块期望的端口、实际端口）

## 引脚
| 端口 | 引脚 | 出处 |
|---|---|---|

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
