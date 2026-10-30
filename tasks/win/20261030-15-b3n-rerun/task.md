# 任务卡 20261030-15-b3n-rerun：B3N 用链头修复重新综合布线，上板复测 board_npu

## 1. 目标

卡 13 中 B3N 时序全部通过，但上板 `board_npu` 的首个卷积用例出错（`B-OP-01-c16_32 FAIL ... mismatches=160`）。用上板同一个 ELF 做的 SoC 级仿真，在 DDR 时延 3–80 周期、行为模型和厂商 APM 模型下都通过，问题只在硬件上出现（调试记录 `docs/debug/2026-10-30-npu-b3n-board-op01.md`）。

最可能的原因：MAC 级联链第 0 级"选 CPI 并把 CPI 接 0"，而 CPI 是 APM 之间的专用走线，接常数在硬件上可能不生效。已改为第 0 级用 `edrv32_mac_npu_int8_head`（MODEZ=0，不用 CPI），与厂商 IP 的做法一致。本卡重新综合布线并上板确认。新的 `board_npu` 遇到输出错误不停止，会打印每个出错用例的出错输出通道，便于对照 APM 布局。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交），拉出 `win/20261030-15-b3n-rerun`，在 `result.md` 记录完整哈希。RTL 为 `2f7cc24b` 及之后。
- 本卡 `src/board_npu.elf`：Linux 端从 `f3227e14` 构建（含新的诊断输出）。

## 3. 环境

- 复用卡 13 的工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3N\`。
- 新增了一个源文件：在 PDS 的 Designs 中**手动添加** `rtl/tech/edrv32_mac_npu_int8_head.v`（与其他源文件同样按仓库路径引用），共 88 个源文件。其余文件、IP、约束不变。
- 本工程单独运行，在 B3R（卡 14）跑完之后再开始。

## 4. 需要的 IP

与卡 13 相同，不需要改动。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261030-15-b3n-rerun origin/zc100116/b3`。把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 在 B3N 工程中添加 `edrv32_mac_npu_int8_head.v`，确认顶层仍为 `edrv32_fpga_board_npu_top`，Designs 中没有游离的顶层模块。 |
| 2 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录耗时；`pnr` 后执行 `generate_constraint -file {apm_placement.pcf} -device {APM}`。报错就停下，回传原文。 |
| 3 | 用户（U） | 下载 bitstream，接好串口，告诉 Codex COM 口号。 |
| 4 | 用户（U） + Codex（C） | 1. 用户按住 KEY1 并复位进入 BIOS；<br>2. Codex 执行 `py tools/board/uart_tool.py tasks/win/20261030-15-b3n-rerun/src/board_npu.elf --elf --baud 2000000 --port COMx --log build/board/b3n_rerun.log`（**用命令行，不用 GUI**；命令行 2 Mbaud 也失败时改 `--baud 115200`，并记下 2 Mbaud 的现象）；<br>3. 等程序打印 `NPU board: PASS n/n` 或 `FAIL k/n` 结束（整网和 20 帧会运行几十秒）；用户报告 LED4/LED5。 |
| 5 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交并推送 `win/20261030-15-b3n-rerun`，提交信息 `win: 20261030-15-b3n-rerun results`。 |

## 6. 产物

放在 `tasks/win/20261030-15-b3n-rerun/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/b3n_rerun.log` | 完整串口日志（每个用例一行，失败用例的出错通道行全部保留） |
| 2 | `timing_summary.txt`、`resource_summary.txt` | 同卡 13 |
| 3 | `flow_summary.txt` | 各阶段耗时、峰值内存 |
| 4 | `apm_placement.pcf` | APM 布局导出 |

## 7. 通过判据

- 上板 `NPU board: PASS 39/39`，日志中有整网 `ms/frame` 和 `fps`。
- 失败时如实回传全部用例行和出错通道行，不作为停止条件。
- 数字来自 PDS 报告和串口日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261030-15-b3n-rerun 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 源文件数 | |
| 各阶段耗时 | |
| 时序（clk_sys / clk_mem / clk_npu slow 角 WNS） | |
| APM 数 | |
| 加载波特率（2 Mbaud 是否成功） | |
| board_npu 结果（最后一行原文） | |
| 整网 ms/frame、fps | |
| LED | |

## 各用例结果（原文）

## 失败用例的出错通道（原文）

## 备注
```
