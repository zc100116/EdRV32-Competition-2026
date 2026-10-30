# 任务卡 20261030-14-b3r-rnd：B3R（渲染器）单独综合布线，上板跑 RND 自检、S3 和 NES

## 1. 目标

RND 已完成时序和结构优化（T-RND1/T-RND2，报告 `docs/reports/2026-10-30-timing-rnd.md`、`2026-10-30-timing-rnd-copy-blur.md`）：Yosys 估算全 RND 最差路径 67 → 27 级，常数乘法从 APM 移到逻辑。卡 10 中 B3R 布线停在第 62 轮、3820 个网络未布通，RND 有 −18.5 ns 的负裕量。本卡用 B3R 工程**单独**跑一次综合和布局布线，再上板验证 RND 功能和 LVGL 帧率。

| 口径 | 工程 | 顶层 | 内容 |
|---|---|---|---|
| 渲染器 | **B3R** | `edrv32_fpga_board_render_top` | CPU、系统外设、DDR、RND、DISP 两层、HDMI。不含摄像头、PIX、GEO、NPU、ETH |

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261030-14-b3r-rnd`，在 `result.md` 中记录完整哈希。
- 约束 `fpga/constraints/edrv32_fpga_board_render_top.fdc`（11 个时钟定义）；导入脚本 `fpga/scripts/import_board_render_top.tcl`，预期 `edrv32: added 86 sources`。
- 上板程序：沿用卡 04 的 `tasks/win/20261029-04-b3r-software/src/`（`rnd_board.elf`、`rnd_expected.log`、`s3.elf`、`nes.elf`、`nes_nodisplay.elf`）。这些程序此后没有改动；RND 的寄存器和命令格式不变。

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676，JTAG，USB 串口，HDMI 显示器。
- 复用已有工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3R-r2\`：切到本卡的提交后直接重新综合（PDS 按路径引用仓库源文件，IP 不变，不用重新导入）。工程不在时按卡 07 第 3–4 节新建。
- **本工程单独运行**，不和其他工程同时综合或布线。

## 4. 需要的 IP

与卡 07 的 B3R 相同，不需要新生成（工程中已有）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261030-14-b3r-rnd origin/zc100116/b3`。阅读本卡和卡 04 第 5 节，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U），或 Codex 在 PDS 控制台 | 打开 B3R-r2 工程，依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录每一步的耗时和峰值内存；布线时记下每一轮的未布通网络数（同卡 13 的 `route_progress.tsv`）。任何一步报错就停下，回传报错原文和已有产物。 |
| 2 | Windows Codex（C） | 确认约束生效：clk_sys 10 ns、clk_mem 8 ns、clk_pix 13.468 ns、clk_serial、DDR IP 内部时钟。setup 违例照常继续，写明即可。 |
| 3 | 用户（U） | 下载 bitstream，接好 HDMI 和串口，告诉 Codex COM 口号。复位后确认串口出现启动信息。 |
| 4 | 用户（U） + Codex（C） | 按卡 04 第 5 节的步骤 2、2a、3、4 依次运行 RND 自检、S3、NES、NES 只计时版。加载一律用命令行：`py tools/board/uart_tool.py <ELF> --elf --baud 2000000 --port COMx --log build/board/<名>.log`，**不要用 GUI 工具**（卡 13 中 GUI 切换 2 Mbaud 后乱码）。命令行 2 Mbaud 也失败时，改用 `--baud 115200` 并在 `result.md` 记下现象。S3 的 benchmark 各场景帧率和平均帧率必须保存。 |
| 5 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261030-14-b3r-rnd results`，推送 `win/20261030-14-b3r-rnd`。中途停下时，已完成部分照常回传，写明停在哪一步和现象。 |

## 6. 产物

放在 `tasks/win/20261030-14-b3r-rnd/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | 布线后每个时钟 slow/fast 角的 WNS/TNS/WHS/THS、违例端点数、推算 Fmax |
| 2 | `setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | CLAUDE.md 10.5 |
| 3 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总；按层次展开到 cpu/sys/mem、RND（及其子模块）、DISP |
| 4 | `flow_summary.txt`、`route_progress.tsv` | 各阶段耗时、峰值内存；布线每轮未布通网络数 |
| 5 | `uart/rnd.log`、`rnd_compare.txt`、`uart/s3.log`、`uart/nes.log`、`uart/nes_nodisplay.log` | 串口日志；`expect.py` 比对输出 |
| 6 | `photos/*.jpg`、`checklist.md` | 同卡 04 第 6 节 |

## 7. 通过判据

- 实现：完成布线和 bitstream。
- 上板：RND 自检 `expect.py` PASS；S3 主界面、游戏、widgets 显示正常，benchmark 打印帧率；NES 正常运行。
- 时序：如实记录，不作为停止条件。
- 所有数字来自 PDS 报告和串口日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261030-14-b3r-rnd 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | |
| 工程路径 | |
| 各阶段耗时 / 峰值内存 | |
| 布线轮数、最后一轮未布通数 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序（布线后）
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

## 上板
| RND 自检 | S3 显示 | benchmark 平均帧率 | NES fps | 加载波特率 |
|---|---|---|---|---|

benchmark 各场景帧率：

## 完整报告在 Windows 本地的路径

## 备注
```
