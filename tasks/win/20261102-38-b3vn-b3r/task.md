# 任务卡 20261102-38-b3vn-b3r：B3VN 和 B3R 用最新 b3 重新实现并上板（初赛备用）

> **更新（2026-11-02）**：已包含 T-FANOUT-RND2（RND 剩余高扇出网络拆分，`docs/reports/2026-11-02-fanout-rnd2.md`，周期逐项不变）和 T-XBAR-SCHED。可以开始。

## 1. 目标

为初赛准备分场景的备用 bitstream：B3VN（图像 + NPU，无 RND）和 B3R（渲染，无图像/NPU），都用带扇出优化的最新 b3 重新实现并上板。与卡 33（B3F）、卡 37（B3F-VRN）、卡 39（B3F-RND1）同时进行，哪一版能用就用哪一版。

和以前相比的变化：
- 扇出优化（T-FANOUT-CPU、T-FANOUT-SOC）和 mem_xbar 调度路径缩短（T-XBAR-SCHED，`docs/reports/2026-11-02-xbar-sched.md`）。
- **B3VN 的 FDC 补上了卡 29/30 的 RGMII RX 修复**（ETH/系统 PLL 位置、RX 输入延迟），与 B3F 一致。卡 21 的 B3VN 没有这一段。
- 卡 21 的 B3VN 第 11 轮未布通 74177，当时放弃。本卡 B3VN 用与卡 33 变体 A 相同的 PnR 设置（拥塞选项、Placement Decongestion Mode 2）。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261102-38-b3vn-b3r`，在 result.md 中记录完整哈希。
- **ROM/SRAM 初始化**：`tasks/win/20261101-24-b3-rnv/src/ip_rom_boot.dat`、`ip_ram_sram.dat`。
- **程序**：
  - B3R：卡 24 `src/` 的 `rnd_board.elf`、`rnd_expected.log`、`s3.elf`、`nes.elf`、`eth_diag.bin`。
  - B3VN：`board_npu.elf`、`eth_diag.bin` 同卡 24；`demo_vnpu.bin` 由协调者稍后放进本卡 `src/`（CPU 画框清除优化 T-VN-OVERLAY 完成后），上板时 `git pull` 取用，布局布线不需要它。

### 工程

| 工程 | 做法 | 顶层 | 导入脚本 | 源文件数 |
|---|---|---|---|---|
| `G:\codex_project\EdRV32-FPGA\EdRV32-B3R-r5`（名字按本机已有的顺延） | **复制卡 24 的 B3R 工程目录**。用户先把卡 24 的 B3R bitstream 另存备份 | `edrv32_fpga_board_render_top` | `import_board_render_top.tcl` | 103 |
| `G:\codex_project\EdRV32-FPGA\EdRV32-B3VN-r3` | **新建工程**，IP 目录从卡 33 的 B3F 工程复制（B3F 包含 B3VN 需要的全部 IP，见导入脚本开头的 IP 清单），方法同卡 34 | `edrv32_fpga_board_vnpu_top` | `import_board_vnpu_top.tcl` | 145 |

新目录与旧目录放在同一父目录下，导入脚本的相对路径才能保持有效。

## 3. 环境

- PDS 2022.2-SP6.1；PG2L200H-6 FBB676。实现期间不要在这台电脑上运行仿真虚拟机。
- 同时跑几个布局布线由用户按本机内存决定（第 5 节第 1 步）。建议顺序：卡 39 B3F-RND1 > 本卡 B3VN > 本卡 B3R（B3R 已有卡 24 的可用 bitstream）。

## 4. 需要的 IP

B3R 沿用卡 24 工程中的 IP；B3VN 从卡 33 B3F 工程复制，不重新生成。不插入 ILA。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-38-b3vn-b3r origin/zc100116/b3`；整理用户清单。 |
| 1 | C | 查看本机空闲内存和已在跑的 PnR（卡 33 B、卡 37、卡 39）的内存，按 1.2 倍峰值估算还能同时开几个，写进 result.md，告诉用户建议的启动顺序。 |
| 2 | 用户（U） | 按第 2 节建两个工程，分别执行导入脚本，确认源文件数为 103 / 145。不一致就停下，回传脚本输出原文。 |
| 3 | U 或 C | 每个工程依次执行 `synthesize -ads`、`dev_map`（`Number of Nets To Report` = 1000）、`pnr`、`report_timing`、`gen_bit_stream`。B3VN 的 PnR 设置与卡 33 变体 A 相同；B3R 与卡 24 相同。线程数记进 result.md。 |
| 4 | C | PnR 期间把每个工程日志中的 `Unrouted general nets at iteration …` 行原样记到 `artifacts/<VN/R>/pnr_progress.txt`，每小时补一次。**B3VN 及时止损**：第 40 轮未布通 > 18000 就停止，回传进度和布局后的时序摘要。B3R 不设止损（卡 23 曾用 4h21m），但每小时记录。 |
| 5 | C | 布线完成的工程收集第 6 节的产物。 |
| 6 | U + C | 上板，见 5R、5VN。 |

