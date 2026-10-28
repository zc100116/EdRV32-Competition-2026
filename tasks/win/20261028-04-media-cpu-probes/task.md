# 任务卡 20261028-04-media-cpu-probes：A 媒体/网络模块 IP 生成和合并 PDS；B CPU 时序探针 P1–P3

两部分合在一张卡里执行（用户 2026-10-28 要求），使用不同的 PDS 工程，互不依赖。

## 1. 目标

- **A**：新建 MEDIA 工程，生成 6 个新 IP，对测量顶层 `edrv32_fpga_media_top`（VIN、DISP、PIX、GEO、ETH 各一实例）做综合和布局布线，取得按模块层次的资源和两个时钟域的路后时序（vision-plan V-W2）。
- **B**：对评估分支上的 3 个探针提交各做一次综合 + 布局布线，测出"去掉 C 扩展""前端与后端之间只有寄存器边界""再切断 RAM 命中、旁路晚到源、宽进位链并约束 core 区域"三步各能拿回多少时序裕量，并导出每版全部违例端点的分组统计（cpu-plan C-W6；设计记录 `docs/design/2026-10-28-cpu-timing-closure.md` 第 5 节第 1 步）。探针 P2、P3 功能不正确，只用于测量，不上板。

## 2. 输入

- 任务卡 commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。

### A 部分

- 测量顶层 `fpga/rtl/edrv32_fpga_media_top.v`：五个模块的输入由串行激励移位寄存器驱动，输出经寄存 XOR 树折叠到引脚，只做测量，不上板。
- 约束 `fpga/constraints/edrv32_fpga_media_top.fdc`：`clk_mem_i` 在 K21、`clk_ext_i` 在 D18，都按 125 MHz 约束，两者为异步时钟组；`stim_i` 设 false path；其余引脚 C22、C23、A20、C18、C19。clk_ext 同时驱动 DISP 像素时钟（实际 74.25 MHz，这里按更严的 125 MHz 测）、两路摄像头 pclk 和网口收发时钟。
- 导入脚本 `fpga/scripts/import_media_top.tcl`：展开 `rtl/filelists/{vin,disp,pix,geo,eth}.f`，加入测量顶层和约束，定义 `FPGA_MODE`。

### B 部分

- 探针提交（在 `origin/probe/cpu-timing` 分支上，按顺序）：
  | 版本 | 提交 | 内容 |
  |---|---|---|
  | P1 | `15d21f8` | RVC_EN 默认 0（C 扩展已决定去掉），软件 rv32im；功能正确 |
  | P2 | `2ec4170` | P1 + 前端所有后端输入寄存一拍，重定向 valid 按 predictor / F1 / IB 三组复制 |
  | P3 | `3615a7e` | P2 + I$/D$ 命中寄存、乘法和 load 结果只从寄存级旁路、CSR 计数器进位寄存、core 区域约束 |
- 约束：P1 只用 `fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`；P2、P3 **另加** `fpga/constraints/edrv32_fpga_cpu_sys_top_probe.fdc`（P2：6 个复制寄存器的 `syn_preserve` / `syn_keep`；P3 另有 `u_cpu_subsys.u_core` 的 `PAP_REGION {423 600 806 791}`）。这些属性名、对象写法和区域语法是 Linux 端按资料推测的，**需要在 PDS 中确认**（见第 5 节步骤 3）。
- 导入脚本：`fpga/scripts/import_cpu_sys_top.tcl`（与第四轮相同）。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- A 工程：**新建** `G:\codex_project\EdRV32-FPGA\EdRV32-MEDIA\EdRV32-MEDIA.pds`，器件同上（与 EdRV32-NPU 工程并列；导入脚本按 `../../EdRV32-Competition-2026` 找仓库）。
- B 工程：沿用 `G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`（7 个 CPU 子系统 IP 已在工程中）。三个探针版本依次在同一工程中重新导入、重新运行；每版跑完先收集产物，再切换下一版。
- 路径不同时写进 `result.md`，并相应调整 `source` 命令。

## 4. 需要的 IP

A：6 个，全部第一次生成，按 `fpga/ip/` 中的创建说明：

| IP | 创建说明 | 规格 | 实例 |
|---|---|---|---|
| `ip_ram_vin_wfifo` | `fpga/ip/ip_ram_vin_wfifo.md` | 512 × 288 简单双口 | 3 |
| `ip_ram_disp_scan` | `fpga/ip/ip_ram_disp_scan.md` | 512 × 256 简单双口，读写独立时钟 | 1 |
| `ip_ram_pix_line` | `fpga/ip/ip_ram_pix_line.md` | 1024 × 48 简单双口 | 4 |
| `ip_ram_geo_src` | `fpga/ip/ip_ram_geo_src.md` | 简单双口，**读写位宽不同**：写 256 × 128 / 读 2048 × 16 | 8 |
| `ip_ram_eth_buf` | `fpga/ip/ip_ram_eth_buf.md` | 1024 × 32 简单双口 | 2 |
| `ip_ram_eth_fifo` | `fpga/ip/ip_ram_eth_fifo.md` | 512 × 10 简单双口，读写独立时钟 | 2 |

