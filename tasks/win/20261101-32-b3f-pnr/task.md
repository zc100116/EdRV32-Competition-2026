# 任务卡 20261101-32-b3f-pnr：B3F 全系统布局布线基线（不加新的区域约束）

> **已取消（2026-11-02）**：RTL 与卡 31 相同，卡 31 续跑的布局布线即为这张卡要的基线。改由卡 33（`tasks/win/20261102-33-b3f-converge`）一次完成扇出优化版的整版收敛。

## 1. 目标

在卡 31 的 B3F 工程上，用当前 RTL 跑完布局布线和 bitstream。取得以下数据，作为全芯片区域规划（`docs/design/2026-10-31-b3f-floorplan.md` 第 8 节）的依据：
- 布线是否成功、耗时；
- 拥塞情况；
- 全系统布线后的真实时序和路径级数；
- 各模块被工具实际放在了芯片的哪里。

本卡**不加新的区域约束**，只保留 FDC 中原有的 `fp_rgmii`、`fp_ddrphy` 和 PLL 位置约束。ILA 本卡不插入，等观测寄存器的保留方式确定后再做。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261101-32-b3f-pnr`，在 result.md 中记录完整哈希。
- **工程**：卡 31 的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F`（IP 不变，不重新生成）。如果导入后源文件有变化，重新执行 `import_board_full_top.tcl`。

## 3. 环境

- PDS 2022.2-SP6.1；PG2L200H-6 FBB676。
- 可以与其他卡并行；在 result.md 中记录与其他 PDS 流程重叠的时间段。
- 实现期间不要在这台电脑上运行仿真虚拟机。

## 4. 需要的 IP

无（沿用卡 31）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261101-32-b3f-pnr origin/zc100116/b3`；整理用户清单。 |
| 1 | 用户（U）或 C | 在 Device Map 设置中把 `Number of Nets To Report`（`-fanout_number`）设为 1000，然后依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。布线线程数记进 result.md。任何阶段报错就停下，回传原文。**布线失败**（有未布通的网络）也照常收集第 6 节中能取得的部分。 |
| 2 | C | 收集第 6 节的产物。 |
| 3 | C | 只查文档，不改工程。卡 31 中 `ila_cpu_r`（没有负载、带 `syn_preserve`）被综合删掉了。在本机 PDS 的综合用户指南和约束指南中，找出让**没有负载的寄存器及其输入逻辑**在综合和 Device Map 后保留下来、供调试核选为探针的属性或设置，例如 `syn_keep`、`syn_noprune`、`PAP_...` 或综合选项。逐条写明：属性名、作用对象（寄存器、线网还是实例）、写法（RTL 注释还是 FDC）、文件名和页码。也查 Inserter 指南里，没有负载的信号该怎样选为探针。结果写入 `artifacts/ila_keep.txt`。 |

### 第 2 步要收集的内容

1. **流程**：
   - 各阶段耗时、CPU 时间、峰值内存；
   - PnR 的布线轮数，以及每轮未布通网络数的变化；
   - Detailed routing 耗时。
2. **时序**：
   - 每个时钟域的 WNS/TNS/WHS/THS；
   - 从 PnR 数据库导出全局最差路径：`report_timing -input_db_file {<工程>/place_route/<顶层>_pnr.adf} -delay_type min_max -max_path 200 -nworst 1 -input_pins TRUE -force_to_run`。每个时钟各取 200 条，一行一条，列出起点、终点、裕量、逻辑级数；
   - 每个时钟最差 20 条的逐级明细（含每段走线的扇出和延迟）；
   - 每个时钟逻辑级数 ≥ 8 的路径条数；
   - RGMII RX 用卡 30 的定向命令另导一份。
3. **资源和扇出**：
   - Device Map 的资源汇总和按层次资源；
   - 高扇出四张表全文（1000 条）；
   - `controlsets`。
4. **放置位置**（用于定区域）：
   - 从 PRR 或 PDS 的放置结果中，统计每个一级模块（`u_cpu`、`u_sys`、`u_mem`、`u_ddr3`、`u_vin`、`u_pix`、`u_geo`、`u_rnd`、`u_disp`、`u_npu`、`u_eth`、`u_rgmii`）的 CLM、DRM、APM 实例所在坐标的范围（x、y 的最小值、最大值、中位数）和数量；
   - 如果 PDS 能导出 PCE Statistics 或拥塞图（Device/Physical View 截图），也一并回传。
5. **拥塞**：PnR 报告中关于拥塞、全局或局部布线资源利用率的段落原文。

## 6. 产物

放在 `tasks/win/20261101-32-b3f-pnr/artifacts/`：

| 产物 | 内容 |
|---|---|
| `flow_summary.txt` | 第 2 步第 1 项 |
| `timing_summary.txt`、`paths_<clock>.txt`、`paths_top20_detail.txt`、`levels_count.txt`、`rgmii_rx_*.txt` | 第 2 步第 2 项 |
| `resource_summary.txt`、`resource_hier.txt`、`high_fanout.txt`、`controlsets.txt` | 第 2 步第 3 项 |
| `placement_by_module.txt`，以及截图（如有） | 第 2 步第 4 项 |
| `congestion.txt` | 第 2 步第 5 项 |
| `ila_keep.txt` | 第 3 步 |
| `native_reports/` | CMR、SNR、DMR、PRR、RTR 原文 |

不提交：工程文件、IP 目录、数据库、网表、bitstream。

## 7. 通过判据

只采集数据，不设门槛。所有数字取自报告原文，找不到的写"未取得"。bitstream 生成后本卡不要求上板。

## 8. result.md 模板

```markdown
# 20261101-32-b3f-pnr 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 布线结果 | 成功 / 未布通网络数 |
| 各阶段耗时、布线轮数、线程数 | |

## 时序
| 时钟 | WNS | TNS | WHS | THS | 最差路径级数 | 级数 ≥ 8 的路径条数 |
|---|---|---|---|---|---|---|

## 各模块放置范围
| 模块 | CLM 数 | x 范围 / 中位 | y 范围 / 中位 | DRM 数与范围 | APM 数与范围 |
|---|---|---|---|---|---|

## 拥塞

## 问题与偏离
```
