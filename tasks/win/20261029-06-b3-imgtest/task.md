# 任务卡 20261029-06-b3-imgtest：无 CPU 图像通路验证工程（B3I），快速验证通路和时序

## 1. 目标

用一个只有图像通路、不带 CPU 的小工程，快速确认三件事：
- 能布通。之前所有工程失败的原因是 TMDS 从串化器的 OSHIFTIN 接了 GND，已修复（7947278）；
- 时序。DISP clk_pix 路径已加流水（5e9e6ee），PERF_MON 直方图路径已缩短（fd6b265）；
- 上板画面：摄像头 → VIN → PIX →（GEO）→ DDR → DISP → HDMI，用 KEY 切换功能。

不需要串口和软件。本卡通过后，协调者再把 B2 及 B3 的其他工程一起重新下发（用户 2026-10-29）。

| 工程 | 顶层 | 内容 |
|---|---|---|
| **B3I 图像通路验证** | `edrv32_fpga_board_imgtest_top` | DDR + mem_subsys、VIN（两路摄像头）、PIX、GEO、DISP（两层，L1 关闭）、HDMI。没有 CPU、UART、网口、NPU、RND。摄像头由硬件 SCCB 初始化；VIN/PIX/GEO/DISP 由硬件配置器配置，帧交接也由硬件完成 |

## 2. 输入

- 代码分支 `origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261029-06-b3-imgtest`，在 `result.md` 中记录完整哈希。
- 板级顶层 `fpga/rtl/edrv32_fpga_board_imgtest_top.v`。端口、引脚、KEY/LED、操作说明见 `fpga/rtl/README.md` 的 B3-9 一节。
- 约束 `fpga/constraints/edrv32_fpga_board_imgtest_top.fdc`，共 12 个时钟定义。
- 导入脚本 `fpga/scripts/import_board_imgtest_top.tcl`，结束时打印 `edrv32: added <N> sources`，预期 N = 67。

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676，JTAG。
- 新建工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3I\`。
- 使用已有的 `zc100116/b3` 检出，先 `git fetch` 并切到包含本卡的提交。
- 之前停掉的 B2/B3R/B3F/B3V 工程不用动，也不用继续跑。

## 4. 需要的 IP

全部从 B2 工程复制，不需要新生成：

`ip_pll_video`、`ip_ddr3`、`ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w`、`ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、`ip_ram_disp_scan`（例化两次，用同一个 IP）。

不需要 `ip_pll_sys`、`ip_pll_npu`、`ip_pll_eth`、ROM/SRAM、CPU、NPU、RND、ETH 的 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 在 b3 检出中 `git fetch origin`，`git switch -c win/20261029-06-b3-imgtest origin/zc100116/b3`。阅读本卡和 `fpga/rtl/README.md` B3-9 一节，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 新建 B3I 工程（PG2L200H-6 / FBB676），按第 4 节从 B2 工程复制 8 种 IP，告诉 Codex IP 目录。 |
| 2 | 用户（U），或 Codex 在 PDS 控制台 | `source <b3 检出>/fpga/scripts/import_board_imgtest_top.tcl`，把打印的 N 告诉 Codex（预期 67）。编译报错就停下，把报错原文交给 Codex。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录每一步的耗时。任何一步报错就停下，回传报错原文和第 6 节中已经取得的产物。 |
| 4 | Windows Codex（C） | **确认约束生效**：应有 clk_mem 8 ns、clk_pix 13.468 ns、clk_serial 2.694 ns、cam0/1 和 DDR IP 内部时钟；没有 clk_sys、clk_npu、clk_eth。`create_generated_clock` 不能报找不到对象。 |
| 5 | 用户（U） | 接两路摄像头和 HDMI 显示器，下载 bitstream，按 USER_BUTTON0 复位。 |
| 6 | 用户（U） + Codex（C） | **上板检查**，按 `fpga/rtl/README.md` B3-9 的 KEY/LED 表逐项记录：<br>1. LED0（DDR）、LED1/LED2（摄像头 0/1 初始化）依次点亮；<br>2. 屏幕出现摄像头 0 的画面，LED3 随帧闪烁；<br>3. KEY1 循环 5 档 PIX：旁路、亮度对比度、Gamma、高斯、Sobel，每档拍一张照片；<br>4. KEY2 循环 4 档 GEO：关、旋转 180°、中心缩小 0.5、中心放大 2，每档拍一张；<br>5. KEY3 切换摄像头 1，再切回 0；<br>6. 全程观察 LED4（任一引擎 ERROR）。点亮时记下是在哪一步亮的。<br>同时记录画面有无错位、撕裂、颜色异常、闪烁。异常时记下现象，继续下一项。 |
| 7 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-06-b3-imgtest results`，推送 `win/20261029-06-b3-imgtest`，告诉用户完成并给出分支名。 |

## 6. 产物

放在 `tasks/win/20261029-06-b3-imgtest/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | 布线后每个时钟 slow/fast 角的 WNS/TNS/WHS/THS、违例端点数、推算 Fmax |
| 2 | `setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | CLAUDE.md 10.5 |
| 3 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总；按层次到 u_mem、u_vin、u_pix、u_geo、u_disp、配置器、摄像头初始化、板级适配 |
| 4 | `flow_summary.txt` | 各阶段耗时、峰值内存、W/C/E 行数；布线失败时附失败网络摘要 |
| 5 | `photos/*.jpg`、`checklist.md` | 第 5 节步骤 6 逐项结果和照片 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 布线完成、生成 bitstream。
- 时序：如实记录各时钟的布线后 WNS/TNS/WHS/THS，不作为停止条件。
- 上板：摄像头画面正常，KEY1–3 各档有效，LED4 不亮。
- 所有数字来自 PDS 报告原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261029-06-b3-imgtest 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | <完整哈希> |
| PDS 版本 | |
| 工程路径 | |
| 导入源文件数 | |
| 各阶段耗时（综合/映射/布局布线） | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序（布线后）
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

## 上板
| 检查项 | 结果（正常/异常） | 现象 |
|---|---|---|
| LED0/1/2 | | |
| 摄像头 0 画面、LED3 | | |
| KEY1 五档 PIX | | |
| KEY2 四档 GEO | | |
| KEY3 切换摄像头 | | |
| LED4 | | |

## 完整报告在 Windows 本地的路径

## 备注
```
