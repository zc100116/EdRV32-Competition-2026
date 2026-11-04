# 卡 57：NPU 独立时序探针（clk_npu 200 MHz）

## 1. 目标

把 NPU（`edrv32_npu`）单独放进一个探针顶层，clk_npu 约束到 200 MHz，跑综合和布局布线，导出所有违例路径。共做两轮：
- R1：clk_npu 切分后的 RTL；
- R2：正式版 RTL。

结果用来确认 `docs/reports/2026-11-04-npu-fmax-rtl.md` 的路径切分实际能达到多少频率。本卡只做时序分析，不生成 bitstream，也不上板。

## 2. 输入

| 轮次 | RTL 检出 | 说明 |
|---|---|---|
| R1 | 本卡所在提交，分支 `zc100116/task-npu-fmax` | 改动内容：APM 链尾和输入本地寄存、激活和权重按簇本地化、输入解包、window、D2 两级、高扇出控制复制 |
| R2 | `e54e471e`，分支 `zc100116/b3`，即正式版 RTL | 正式版 NPU（Q6 加 OPT2），作为对照 |

两轮共用本卡 `src/` 下的三个文件，都从 R1 检出里取：
- `edrv32_npu_timing_probe.v`：探针顶层。NPU 所有输入由 clk_mem 域的串行移位链驱动；APB/AXI 输出在 clk_mem 寄存后折叠成异或链，从 `scan_o` 输出；`irq_o` 在 clk_npu 寄存后从 `irq_scan_o` 输出。
- `edrv32_npu_timing_probe.fdc`：
  - `clk_npu_i` 在 D18 引脚上，周期 5.000 ns；
  - `clk_mem_i` 周期 8.000 ns，引脚由工具自动分配；
  - 两个时钟之间设为异步时钟组，与板级约束相同；
  - setup uncertainty 0.15 ns。
- `import_npu_timing_probe.tcl`：按 `rtl/filelists/npu.f` 导入源文件，定义 `FPGA_MODE`。

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 48 相同。

## 4. 需要的 IP

| IP | 创建说明 | R1 | R2 |
|---|---|---|---|
| `ip_ram_npu_line`、`ip_ram_npu_weight`、`ip_ram_npu_scratch`、`ip_ram_npu_lut`、`ip_lutram_npu_quant`、`ip_lutram_npu_residual`、`ip_lutram_npu_result`、`ip_mul_npu_quant_low`、`ip_mul_npu_quant_high` | `fpga/ip/` 下同名 `.md` | 要 | 要 |

- 这些 IP 的配置与卡 48 的 B3F 工程完全相同，可以直接复制，两轮也一样。R1 只改了 `rtl/tech` 包装模块里 IP 外面的寄存器，没有改 IP 本身。
- 如果导入后 PDS 还报缺少其他模块，比如 NPU AXI 异步桥用到的 RAM，也从 B3F 工程复制同名 IP，并在 `result.md` 里记下名字。

## 5. 操作步骤

1. **Windows Codex（命令行）**：
   - 从本卡所在提交拉出分支 `win/20261104-57-npu-timing-probe`，检出到 `codex_project/EdRV32-Competition-2026`，作为 R1 检出；
   - 如果卡 56 已经建过 R2 检出 `../EdRV32-Competition-2026-r2`（`e54e471e`），直接复用，否则用 `git worktree add ../EdRV32-Competition-2026-r2 e54e471e` 新建。
2. **用户（GUI）**：新建两个工程，器件都是 PG2L200H-6 FBB676：
   - `EdRV32-FPGA/EdRV32-PROBE-NPU-FMAX`（R1）；
   - `EdRV32-FPGA/EdRV32-PROBE-NPU-REL`（R2）。
   按第 4 节生成或复制 IP。
3. **用户（GUI，Tcl 控制台）**：在各自的工程目录下执行。
   R1：
   ```tcl
   set edrv32_repo ../../EdRV32-Competition-2026
   set edrv32_card ../../EdRV32-Competition-2026/tasks/win/20261104-57-npu-timing-probe
   source $edrv32_card/src/import_npu_timing_probe.tcl
   ```
   R2：
   ```tcl
   set edrv32_repo ../../EdRV32-Competition-2026-r2
   set edrv32_card ../../EdRV32-Competition-2026/tasks/win/20261104-57-npu-timing-probe
   source $edrv32_card/src/import_npu_timing_probe.tcl
   ```
4. **用户或 Windows Codex**：综合、Map、布局布线。
   - 先用默认参数跑，在 `settings.txt` 里记下实际参数。
   - 如果 clk_npu 的 WNS 比 −1.0 ns 还差，再用卡 48 F125 r2 的参数补跑一次，两组结果都回传。卡 48 的参数是 `-plc_decongestion 2 -pin_cost_increasing_speed 600 -logic_optimize_lut6d_combing_strategy 0`。
   - 检查综合报告：`keep`/`syn_preserve` 标记的复制寄存器（`rd_en_r` 等）有没有被合并。在 `result.md` 里写明是否保留。
5. **Windows Codex（命令行）**：对两轮的 `_pnr.adf` 分别执行：
   ```tcl
   set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
   report_timing -input_db_file {<工程>/place_route/edrv32_npu_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
   ```
   从这份报告整理出第 6 节的产物。

## 6. 产物

放在 `artifacts/R1/` 和 `artifacts/R2/` 下；如果补跑了卡 48 的参数，结果放在 `R1-d2/`、`R2-d2/`。产物格式与卡 56 第 6 节相同：

| 文件 | 内容 |
|---|---|
| `timing_summary.txt` | clk_npu 和 clk_mem 在慢角、快角的 WNS、TNS、WHS、THS；setup 违例端点数；**clk_npu 估算 Fmax = 1000 / (5.000 − WNS)** |
| `timing_setup_top200.txt` | clk_npu 最差 200 条 setup 路径，每条一行，列同卡 48 |
| `timing_setup_fail_all.txt` | clk_npu 慢角所有 slack<0 的 setup 路径，每个端点一行 |
| `timing_setup_top20_detail.txt` | clk_npu 最差 20 条 setup 路径的逐级明细 |
| `timing_hold_top20.txt` | 最差 20 条 hold 路径 |
| `high_fanout.txt` | 扇出最高的网络，格式同卡 48 |
| `resource_summary.txt`、`resource_hier.txt` | 资源汇总，以及 `u_npu` 下按模块层次的分布 |
| `settings.txt` | 布局布线的实际参数和 PDS 版本 |
| `native_reports/` | `.rtr.gz`、`.prr.gz` |

## 7. 通过判据

两轮都完成布局布线，第 6 节的产物齐全。**本卡不要求时序满足**，违例本身就是要测量的数据。

## 8. result.md 模板

```markdown
# 卡 57 结果

| 轮次 | 布局布线参数 | clk_npu 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | LUT / FF / DRM / APM / 分布式 RAM |
|---|---|---|---|---|---|---|
| R1 切分后 | | | | | | |
| R2 正式版 | | | | | | |

## 最差路径分类（每轮最多 10 类，按起点/终点所在模块归类）

| 轮次 | 类别（起点模块 → 终点模块） | 条数 | 最差 slack | 级数范围 | 主要扇出 |
|---|---|---|---|---|---|

## 复制寄存器是否保留（R1）

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
