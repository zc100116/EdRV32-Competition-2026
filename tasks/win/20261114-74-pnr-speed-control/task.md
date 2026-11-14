# 卡 74：布线速度对照——在当前机器上重跑卡 68 R2 的布局布线

## 1. 目标

卡 73 每轮布线耗时是卡 68 R2 的 5–6 倍，第 7 轮 605 s，卡 68 R2 是 111 s。但到第 7 轮，两者的未布通网络数只差 3.7%。本卡回答一个问题：**这是因为卡 73 的设计更难布，还是因为两个 PnR 同时运行造成机器负载过重？**

做法：在卡 73 运行的同时，用卡 68 R2 的原网表重跑一次 PnR，和卡 73 A 并行，代替卡 73 B。这样负载条件和卡 73 相同（同时有两个 PnR）。

| 结果 | 结论 |
|---|---|
| 对照每轮耗时也比卡 68 R2 原始记录慢好几倍 | 慢在机器负载，卡 73 改为单独运行 |
| 对照每轮耗时和原始记录相当，卡 73 A 仍然慢 | 慢在设计本身 |

另外，对照的网表、布局都和 R2 相同，各轮未布通数应该和 R2 的原始记录完全一致。这同时检验 PDS 布线结果是否与运行速度无关。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 无需新代码；结果分支从 `origin/zc100116/b3` 拉出 `win/20261114-74-pnr-speed-control` |
| 工程 | 卡 68 R2 的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-V021`。**不在原工程上运行**，复制为 `EdRV32-B3F-V021-CTRL` 后使用 |
| 网表 | 复制过来的工程中现有的 `device_map/edrv32_fpga_board_full_top_map.adf`，即 R2 的映射结果。不重新导入、不重新综合 |
| 原始记录 | `origin/win/20261108-68-soc-v021-full` 的 `tasks/win/20261108-68-soc-v021-full/artifacts/R2/routing_congestion.txt` |

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 卡 73 A 继续运行。卡 73 B 停掉：它与 A 的未布通数几乎相同（第 7 轮 74,015 对 74,336），继续跑没有新信息。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261114-74-pnr-speed-control origin/zc100116/b3`。 |
| 1 | 用户（U） | 停掉卡 73 B（`EdRV32-B3F-POST-B` 的 PnR）。卡 73 A 不动。 |
| 2 | U | 把 `EdRV32-B3F-V021` 整个目录复制为 `EdRV32-B3F-V021-CTRL`。 |
| 3 | C | 记录当时的可用物理内存，然后只运行布局布线，参数与卡 68 R2 相同：<br>`pds_shell.exe -action place_route -dump_router_congestion_plot true -logic_optimize_lut6d_combing_strategy 0 -pin_cost_increasing_speed 600 -plc_decongestion 2 -project_file G:/codex_project/EdRV32-FPGA/EdRV32-B3F-V021-CTRL/EdRV32-B3F-V021.pds -slack_weight 40 G:/codex_project/EdRV32-FPGA/EdRV32-B3F-V021-CTRL/device_map/edrv32_fpga_board_full_top_map.adf`<br>复制后的 `.pds` 文件名以实际为准。如果 PDS 要求先重新综合，就停下回报，不要重新综合。 |
| 4 | C | 跑到通用第 10 轮后停止对照，日志中第一条 `Unrouted general nets` 记为第 1 轮。对照运行期间，每 15 分钟同时记录：<br>- 对照和卡 73 A 的最新轮次与单轮耗时；<br>- 可用物理内存；<br>- 两个 `pds_shell` 进程的工作集和 CPU 占用。 |
| 5 | C | 对照停止后，卡 73 A 单独运行。再记录 A 接下来 3 轮的单轮耗时。 |
| 6 | C | 整理 result.md，推送 `win/20261114-74-pnr-speed-control`。卡 73 A 的后续进度照常写在卡 73 的结果分支。 |

## 6. 产物

放在 `tasks/win/20261114-74-pnr-speed-control/artifacts/`：
- `routing_ctrl.txt`：对照的布局用时、预布线用时和逐轮日志，原文；
- `samples.csv`：第 4、5 步的采样，列为时间、对照轮次/耗时、A 轮次/耗时、可用内存、两个进程的工作集和 CPU。

## 7. 通过判据

数字都取自日志或采样原文，取不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 74 结果

## 对照：卡 68 R2 网表在当前机器上重跑（与卡 73 A 并行）
| 通用第 N 轮 | R2 原始：未布通 / 秒 | 对照：未布通 / 秒 | 同时段卡 73 A：轮次 / 秒 |
|---|---|---|---|
| 1 | 147,564 / 16.0 | | |
| 3 | 117,783 / 18.8 | | |
| 5 | 94,214 / 44.2 | | |
| 7 | 71,679 / 111.5 | | |
| 8 | 63,103 / 152.9 | | |
| 10 | 50,187 / 196.2 | | |

- 对照的布局用时（R2 原始 264.92 s）：
- 对照未布通数是否与 R2 逐轮相同：
- 对照开始时的可用物理内存：

## 对照停止后卡 73 A 单独运行
| A 通用轮次 | 单轮秒数 | 可用内存 |
|---|---|---|

## 问题与偏离
```
