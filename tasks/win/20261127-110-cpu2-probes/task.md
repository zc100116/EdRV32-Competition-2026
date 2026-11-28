# 卡 110：CPU v2 关键路径探针（整数 + FP32 FMA）布局布线

## 1. 目标

把 CPU v2 的几条关键路径做成两个独立的小工程，在 PG2L200H-6 上综合、布局布线，量出每条路径在 150 MHz 约束下的真实裕量和资源。只做时序和资源分析，不生成比特流，不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 用 `git log -1 --format=%H origin/zc100116/gpu-dev -- tasks/win/20261127-110-cpu2-probes` 找到本卡的提交，从它拉出 `win/20261127-110-cpu2-probes`，记录 HEAD |
| 工程 A（整数） | 顶层 `edrv32_fpga_probe_cpu2_int_top`；约束 `fpga/constraints/edrv32_fpga_probe_cpu2_int_top.fdc`；导入脚本 `fpga/scripts/import_probe_cpu2_int_top.tcl`；文件列表 `rtl/filelists/cpu2_probe_int.f` |
| 工程 B（FMA） | 顶层 `edrv32_fpga_probe_cpu2_fma_top`；约束 `fpga/constraints/edrv32_fpga_probe_cpu2_fma_top.fdc`；导入脚本 `fpga/scripts/import_probe_cpu2_fma_top.tcl`；文件列表 `rtl/filelists/cpu2_probe_fma.f` |
| 各路径的起点终点 | `docs/design/2026-11-27-cpu-v2-probes.md`（整数探针表、FMA 探针表） |

两个工程都是单时钟 `clk_i`，约束 6.667 ns（150 MHz），没有 PLL。

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 107 相同。

## 4. 需要的 IP

**工程 A**：在工程 `EdRV32-FPGA/cpu2_probe_int` 中按下列说明生成 9 个 IP（说明在 `fpga/ip/`）：

| IP | 类型 | 几何 |
|---|---|---|
| `ip_lutram_cpu2_rf` | 分布式 RAM，组合读 | 32×32 |
| `ip_lutram_cpu2_btb` | 分布式 RAM，组合读 | 64×59 |
| `ip_lutram_cpu2_fast` | 分布式 RAM，组合读 | 1024×2 |
| `ip_ram_cpu2_cache_data` | DRM，同步读 | 2048×32 |
| `ip_ram_cpu2_cache_tag` | DRM，同步读 | 512×19 |
| `ip_ram_cpu2_tage` | DRM，同步读 | 256×16 |
| `ip_ram_cpu2_tage_train` | DRM，同步读 | 512×16 |
| `ip_ram_cpu2_base` | DRM，同步读 | 2048×2 |
| `ip_ram_cpu2_base_train` | DRM，同步读 | 4096×2 |

**生成后逐个核对模块名、端口名和位宽与说明一致；不一致就停下，把实际端口记入 result.md，不要改包装模块。**

**工程 B**：不需要生成 IP。乘法直接例化 `GTP_APM_E2` 原语（说明 `fpga/ip/apm_cpu2_fpu.md`）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | 按第 2 节拉分支，记录 HEAD |
| 1 | U | 新建工程 `EdRV32-FPGA/cpu2_probe_int`（PG2L200H-6 FBB676），按第 4 节生成 9 个 IP |
| 2 | U | 在该工程目录的 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_probe_cpu2_int_top.tcl` |
| 3 | U | 默认参数跑综合、Device Map、布局布线；关闭 Generate Bitstream 的 Auto Run |
| 4 | U | 新建工程 `EdRV32-FPGA/cpu2_probe_fma`（同器件），执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_probe_cpu2_fma_top.tcl`，同样跑到布局布线 |
| 5 | C | 两个工程各自导出报告并整理（第 6 节）。导出命令与卡 67 相同：`report_timing -input_db_file {<工程>/place_route/<顶层>_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run` |
| 6 | C | 填写 result.md，提交推送 |

两个工程互不依赖，可以先后跑，也可以同时跑。某一步报错，把报错原文写进 result.md 后停下，不要改 RTL 或约束。

## 6. 产物

