# 任务卡 20261029-01-media-r4：媒体/网络合并 PDS 第四轮（V-R8 余量提升后）

## 1. 目标

在 MEDIA 工程中重新导入、综合和布局布线 `edrv32_fpga_media_top`，测出 V-R8（`docs/debug/2026-10-28-media-timing-r3.md`）后 clk_mem 125 MHz 的余量，确认复制的推进使能寄存器是否保留（vision-plan V-W5）。

## 2. 输入

- 任务卡 commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。
- 与第三轮（`tasks/win/20261028-07-media-r3-b1/` A 部分，结果 `docs/reports/2026-10-28-timing-media-top-r3.md`：clk_mem slow +0.388 ns，0 违例）相比，只改了 `rtl/media/pix/`、`rtl/media/vin/`、`rtl/media/geo/`、`rtl/media/disp/`、`rtl/eth/` 下的 RTL；文件列表、测量顶层、约束 `fpga/constraints/edrv32_fpga_media_top.fdc`、导入脚本 `fpga/scripts/import_media_top.tcl` 和 IP 都不变。
- PIX 的推进使能按局部复制成 103 份寄存器，带 `/* synthesis syn_preserve=1 */`（RTL 中的名字：`u_pix/advance_input_r`、`advance_point1_r`、`advance_point2_r`、`advance_filter1_r`、`advance_filter2_r`、`advance_kernel10_r`、`advance_kernel11_r`、`advance_kernel20_r`、`advance_kernel21_r`，以及各 kernel 内的操作码复制寄存器）。PDS 是否保留这些复制寄存器是本轮要确认的事项之一。

## 3. 环境

PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676；工程 `G:\codex_project\EdRV32-FPGA\EdRV32-MEDIA\EdRV32-MEDIA.pds`（与第三轮相同）。

## 4. 需要的 IP

无新增，沿用工程中已有的 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261029-01-media-r4 origin/main`；阅读本卡，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U），或 Codex 在 PDS 控制台 | 在工程中移除上一轮导入的全部设计源文件和约束（保留 IP）；PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_media_top.tcl`，确认打印的 `edrv32: added N sources` 数量与第三轮一致（58）；依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。报错就停下，把原文交给 Codex。 |
| 2 | Windows Codex（C） | 收集第 6 节产物。时序导出方法同第三轮（全量违例端点：`-max_path 100000`、`-nworst 1`、slack < 0；危险正裕量：0 < slack < 1 ns 全部路径）。 |
| 3 | Windows Codex（C） | **复制寄存器核对**：在综合后网表或资源/扇出报告中查找第 2 节列出的 `u_pix/advance_*_r` 寄存器，记录实际保留的个数（每个名字保留了几位）以及每份驱动的扇出（可用 `high_fanout` 报告或 `report_timing` 中该网络的 fanout）；同时记录 `u_pix` 内扇出最大的 10 个网络（名字、扇出、驱动单元类型）。综合日志中与 `syn_preserve` 有关的提示原文摘录。 |
| 4 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-01-media-r4 results`，推送 `win/20261029-01-media-r4`，告诉用户完成并给出分支名。 |

## 6. 产物

放在 `tasks/win/20261029-01-media-r4/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | clk_mem、clk_ext 的 slow/fast 角 WNS/TNS/WHS/THS、违例端点数；推算 Fmax（`1000 / (8.000 − WNS)` MHz） |
| 2 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总和按层次（`u_vin`、`u_disp`、`u_pix`、`u_geo`、`u_eth` 及其下一级，PnR 后） |
| 3 | `setup_top200.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | 每个时钟域最差 200 条 setup、最差 20 条逐级明细、fast 角最差 20 条 hold |
| 4 | `endpoints_violating.tsv`、`setup_near_positive_top200.txt`、`setup_near_positive_top20_detail.txt` | clk_mem slow 全部 setup 违例端点（没有时写"无"）；0 < slack < 1 ns 的全部路径和最差 20 条逐级明细 |
| 5 | `replication_check.txt` | 第 5 节步骤 3 的核对结果 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

布局布线完成；产物齐全；数字来自 PDS 报告原文，找不到的写"未取得"。目标是 clk_mem slow WNS ≥ +1.0 ns，但达不到不是停止条件。

## 8. result.md 模板

```markdown
# 20261029-01-media-r4 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | <完整哈希> |
| PDS 版本 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序

| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

上一轮：clk_mem slow +0.388 ns（131.4 MHz），0 违例；0–1 ns 路径 146 条。

0 < slack < 1 ns 路径按"起点 → 终点"分组（端点数、最差、级数）：

## 复制寄存器

| 寄存器 | RTL 位数 | 保留位数 | 每份扇出 |
|---|---|---|---|

u_pix 扇出最大的 10 个网络：
syn_preserve 相关提示：

## 资源

| 模块 | LUT | FF | 分布式 RAM | APM | DRM36K 当量 |
|---|---|---|---|---|---|

上一轮：u_vin 3562、u_pix 4943 / 132 APM、u_disp 1468、u_geo 3184 / 9 APM、u_eth 3858 LUT；整个顶层 18416 LUT、23199 FF。

## 完整报告在 Windows 本地的路径

## 备注
```
