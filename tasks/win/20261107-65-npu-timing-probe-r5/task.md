# 卡 65：NPU 独立时序探针第 5 轮（clk_npu 200 MHz，布线主导路径本地化）

## 1. 目标

卡 63 剩下的是 0–1 级、以布线为主的路径。本轮把这些路径的源寄存器在本地复制、加寄存，然后用同一个探针在 200 MHz 下复测。目标是 clk_npu 的 WNS ≥ +0.3 ns，为整片拥塞留余量（用户 2026-11-07）。本卡只做时序分析，不生成 bitstream，也不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| RTL 检出 | 本卡所在提交，分支 `zc100116/task-npu-fmax`。RTL 改动在 `a4d22e30` |
| 本次改动 | `rtl/npu/` 中 weight_store、mac_array、window、conv、top。权重写地址、写使能、写数据按 bank/segment 本地寄存；权重读选择分组复制；APM 激活和权重输入的末级按链复制；像素选择复制；schedule_row 改为并行匹配，stop 路径简化。新增约 6,000 个 FF（带 `keep`/`syn_preserve`），APM 和 DRM 数量不变。明细见 `docs/reports/2026-11-07-npu-fmax5.md` |
| 探针源文件 | 沿用卡 57 的 `tasks/win/20261104-57-npu-timing-probe/src/`，内容不变 |
| 对照数据 | 卡 63：WNS −0.027 ns，2 个违例端点，198.9 MHz；LUT / FF 为 17069 / 40025 |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 63 相同。

## 4. 需要的 IP

与卡 63 相同，不需要新的 IP。直接复用工程 `EdRV32-FPGA/EdRV32-PROBE-NPU-FMAX`。

## 5. 操作步骤

1. **Windows Codex（命令行）**：在 `codex_project/EdRV32-Competition-2026` 中，从本卡所在提交拉出分支 `win/20261107-65-npu-timing-probe-r5` 并检出。
2. **用户（GUI）**：
   - 打开 `EdRV32-PROBE-NPU-FMAX` 工程。源文件路径不变，不需要重新导入。
   - 用与卡 63 相同的默认参数重新跑综合、Map、布局布线。
   - 关闭 Generate Bitstream 的 Auto Run。
3. **Windows Codex（命令行）**：对新的 `_pnr.adf` 导出报告，命令与卡 63 第 5 节第 3 步相同：
   ```tcl
   set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
   report_timing -input_db_file {<工程>/place_route/edrv32_npu_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
   ```
   然后按第 6 节整理产物。
4. **Windows Codex**：在综合报告中检查以下三类副本是否保留，没有被合并：
   - `u_weight_store` 中按 bank/segment 的写地址和写使能副本；
   - `u_mac_array` 中各链的激活副本；
   - `u_window` 中的选择副本。

   每类写出保留的实例数。

## 6. 产物

放在 `artifacts/R5/` 下，格式与卡 63 第 6 节相同：
- `timing_summary.txt`：clk_npu 估算 Fmax = 1000 / (5.000 − WNS)；
- `timing_setup_top200.txt`、`timing_setup_fail_all.txt`、`timing_setup_top20_detail.txt`；
- `timing_setup_near_positive.txt`：0 到 +0.3 ns 之间的 200 条 setup 路径（本卡窗口改为 +0.3 ns）；
- `timing_hold_top20.txt`、`high_fanout.txt`；
- `resource_summary.txt`、`resource_hier.txt`、`settings.txt`；
- `preserve_registers.txt`：第 5 节第 4 步的检查结果；
- `native_reports/`。

## 7. 通过判据

布局布线完成，产物齐全。目标为 clk_npu 慢角 WNS ≥ +0.3 ns。没有达到时，WNS 最差的路径和 0–0.3 ns 内的路径就是下一轮的输入。另外报告布线拥塞的摘要，如果 PDS 能导出的话。

## 8. result.md 模板

```markdown
# 卡 65 结果

| 布局布线参数 | clk_npu 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | clk_mem WNS | LUT / FF / DRM / APM / 分布式 RAM |
|---|---|---|---|---|---|---|
| | | | | | | |

## 与卡 63 对比

## 最差路径分类（最多 10 类，含 0–0.3 ns 的路径）

| 类别（起点模块 → 终点模块） | 条数 | 最差 slack | 级数范围 | 主要扇出 |
|---|---|---|---|---|

## 副本保留情况

## 布线拥塞（如果能导出）

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