### 5R：B3R

1. BIOS：同卡 24 第 5.0 节第 1 步（串口烧录一次；网口用 CLI 一次、调试工具一次，记录"等待网卡 … 就绪"行）。
2. 同卡 24 第 5R 节全部（RND 自检用 `rnd_expected.log`、S3 菜单 5 项各两轮、benchmark、RN-17、LAYERS、NES 松键、网口与 EDTM、虚拟输入）。S3 启动后直接在调试工具中连接遥测，不手动等网卡。
3. `eth_diag.bin` 5 次。

### 5VN：B3VN

1. BIOS：同上。
2. `board_npu.elf`：应为 `NPU board: PASS 39/39`，记录 C-YOLO 行原文。
3. `demo_vnpu.bin`：同卡 21 第 5VN 节全部 4 步（启动日志 `demo_vnpu (B3VN vision + NPU)`、`sw/apps/demo/README.md` 上板检查清单逐行、S1 中 `status` 至少 3 次记录 `Overlay CPU cycles`/推理次数/检测数、ETH 检查 5–8）。检测框要拍照：框是否落在目标上、移动时旧框是否清干净。
4. `eth_diag.bin` 5 次。

任何一项失败都继续做后面的项，把失败现象和串口原文记下来。

## 6. 产物

放在 `tasks/win/20261102-38-b3vn-b3r/artifacts/<VN 或 R>/`：

| 产物 | 内容 |
|---|---|
| `flow_summary.txt`、`pnr_progress.txt` | 各阶段耗时、CPU 时间、峰值内存；每轮未布通/过用原文 |
| `timing_summary.txt` | 每个时钟域的 WNS/TNS/WHS/THS（slow/fast） |
| `timing_setup_top200.txt`、`timing_setup_top20_detail.txt`、`timing_hold_top20.txt` | 同卡 24 |
| `resource_summary.txt`、`resource_hier.txt`、`high_fanout.txt` | Device Map 资源、按层次资源、高扇出四张表（1000 条） |
| `uart/*.log`、`uart/*.raw` | 各程序串口全文 |
| `edtm_*.csv`、`photos/*` | 同卡 24；B3VN 的检测框照片 |
| `native_reports/` | CMR、SNR、DMR、PRR、RTR 原文 |

不提交：工程文件、IP 目录、数据库、网表、bitstream。

## 7. 通过判据

- 布线完成，0 未布通网络；各时钟域 setup/hold 不违例（RGMII RX 慢角 hold 按卡 30 的已知例外处理，单独列出）。
- B3R：RND 自检 CRC 与 `rnd_expected.log` 一致；S3 菜单无 `S3 CPU mcause`；网口烧录成功。
- B3VN：`PASS 39/39`；S1 检测框落在目标上、旧框清除干净；网口烧录成功。
- 所有数字取自报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-38-b3vn-b3r 结果

| 项 | B3R | B3VN |
|---|---|---|
| 代码 commit | | |
| 源文件数 | | |
| PnR 设置、线程数 | | |
| 各阶段耗时、布线轮数 | | |
| 峰值内存 | | |

## 时序
| 工程 | 时钟 | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|

## 资源
| 工程 | LUT | FF | DRM | APM | 分布式 RAM |
|---|---|---|---|---|---|

## B3R 上板

## B3VN 上板
`Overlay CPU cycles`（3 次）、推理次数、检测数；照片位置。

## 问题与偏离
```
