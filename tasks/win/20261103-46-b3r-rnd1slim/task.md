# 任务卡 20261103-46-b3r-rnd1slim：精简 RND v1 的 B3R 实现与上板（RND 自检 + showcase）

## 1. 目标

用户 2026-11-03 决定：最终演示用精简 RND v1（rnd-spec v0.5）。只保留 FILL、BORDER、GLYPH、BLIT（RGB565/ARGB8888/I8）、COPY；删除阴影、模糊、瓦片地图、非正常混合模式和 I4/I2/I1，并对高扇出网络做了同拍复制。LVGL 中 RND 不再支持的绘制改由 CPU 软件完成。本卡在 B3R（CPU + RND + DISP + ETH）上：
1. 实现并取得 RND 的原生资源、时序、布线耗时和高扇出表，与卡 43 VRN 中的原版 RND v1（82 APM / 60 DRM）和卡 24 B3R（RND v2：4h21m、639 轮）对比；
2. 上板验证 RND 自检和 showcase。

软件报告 `docs/reports/2026-11-03-rnd1-slim.md`。本地验证已通过：RND 单元、模块级 43 项、board_render 冒烟、四个顶层 lint。

## 2. 输入

- **代码**：`origin/zc100116/task-rnd1-slim`（包含本卡的提交）。拉出 `win/20261103-46-b3r-rnd1slim`，在 result.md 记录完整哈希。这是实验分支，上板通过后再合入 b3。
- **工程**：把卡 24 的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3R` 复制为 `EdRV32-B3R-RND1S`，原工程保留。在复制的工程里：
  - 清空原源文件列表后执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_render_top.tcl`，应输出 `added 94 sources`；
  - 从工程中移除 `ip_ram_rnd_window`（精简版不用）。
- **本卡 `src/`**：

| 文件 | 用途 |
|---|---|
| `ip_rom_boot.dat`、`ip_ram_sram.dat` | 与卡 43 相同的 BIOS/monitor 初始化（含波特率切换修复） |
| `eth_diag.bin` | 网口诊断（卡 43 同一文件） |
| `rnd_board.elf`、`rnd_board_expected.log` | 精简 RND 自检：两种目标格式 × 五条命令，共 10 行 CRC |
| `showcase.elf`、`showcase-test.elf` | 精简 RND 版 showcase；test 版已打包仓库测试 ROM（`games/`）。用户本地游戏包按卡 44 第 1 步方式用 `showcase.elf` 打包，ROM 和输出 ELF 不入库 |

## 3. 环境

PDS 2022.2-SP6.1；PG2L200H-6 FBB676；clk_mem 125 MHz（RND），其余同卡 24。接 HDMI、串口、网口。

**与卡 45 的关系**：卡 45（F 重跑）优先。只有在卡 45 的 F 已启动、且此时空闲物理内存仍 ≥ 12 GB 时，才并行跑本卡的 PnR；否则等 F 结束后再跑。机器上同时运行的 PnR 不超过 2 个（如有必要先停 VRN-D2）。

## 4. 需要的 IP

沿用卡 24 B3R 工程的 IP；用本卡 `src/` 的两个 dat 重新生成 `ip_rom_boot`、`ip_ram_sram` 的初始化内容。`ip_ram_rnd_window` 移除；`ip_ram_rnd_line`、`ip_ram_rnd_palette` 沿用（实例数以导入后的网表为准）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261103-46-b3r-rnd1slim origin/zc100116/task-rnd1-slim`；整理用户清单；按第 3 节检查内存和卡 45 的状态，决定何时启动。 |
| 1 | 用户（U） | 按第 2 节复制工程、导入、移除 window IP，更新 ROM/SRAM 初始化，执行 `synthesize -ads`。 |
| 2 | U | Device Map 的 `Number of Nets To Report` 设为 1000；PnR 沿用卡 24 B3R 的设置，另外勾选 Dump Router Congestion Plot，线程 5；依次 `dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。不插 ILA。 |
| 3 | C | 每小时记录 PnR 轮次、未布通、过用、该轮 MT route time；收集时序、资源（含 `u_rnd` 及子模块的层次资源）、高扇出四张表、拥塞图首尾两轮。 |
| 4 | U + C | **5.0 网口**：KEY1 复位进 BIOS，用调试工具网口加载 `eth_diag.bin` 一次，记录结果。 |
| 5 | U + C | **RND 自检**：串口 921600 加载 `rnd_board.elf`（`py tools/board/uart_tool.py tasks/win/20261103-46-b3r-rnd1slim/src/rnd_board.elf --elf --baud 921600 --port COMx --log <日志>`），串口 10 行 CRC 与 `rnd_board_expected.log` 逐行比较；HDMI 画面拍照。 |
| 6 | U + C | **showcase**：调试工具网口加载 `showcase-test.elf`（或用户游戏包）。按卡 44 第 5–8 步做：启动器静止 30 s 的 CPU 行、benchmark 全部场景 fps 与 split 原文、组件/图层示例进出、NES 60 s（模拟/显示 fps、CPU）和两级退出、系统状态页。同时看界面中阴影、圆角、线条、弧形控件（改由 CPU 软件绘制）显示是否正常，拍照。 |

## 6. 产物

放在 `tasks/win/20261103-46-b3r-rnd1slim/artifacts/`：

| 产物 | 内容 |
|---|---|
| `flow_summary.txt`、`pnr_progress.txt` | 各阶段耗时、CPU 时间、峰值内存、同时运行的 PnR；逐轮原文 |
| `resource_summary.txt`、`resource_hier.txt` | Map 资源；`u_rnd` 及子模块层次资源 |
| `high_fanout.txt` | 四张表（1000 条），单独摘出 `u_rnd` 下扇出 ≥ 300 的网络 |
| `timing_summary.txt`、`timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 每时钟 slow/fast WNS/TNS/WHS/THS；clk_mem 最差路径是否在 RND |
| `congestion/` | 首尾两轮拥塞图 txt |
| `uart/*.log` | eth_diag、rnd_board、showcase 串口原文 |
| `benchmark.txt`、`cpu.csv`、`photos/` | 同卡 44 |

## 7. 通过判据

- 实现完成、0 未布通；时序按卡 24 判据报告（RGMII 慢角 hold 为已知例外，其余违例照实报告）。
- RND 自检 10/10 CRC 与期望日志一致。
- showcase 各应用能进出、画面正常；benchmark、NES 数字照实记录。
- 对比表：本卡 RND 的 LUT/FF/APM/DRM 对卡 43 VRN 原版 v1；PnR 墙钟和轮数对卡 24。
- 数字取自报告和日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261103-46-b3r-rnd1slim 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 工程 | 路径 |
| 同时运行的 PnR / 空闲内存 | |

## 实现
| 阶段 | 墙钟 | CPU | 峰值内存 |
|---|---|---|---|
PnR 轮数、未布通、bitstream 是否生成；与卡 24 对比

## 资源
| 项 | 本卡 RND | 卡 43 VRN RND v1 | 整机 |
|---|---|---|---|

## 时序
| 时钟 | slow WNS | slow WHS | fast WNS | fast WHS |
|---|---|---|---|---|

## RND 高扇出（≥300）

## 上板
| 项 | 结果 |
|---|---|
| eth_diag 网口加载 | |
| RND 自检 10 行 CRC | |
| showcase：静止 CPU / benchmark 平均 / NES 模拟·显示 fps | |
| 软件绘制控件显示 | |

## 问题与偏离
```
