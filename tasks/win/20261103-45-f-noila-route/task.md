# 任务卡 20261103-45-f-noila-route：完整 F 不插 ILA、调布线选项后单独重跑（不改 RTL）

## 1. 目标

卡 43 的 F（B3F-RND1-N）两次都以 `Route-0039`（单轮布线超过 2000 s）失败。当时同一台机器上同时跑 5–6 个布局布线，可用内存约 13 GB，而每个 PnR 峰值约 6–7 GB，F 的 PnR 墙钟 117 min 里 CPU 只用了 33 min。本卡排除这些环境因素，再加两项低成本的拥塞措施，单独重跑 F，看它能否布通：

1. **不插 CPU ILA**：ILA 的功能已在卡 34/36 的 B1 上验证；能布通的 VN 本来也没有插。
2. **布线器更偏向拥塞**：布局后 slack 为正（+380 ps），把时序在布线中的权重降下来。
3. **关闭 LUT6D 合并**：降低单个 slice 的引脚密度。

RTL、约束、IP 都与卡 43 相同。

## 2. 输入

- **代码**：卡 43 的输入 `13a17403ef38b27aedbfa9a816d5103aff1dce8d`（实验分支 `zc100116/b3f-rnd1-npu-opt`），不重新导入、不重新综合。本卡 task.md 在 `origin/zc100116/b3` 上；结果分支 `win/20261103-45-f-noila-route` 从 `origin/zc100116/b3` 拉出，只放 result.md 和 artifacts。
- **工程**：把卡 43 的 F 工程 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1-N` 复制为 `EdRV32-B3F-RND1-N-NOILA`。保留综合结果，**从工程中移除 ILA**：删除/取消关联 .fic，确认 Inserter 中没有调试核。然后从 Device Map 开始重跑。
- **程序**：上板用卡 43 的 `tasks/win/20261102-43-npu-rnd1-boards/src/`（在实验分支上）。

## 3. 环境

PDS 2022.2-SP6.1；PG2L200H-6 FBB676。

## 4. 需要的 IP

无变化（沿用卡 43 F 工程）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261103-45-f-noila-route origin/zc100116/b3`；整理用户清单。 |
| 1 | 用户（U） | **停止**以下布局布线：旧 F（`EdRV32-B3F`，卡 33 A）、VRN-D3、F-D1（以及尚未启动的 F-D4 副本，不启动）。停止前 C 把各自最后一轮的未布通/过用数记进 result.md。VRN-D2 继续运行。 |
| 2 | C | 记录停止后的空闲物理内存。F 启动后，机器上同时运行的 PnR 只能是 F 和 VRN-D2 两个。若空闲内存低于 16 GB，也停止 VRN-D2（先记最后一轮数字），让 F 独占。 |
| 3 | U | 在 NOILA 副本中按第 2 节移除 ILA，Device Map 的 `Number of Nets To Report` 设为 1000，执行 `dev_map`。 |
| 4 | U | PnR 设置（其余保持卡 43 F）：Placement Decongestion Mode **2**；Placement Logic Optimization 保持勾选，**LUT6D Packing Strategy 0**；**Slack Weight 40**（默认 90）；**Pin Cost Increasing Speed 600**（默认 300）；Multi-thread routing thread size **5**（工具允许的最大值）；Dump Router Congestion Plot 勾选。截图设置页后执行 `pnr`。 |
| 5 | C | 每小时记录一次轮次、未布通数、过用数和该轮 MT route time。第 14、40、80 轮的数字单独列出，与卡 43 对照（F 第 14 轮 102322 / 581383；VRN 第 40 轮 32181 / 103588）。到第 80 轮仍超过 15000 条，且最近 20 轮没有下降时，停止并回传。 |
| 6 | U + C | 布通后 `report_timing`、`gen_bit_stream`，按卡 43 第 6 节收集时序、资源、拥塞图。有 bitstream 时，按卡 43 的上板矩阵做 F 的 5.0、5N、5F、5R（不做 5C，因为没有 ILA）。 |

## 6. 产物

放在 `tasks/win/20261103-45-f-noila-route/artifacts/`：

| 产物 | 内容 |
|---|---|
| `stopped_runs.txt` | 第 1、2 步停止的各工程最后一轮原文和空闲内存 |
| `settings/*.png` | PnR 设置截图 |
| `flow_summary.txt`、`pnr_progress.txt` | 各阶段耗时、CPU 时间、峰值内存；逐轮原文 |
| `congestion/` | 首轮和最后一轮（或第 40、80 轮）拥塞图 txt |
| `resource_summary.txt` | Device Map 资源（不含 ILA） |
| 布通时 | `timing_summary.txt`、`timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt`、`native_reports/`，以及上板串口原文 |

## 7. 通过判据

- 布通，0 条未布通网络；时序按卡 43 判据报告（RGMII 慢角 hold 为已知例外）。
- 未布通时，第 14/40/80 轮数字与卡 43 的对照写清楚，并写明失败原文。
- 所有数字取自日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261103-45-f-noila-route 结果

| 项 | 内容 |
|---|---|
| 工程 | 路径 |
| 同时运行的 PnR | |
| 空闲内存（启动时） | |
| 设置 | Decongestion / LUT6D / Slack Weight / Pin Cost / 线程（附截图） |

## 停止的工程
| 工程 | 最后一轮 | 未布通 | 过用 |
|---|---|---|---|

## 布线进度
| 轮 | 未布通 | 过用 | 该轮 MT route time | 卡 43 F 对照 |
|---|---|---|---|---|

## 结果（布通 / 未布通、失败原文）

## 时序与资源（布通时）

## 上板（有 bitstream 时）

## 问题与偏离
```
