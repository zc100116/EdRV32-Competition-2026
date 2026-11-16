# 卡 89：卡 75 代码、clk_npu 降到 150 MHz 的备份比特流

## 1. 目标

用卡 75 的代码重新布局布线，只把 clk_npu 从 180 MHz 降到 150 MHz，得到 NPU 侧有时序余量的备份比特流，并上板确认。

**背景**：卡 75 布线后慢角有 565 个 setup 违例终点：

| 时钟 | 约束 | 慢角 WNS | 违例终点 | 主要路径 |
|---|---:|---:|---:|---|
| clk_sys | 125 MHz | −0.546 ns | 479 | CPU I-cache tag → 前端预译码（427 个） |
| clk_mem | 125 MHz | −0.218 ns | 52 | DISP 读取、DDR PHY → MEM xbar 读缓冲等 |
| clk_npu | 180 MHz | −0.123 ns | 34 | NPU 卷积 MAC 阵列内部 |

卡 75 上板正常：board_npu 39/39，实时识别 27 fps。

**预期**：
- 降频后 clk_npu 周期多出约 1.1 ns，NPU 的违例应当消失；
- clk_sys 和 clk_mem 与 NPU 频率无关，**预计仍有违例**。本卡如实记录，不作为失败；
- NPU 每帧由约 34.4 ms 变为约 41.2 ms，实时识别帧率预计降到约 24 fps。

本卡与 RTL 无关，可以和其他上板卡（卡 88 等）穿插进行：PnR 期间照常可以下载比特流、跑程序。PnR 期间请关闭仿真虚拟机（内存原因，见卡 68）。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261116-89-npu150-backup`，记录 HEAD。卡 75 的 HEAD 是 `42b3fa16`，此后 `rtl/` 和 `fpga/` 没有改动 |
| 工程 | 从卡 75 的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST` 复制一份，放在同一父目录下，命名为 `EdRV32-B3F-NPU150`。**原工程不要改**，它是当前演示用比特流的来源 |
| 约束 | 本卡 `src/edrv32_fpga_board_full_top_npu150.fdc`：与仓库中的 `fpga/constraints/edrv32_fpga_board_full_top.fdc` 只差第 11 行，clk_npu 由 27 × 20 / 3 改为 27 × 50 / 9 = 150 MHz |
| 程序 | 与卡 75 相同：卡 70 的 `tasks/win/20261108-70-soc-npu-post/src/board_npu.elf` 和 `src/showcase-post.elf`，不要重新编译 |
| 调试工具 | 与卡 75 相同：`git show cc5df889:tools/debug_tool` 导出到临时目录后使用 |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676。只运行这一个工程。

## 4. 需要的 IP

**只重新生成 `ip_pll_npu`**，按 `fpga/ip/ip_pll_npu.md` 的步骤，只有一处不同：CLKOUT0 填 **150.000 MHz**。生成后实际频率必须正好是 150.000 MHz，否则停下回报。

其余 IP 沿用复制过来的工程，不要重新生成。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261116-89-npu150-backup origin/zc100116/b3`，记录 HEAD。 |
| 1 | 用户（U） | 把 `EdRV32-B3F-POST` 整个目录复制为 `EdRV32-B3F-NPU150`。可以删掉副本中的 `place_route/`、`generate_bitstream/`、`report_timing/` 等运行产物目录，以节省空间。打开副本工程。 |
| 2 | U | 在副本中按第 4 节重新生成 `ip_pll_npu`（CLKOUT0 = 150 MHz）。记录 IP Compiler 显示的实际频率和分频参数。 |
| 3 | U 或 C | 在副本中执行：<br>- 清空源文件列表；<br>- 在工程目录下 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`；<br>- 在约束文件列表中移除 `fpga/constraints/edrv32_fpga_board_full_top.fdc`，改为加入本卡的 `src/edrv32_fpga_board_full_top_npu150.fdc`；<br>- 核对工程中只剩这一个 .fdc，并且其中 clk_npu 一行为 `-multiply_by {50} -divide_by {9}`。 |
| 4 | U | Compile、`synthesize -ads`、`dev_map`、PnR。PnR 参数与卡 75 完全相同（Slack Weight 40、Placement Decongestion 2、开启拥塞网格），格式同卡 75 的 `artifacts/settings.txt` 导出实际参数。**不设止损**，除非工具报 Route-0039 或 Route-0008。 |
| 5 | C | 每完成一个通用轮次就记录：轮次、单轮耗时、未布通数、过用数（同卡 75）。 |
| 6 | U + C | 布通后按第 6 节导出时序，生成比特流。有时序违例也照常上板。 |
| 7 | U | 下载比特流，按 KEY1 复位进入 BIOS，记录 `CLK_SYS_HZ`。 |
| 8 | U + C | **board_npu** 跑 1 次：要求 39/39，D 组 CRC 与卡 75 一致；记录 C-YOLO 的 PERF0。每帧时间和 fps **按 150 MHz 换算**。 |
| 9 | U + C | **showcase**（`showcase-post.elf`，加载方法同卡 75）：实时识别连续运行 **5 分钟**，保存全部 `vision fps=` 串口行；检测框的位置和类别正常。说明：界面上的 NPU 占用率按 180 MHz 换算，本比特流上会偏高，只记录、不作判断。 |
| 10 | C | 整理 result.md，推送 `win/20261116-89-npu150-backup`。 |

