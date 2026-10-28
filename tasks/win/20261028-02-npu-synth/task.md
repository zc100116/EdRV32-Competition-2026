# 任务卡 20261028-02-npu-synth：完整 NPU 综合 + 布局布线

## 1. 目标

取得完整 NPU `edrv32_npu`（数据通路 + 控制器、描述符、读写 DMA、非卷积、APB/AXI256 异步桥）在 clk_npu 150 MHz、clk_mem 125 MHz 约束下的时序、关键路径和资源（npu-plan N-W2，NPU 规格第 9 节 [待定] 项的定稿依据）。

## 2. 输入

- commit：分支 `zc100116/SOC系统设计` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录实际使用的完整哈希）。分支：`git fetch origin`，`git switch -c win/20261028-02-npu-synth origin/zc100116/SOC系统设计`。本轮 NPU RTL 尚未合入 `main`。
- 测量顶层 `fpga/rtl/edrv32_fpga_npu_top.v`：`edrv32_npu` 的 319 位 APB/AXI256 输入由 clk_mem 域的串行激励移位寄存器（引脚 `stim_i`）逐位驱动；402 位输出逐位打一拍后经带寄存器的 6 输入异或树折叠到 `obs_o`；`irq_o` 在 clk_npu 域打一拍输出到 `irq_obs_o`。6 个引脚：`clk_npu_i`、`clk_mem_i`、`rst_n_i`、`stim_i`、`obs_o`、`irq_obs_o`。
- 导入脚本 `fpga/scripts/import_npu_top.tcl`：按 `rtl/filelists/npu.f` 展开 36 个源文件（其中 10 个 `rtl/tech/` 包装），加 `rtl/common/edrv32_reset_sync.v` 和顶层，共 38 个；导入约束；以头文件目录 `rtl/include`、宏 `FPGA_MODE` 编译。应打印 `edrv32: added 38 sources`。
- 约束 `fpga/constraints/edrv32_fpga_npu_top.fdc`：`clk_npu_i`（D18）150 MHz，`clk_mem_i`（B24）125 MHz，两者为异步时钟组；其余引脚 C22、C23、A20、C18。只做测量，不上板。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- **新建**工程 `G:\codex_project\EdRV32-FPGA\EdRV32-NPU\EdRV32-NPU.pds`，器件同上（与仓库 `G:\codex_project\EdRV32-Competition-2026` 的相对位置与上一轮 NPU-DP 工程相同，导入脚本按 `../../EdRV32-Competition-2026` 找仓库）。路径不同时写进 `result.md`，并相应调整 `source` 命令。

## 4. 需要的 IP

与上一轮（20261027-02 B 部分）相同的 9 个 NPU IP，**不需要重新设计选项**：`ip_ram_npu_line`、`ip_ram_npu_weight`、`ip_ram_npu_quant`、`ip_ram_npu_lut`、`ip_ram_npu_residual`、`ip_ram_npu_result`、`ip_ram_npu_scratch`、`ip_mul_npu_quant_low`、`ip_mul_npu_quant_high`（创建说明见 `fpga/ip/`）。`edrv32_mul_npu_int8_pair` 直接例化原语，不需要生成。

优先把 NPU-DP 工程中已生成的 9 个 IP 加入新工程（PDS 中添加已有 IP 的 `.idf`）；PDS 不支持时，按创建说明在新工程中重新生成。包装模块已在上一轮按实际端口适配，本轮不改包装模块。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-02-npu-synth origin/zc100116/SOC系统设计`。阅读本卡，把用户步骤整理成清单交给用户。 |
| 2 | 用户（U） | 新建第 3 节的工程，按第 4 节加入（或重新生成）9 个 IP；告诉 Codex 工程路径和 IP 目录，Codex 核对 9 个 IP 的模块名和端口与包装模块 FPGA 分支一致。 |
| 3 | 用户（U） | 在 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_npu_top.tcl`，确认打印 `edrv32: added 38 sources`。编译报错（包括 `set_clock_groups` 语法不被接受）就停下，把报错原文交给 Codex。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。 |
| 5 | Windows Codex（C） | 收集第 6 节产物 1–7；产物 8 的分组方法与 `tasks/win/20261028-01-cpu-sys-synth-r3/task.md` 第 5 节步骤 5 相同（按起点/终点寄存器名主体分组，每组最差一条逐级明细，最多 30 组，两个时钟域分别做）。 |
| 6 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-02-npu-synth results`，推送 `win/20261028-02-npu-synth`，告诉用户完成并给出分支名。 |

本任务与 20261028-01（CPU 第三轮）互不依赖，用不同工程，可以按任意顺序做。不做多种子运行，不上板。

## 6. 产物

放在 `tasks/win/20261028-02-npu-synth/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `ip_ports.md` | 9 个 IP 的来源（沿用 / 重新生成）、模块名、实际端口是否与包装模块一致、DRM/APM 占用 |
| 2 | `timing_summary.txt` | clk_npu、clk_mem 各自的 WNS/TNS/WHS/THS、违例端点数；推算 Fmax（clk_npu：`1000 / (6.667 − WNS)` MHz；clk_mem：`1000 / (8.000 − WNS)` MHz）；确认两时钟间路径未被计入（异步组生效） |
| 3 | `resource_summary.txt` | 资源汇总：LUT、FF、DRM（18K/36K 分别计数）、APM、分布式 RAM、IO、PLL；器件总量和占用率 |
| 4 | `resource_hier.txt` | 按层次的资源分布，至少到 `u_npu` 下每个子模块实例（datapath 及其子模块、regs、descriptor、read_dma、write_dma、conv、conv_write、nonconv、APB/AXI 异步桥），以及顶层激励/观测寄存器 |
| 5 | `setup_top200.txt` | 每个时钟域最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 6 | `setup_top20_detail.txt` | 每个时钟域最差 20 条 setup 路径的逐级明细（每级单元、扇出、单元延迟和线延迟） |
| 7 | `hold_top20.txt`、`high_fanout.txt` | 最差 20 条 hold 路径；扇出最大的 100 个网络 |
| 8 | `setup_group_detail.txt` | 第 5 节步骤 5 的分组明细，段首写组名、组内路径数、最差裕量、所用命令 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。单个产物超过几 MB 时，在 `result.md` 里说明原因。

## 7. 通过判据

- 9 个 IP 与包装模块端口一致；综合、布局布线完成，没有未解析的模块或黑盒（IP 和原语除外）；DRM、APM 不超过器件容量。
- 第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。

时序是否达到 150 MHz 不是本任务的通过条件。

## 8. result.md 模板

```markdown
# 20261028-02-npu-synth 结果

| 项 | 内容 |
|---|---|
| commit | <完整哈希> |
| PDS 版本 | |
| 器件 | PG2L200H-6 FBB676 |
| 工程路径 | |
| IP 来源 | 沿用 NPU-DP 工程 / 重新生成 |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

上一轮（20261027-02 B，仅数据通路）：clk_npu slow WNS +0.341 ns（约 158 MHz）。

每个时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

上一轮（仅数据通路）：22023 LUT、31747 FF、148 DRM36K 当量、288 APM。规格预算：NPU（含输入适配）≤ 50K LUT（SoC 规格 9.3）。

按层次（u_npu 各子模块）：

## 完整报告在 Windows 本地的路径

## 备注
```
