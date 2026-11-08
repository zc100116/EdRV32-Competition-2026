# 卡 56：CPU+L1 独立时序探针（150 MHz）

## 1. 目标

把 CPU 和两个 L1 cache（`edrv32_cpu_subsys`）单独放进一个探针顶层，约束到 150 MHz 跑综合和布局布线，导出所有违例路径和 LUTRAM 的实测延迟。共做两轮：
- R1：CPU v0.15；
- R2：正式版 CPU。

结果用于校准设计记录 `docs/design/2026-11-04-cpu-fmax-ipc.md` 的时序预算。本卡只做时序分析，不生成 bitstream，也不上板。

## 2. 输入

| 轮次 | RTL 检出 | 说明 |
|---|---|---|
| R1 | 本卡所在提交，分支 `zc100116/cpu-v015-probe` | CPU v0.15：BTB 128、gshare 4096（LUTRAM）、V3s、无 C |
| R2 | `e54e471e`，分支 `zc100116/b3`，即正式版 RTL | 正式版 CPU，预测器为触发器阵列 |

两轮共用本卡 `src/` 下的三个文件，都从 R1 检出里取：
- `edrv32_cpu_l1_timing_probe.v`：探针顶层。CPU 子系统的所有输入由一条串行移位链驱动，所有输出寄存后折叠进一条串行异或链，因此没有常量输入，也没有悬空输出。`debug_o` 不接，与板级顶层一致。
- `edrv32_cpu_l1_timing_probe.fdc`：`clk_i` 在 D18 引脚上，周期 6.667 ns；setup uncertainty 0.15 ns，与卡 48 相同；只把探针引脚设为 false path。
- `import_cpu_l1_timing_probe.tcl`：按 `rtl/filelists/cpu_subsys.f` 导入源文件，定义 `FPGA_MODE`。

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 48 相同。

## 4. 需要的 IP

| IP | 创建说明 | R1 | R2 |
|---|---|---|---|
| `ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、`ip_ram_dcache_data`、`ip_mul_s33x33` | `fpga/ip/` 下同名 `.md` | 要 | 要 |
| `ip_lutram_cpu_btb` | R1 检出里的 `fpga/ip/ip_lutram_cpu_btb.md` | 要（**新生成**） | 不要 |
| `ip_lutram_cpu_direction` | R1 检出里的 `fpga/ip/ip_lutram_cpu_direction.md` | 要（**新生成 1024×4**，带 1024 行 `.dat` 初始化文件；包装把两个 bank 拼成 2048×4，2026-11-05 修订） | 不要 |

前五个 IP 的配置和卡 48 的 B3F 工程完全相同，可以直接复制那边已经生成的 IP。如果分布式 RAM 不提供初始化文件选项，按创建说明停止并回报。

## 5. 操作步骤

1. **Windows Codex（命令行）**：
   - 从本卡所在提交拉出 `win/20261104-56-cpu-l1-timing-probe`，检出到 `codex_project/EdRV32-Competition-2026`，作为 R1 检出；
   - 再用 `git worktree add ../EdRV32-Competition-2026-r2 e54e471e` 建 R2 检出。
2. **用户（GUI）**：新建两个工程，器件都是 PG2L200H-6 FBB676：
   - `EdRV32-FPGA/EdRV32-PROBE-V015`（R1）；
   - `EdRV32-FPGA/EdRV32-PROBE-REL`（R2）。
   按第 4 节在两个工程里生成或复制 IP。
3. **用户（GUI，Tcl 控制台）**：在工程目录下依次执行下面的命令。
   R1：
   ```tcl
   set edrv32_repo ../../EdRV32-Competition-2026
   set edrv32_card ../../EdRV32-Competition-2026/tasks/win/20261104-56-cpu-l1-timing-probe
   source $edrv32_card/src/import_cpu_l1_timing_probe.tcl
   ```
   R2：
   ```tcl
   set edrv32_repo ../../EdRV32-Competition-2026-r2
   set edrv32_card ../../EdRV32-Competition-2026/tasks/win/20261104-56-cpu-l1-timing-probe
   source $edrv32_card/src/import_cpu_l1_timing_probe.tcl
   ```
4. **用户或 Windows Codex**：综合、Map、布局布线。
   - 布局布线先用工具默认参数跑一次，在 `settings.txt` 里记下实际参数。
   - 如果默认参数下 clk_sys 的 WNS 比 −1.0 ns 还差，再用卡 48 F125 r2 的参数补跑一次，两组结果都回传。卡 48 的参数是 `-plc_decongestion 2 -pin_cost_increasing_speed 600 -logic_optimize_lut6d_combing_strategy 0`。
5. **Windows Codex（命令行）**：仿照卡 48 的 `timing_export.tcl`，对两轮的 `_pnr.adf` 各导出以下内容：
   ```tcl
   set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
   report_timing -input_db_file {<工程>/place_route/edrv32_cpu_l1_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
   ```
   从这份报告整理出第 6 节的产物。

## 6. 产物

放在 `artifacts/R1/` 和 `artifacts/R2/` 下。如果第 4 步补跑了卡 48 的参数，补跑结果放在 `R1-d2/`、`R2-d2/`。

| 文件 | 内容 |
|---|---|
| `timing_summary.txt` | clk_sys 慢角和快角的 WNS、TNS、WHS、THS；setup 违例端点数；**估算 Fmax = 1000 / (6.667 − WNS)** |
| `timing_setup_top200.txt` | 最差 200 条 setup 路径，每条一行，列与卡 48 相同：source、corner、clock、type、class、slack_ns、logic_levels、startpoint、endpoint |
| `timing_setup_fail_all.txt` | **慢角所有 slack<0 的 setup 路径**，每个端点一行，列同上。超过 5000 条时，写明总数和截断位置 |
| `timing_setup_top20_detail.txt` | 最差 20 条 setup 路径的逐级明细，格式同卡 48 |
| `timing_lutram_detail.txt` | 只有 R1 需要：经过 `u_cpu/u_core/u_frontend/u_predictor` 中 `ip_lutram_cpu_btb` 和 `ip_lutram_cpu_direction` 实例的最差 10 条路径的逐级明细，要标出 LUTRAM 输出弧的延迟。`report_timing` 不支持 `-from`/`-through` 时，从 5000 条报告中筛选 |
| `timing_hold_top20.txt` | 最差 20 条 hold 路径 |
| `resource_summary.txt`、`resource_hier.txt` | 资源汇总，以及 `u_cpu` 下按模块层次的分布 |
| `settings.txt` | 布局布线的实际参数和 PDS 版本 |
| `native_reports/` | `report_timing` 原始 `.rtr` 压缩成 `.gz`，以及 `.prr.gz` |

## 7. 通过判据

两轮都完成布局布线，第 6 节的产物齐全。**本卡不要求时序满足**，违例本身就是要测量的数据。

## 8. result.md 模板

```markdown
# 卡 56 结果

| 轮次 | 布局布线参数 | 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | LUT / FF / DRM / APM / LUTRAM |
|---|---|---|---|---|---|---|
| R1 v0.15 | | | | | | |
| R2 正式版 | | | | | | |

## 最差路径分类（每轮最多 10 类，按起点/终点所在模块归类）

| 轮次 | 类别（起点模块 → 终点模块） | 条数 | 最差 slack | 级数范围 |
|---|---|---|---|---|

## LUTRAM 输出延迟（R1）

| 实例 | 输出弧延迟 ns | 所在路径 slack |
|---|---|---|

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