## 6. 产物

放在 `tasks/win/20261116-89-npu150-backup/artifacts/`：
- `settings.txt`：第 4 步的实际参数，以及 `ip_pll_npu` 的实际频率和分频；
- 资源汇总（LUT、FF、DRM、APM），以及 `u_npu`、`u_rnd`、`u_mem` 的 LUT / FF；
- `routing_rounds.csv`：每轮的轮次、耗时、未布通数、过用数；
- 时序：
  - 三个时钟域、快慢两角的 WNS/TNS/WHS/THS 汇总；
  - 每个域 slack ≤ +0.5 ns 的全部 setup 路径，一行一条：起点、终点、slack、逻辑级数、逻辑延迟、走线延迟（同卡 75 的 `timing_setup_le_0p5.csv`）；
  - 每个域最差 20 条 setup 路径的逐级明细；最差 20 条 hold 路径；
- `uart/*.log`：board_npu、showcase 全部串口。

## 7. 通过判据

- 布通并生成比特流；
- `ip_pll_npu` 实际频率 150.000 MHz；
- clk_npu 慢角 WNS ≥ 0（clk_sys、clk_mem 只记录）；
- board_npu 39/39，CRC 与卡 75 一致；
- 实时识别 5 分钟无异常；
- 所有数字都取自报告或日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 89 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| ip_pll_npu 实际频率 / 分频 | |
| 收敛轮次 / PnR 用时 | |
| CLK_SYS_HZ | |

## 资源（与卡 75 对比）
| 项 | 卡 75 | 卡 89 |
|---|---|---|
| LUT / FF / DRM / APM | 89,032 / 109,052 / 298 / 373 | |
| u_npu / u_rnd / u_mem 的 LUT/FF | | |

## 时序（慢角 WNS / TNS / 违例终点；快角 WHS）
| 时钟域 | 约束 MHz | 卡 75 | 卡 89 |
|---|---|---|---|
| clk_sys | 125 | −0.546 / −73.191 / 479 | |
| clk_npu | 卡 75 为 180，卡 89 为 150 | −0.123 / −0.970 / 34 | |
| clk_mem | 125 | −0.218 / −4.297 / 52 | |
| hold（含 RGMII RX） | | WHS −0.361 | |

## 布线（通用第 N 轮）
| 通用第 N 轮 | 卡 75 未布通 | 卡 89 未布通 | 卡 89 单轮耗时（秒） |
|---|---|---|---|
| 1 / 9 / 20 / 34 / 100 / 收敛 | 150,022 / 61,746 / 31,728 / 20,033 / 6,461 / 第 911 轮 | | |

## 上板
| 项目 | 结果 | 关键数字 |
|---|---|---|
| board_npu | | 通过数、C-YOLO PERF0、ms/帧（150 MHz）、fps |
| 实时识别 5 min | | fps、npu、wait、gui、e2e（最小 / 中位数 / 最大） |
| 死机、复位 | | |

## 问题与偏离
```
