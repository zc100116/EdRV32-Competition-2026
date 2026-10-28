# 任务卡 20261028-04-media-synth：生成 6 个媒体/网络 IP，五个模块合并 PDS 综合 + 布局布线

## 1. 目标

新建 MEDIA 工程，生成 6 个新 IP，对测量顶层 `edrv32_fpga_media_top`（VIN、DISP、PIX、GEO、ETH 各一实例）做综合和布局布线，取得按模块层次的资源和两个时钟域的路后时序（vision-plan V-W2）。

## 2. 输入

- commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。分支：`git fetch origin`，`git switch -c win/20261028-04-media-synth origin/main`。
- 测量顶层 `fpga/rtl/edrv32_fpga_media_top.v`：五个模块的输入由串行激励移位寄存器驱动，输出经寄存 XOR 树折叠到引脚，只做测量，不上板。
- 约束 `fpga/constraints/edrv32_fpga_media_top.fdc`：`clk_mem_i` 在 K21、`clk_ext_i` 在 D18，都按 125 MHz 约束，两者为异步时钟组；`stim_i` 设 false path；其余引脚 C22、C23、A20、C18、C19。clk_ext 同时驱动 DISP 像素时钟（实际 74.25 MHz，这里按更严的 125 MHz 测）、两路摄像头 pclk 和网口收发时钟。
- 导入脚本 `fpga/scripts/import_media_top.tcl`：展开 `rtl/filelists/{vin,disp,pix,geo,eth}.f`，加入测量顶层和约束，定义 `FPGA_MODE`。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- 工程：**新建** `G:\codex_project\EdRV32-FPGA\EdRV32-MEDIA\EdRV32-MEDIA.pds`，器件同上（与 EdRV32-NPU 工程并列；导入脚本按 `../../EdRV32-Competition-2026` 找仓库）。
- 路径不同时写进 `result.md`，并相应调整 `source` 命令。

## 4. 需要的 IP

6 个，全部第一次生成，按 `fpga/ip/` 中的创建说明：

| IP | 创建说明 | 规格 | 实例 |
|---|---|---|---|
| `ip_ram_vin_wfifo` | `fpga/ip/ip_ram_vin_wfifo.md` | 512 × 288 简单双口 | 3 |
| `ip_ram_disp_scan` | `fpga/ip/ip_ram_disp_scan.md` | 512 × 256 简单双口，读写独立时钟 | 1 |
| `ip_ram_pix_line` | `fpga/ip/ip_ram_pix_line.md` | 1024 × 48 简单双口 | 4 |
| `ip_ram_geo_src` | `fpga/ip/ip_ram_geo_src.md` | 简单双口，**读写位宽不同**：写 256 × 128 / 读 2048 × 16 | 8 |
| `ip_ram_eth_buf` | `fpga/ip/ip_ram_eth_buf.md` | 1024 × 32 简单双口 | 2 |
| `ip_ram_eth_fifo` | `fpga/ip/ip_ram_eth_fifo.md` | 512 × 10 简单双口，读写独立时钟 | 2 |

