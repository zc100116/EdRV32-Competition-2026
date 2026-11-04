# 卡 55：正式版本时序报告（RGMII 接收 hold 豁免）

## 1. 目标

在正式版本的 F125 r2 工程上，**只重跑时序分析**，生成一份可放进技术文档的时序报告。分析时加一条只用于报告的约束：豁免 RGMII 接收输入端口的 hold 检查。不重新综合、布局布线，也不重新生成比特流。

## 2. 输入

- **代码**：`origin/main` 上包含本卡的提交。从这里拉出 `win/20261104-55-release-timing-report`，并记录 HEAD。
- **工程**：卡 48 的 F125 工程 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125/`。它最后一次布线是 r2，正式版本的比特流 `EdRV32-F-cpu125m-r2.sbit` 就出自这一次。
- **附加约束**：`src/rgmii_rx_hold_waiver.fdc`，只有一条：
  ```
  set_false_path -hold -from [get_ports {rgmii_rxd_i[*] rgmii_rx_ctl_i}]
  ```
  依据是设计记录 `docs/design/2026-11-01-rgmii-rx-clock.md`：
  - 按 PHY 手册的最小窗口（±1.0 ns）分析，慢角下 setup 和 hold 不可能同时满足，任何固定的采样相位都做不到；
  - 卡 30 上板实测：PHY 复位 10 次全部无错，网口视频没有丢帧。
- **对照数据**：卡 48 r2 的原始报告，在 `origin/win/20261103-48-vrn-f-rnd1slim` 的 `tasks/win/20261103-48-vrn-f-rnd1slim/f_cpu125_r2_results.md` 和 `artifacts/F-cpu125m-r2/`。

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676。

## 4. 需要的 IP

无。不重新生成任何 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 拉分支。**先核对工程状态**：工程现有的时序结果必须与 r2 一致，即慢角 setup WNS 为 clk_sys +0.087、clk_npu +0.048、clk_mem +0.179、clk_eth +1.864 ns，RGMII 输入 hold 为 −0.242 ns，共 5 个端点。不一致就停下来告诉用户，不要继续 |
| 1 | C | **把整个工程目录复制一份**，例如 `EdRV32-B3F-RND1S-CPU125-report/`。以后所有操作都在副本上做，原工程和它的比特流不能动 |
| 2 | C（必要时请用户在 GUI 中操作） | 在副本上，用布线后的数据库加上附加约束，只运行时序分析（Report Timing）：<br>- 先查 PDS 的方法，例如时序分析工具的 Tcl 控制台读入附加约束后重新报告，或把附加约束加进副本的约束文件后只运行 Report Timing；<br>- **任何一种做法都不能重新运行 Compile、Synthesize、Device Map、Place & Route、Generate Bitstream**；<br>- 记录用了哪种方法、执行的命令原文，以及布线数据库文件在操作前后的修改时间（应当不变）；<br>- 如果 PDS 只能在重跑布线后才能报告，就停下来告诉用户，不要重跑 |
| 3 | C | 收集第 6 节的产物，填写 result.md，推送分支 |

## 6. 产物

放在 `artifacts/`：

| 文件 | 内容 |
|---|---|
| `timing_summary.txt` | 每个时钟域在慢角和快角下的 WNS、TNS、WHS、THS，以及 recovery/removal 汇总。为加约束后的结果 |
| `compare.md` | 与 r2 原报告逐项对比的一张表。除 RGMII 接收 hold 那 5 个端点以外，**其余数字应当完全相同** |
| `waived_paths.txt` | 被豁免的 hold 路径：起点、终点、原裕量（来自 r2 原报告） |
| `setup_top20.txt`、`hold_top20.txt` | 加约束后最差的 20 条 setup 路径和 20 条 hold 路径，一行一条 |
| `timing_summary.png` | PDS 时序汇总页面的截图，要清楚完整，用于技术文档 |
| `method.md` | 采用的方法、命令原文，以及数据库文件修改时间的前后对比 |

## 7. 通过判据

- 没有重新运行任何实现阶段，数据库的修改时间前后一致；
- 加约束后，所有时钟域的 setup、hold、recovery、removal 裕量都 ≥ 0；
- 除被豁免的 5 条 RGMII 接收 hold 路径外，其余数字与 r2 原报告完全一致；
- RGMII 接收输入的 setup 检查仍然出现在报告中，并且满足。

## 8. result.md 模板

```
# 卡 55 结果

| 项 | 内容 |
|---|---|
| 分支 HEAD | |
| 工程副本路径 | |
| 第 0 步核对（与 r2 一致？） | |
| 采用的方法 | |
| 数据库修改时间是否不变 | |
| 加约束后最差 WNS / WHS（每个时钟域） | |
| 被豁免的路径数 | |
| 与 r2 的差异（应只有被豁免的路径） | |
| RGMII 接收 setup 最差裕量 | |
| 截图 | artifacts/timing_summary.png |

## 问题与偏离
```