- 建议先生成 `ip_ram_geo_src`：如果 PDS 的简单双口 RAM 不支持写 128 位 / 读 16 位这种不同位宽，**停下**，把 IP Compiler 中可选的位宽组合截图回传（协调者改存储组织），其余 IP 照常生成，但不要继续步骤 A4 之后的步骤。
- 每个 IP 生成后，Windows Codex 核对实际模块名和端口与对应包装模块（`rtl/tech/edrv32_ram_*.v`）`EDRV32_FPGA_MEMORY_MODE` 分支的连接一致；不一致时**不改生成文件，也不改包装模块**，把实际端口列表写进 `result.md` 后停下（协调者修改包装后重新下发）。

B：无新增。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-04-media-cpu-probes origin/main`（产物和 result.md 提交在这个分支）。另用 `git worktree add ../probe-src origin/probe/cpu-timing` 检出 B 部分的探针源码，B 部分按版本 `git -C ../probe-src checkout <提交>`，CPU 导入脚本中的仓库路径相应指向 `../probe-src`（只在本地改路径，不提交）。阅读本卡，把 A、B 两部分的用户步骤整理成一张清单交给用户。A、B 用不同的 PDS 工程，互不影响；建议先做 A 的 IP 生成，等 IP 时可以先跑 B。 |
| A2 | 用户（U） | 新建第 3 节的工程。 |
| A3 | 用户（U） | 按第 4 节生成 6 个 IP（先 `ip_ram_geo_src`）；告诉 Codex 工程路径和 IP 目录。 |
| A4 | Windows Codex（C） | 核对 6 个 IP 的模块名和端口（第 4 节）；记录每个 IP 实际占用的 DRM 块数（IP 生成报告中有）和选项截图（放 `artifacts/media/ip/`）。 |
| A5 | 用户（U） | 在 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_media_top.tcl`，确认打印 `edrv32: added 58 sources`。编译报错就停下，把报错原文交给 Codex。 |
| A6 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。**不要加 `PAP_CLOCK_DEDICATED_ROUTE FALSE`**；报 Place-0084 时停下回传。资源超出器件容量（map 或 pnr 报资源不足）时也停下，回传综合后的资源报告。 |
| A7 | Windows Codex（C） | 在 PnR 日志中确认 `clk_mem_i` 在 K21、`clk_ext_i` 在 D18，各经一个全局时钟缓冲；收集第 6 节产物。 |
| B2 | 用户（U），或 Codex 在 PDS 控制台 | **P1**：检出 `15d21f8`，在 PDS Tcl 控制台 `source` 导入脚本，确认打印的源文件数；依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。任何一步报错就停下，把报错原文交给 Codex。 |
| B3 | Windows Codex（C） | 收集 P1 的第 6 节产物。查 PDS 文档（或用一个最小工程试验）确认：保留属性的正确写法（`syn_preserve` / `syn_keep` 或 PDS 的等效属性，对象类别 `i:` / `n:`、层次分隔符）；`PAP_REGION`（或 PDS 的等效区域约束）的语法、坐标单位，以及该区域在 PG2L200H 上是否合法、是否覆盖 4 个 APM。需要改写 `edrv32_fpga_cpu_sys_top_probe.fdc` 时，**只在本地改**，把改后的全文作为产物回传，并在 result.md 中说明改了什么。 |
| B4 | 用户（U），或 Codex 在 PDS 控制台 | **P2**：检出 `2ec4170`，导入脚本之后再执行 `add_constraint <probe-src>/fpga/constraints/edrv32_fpga_cpu_sys_top_probe.fdc`（P2 版本中没有区域约束）；同步骤 B2 跑完四步。 |
| B5 | Windows Codex（C） | 收集 P2 产物；在 map 报告中确认 6 个复制的 valid 寄存器没有被合并（各自独立存在），合并了就写明。 |
| B6 | 用户（U），或 Codex 在 PDS 控制台 | **P3**：检出 `3615a7e`，同步骤 B4（含区域约束）跑完四步。区域约束导致布局失败时，去掉区域约束再跑一次，两次的结果都回传。 |
| B7 | Windows Codex（C） | 收集 P3 产物。 |
| C | Windows Codex（C） | 填写 `result.md`（A、B 两部分），提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-04-media-cpu-probes results`，推送 `win/20261028-04-media-cpu-probes`，告诉用户完成并给出分支名。A 或 B 中途停下时，已完成部分照常回传，并写明停在哪一步。 |

## 6. 产物

### A 部分

放在 `tasks/win/20261028-04-media-cpu-probes/artifacts/media/`：

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

### B 部分

每个版本一个子目录 `artifacts/cpu/p1/`、`artifacts/cpu/p2/`、`artifacts/cpu/p3/`（P3 去掉区域约束重跑时另加 `artifacts/cpu/p3_noregion/`），各含：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | slow/fast 角 WNS/TNS/WHS/THS、违例端点数、推算 Fmax（`1000 / (6.667 − WNS)` MHz） |
| 2 | `resource_summary.txt` | LUT、FF、DRM、APM、分布式 RAM；`u_core` 及其下一级子模块的 LUT/FF |
| 3 | `setup_top200.txt` | slow 角最差 200 条 setup 路径，一行一条：起点、终点、裕量、逻辑级数 |
| 4 | `setup_top20_detail.txt` | slow 角最差 20 条的逐级明细（每级单元、扇出、单元延迟和线延迟） |
| 5 | `endpoints_violating.tsv` | **全部** setup 违例端点（slow 角），每个端点一行：端点、该端点最差路径的起点、裕量、逻辑级数。PDS 能按端点导出就用端点导出（例如每个端点 1 条路径）；不能时导出尽可能多的路径（例如 `-max_path 10000`），并写明所用命令和是否覆盖全部违例端点 |
| 6 | `endpoint_groups.txt` | 对第 5 项按"起点寄存器名去掉位下标 → 终点寄存器名去掉位下标"分组，每组一行：组名、端点数、最差裕量、最差级数；按最差裕量排序 |
| 7 | `fdc_used.fdc`（仅 P2、P3） | 实际使用的探针约束全文 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- A：6 个 IP 生成且端口与包装一致；布局布线完成，两个时钟在指定引脚，未使用专用时钟布线放宽；第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。；时序是否达到 125 MHz、资源是否在预算内都不是本任务的通过条件。
- B：三个版本都完成布局布线（或在第 5 节规定的情况下停下并说明）；第 6 节产物齐全；所有数字来自 PDS 报告原文，找不到的写"未取得"。；时序是否达到 150 MHz 不是本任务的通过条件。

## 8. result.md 模板

```markdown
# 20261028-04-media-cpu-probes 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | <完整哈希> |
| 探针提交 | P1 15d21f8 / P2 2ec4170 / P3 3615a7e（完整哈希） |
| PDS 版本 | |
| A 工程路径 | |
| B 工程路径 | |
| 完成情况 | A：全部完成 / 在步骤 AN 停止（原因）；B：全部完成 / 在步骤 BN 停止（原因） |