- 建议先生成 `ip_ram_geo_src`：如果 PDS 的简单双口 RAM 不支持写 128 位 / 读 16 位这种不同位宽，**停下**，把 IP Compiler 中可选的位宽组合截图回传（协调者改存储组织），其余 IP 照常生成，但不要继续第 5 节步骤 4 之后的步骤。
- 每个 IP 生成后，Windows Codex 核对实际模块名和端口与对应包装模块（`rtl/tech/edrv32_ram_*.v`）`EDRV32_FPGA_MEMORY_MODE` 分支的连接一致；不一致时**不改生成文件，也不改包装模块**，把实际端口列表写进 `result.md` 后停下（协调者修改包装后重新下发）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 1 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-04-media-synth origin/main`。阅读本卡，把用户步骤整理成一张清单交给用户。 |
| 2 | 用户（U） | 新建第 3 节的工程。 |
| 3 | 用户（U） | 按第 4 节生成 6 个 IP（先 `ip_ram_geo_src`）；告诉 Codex 工程路径和 IP 目录。 |
| 4 | Windows Codex（C） | 核对 6 个 IP 的模块名和端口（第 4 节）；记录每个 IP 实际占用的 DRM 块数（IP 生成报告中有）和选项截图（放 `artifacts/ip/`）。 |
| 5 | 用户（U） | 在 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_media_top.tcl`，确认打印 `edrv32: added 58 sources`。编译报错就停下，把报错原文交给 Codex。 |
| 6 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。**不要加 `PAP_CLOCK_DEDICATED_ROUTE FALSE`**；报 Place-0084 时停下回传。资源超出器件容量（map 或 pnr 报资源不足）时也停下，回传综合后的资源报告。 |
| 7 | Windows Codex（C） | 在 PnR 日志中确认 `clk_mem_i` 在 K21、`clk_ext_i` 在 D18，各经一个全局时钟缓冲；收集第 6 节产物。 |
| 8 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-04-media-synth results`，推送 `win/20261028-04-media-synth`，告诉用户完成并给出分支名。 |

## 6. 产物

放在 `tasks/win/20261028-04-media-synth/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `ip/` | 6 个 IP 的选项截图（PNG）、实际端口列表（文本） |
| 2 | `timing_summary.txt` | clk_mem、clk_ext 各自的 WNS/TNS/WHS/THS、违例端点数；推算 Fmax（`1000 / (8.000 − WNS)` MHz）；确认两时钟间路径未被计入（异步组生效） |
| 3 | `resource_summary.txt` | 资源汇总：LUT、FF、DRM（18K/36K 分别计数）、APM、分布式 RAM、IO、PLL；器件总量和占用率；综合后和 PnR 后各一份 |
| 4 | `resource_hier.txt` | 按层次的资源分布：`u_vin`、`u_disp`、`u_pix`、`u_geo`、`u_eth` 及其下一级每个子模块实例，以及顶层激励/观测寄存器（PnR 后；PnR 后无法按层次导出时用综合后的） |
| 5 | `setup_top200.txt` | 每个时钟域最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 6 | `setup_top20_detail.txt` | 每个时钟域最差 20 条 setup 路径的逐级明细（每级单元、扇出、单元延迟和线延迟） |
| 7 | `hold_top20.txt`、`high_fanout.txt` | 最差 20 条 hold 路径；扇出最大的 100 个网络 |
| 8 | `setup_group_detail.txt` | 分组明细（方法与 20261028-01 A5 相同：按起点/终点寄存器名去掉位下标分组，每组最差一条逐级明细，最多 30 组，两个时钟域分别做），段首写组名、组内路径数、最差裕量、所用命令。另外，`u_disp` 内终点在 clk_ext 域的路径单独列出最差 20 条（判断 74.25 MHz 下是否满足） |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 6 个 IP 生成且端口与包装一致；布局布线完成，两个时钟在指定引脚，未使用专用时钟布线放宽。
- 第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。
- 时序是否达到 125 MHz、资源是否在预算内都不是本任务的通过条件。

## 8. result.md 模板

```markdown
# 20261028-04-media-synth 结果

| 项 | 内容 |
|---|---|
| commit | <完整哈希> |
| PDS 版本 | |
| 器件 | PG2L200H-6 FBB676 |
| 工程路径 | |
| clk_mem_i / clk_ext_i 位置和时钟缓冲 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## IP
| IP | 模块名 | 端口与包装一致 | DRM 块数 | 备注 |
|---|---|---|---|---|

## 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

异步组是否生效（两时钟间路径未计入）：

每个时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

u_disp 在 clk_ext 域的最差裕量（按 8.000 ns 约束）：

## 资源
| | LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|
| 综合后 | | | | | | | |
| PnR 后 | | | | | | | |

按模块（u_vin、u_disp、u_pix、u_geo、u_eth；LUT / FF / DRM / APM）：

Linux 端 Yosys 参考（LUT6/FF，RAM 黑盒）：VIN 8422/5651、DISP 3179/1856、PIX 32535/5234、GEO 9043/3116、ETH 8279/4553。SoC 规格 9.3 预算：VIN + PIX + DISP 10K、GEO 8K、ETH 5K。

## 完整报告在 Windows 本地的路径

## 备注
```
