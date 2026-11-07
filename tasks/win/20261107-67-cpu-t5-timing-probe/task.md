# 卡 67：CPU 冻结候选（v0.22 + T5 修复）+ L1 独立时序探针（150 MHz）

## 1. 目标

测量 T5 修复后的 CPU 在 150 MHz 下的布局布线时序，与卡 64（138.3 MHz）和卡 66（133.0 MHz）对比。用户 2026-11-07 决定：本卡与卡 64 中频率较高的一版冻结，转入整片集成。本卡只做时序分析，不生成 bitstream，也不上板。

T5 的改动（周期不变，R-05 仍为 1,808,045）：
- IB 数据寄存器的写使能改为只来自寄存的空槽状态，不再取决于本拍 I$ 命中；
- F2 纠正对 IB 计数的影响改为按寄存的两套候选选择；
- D$ 写缓冲地址比较前移到请求进入 M 之前并寄存；
- D$ 命中按使用者分组比较，每组扇出 ≤ 8；
- 删去若干无用副本。

## 2. 输入

| 项 | 内容 |
|---|---|
| RTL 检出 | 本卡所在提交，分支 `zc100116/cpu-n16`（T5 RTL 为 `f1e0d42f`） |
| 新增源文件 | 无（与卡 66 相同） |
| 探针源文件 | 沿用卡 60 的 `tasks/win/20261105-60-cpu-v018-tournament-probe/src/` 下三个文件，内容不变 |
| 对照数据 | 卡 64：WNS −0.562 ns，138.3 MHz，1625 个端点；卡 66：WNS −0.849 ns，133.0 MHz，2961 个端点，LUT / FF 为 23336 / 14282 |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 66 相同。

## 4. 需要的 IP

与卡 66 相同，包括已生成的 108 位 `ip_ram_icache_data`。不需要新的 IP。

## 5. 操作步骤

1. **Windows Codex（命令行）**：在 `../EdRV32-Competition-2026-v018` 中，从本卡所在提交拉出分支 `win/20261107-67-cpu-t5-timing-probe` 并检出。
2. **用户（GUI）**：打开卡 66 的工程 `EdRV32-FPGA/EdRV32-PROBE-V018`。源文件路径不变，不需要重新导入。用默认参数重新跑综合、Map、布局布线，关闭 Generate Bitstream 的 Auto Run。
3. **Windows Codex（命令行）**：导出报告，命令与卡 66 相同：
   ```tcl
   set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
   report_timing -input_db_file {<工程>/place_route/edrv32_cpu_l1_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
   ```
   然后按第 6 节整理产物。

## 6. 产物

放在 `artifacts/R1/` 下，文件和格式与卡 66 相同：
- `timing_summary.txt`
- `timing_setup_top200.txt`
- `timing_setup_fail_all.txt`
- `timing_setup_top20_detail.txt`
- `timing_setup_near_positive.txt`：0 到 +0.3 ns
- `timing_group_worst.txt`：按起点模块 → 终点模块分类，列出违例条数最多的 8 类
- `timing_hold_top20.txt`
- `high_fanout.txt`
- `resource_summary.txt`
- `resource_hier.txt`
- `settings.txt`
- `native_reports/`
- 布线迭代统计，与卡 65 的 `routing_congestion.txt` 格式相同

## 7. 通过判据

布局布线完成，产物齐全。以估算 Fmax 与卡 64 比较，决定冻结哪一版。

## 8. result.md 模板

```markdown
# 卡 67 结果

| 布局布线参数 | 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---|---|---|---|---|---|
| | | | | | | |

## 分类（起点模块 → 终点模块，最多 8 类）

| 类 | 违例条数 | 最差 slack | 级数范围 | 最差路径 逻辑 / 布线 ns | 起点 → 终点 |
|---|---|---|---|---|---|

## 与卡 64、卡 66 对比

## 布线拥塞

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
