# 任务卡 20261028-02-npu-pnr-r2：完整 NPU 布局布线重跑（clk_mem 改用时钟引脚）

## 1. 目标

在 20261028-01 B 部分的工程上，把 `clk_mem_i` 从 B24 改到能接全局时钟的 K21 后，完成完整 NPU 的布局布线，取得 clk_npu 150 MHz、clk_mem 125 MHz 下的路后时序和资源（npu-plan N-W2）。

## 2. 输入

- commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。分支：`git fetch origin`，`git switch -c win/20261028-02-npu-pnr-r2 origin/main`。
- 与 20261028-01 的区别只有两处：
  - `fpga/constraints/edrv32_fpga_npu_top.fdc`：`clk_mem_i` 的 `PAP_IO_LOC` 由 B24 改为 K21。K21 是厂商 HDMI 例程中 `pixclk_in` 的引脚，例程直接把它作为时钟输入。上一轮 B24 是普通 IO，PnR 报 Place-0084。
  - `fpga/scripts/import_cpu_sys_top.tcl`、`import_npu_top.tcl`：并入上一轮 Windows 端的路径修正，内容与 `win/20261028-01-cpu-npu-synth` 相同。
- RTL、IP、其余约束不变。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- 工程：沿用 `G:\codex_project\EdRV32-FPGA\EdRV32-NPU\EdRV32-NPU.pds`（9 个 IP 已在工程中）。

## 4. 需要的 IP

无新增，沿用工程中的 9 个 NPU IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-02-npu-pnr-r2 origin/main`，确认仓库中 `edrv32_fpga_npu_top.fdc` 的 `clk_mem_i` 为 K21；确认工程使用的是仓库中的这个 `.fdc`（不是复制到工程目录的旧副本），否则停下告诉用户。 |
| 2 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。**不要加 `PAP_CLOCK_DEDICATED_ROUTE FALSE`**；K21 仍报 Place-0084 时停下回传。 |
| 3 | Windows Codex（C） | 在 PnR 日志中确认 `clk_mem_i` 位于 K21、两个时钟各经一个全局时钟缓冲；收集第 6 节产物。 |
| 4 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-02-npu-pnr-r2 results`，推送 `win/20261028-02-npu-pnr-r2`，告诉用户完成并给出分支名。 |

## 6. 产物

放在 `tasks/win/20261028-02-npu-pnr-r2/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| # | 产物 | 内容 |
| 2 | `timing_summary.txt` | clk_npu、clk_mem 各自的 WNS/TNS/WHS/THS、违例端点数；推算 Fmax（clk_npu：`1000 / (6.667 − WNS)` MHz；clk_mem：`1000 / (8.000 − WNS)` MHz）；确认两时钟间路径未被计入（异步组生效） |
| 3 | `resource_summary.txt` | 资源汇总：LUT、FF、DRM（18K/36K 分别计数）、APM、分布式 RAM、IO、PLL；器件总量和占用率 |
| 4 | `resource_hier.txt` | 按层次的资源分布，至少到 `u_npu` 下每个子模块实例（datapath 及其子模块、regs、descriptor、read_dma、write_dma、conv、conv_write、nonconv、APB/AXI 异步桥），以及顶层激励/观测寄存器 |
| 5 | `setup_top200.txt` | 每个时钟域最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 6 | `setup_top20_detail.txt` | 每个时钟域最差 20 条 setup 路径的逐级明细（每级单元、扇出、单元延迟和线延迟） |
| 7 | `hold_top20.txt`、`high_fanout.txt` | 最差 20 条 hold 路径；扇出最大的 100 个网络 |
| 8 | `setup_group_detail.txt` | 分组明细（方法与 20261028-01 B5 相同：按起点/终点寄存器名主体分组，每组最差一条逐级明细，最多 30 组，两个时钟域分别做），段首写组名、组内路径数、最差裕量、所用命令 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 布局布线完成，`clk_mem_i` 在 K21，未使用专用时钟布线放宽。
- 第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。
- 时序是否达到 150 MHz / 125 MHz 不是本任务的通过条件。

## 8. result.md 模板

```markdown
# 20261028-02-npu-pnr-r2 结果

| 项 | 内容 |
|---|---|
| commit | <完整哈希> |
| PDS 版本 | |
| 器件 | PG2L200H-6 FBB676 |
| 工程路径 | |
| clk_mem_i 位置 / 时钟缓冲 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

综合预估（20261028-01）：clk_npu WNS +0.107 ns，clk_mem +4.998 ns；仅数据通路的上一轮路后 clk_npu +0.341 ns。
异步组是否生效（两时钟间路径未计入）：

每个时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

综合（20261028-01）：27372 LUT、36737 FF、157 DRM36K、290 APM。

按层次（u_npu 各子模块）：

## 完整报告在 Windows 本地的路径

## 备注
```
