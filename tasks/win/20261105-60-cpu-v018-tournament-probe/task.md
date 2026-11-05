# 卡 60：CPU v0.18（tournament）+ L1 独立时序探针（150 MHz）

## 1. 目标

用卡 56 的探针顶层和约束，测量 CPU v0.18（v0.17 + tournament 第二级方向预测，cpu-spec 4.4）在 150 MHz 下的布局布线时序和资源，与卡 59（v0.17）对比。目标：频率不低于卡 59 的 98%（cpu-spec 第 9 节第 15 项）。本卡只做时序分析，不生成 bitstream，也不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| RTL 检出 | 本卡所在提交，分支 `zc100116/task-cpu-n-tour`。CPU v0.18 = 卡 59 的 v0.17 + JAL 映射修复 + tournament |
| 探针源文件 | 本卡 `src/` 下三个文件，内容与卡 59 相同，只改了注释 |
| 对照数据 | 卡 59（v0.17），与本卡同时执行；卡 56 R1（v0.16）WNS −1.342 ns，估算 124.9 MHz |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 56 相同。

## 4. 需要的 IP

| IP | 创建说明 | 来源 |
|---|---|---|
| `ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、`ip_ram_dcache_data`、`ip_mul_s33x33`、`ip_lutram_cpu_btb`、`ip_lutram_cpu_direction` | `fpga/ip/` 下同名 `.md` | 从卡 59 的 `EdRV32-PROBE-V017` 工程复制 |
| `ip_lutram_cpu_local_history` | `fpga/ip/ip_lutram_cpu_local_history.md`（256×10，初值 0） | **新生成**，包装中 3 个实例 |
| `ip_lutram_cpu_tournament` | `fpga/ip/ip_lutram_cpu_tournament.md`（1024×2，初值 01） | **新生成**，包装中 11 个实例：局部方向 3 个，选择器 8 个 |

两个新 IP 都带初始化 `.dat` 文件，生成命令写在各自的说明里。如果分布式 RAM 不提供初始化文件选项，按说明停止并回报。

## 5. 操作步骤

1. **Windows Codex（命令行）**：从本卡所在提交拉出 `win/20261105-60-cpu-v018-tournament-probe`，用 `git worktree add ../EdRV32-Competition-2026-v018 <本卡提交>` 建一个单独的检出，不要占用卡 59 的检出。
2. **用户（GUI）**：新建工程 `EdRV32-FPGA/EdRV32-PROBE-V018`，器件 PG2L200H-6 FBB676，按第 4 节复制或生成 IP。
3. **用户（GUI，Tcl 控制台）**：在工程目录下执行：
   ```tcl
   set edrv32_repo ../../EdRV32-Competition-2026-v018
   set edrv32_card ../../EdRV32-Competition-2026-v018/tasks/win/20261105-60-cpu-v018-tournament-probe
   source $edrv32_card/src/import_cpu_l1_timing_probe.tcl
   ```
4. **用户或 Windows Codex**：综合、Map、布局布线，全部用默认参数。在 `settings.txt` 里记下实际参数。
   - 卡 56 中去拥塞参数的结果更差，本卡不补跑；
   - 关闭 Generate Bitstream 的 Auto Run。
5. **Windows Codex（命令行）**：按卡 56 的方法对 `_pnr.adf` 导出报告：
   ```tcl
   set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
   report_timing -input_db_file {<工程>/place_route/edrv32_cpu_l1_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
   ```
   再从报告中整理出第 6 节的产物。

## 6. 产物

放在 `artifacts/R1/` 下。

| 文件 | 内容 |
|---|---|
| `timing_summary.txt` | clk_sys 慢角和快角的 WNS、TNS、WHS、THS；setup 违例端点数；**估算 Fmax = 1000 / (6.667 − WNS)** |
| `timing_setup_top200.txt` | 最差 200 条 setup 路径，每条一行，列与卡 56 相同 |
| `timing_setup_fail_all.txt` | 慢角所有 slack < 0 的 setup 路径，每个端点一行，列同上。超过 5000 条时写明总数 |
| `timing_setup_top20_detail.txt` | 最差 20 条 setup 路径的逐级明细，格式同卡 56 |
| `timing_group_worst.txt` | 下面每一组的最差一条路径的逐级明细，并标出每一级的扇出。没有违例的组也要给，写出它的 slack |
| `timing_hold_top20.txt` | 最差 20 条 hold 路径 |
| `resource_summary.txt`、`resource_hier.txt` | 资源汇总，以及 `u_cpu` 下按模块层次的分布，**写明分布式 RAM 总数及 `u_predictor` 的 LUT 和分布式 RAM**，与卡 59 对比 |
| `settings.txt` | 布局布线的实际参数和 PDS 版本 |
| `native_reports/` | `report_timing` 原始 `.rtr` 的 `.gz` 压缩包，以及 `.prr.gz` |

`timing_group_worst.txt` 的分组（按起点和终点名称从 5000 条报告中筛选）：

| 组 | 起点 → 终点 |
|---|---|
| G1 F1 环 | `u_frontend/f1_pc_r` 或 `f1_icache_pc_r` → `u_frontend/f1_pc_r` |
| G2 I$ → 前端 | `u_icache` 的 tag/data DRM → `u_frontend`、`u_ib`、`u_predictor` |
| G3 ALU 旁路环 | `u_core` 的 E 级操作数寄存器 → E 级操作数寄存器 |
| G4 D$ → 操作数 | `u_dcache` 的 tag/data DRM（含副本）→ `u_core` |
| G5 重定向 | `u_core` 中寄存的重定向或训练寄存器 → `u_frontend`、`u_predictor`、`u_ib`、`u_icache` |
| G6 乘法 | `u_mul` 的 APM → 任意 |
| G7 D 级 | `u_ib` 的条目或指针 → `u_core` 的 E 级寄存器（含提前地址到 D$ 地址的路径） |
| G8 F2 纠正 | tournament 三张表的 LUTRAM 输出或 `u_frontend` 的 F2 寄存器 → `u_frontend/f1_pc_r`、`f1_icache_pc_r`、I$ 请求 |

## 7. 通过判据

布局布线完成，第 6 节的产物齐全。**本卡不要求时序满足**，违例本身就是要测量的数据。

## 8. result.md 模板

```markdown
# 卡 60 结果

| 布局布线参数 | 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---|---|---|---|---|---|
| | | | | | | |

## 分组最差路径

| 组 | 最差 slack | 级数 | 逻辑 / 布线 ns | 起点 → 终点 |
|---|---|---|---|---|

## 最差路径分类（最多 10 类，按起点和终点所在模块归类）

| 类别 | 条数 | 最差 slack | 级数范围 |
|---|---|---|---|

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