放在 `artifacts/int/` 和 `artifacts/fma/` 下，两边各一套：
- `timing_summary.txt`：WNS/TNS/WHS/THS 和估算 Fmax；
- `setup_top200.txt`：最差 200 条 setup 路径，一行一条（起点、终点、裕量、逻辑级数、逻辑延迟/布线延迟）；
- `setup_top20_detail.txt`：最差 20 条逐级明细；`hold_top20.txt`；
- `segments.txt`（**本卡重点**）：按设计记录中的关键段分组，每组给出终点落在该组的最差 3 条路径（起点、终点、裕量、级数、逻辑/布线延迟）。分组按终点寄存器名匹配：
  - 工程 A：`rf_id_data_r`；`ex_addr_r`（u_id_agu）；`ib_candidates_r`（u_fetch）；`tage_f2_prediction_r` / `alternate_r` / `provider_r`；`f2_shadow_`（u_tage）；`operand_data_r` / `hit_r`（u_id_agu）。另加一组"其他"：不属于上述任何组的最差 3 条。
  - 工程 B：按 FMA 流水级分 8 组，终点分别以 `e1_` … `e7_` 开头，以及 FMA 结果寄存器（`result`）；另记 APM 内部或 CPI/CPO 级联上的最差路径（如果报告中出现）。
- `resource_summary.txt`：LUT、FF、DRM、APM、分布式 RAM、IO；`resource_hier.txt`：按模块层次的资源；
- 工程 A 另交 `ram_mapping.txt`：每个 IP 实例实际占几块 DRM（18K/36K）或几个 LUTRAM 单元；
- `high_fanout.txt`；`settings.txt`（实际 P&R 参数）。

## 6a. 第 2 轮（2026-11-28，只重跑工程 A）

- **原因**：第 1 轮工程 A 在 Compile 的 DFF-inference 崩溃（signal 11）。原因与卡 109 相同：多个 always 块写同一个寄存器数组。380c93e49 已把 TAGE、取指、寄存器堆中的这类写法改成每个 generate 迭代各自的寄存器，行为和拍数不变，四个单元测试已通过。
- **工程 B 不重跑**，第 1 轮结果有效。
- **做法**：取本卡最新提交。沿用 `EdRV32-FPGA/cpu2_probe_int` 工程和已生成的 9 个 IP，不用重新生成。移除旧源文件，重新执行导入脚本，从 Compile 开始，默认参数跑到布局布线，不生成比特流。
- **如果 Compile 仍然崩溃**：不要停在那里，按卡 109 的办法定位。工程 A 的 4 个模块（`edrv32_cpu2_rf`、`edrv32_cpu2_fetch`、`edrv32_cpu2_tage`、`edrv32_cpu2_id_agu`）各自作为顶层单独 Compile，记录每个的结果和最后一条日志。对崩溃的模块，在仓库外的副本里逐处删减，找到删掉就不崩的那一处，记录源码行号和原文。
- **产物**：同第 6 节的工程 A 部分，放在 `artifacts/int/`（覆盖第 1 轮的 `compile_failure.log` 无妨，第 1 轮的日志已在分支历史里）。

## 6b. 第 3 轮（2026-11-28，两个工程都重跑，目标 165 MHz）

- **原因**：第 2 轮整数 153.5 MHz、FMA 158.5 MHz，都过了 150 MHz，但余量薄。用户要求多留余量，两个探针的约束都改为 **6.061 ns（165 MHz）**。fd048ddf3（整数：取指 F2 两路并行查 owner、IB 写控制寄存、TAGE 比较提前）和 8344727fc（FMA：E7/E8 工作前移、舍入并行）已改，拍数不变，仿真全部通过。
- **IP**：没有新增或修改，两个工程沿用已生成的 IP（工程 B 本来就不需要 IP）。
- **做法**：取本卡最新提交。两个工程各自移除旧源文件和旧约束，重新执行导入脚本（脚本会加入新的 .fdc），从 Compile 开始，默认参数跑到布局布线，不生成比特流。确认导入后约束周期是 6.061 ns。
- **产物**：同第 6 节，分别放在 `artifacts/int/`、`artifacts/fma/`（覆盖第 2 轮文件无妨，历史在分支里）。`segments.txt` 的分组同第 6 节。result.md 汇总表加一行"第 3 轮"，裕量按 6.061 ns 约束填写。
- 某一步报错，把报错原文写进 result.md 后停下，不要改 RTL 或约束。

## 7. 通过判据

两个工程都完成布局布线，产物齐全。裕量正负都照实记录，本卡不设频率门槛。

## 8. result.md 模板

```markdown
# 卡 110 结果

| 工程 | 慢角 WNS / TNS | WHS | 估算 Fmax | LUT / FF / DRM / APM / 分布式RAM | P&R 用时 |
|---|---|---|---|---|---|
| A int | | | | | |
| B fma | | | | | |

## 关键段（每组最差一条）

| 工程 | 组 | 裕量 | 级数 | 逻辑 / 布线 ns | 起点 → 终点 |
|---|---|---|---|---|---|

## IP 端口核对

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
