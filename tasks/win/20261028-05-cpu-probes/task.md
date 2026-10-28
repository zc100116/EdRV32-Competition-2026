# 任务卡 20261028-05-cpu-probes：CPU 时序探针 P1/P2/P3 各一次 PDS

## 1. 目标

对评估分支上的 3 个探针提交各做一次综合 + 布局布线，测出"去掉 C 扩展""前端与后端之间只有寄存器边界""再切断 RAM 命中、旁路晚到源、宽进位链并约束 core 区域"三步各能拿回多少时序裕量，并导出每版全部违例端点的分组统计（cpu-plan C-W6；设计记录 `docs/design/2026-10-28-cpu-timing-closure.md` 第 5 节第 1 步）。探针 P2、P3 功能不正确，只用于测量，不上板。

## 2. 输入

- 任务卡所在 commit：`main` 上包含本任务卡的提交。
- 探针提交（在 `origin/probe/cpu-timing` 分支上，按顺序）：
  | 版本 | 提交 | 内容 |
  |---|---|---|
  | P1 | `15d21f8` | RVC_EN 默认 0（C 扩展已决定去掉），软件 rv32im；功能正确 |
  | P2 | `2ec4170` | P1 + 前端所有后端输入寄存一拍，重定向 valid 按 predictor / F1 / IB 三组复制 |
  | P3 | `3615a7e` | P2 + I$/D$ 命中寄存、乘法和 load 结果只从寄存级旁路、CSR 计数器进位寄存、core 区域约束 |
- 约束：P1 只用 `fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`；P2、P3 **另加** `fpga/constraints/edrv32_fpga_cpu_sys_top_probe.fdc`（P2：6 个复制寄存器的 `syn_preserve` / `syn_keep`；P3 另有 `u_cpu_subsys.u_core` 的 `PAP_REGION {423 600 806 791}`）。这些属性名、对象写法和区域语法是 Linux 端按资料推测的，**需要在 PDS 中确认**（见第 5 节步骤 3）。
- 导入脚本：`fpga/scripts/import_cpu_sys_top.tcl`（与第四轮相同）。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- 工程：沿用 `G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`（7 个 CPU 子系统 IP 已在工程中）。三个版本依次在同一工程中重新导入、重新运行；每版跑完先收集产物，再切换下一版。

## 4. 需要的 IP

无新增。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-05-cpu-probes origin/main`（产物和 result.md 提交在这个分支）。另开一个工作目录或用 `git worktree add ../probe-src origin/probe/cpu-timing` 检出探针源码，后续按版本 `git -C ../probe-src checkout <提交>`；导入脚本中的仓库路径相应指向 `../probe-src`（只在本地改路径，不提交）。把用户步骤整理成清单交给用户。 |
| 2 | 用户（U），或 Codex 在 PDS 控制台 | **P1**：检出 `15d21f8`，在 PDS Tcl 控制台 `source` 导入脚本，确认打印的源文件数；依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。 |
| 3 | Windows Codex（C） | 收集 P1 的第 6 节产物。查 PDS 文档（或用一个最小工程试验）确认：保留属性的正确写法（`syn_preserve` / `syn_keep` 或 PDS 的等效属性，对象类别 `i:` / `n:`、层次分隔符）；`PAP_REGION`（或 PDS 的等效区域约束）的语法、坐标单位，以及该区域在 PG2L200H 上是否合法、是否覆盖 4 个 APM。需要改写 `edrv32_fpga_cpu_sys_top_probe.fdc` 时，**只在本地改**，把改后的全文作为产物回传，并在 result.md 中说明改了什么。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | **P2**：检出 `2ec4170`，导入脚本之后再执行 `add_constraint <probe-src>/fpga/constraints/edrv32_fpga_cpu_sys_top_probe.fdc`（P2 版本中没有区域约束）；同步骤 2 跑完四步。 |
| 5 | Windows Codex（C） | 收集 P2 产物；在 map 报告中确认 6 个复制的 valid 寄存器没有被合并（各自独立存在），合并了就写明。 |
| 6 | 用户（U），或 Codex 在 PDS 控制台 | **P3**：检出 `3615a7e`，同步骤 4（含区域约束）跑完四步。区域约束导致布局失败时，去掉区域约束再跑一次，两次的结果都回传。 |
| 7 | Windows Codex（C） | 收集 P3 产物；填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-05-cpu-probes results`，推送 `win/20261028-05-cpu-probes`，告诉用户完成并给出分支名。 |

## 6. 产物

每个版本一个子目录 `artifacts/p1/`、`artifacts/p2/`、`artifacts/p3/`（P3 去掉区域约束重跑时另加 `artifacts/p3_noregion/`），各含：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | slow/fast 角 WNS/TNS/WHS/THS、违例端点数、推算 Fmax（`1000 / (6.667 − WNS)` MHz） |
| 2 | `resource_summary.txt` | LUT、FF、DRM、APM、分布式 RAM；`u_core` 及其下一级子模块的 LUT/FF |
| 3 | `setup_top200.txt` | slow 角最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 4 | `setup_top20_detail.txt` | slow 角最差 20 条的逐级明细（每级单元、扇出、单元延迟和线延迟） |
| 5 | `endpoints_violating.tsv` | **全部** setup 违例端点（slow 角），每个端点一行：端点、该端点最差路径的起点、裕量、逻辑级数。PDS 能按端点导出就用端点导出（例如每个端点 1 条路径）；不能时导出尽可能多的路径（例如 `-max_path 10000`），并写明所用命令和是否覆盖全部违例端点 |
| 6 | `endpoint_groups.txt` | 对第 5 项按"起点寄存器名去掉位下标 → 终点寄存器名去掉位下标"分组，每组一行：组名、端点数、最差裕量、最差级数；按最差裕量排序 |
| 7 | `fdc_used.fdc`（仅 P2、P3） | 实际使用的探针约束全文 |

不提交 PDS 工程文件、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 三个版本都完成布局布线（或在第 5 节规定的情况下停下并说明）；第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。
- 时序是否达到 150 MHz 不是本任务的通过条件。

## 8. result.md 模板

```markdown
# 20261028-05-cpu-probes 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | <完整哈希> |
| 探针提交 | P1 15d21f8 / P2 2ec4170 / P3 3615a7e（完整哈希） |
| PDS 版本 | |
| 工程路径 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 约束确认
- 保留属性的正确写法：
- 6 个复制寄存器是否保留：
- 区域约束语法和是否生效：
- 对探针 .fdc 的本地修改：

## 时序（slow 角）
| 版本 | WNS | TNS | 违例端点数 | Fmax（推算） | 最差路径（起点 → 终点，级数） |
|---|---|---|---|---|---|
| 第四轮（RVC=1） | −1.789 | −4967.383 | 7611 | 118.3 | e_jalr_expected_odd_r → ras_data_r，16 |
| P1 | | | | | |
| P2 | | | | | |
| P3 | | | | | |

每个版本 endpoint_groups 的前 10 组：

## 资源
| 版本 | LUT | FF | DRM | APM | u_core LUT |
|---|---|---|---|---|---|

## 完整报告在 Windows 本地的路径

## 备注
```
