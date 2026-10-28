# 任务卡 20261028-05-media-r2：PIX 流水化后媒体/网络模块合并 PDS 复测

## 1. 目标

在已有的 MEDIA 工程中重新导入、综合和布局布线 `edrv32_fpga_media_top`，测出 PIX 流水化（vision-plan V-R6，`docs/debug/2026-10-28-pix-pipeline.md`）后 clk_mem 125 MHz 的时序和各模块资源，并导出 clk_mem **全部**违例端点按模块分组的统计（上一轮只导出了最差 200 条，PIX 以外的模块是否违例未知）。

## 2. 输入

- 任务卡 commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。
- 与上一轮（`tasks/win/20261028-04-media-cpu-probes/` A 部分，结果 `docs/reports/2026-10-28-timing-media-top.md`）相比，只有 `rtl/media/pix/` 的 4 个文件改变（3×3 核和点运算切成流水，÷9 改为常数乘）；文件列表、测量顶层、约束、导入脚本和 IP 都不变。
- 测量顶层 `fpga/rtl/edrv32_fpga_media_top.v`，约束 `fpga/constraints/edrv32_fpga_media_top.fdc`（clk_mem K21、clk_ext D18，均 8.000 ns，异步组），导入脚本 `fpga/scripts/import_media_top.tcl`。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- 工程：沿用 `G:\codex_project\EdRV32-FPGA\EdRV32-MEDIA\EdRV32-MEDIA.pds`（6 个媒体/网络 IP 已在工程中）。

## 4. 需要的 IP

无新增，沿用工程中已生成的 6 个 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-05-media-r2 origin/main`；阅读本卡，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U），或 Codex 在 PDS 控制台 | 在 MEDIA 工程的 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_media_top.tcl`（脚本带 `-force_to_run`，会用新的 PIX 源文件重新编译），确认打印 `edrv32: added 58 sources`。编译报错就停下，把报错原文交给 Codex。 |
| 2 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。不要加 `PAP_CLOCK_DEDICATED_ROUTE FALSE`。 |
| 3 | Windows Codex（C） | 收集第 6 节产物；`endpoints_violating.tsv` 的导出方法与上一轮 B 部分相同（`-max_path 100000`、`-nworst 1`、slack < 0，去重后与 PDS 汇总的违例端点数核对）。 |
| 4 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-05-media-r2 results`，推送 `win/20261028-05-media-r2`，告诉用户完成并给出分支名。中途停下时，已完成部分照常回传，并写明停在哪一步。 |

## 6. 产物

放在 `tasks/win/20261028-05-media-r2/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | clk_mem、clk_ext 的 slow/fast 角 WNS/TNS/WHS/THS、违例端点数；推算 Fmax（`1000 / (8.000 − WNS)` MHz） |
| 2 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM 18K/36K、APM、分布式 RAM、IO、PLL，器件总量和占用率）；按层次：`u_vin`、`u_disp`、`u_pix`、`u_geo`、`u_eth` 及其下一级子模块（PnR 后） |
| 3 | `setup_top200.txt`、`setup_top20_detail.txt` | 每个时钟域最差 200 条 setup 路径（一行一条：起点、终点、裕量、级数）；最差 20 条逐级明细 |
| 4 | `endpoints_violating.tsv` | clk_mem slow 角**全部** setup 违例端点，每端点一行：端点、最差路径起点、裕量、级数（没有违例时写明"无"） |
| 5 | `endpoint_groups.txt` | 对第 4 项分组两次：(a) 按终点所属的顶层模块（`u_vin`、`u_pix`、`u_geo`、`u_disp`、`u_eth`、顶层自身）统计端点数和最差裕量；(b) 按"起点寄存器名去掉位下标 → 终点寄存器名去掉位下标"分组，每组一行：组名、端点数、最差裕量、最差级数，按最差裕量排序 |
| 6 | `hold_top20.txt` | fast 角最差 20 条 hold 路径 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

布局布线完成，两个时钟在指定引脚；第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。时序是否达到 125 MHz 不是本任务的通过条件。

## 8. result.md 模板

```markdown
# 20261028-05-media-r2 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | <完整哈希> |
| PDS 版本 | |
| 工程路径 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

上一轮：clk_mem slow −7.667 ns（63.8 MHz），6356 个违例端点，最差 200 条全在 PIX。

clk_mem 违例端点按模块（endpoint_groups (a)）：

endpoint_groups (b) 前 15 组：

## 资源
| 模块 | LUT | FF | 分布式 RAM | APM | DRM36K 当量 |
|---|---|---|---|---|---|

上一轮：u_vin 3482、u_pix 5593 / 96 APM、u_disp 1448、u_geo 3238、u_eth 3863 LUT。

## 完整报告在 Windows 本地的路径

## 备注
```
