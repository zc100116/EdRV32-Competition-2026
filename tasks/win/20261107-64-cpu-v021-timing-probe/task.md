# 卡 64：CPU v0.21（时序第三轮）+ L1 独立时序探针（150 MHz）

## 1. 目标

测量第三轮等价修复后的 CPU 在 150 MHz 下的布局布线时序，并与卡 62（v0.20，134.8 MHz）对比。
- RTL 的流水结构和延迟与 v0.20 相同，R-05 仍为 1,807,726 周期。
- 第三轮改动：
  - I$/D$ 命中比较结果先寄存，LRU 和有效位晚一拍更新；
  - 写缓冲捕获改从寄存状态取；
  - F2 纠正候选地址预先寄存；
  - IB 读指针按槽预先寄存；
  - 除法、CSR、W 级旁路前移；
  - 若干网络按扇出复制。

这张卡的结果用于：
- 确定还剩哪些路径组；
- 决定是否需要进一步切分流水线（D 级拆分、C6 行预测）；
- 规格 4.9 级数预算的定稿。

用户要求为整片 SoC 的拥塞留余量：独立探针的目标是 150 MHz 下 WNS ≥ +0.3 ns（约 157 MHz）。本卡只做时序分析，不生成 bitstream，也不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| RTL 检出 | 本卡所在提交，分支 `zc100116/cpu-n16` |
| 探针源文件 | 沿用卡 60 的 `tasks/win/20261105-60-cpu-v018-tournament-probe/src/` 下三个文件，内容不变 |
| 对照数据 | 卡 62：WNS −0.752 ns，134.8 MHz，3896 个违例端点；卡 60：109.0 MHz；卡 56 正式版：131.7 MHz |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 60 相同。

## 4. 需要的 IP

与卡 60 完全相同，共 9 个，不需要新 IP。RTL 没有新增文件，文件列表也不变。

## 5. 操作步骤

1. **Windows Codex（命令行）**：在卡 60/62 用过的检出 `../EdRV32-Competition-2026-v018` 中，从本卡所在提交拉出分支 `win/20261107-64-cpu-v021-timing-probe` 并检出。卡 62 的结果已经推送，切换分支不会丢失。
2. **用户（GUI）**：
   - 打开卡 60/62 的工程 `EdRV32-FPGA/EdRV32-PROBE-V018`。源文件路径不变，不需要重新导入；
   - 用默认参数重新跑综合、Map、布局布线；
   - 关闭 Generate Bitstream 的 Auto Run。
3. **Windows Codex（命令行）**：导出报告：
   ```tcl
   set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
   report_timing -input_db_file {<工程>/place_route/edrv32_cpu_l1_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
   ```
   再按第 6 节整理产物。

## 6. 产物

放在 `artifacts/R1/` 下。文件和格式与卡 60 第 6 节相同：
- `timing_summary.txt`
- `timing_setup_top200.txt`
- `timing_setup_fail_all.txt`
- `timing_setup_top20_detail.txt`
- `timing_setup_near_positive.txt`
- `timing_hold_top20.txt`
- `high_fanout.txt`
- `resource_summary.txt`
- `resource_hier.txt`
- `settings.txt`
- `native_reports/`（包含 `timing5000.rtr.gz`）

`timing_group_worst.txt` 改为按下表分组。分组规则与 Linux 校准工具 `tools/synth/cpu_calibrate.py` 的 `group()` 相同，按表中顺序取第一个匹配的组：

| 组 | 起点包含 | 终点包含 |
|---|---|---|
| P10 | `e_redirect_r` | `ras_data_r` |
| P1 | `e_branch_` | 任意 |
| P6 | `/u_dcache/` 或 `/addr_r` | `e_operand_` 或 `e_branch_` |
| P5 | `e_operand_` | `e_operand_` 或 `e_branch_` |
| P4 | `/u_ib/` 或 `/u_dcache/` | `early_` |
| P3 | `/u_ib/` | `/u_core/e_` |
| P2 | `/u_dcache/` | 任意（不属于上面各组的） |
| P7 | `/u_icache/u_tag` | `f1_pc` |
| P8 | `f1_` 或 `/u_frontend/` | `/u_predictor/` |
| P9 | `f1_pc` | `f1_pc` |
| 其他 | 以上都不匹配 | 按起点和终点所在模块归类，列出条数最多的 5 类 |

每组给出：违例条数、最差 slack、级数范围，以及最差一条路径的逐级明细和每一级的扇出。某组在 5000 条中没有出现时：
- 如果 PDS `report_timing` 能按起点或终点筛选，就对该组单独导出最差 1 条；
- 不能筛选时，写"未取得"。

## 7. 通过判据

布局布线完成，产物齐全。**本卡不要求时序满足**。目标是 150 MHz 下 WNS ≥ +0.3 ns，这是为整片 SoC 留的余量。

## 8. result.md 模板

```markdown
# 卡 64 结果

| 布局布线参数 | 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---|---|---|---|---|---|
| | | | | | | |

## 分组（P1–P10、其他）

| 组 | 违例条数 | 最差 slack | 级数范围 | 最差路径 逻辑 / 布线 ns | 起点 → 终点 |
|---|---|---|---|---|---|

## 与卡 62 对比

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
