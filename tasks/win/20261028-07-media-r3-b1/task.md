# 任务卡 20261028-07-media-r3-b1：A 媒体/网络合并 PDS 第三轮复测；B B1 上板补测

两部分合在一张卡里（用户 2026-10-28 要求），使用不同的 PDS 工程，互不依赖。

## 1. 目标

- **A**：在 MEDIA 工程中重新导入、综合和布局布线 `edrv32_fpga_media_top`，测出 ETH、GEO、VIN 时序修复（vision-plan V-R7，`docs/debug/2026-10-28-media-timing-r2.md`）后 clk_mem 125 MHz 的时序和各模块资源（V-W4）。
- **B**：用修正后的监控程序重新生成 B1 的 ROM/SRAM 初始化内容并重新生成 bitstream，上板取得 5000 次迭代的 O2 和 tuned 正式 CoreMark 成绩，以及新的按键测试结果（board-plan B1-7）。

## 2. 输入

- 任务卡 commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。

### A 部分

- 与上一轮（`tasks/win/20261028-05-media-r2/`，结果 `docs/reports/2026-10-28-timing-media-top-r2.md`：clk_mem −1.270 ns，542 个端点，全在 ETH、GEO、VIN）相比，只改了 `rtl/eth/edrv32_eth_rx.v`、`edrv32_eth_tx.v`、`rtl/media/geo/edrv32_geo.v`、`edrv32_geo_range.v`、`edrv32_geo_bilinear.v`、`rtl/media/vin/edrv32_vin_p1_arb.v`；文件列表、测量顶层 `fpga/rtl/edrv32_fpga_media_top.v`、约束 `fpga/constraints/edrv32_fpga_media_top.fdc`、导入脚本 `fpga/scripts/import_media_top.tcl` 和 IP 都不变。

### B 部分

- RTL、约束、导入脚本与上一次（`tasks/win/20261028-06-board-b1/`，结果 `docs/reports/2026-10-28-board-b1.md`）相同，只换软件。监控程序修正了两处（用户上板反馈）：
  1. 菜单选择和迭代次数各是一行，按 Enter 结束；串口工具在 `1` 后自动补的回车不再被当成"迭代次数选默认值"。输入 `1` 回车后会出现 `Iterations input` 提示并等待输入。
  2. 外设测试的按键部分：LED 依次点亮后，**10 秒内等待按下并松开 KEY1（C23）**，按下期间 4 个 LED 全亮，打印按下和松开的时刻（ms），按下并松开为 PASS，10 秒内没按为 `NOT PRESSED within wait`。
- 本卡 `src/`（Linux 端由 commit `207b05a` 构建，GCC 15.2.0，rv32im_zicsr_zifencei）：

  | 文件 | 内容 |
  |---|---|
  | `ip_rom_boot.dat` | bootloader，ROM 初始化文件（2048 行） |
  | `ip_ram_sram.dat` | 修正后的 -O2 监控程序，SRAM 初始化文件（8192 行） |
  | `monitor_tuned.wire` | tuned 选项（`-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4`）的监控程序，**已含 bootloader 下载协议的 4 字节小端长度头**，串口工具按原始字节发送整个文件即可 |
  | `monitor_o2.wire` | 同 `ip_ram_sram.dat` 的 -O2 监控程序，下载格式同上（备用） |

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676。
- A 工程：`G:\codex_project\EdRV32-FPGA\EdRV32-MEDIA\EdRV32-MEDIA.pds`。
- B 工程：`G:\codex_project\EdRV32-FPGA\EdRV32-B1\EdRV32-B1.pds`；串口用用户的串口工具，COM7、115200 8N1。

## 4. 需要的 IP

