# 卡 63：NPU 独立时序探针复测（clk_npu 200 MHz，修 mac_array 空闲或树）

## 1. 目标

修复卡 61 的 72 条违例，然后用同一个探针在 200 MHz 下复测，确认 clk_npu 的 WNS ≥ 0。本卡只做时序分析，不生成 bitstream，也不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| RTL 检出 | 本卡所在提交，分支 `zc100116/task-npu-fmax`。RTL 改动在 `ef1eea7e` |
| 本次改动 | `rtl/npu/edrv32_npu_mac_array.v`。卡 61 的最差路径（−0.335 ns）从 32 个通道 × 12 级的 `valid_r` 或树出发，经 datapath 的 idle，到 conv 的 `model_*_addr_r` CE。现在 `idle_o` 改由一个带 keep 的控制链和寄存的 `busy_r` 直接给出，逻辑等价 |
| 探针源文件 | 沿用卡 57 的 `tasks/win/20261104-57-npu-timing-probe/src/`，内容不变 |
| 对照数据 | 卡 61：WNS −0.335 ns，72 个违例端点，187.4 MHz；卡 57 R1：194.4 MHz |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 57 相同。

## 4. 需要的 IP

与卡 57 R1 相同，不需要新的 IP。直接复用卡 57 的 R1 工程 `EdRV32-FPGA/EdRV32-PROBE-NPU-FMAX`。

## 5. 操作步骤

1. **Windows Codex（命令行）**：在 `codex_project/EdRV32-Competition-2026` 中，从本卡所在提交拉出分支 `win/20261107-63-npu-timing-probe-r4` 并检出。卡 61 的结果已经推送，切换分支不会丢失。
2. **用户（GUI）**：
   - 打开 `EdRV32-PROBE-NPU-FMAX` 工程，源文件路径不变，所以不需要重新导入；
   - 用卡 57 R1 相同的默认参数重新跑综合、Map、布局布线；
   - 关闭 Generate Bitstream 的 Auto Run。
3. **Windows Codex（命令行）**：对新的 `_pnr.adf` 导出报告：
   ```tcl
   set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
   report_timing -input_db_file {<工程>/place_route/edrv32_npu_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
   ```
   再按第 6 节整理产物。
4. 在综合报告中检查 `u_mac_array` 的 `busy_r`、`ctrl_valid_r` 是否保留，没有与各通道的 `valid_r` 合并。

## 6. 产物

放在 `artifacts/R4/` 下，格式与卡 57 第 6 节相同：
- `timing_summary.txt`：clk_npu 估算 Fmax = 1000 / (5.000 − WNS)；
- `timing_setup_top200.txt`、`timing_setup_fail_all.txt`、`timing_setup_top20_detail.txt`；
- `timing_setup_near_positive.txt`：0 到 +0.2 ns 之间的 200 条 setup 路径；
- `timing_hold_top20.txt`、`high_fanout.txt`；
- `resource_summary.txt`、`resource_hier.txt`、`settings.txt`；
- `native_reports/`。

## 7. 通过判据

布局布线完成，产物齐全。clk_npu 慢角 WNS ≥ 0 为目标，没有达到时，违例路径就是下一轮的输入。

## 8. result.md 模板

```markdown
# 卡 63 结果

| 布局布线参数 | clk_npu 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | clk_mem WNS | LUT / FF / DRM / APM / 分布式 RAM |
|---|---|---|---|---|---|---|
| | | | | | | |

## 最差路径分类（最多 10 类）

| 类别（起点模块 → 终点模块） | 条数 | 最差 slack | 级数范围 | 主要扇出 |
|---|---|---|---|---|

## busy_r / ctrl_valid_r 是否保留

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
