# 任务卡 20261102-33-b3f-converge：B3F 整版收敛（扇出优化 + ILA），布局布线并上板

> **恢复（2026-11-02）**：卡 34/36 已证明计数器 ILA 可用（冻结值 20/20 与串口相等）；卡 35/36 证明网口硬件正常，烧录问题出在 PC 工具，已由 T-ETH-LINKWAIT 修复（GUI 网口烧录 1/1 成功）。
>
> **卡 31 续跑的结论**（win `a4fd6d83` 快照）：不加优化和区域约束时，布局后 worst slack −1.028 ns（大部分在 RND draw），布线到第 116 轮（约 12 小时以上）仍有 13273 条未布通、29690 处资源过用，每轮只减少约 1%，按此趋势不会在可接受时间内布通。

## 1. 目标

用带全部扇出优化的最新 RTL 跑 B3F 全系统。一次完成：综合、插入 ILA、Device Map、布局布线、bitstream、上板冒烟。这是初赛整版的收敛构建。

和卡 31/32 相比的变化：
1. **扇出优化**：T-FANOUT-CPU（`docs/reports/2026-11-02-fanout-cpu.md`）和 T-FANOUT-SOC（`docs/reports/2026-11-02-fanout-soc.md`）。卡 31 综合估算中 clk_mem 最差的那条路径（VIN 配置错误计数，14 级，−0.507 ns）已拆成两拍。
2. **ILA 只观察 CSR 计数器**（`fpga/ip/ila_cpu.md`，400 位 × 1024）。卡 31 中没有负载的 `ila_cpu_r` 已删除。计数器有 CSR 读负载，综合后保留。
3. **卡 32 取消**：卡 32 的 RTL 与卡 31 相同。卡 31 昨晚续跑的布局布线就是卡 32 要的基线，不再另跑。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261102-33-b3f-converge`，在 result.md 中记录完整哈希。
- **工程**：在卡 31 的 B3F 工程基础上，重新执行 `import_board_full_top.tcl`（源文件数仍为 164，扇出优化没有新增 RTL 文件）。IP 不变，不重新生成。
- **ROM/SRAM 初始化和上板程序**：沿用 `tasks/win/20261101-24-b3-rnv/src/`（`ip_rom_boot.dat`、`ip_ram_sram.dat`、`rnd_board.elf`、`s3.elf`、`board_npu.elf`、`demo_vision.bin`、`eth_diag.bin`）。扇出优化不改变软件可见的行为，程序不用重新构建。如果卡 31 工程里的 ROM/SRAM IP 用的就是这两个 dat，不必重新生成。
- **变体 B 约束**（只在第 5 节第 2 步决定并行时用）：`tasks/win/20261102-33-b3f-converge/src/edrv32_fpga_board_full_top_left.fdc`。它和仓库里的 FDC 只差一处：RND、VIN、PIX、GEO、DISP、ETH 加一个左半区硬区域 `fp_left (0,121,0,219)`（设计记录 2026-10-31-b3f-floorplan 第 8.5 节 D2）。

## 3. 环境

PDS 2022.2-SP6.1；PG2L200H-6 FBB676。实现期间不要在这台电脑上运行仿真虚拟机。

## 4. 需要的 IP

沿用卡 31，另加调试核 `ila_cpu`（Inserter 插入，见 `fpga/ip/ila_cpu.md`）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | **立即停止卡 31 的布局布线**（进度快照已在 win `a4fd6d83` 回传，不用再收集），把机器让给本卡。 |
| 1 | C | `git fetch origin`，`git switch -c win/20261102-33-b3f-converge origin/zc100116/b3`；整理用户清单。 |
| 2 | C | 查看机器的物理内存和核数，以及卡 24 B3R 布局布线时的峰值内存。如果内存够同时跑两个布局布线（≥ 2 倍峰值，再留出余量），就**并行跑变体 A 和 B**：把 B3F 工程目录复制一份给 B，B 的约束换成 `src/edrv32_fpga_board_full_top_left.fdc`。不够就只跑 A。决定和依据写进 result.md。 |
| 2b | C | 查本机 PDS 布局布线的可选设置（GUI 中 Place & Route 的设置页，或 Tcl `pnr` 的帮助），列出与拥塞、布局密度、布线力度有关的选项及其默认值，写进 result.md。有"拥塞驱动布局"或"提高布线力度"一类选项就打开（A、B 两个变体相同），没有就保持默认。 |
| 3 | 用户（U）或 C | 在工程 Tcl 控制台中 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`，然后执行 `synthesize -ads`。在综合网表中确认 A 组探针都在：`u_cpu/u_core/u_csr` 下的 `cycle_r`、`instret_r`、`g_counter[2]`…`g_counter[9]` 的 `count_r`，各取低 40 位，记下实际实例名。找不到就停下，回传原文。 |
| 4 | U（C 协助） | 按 `fpga/ip/ila_cpu.md` 插入 ILA：clk_sys，A 组 400 位，触发探针 `minstret`、`mcycle`，深度 1024，触发位置 10%。保存 .fic 并截图。变体 B 用同一份 .fic。 |
| 5 | U 或 C | Device Map 设置中把 `Number of Nets To Report` 设为 1000，然后执行 `dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。布线线程数设为本机允许的最大值，记进 result.md。每小时记录一次 PnR 进度（阶段、布线轮数、未布通网络数、过用数）到 `artifacts/pnr_progress_<A/B>.txt`。**及时止损**：卡 31 在第 40 轮时未布通 37297、过用 107752。某个变体到第 40 轮时未布通仍 > 18000（不到卡 31 的一半），就停止该变体，回传进度和布局后的时序摘要，不要再跑十几个小时。两个变体都停了就告诉用户，等协调者的新方案。 |
| 6 | C | 布线完成后收集第 6 节的产物。两个变体都完成时，用时序更好的一个上板（先看 clk_mem/clk_sys/clk_npu 有没有违例，再看 WNS）；另一个只收集数据。 |
| 7 | U + C | 上板冒烟，用第 6 步选中的 bitstream，见下表。 |

### 第 7 步上板冒烟

| # | 项 | 方法 | 记录 |
|---|---|---|---|
| 1 | BIOS | 先 `git pull` 并重启调试工具（含 T-ETH-LINKWAIT）。同卡 24 第 5.0 节第 1 步：串口烧录 115200 一次；网口烧录用 CLI 一次、调试工具一次 | 菜单、两种烧录的结果和耗时；网口烧录日志中的"等待网卡 … 就绪 … 用时"行 |
| 2 | CoreMark + ILA | 进入 monitor，菜单 `1=CoreMark`、`5000`。按 `fpga/ip/ila_cpu.md` "运行时使用"第 1 条（触发 `minstret == 0x0055E44C09`，方法同卡 36），两轮各抓一次冻结值，和串口打印逐项对比；再按第 2 条，在第 1 轮运行中抓一次 1024 周期的窗口。同一个 monitor 程序指令数应相同；若串口的 `HPM round instructions` 不是 1441025033，就用串口实际值作为触发值重抓 | 串口全文；ILA 截图和导出数据（CSV） |
| 3 | 网口接收 | 同卡 24 第 5.0 节第 4 步（`eth_diag.bin`，5 次） | 成功次数 |
| 4 | 视频 S1 | 同卡 24 第 5V 节（`demo_vision.bin`） | 是否出图、fps |
| 5 | NPU | 同卡 24 第 5N 节（`board_npu.elf`，39 项） | 通过数 |
| 6 | RND | 同卡 24 第 5R 节（`rnd_board.elf` 自检，然后 `s3.elf`）。S3 启动后直接在调试工具中连接遥测，不手动等网卡 | 自检 CRC 结果、S3 各场景 fps、遥测 60 s 记录数和 lost |

任何一项失败都继续做后面的项，把失败现象和串口原文记下来。

## 6. 产物

放在 `tasks/win/20261102-33-b3f-converge/artifacts/`，变体 B 的放在 `artifacts/B/` 下，文件名相同：

| 产物 | 内容 |
|---|---|
| `card31_pnr_progress.txt` 或 `card31_pnr/` | 第 0 步 |
| `flow_summary.txt`、`pnr_progress_<A/B>.txt` | 各阶段耗时、CPU 时间、峰值内存、布线轮数和未布通网络数的变化 |
| `timing_summary.txt` | 每个时钟域的 WNS/TNS/WHS/THS（slow/fast） |
| `paths_<clock>.txt`、`paths_top20_detail.txt`、`levels_count.txt` | 从 PnR 数据库导出（命令同卡 32 第 2 步第 2 项）：每个时钟 200 条，最差 20 条的逐级明细，级数 ≥ 8 的条数 |
| `rgmii_rx_*.txt` | 卡 30 的 RGMII RX 定向报告 |
| `resource_summary.txt`、`resource_hier.txt`、`high_fanout.txt` | Device Map 资源、按层次资源、高扇出四张表（1000 条） |
| `placement_by_module.txt` | 同卡 32 第 2 步第 4 项（各一级模块的放置范围） |
| `congestion.txt` | PnR 报告中拥塞/布线资源利用率段落原文 |
| `ila/` | .fic、插入截图、上板抓到的截图和 CSV |
| `uart/*.log` | 上板各程序的串口全文 |
| `native_reports/` | CMR、SNR、DMR、PRR、RTR 原文 |

不提交：工程文件、IP 目录、数据库、网表、bitstream。

## 7. 通过判据

- 布线完成，0 未布通网络；clk_sys、clk_mem、clk_npu、clk_pix、clk_eth 的 setup/hold 不违例（RGMII RX 慢角 hold 按卡 30 的已知例外处理，单独列出）。
- ILA 插入成功，上板抓到的 A 组计数与串口打印一致。
- 第 7 步 6 项全部给出结果。
- 所有数字取自报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-33-b3f-converge 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 卡 31 续跑的布局布线 | 停止时的阶段/轮数/未布通数/已用时间，或跑完的结果 |
| 并行变体 | A / A+B，依据（内存、核数） |
| 各阶段耗时、布线轮数、线程数 | A： B： |
| 上板用的变体 | |

## 时序（A / B）
| 时钟 | WNS | TNS | WHS | THS | 最差路径级数 | 级数 ≥ 8 的条数 |
|---|---|---|---|---|---|---|

## 资源（含 ILA）
| 项 | LUT | FF | DRM | APM | 分布式 RAM |
|---|---|---|---|---|---|

## 各模块放置范围

## 拥塞

## ILA
探针实际实例名；两轮计数与串口对比；流水线窗口截图位置。

## 上板冒烟
| # | 项 | 结果 |
|---|---|---|

## 问题与偏离
```
