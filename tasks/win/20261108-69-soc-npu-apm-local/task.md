# 卡 69：整片 SoC：NPU APM 本地化 + PnR 参数对照 + 完整时序和拥塞导出

## 1. 目标

在卡 68 第 2 轮的整片工程上，只换 NPU 的 RTL（T-NPU-APM-LOCAL），完成两件事：
1. 消除 clk_npu 的违例；
2. 按整片排查报告（`docs/reports/2026-11-08-timing-soc-audit.md`）导出完整的时序和拥塞数据，为继续提频做准备。

同一份 RTL 跑两次 PnR，只改一个参数 `Slack Weight`，比较效果。

**对照：卡 68 第 2 轮**（`origin/win/20261108-68-soc-v021-full`，`artifacts/R2/`）

| 时钟域 | 约束 (MHz) | 慢角 WNS (ns) | 违例端点 |
|---|---:|---:|---:|
| clk_sys | 125 | −0.088 | 10 |
| clk_npu | 180 | −0.205 | 47 |
| clk_mem | 125 | −0.025 | 5 |

- 第 176 轮收敛，PnR 2h25m；
- CLMA / CLMS 占用 87% / 86%。

**本次改动**（报告 `docs/reports/2026-11-08-npu-apm-local.md`）
- 只改 `rtl/npu/edrv32_npu_{window,mac_array,datapath}.v`，文件路径不变；
- 新增 2,740 个寄存位，APM / DRM 不变；
- 新增综合属性 `syn_srlstyle = "registers"`，目的是禁止把这些寄存器打包成 SRL。需要在本卡确认它是否生效。

CPU、软件、IP、约束全部不变。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交。从这里拉出 `win/20261108-69-soc-npu-apm-local`，记录 HEAD |
| 顶层 / 导入脚本 / 约束 | 与卡 68 相同 |
| 程序 | 与卡 68 相同：`tasks/win/20261108-68-soc-v021-full/src/showcase-v021.elf` 和 `src/board_npu.elf` |

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- **仿真虚拟机必须关机**。PnR 期间不要运行其他占内存的程序。

## 4. 需要的 IP

无新增。两个工程都由卡 68 的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-V021` 复制，沿用其中全部 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261108-69-soc-npu-apm-local origin/zc100116/b3`，记录 HEAD 和空闲物理内存。 |
| 1 | 用户（U） | 把 `EdRV32-B3F-V021` 复制两份：`EdRV32-B3F-V021-A` 和 `EdRV32-B3F-V021-B`。 |
| 2 | U 或 C | 在两个工程中分别执行：<br>- 清空源文件列表；<br>- 在工程目录下 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`；<br>- Compile、`synthesize -ads`、`dev_map`。<br>记录综合资源。在综合报告或网表中确认 `u_npu` 的 `activation_r`、`local_sum_r`、`weight_route_r` 没有被打包成 SRL，写明依据，例如单元类型或名称中是否还带 `_srl`。 |
| 3 | U | **A 工程**：PnR 设置与卡 68 完全相同（Slack Weight 40，其余见卡 68 第 5 节第 5 步），运行 `pnr`。 |
| 4 | U | **B 工程**：只把 Slack Weight 改为 **90**，其他与 A 相同，运行 `pnr`。<br>- A 跑完再开始 B；<br>- 如果空闲物理内存 ≥ 22 GB 且 CPU ≥ 12 核，也可以与 A 同时运行。<br>截图两个工程的设置页。 |
| 5 | C | 每小时记录两个工程的布线轮次、单轮耗时、未布通数、过用数和空闲内存。**止损**：<br>- 工具报 Route-0039 / Route-0008；<br>- 第 40 轮时未布通数仍大于 18000；<br>- 单轮耗时持续超过 600 s。<br>出现任何一条就停止该工程并回报。 |
| 6 | U + C | 两个工程布通后，各自按第 6 节导出。 |
| 7 | U + C | 选**三个时钟域慢角 WNS 之和较大**的一份生成比特流，上板做简短检查：<br>- `CLK_SYS_HZ`；<br>- `board_npu.elf` 1 次，要求 39/39，记录 C-YOLO 的 PERF0 和 fps；<br>- showcase 中 CoreMark 1 次；<br>- 视觉识别 2 分钟；<br>- 不跑 benchmark 和 NES。 |
| 8 | C | 整理 result.md，推送 `win/20261108-69-soc-npu-apm-local`。 |

## 6. 产物

A、B 两份分别放在 `artifacts/A/`、`artifacts/B/` 下。

1. **时序**（慢角和快角都要）
   - 每个时钟对的 WNS/TNS/WHS/THS 汇总，包括 setup、hold、recovery、removal。
   - **clk_sys、clk_npu、clk_mem 各自 slack ≤ +1.0 ns 的全部 setup 路径**，不受 200 条限制：
     - 用 `report_timing` 加大 `-max_path`，例如每组 5000，卡 57 用过同样的做法；
     - 如果 5000 条仍未覆盖到 +1.0 ns，写明实际覆盖到的 slack；
     - 每条一行：起点、终点、slack、逻辑级数、逻辑延迟、走线延迟、最大扇出。
   - clk_npu 的 recovery 路径中 slack ≤ +1.0 ns 的全部路径，格式同上。
   - 每个时钟域最差 50 条路径的逐级明细，包括器件坐标。
   - `native_reports/` 中放压缩的 `report_timing` 原文。
2. **拥塞**
   - 原始 CongestionPlot 网格文本：初始一轮、第 40 轮前后、最后仍有残余的一轮、最终一轮。注明轮次、网格划分和坐标方向。
   - 每份对应的 PNG。
   - 每轮的轮次、单轮耗时、未布通数、过用数，格式同卡 68 的 `routing_congestion.txt`。
3. **放置**（如果 PDS 能导出）
   - 按模块统计 CLMA / CLMS / DRM / APM 占用：CPU、NPU MAC、NPU weight_store、NPU 其余、RND、mem、DDR、ETH、VIN；
   - Device / Floorplan 视图中这些模块着色后的截图，重点看 NPU 第 5、7 通道附近、CPU 的 I$ tag 和 IB、两侧 CDC FIFO。

   导不出的项写"未取得"，并说明原因。
4. **资源**：资源汇总（已用 / 总数）、按模块层次的资源分布、`high_fanout.txt`。
5. **上板**（只对选中的一份）：`uart/*.log`，加上 CoreMark 和识别画面各 1 张照片。

## 7. 通过判据

- A、B 都布通；
- 两份的时序、拥塞和导出齐全，或者写明未取得的原因；
- 选中那份的上板检查无异常，board_npu 39/39；
- 所有数字都取自报告或日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 69 结果

| 项 | A（Slack Weight 40） | B（Slack Weight 90） |
|---|---|---|
| 代码 HEAD | | |
| 收敛轮次 / PnR 用时 | | |
| clk_sys WNS / TNS / 违例端点 | | |
| clk_npu WNS / TNS / 违例端点 | | |
| clk_mem WNS / TNS / 违例端点 | | |
| clk_npu recovery 最差 | | |
| LUT / FF / DRM / APM | | |
| CLMA / CLMS 占用 | | |
| SRL 打包检查 | | |

## 上板（选用 A 或 B：__）
| 项目 | 结果 | 关键数字 |
|---|---|---|
| CLK_SYS_HZ | | |
| board_npu | | PERF0、fps |
| CoreMark | | Iterations/Sec、CoreMark/MHz |
| 视觉识别 2 min | | fps、NPU ms |

## 未取得项和原因

## 问题与偏离
```