- A：无新增。
- B：`ip_rom_boot`、`ip_ram_sram` 按 `fpga/ip/ip_rom_boot.md`、`ip_ram_sram.md` **重新生成**，初始化文件分别选本卡 `src/ip_rom_boot.dat`、`src/ip_ram_sram.dat`（PDS 把初始化内容展开进生成的 RTL，换内容必须重新生成）；`ip_pll_sys` 和其余 5 个 IP 沿用。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-07-media-r3-b1 origin/main`；阅读本卡，把 A、B 两部分的用户步骤整理成一张清单交给用户。A、B 用不同工程，可以先跑 A 的综合，同时做 B 的 IP 生成。 |
| A1 | 用户（U），或 Codex 在 PDS 控制台 | MEDIA 工程 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_media_top.tcl`，确认打印 `edrv32: added 58 sources`；依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`（不生成 bitstream）。报错就停下，把原文交给 Codex。不要加 `PAP_CLOCK_DEDICATED_ROUTE FALSE`。 |
| A2 | Windows Codex（C） | 收集第 6 节 A 部分产物；`endpoints_violating.tsv` 的导出方法同上一轮（`-max_path 100000`、`-nworst 1`、slack < 0，去重后与 PDS 汇总核对）。 |
| B1 | 用户（U） | B1 工程中按第 4 节重新生成 `ip_rom_boot`、`ip_ram_sram`。 |
| B2 | 用户（U），或 Codex 在 PDS 控制台 | `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_b1_top.tcl`（确认 `edrv32: added 42 sources`），依次 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，下载 bitstream。 |
| B3 | 用户（U） | **启动信息和 O2 CoreMark**：串口工具打开 COM7 后按一下复位键（C22）。确认 logo 和启动信息里 `Build commit: 207b05a`；在菜单处输入 `1` 回车，看到 `Iterations input` 后输入 `5000` 回车，约 14 秒后出结果（`Score status` 不再是 short diagnostic）。 |
| B4 | 用户（U） | **tuned CoreMark**：按住 KEY1（C23）再按一下复位键（C22），看到 `UART download ready` 后松开 KEY1，用串口工具的发送文件功能按原始字节发送 `src/monitor_tuned.wire`；出现菜单后同 B3 输入 `1`、`5000`。启动信息中 `Boot mode` 应为 UART 下载，`Compiler flags` 含 `-O3`。 |
| B5 | 用户（U） | **外设测试和系统信息**：按一下复位键，菜单输入 `2` 回车：LED 依次点亮后出现 `GPIO button action` 提示，在 10 秒内按下 KEY1 停一下再松开（按下时 4 个 LED 全亮）；然后输入 `3` 回车。 |
| B6 | Windows Codex（C） | 从串口工具会话中取 B3–B5 的日志，收集第 6 节 B 部分产物。 |
| C | Windows Codex（C） | 填写 `result.md`（A、B 两部分），提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-07-media-r3-b1 results`，推送 `win/20261028-07-media-r3-b1`，告诉用户完成并给出分支名。中途停下时，已完成部分照常回传，并写明停在哪一步。 |

## 6. 产物

放在 `tasks/win/20261028-07-media-r3-b1/artifacts/`。

### A 部分（`artifacts/media/`）

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt` | clk_mem、clk_ext 的 slow/fast 角 WNS/TNS/WHS/THS、违例端点数；推算 Fmax（`1000 / (8.000 − WNS)` MHz） |
| 2 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总和按层次（`u_vin`、`u_disp`、`u_pix`、`u_geo`、`u_eth` 及其下一级，PnR 后） |
| 3 | `setup_top200.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | 每个时钟域最差 200 条 setup、最差 20 条逐级明细；fast 角最差 20 条 hold |
| 4 | `endpoints_violating.tsv`、`endpoint_groups.txt` | clk_mem slow 全部 setup 违例端点（没有时写"无"）；按终点模块、按"起点寄存器 → 终点寄存器"两种分组 |

### B 部分（`artifacts/b1/`）

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/b1_o2.log`、`b1_tuned.log`、`b1_periph.log`、`b1_sysinfo.log` | 串口原始日志 |
| 2 | `timing_summary.txt`、`resource_summary.txt` | clk_sys slow/fast WNS/TNS/WHS/THS；资源汇总（确认与上一次一致或写明差异） |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- A：布局布线完成；产物齐全；数字来自 PDS 报告原文，找不到的写"未取得"。时序是否达到 125 MHz 不是通过条件。
- B：O2 和 tuned 两次 5000 次迭代的 CoreMark CRC 正确且运行 ≥ 10 秒；按键测试有结果；数字来自串口日志原文。

## 8. result.md 模板

```markdown
# 20261028-07-media-r3-b1 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | <完整哈希> |
| PDS 版本 | |
| 完成情况 | A：全部完成 / 在步骤 AN 停止（原因）；B：全部完成 / 在步骤 BN 停止（原因） |

## A 媒体/网络模块

| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

上一轮：clk_mem slow −1.270 ns（107.9 MHz），542 个端点：ETH 196、GEO 174、VIN 172。

clk_mem 违例端点按模块；"起点 → 终点"分组前 15 组：

| 模块 | LUT | FF | 分布式 RAM | APM | DRM36K 当量 |
|---|---|---|---|---|---|

上一轮：u_vin 3532、u_pix 4935 / 132 APM、u_disp 1452、u_geo 3357 / 9 APM、u_eth 3841 LUT。

## B B1 上板补测

- 启动信息（Build commit、Boot mode）：
- clk_sys 时序和资源（与上一次比较）：

| 编译选项 | 迭代次数 | 计时周期 | 运行秒数 | CoreMark | CoreMark/MHz | CRC | IPC |
|---|---|---|---|---|---|---|---|
| O2 | 5000 | | | | | | |
| tuned | 5000 | | | | | | |

上一次 O2 10 次短诊断：3.600 CoreMark/MHz。仿真参考：O2 3.592456，tuned 4.290770。

- 按键测试（按下/松开时刻、结果、LED 观察）：
- 系统信息：

## 完整报告在 Windows 本地的路径

## 备注
```