## A 媒体/网络模块

### IP
| IP | 模块名 | 端口与包装一致 | DRM 块数 | 备注 |
|---|---|---|---|---|

### 时序
| 时钟 | WNS | TNS | WHS | THS | 违例端点数 | Fmax（推算） |
|---|---|---|---|---|---|---|

异步组是否生效（两时钟间路径未计入）：

每个时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

u_disp 在 clk_ext 域的最差裕量（按 8.000 ns 约束）：

### 资源
| | LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|
| 综合后 | | | | | | | |
| PnR 后 | | | | | | | |

按模块（u_vin、u_disp、u_pix、u_geo、u_eth；LUT / FF / DRM / APM）：

Linux 端 Yosys 参考（LUT6/FF，RAM 黑盒）：VIN 8422/5651、DISP 3179/1856、PIX 32535/5234、GEO 9043/3116、ETH 8279/4553。SoC 规格 9.3 预算：VIN + PIX + DISP 10K、GEO 8K、ETH 5K。

### 完整报告在 Windows 本地的路径

### 备注

## B CPU 时序探针

### 约束确认
- 保留属性的正确写法：
- 6 个复制寄存器是否保留：
- 区域约束语法和是否生效：
- 对探针 .fdc 的本地修改：

### 时序（slow 角）
| 版本 | WNS | TNS | 违例端点数 | Fmax（推算） | 最差路径（起点 → 终点，级数） |
|---|---|---|---|---|---|
| 第四轮（RVC=1） | −1.789 | −4967.383 | 7611 | 118.3 | e_jalr_expected_odd_r → ras_data_r，16 |
| P1 | | | | | |
| P2 | | | | | |
| P3 | | | | | |

每个版本 endpoint_groups 的前 10 组：

### 资源
| 版本 | LUT | FF | DRM | APM | u_core LUT |
|---|---|---|---|---|---|

### 完整报告在 Windows 本地的路径

### 备注
```
