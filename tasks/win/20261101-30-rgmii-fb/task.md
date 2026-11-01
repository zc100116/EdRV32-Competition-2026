# 任务卡 20261101-30-rgmii-fb：厂商网口例程基线 + ETH PLL 外部反馈试验（只做 B3V）

## 1. 目标

卡 29 的时序报告表明，RGMII 接收时钟从 RXC 引脚经 PLL（内部反馈）和全局缓冲到 IDDR 要 2.5–5.0 ns，随布局和工艺角漂移，没有一组固定的相位/IODELAY 能保证采样正确（`docs/design/2026-11-01-rgmii-rx-clock.md`）。本卡分两部分：

- **A. 厂商 UDP 例程基线**：在我们这块板上跑厂商 2_11_ethernet_test，确认板子、PHY、网线和 PC 本身没有问题。
- **B. B3V 新时钟结构**：`ip_pll_eth` 改为外部反馈（反馈取自全局缓冲输出），0°，RX 去掉 IODELAY。看 PDS 时序是否收敛，并上板测试稳定性。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交），拉出 `win/20261101-30-rgmii-fb`，记录完整哈希。
- **B 的改动**：`fpga/rtl/edrv32_fpga_rgmii.v`，`fpga/constraints/edrv32_fpga_board_vision_top.fdc`（`clk_eth` 相移改为 0；RX 输入延迟和 PLL 位置约束保留）。
- **IP 说明**：`fpga/ip/ip_pll_eth.md`（已更新）。
- **程序**：`tasks/win/20261031-23-b3-converged/src/eth_diag.bin`，`tasks/win/20261101-24-b3-rnv/src/demo_vision.bin`。
- **厂商例程**：资料包 `docs/board/pago_200/2_Demo/2_11_ethernet_test/`（卡 28 的路径），以及教程 2 第 11 章（PDF 158 页起）。

## 3. 环境

- PDS 2022.2-SP6.1；PG2L200H-6 FBB676。
- B3V 工程：`G:\codex_project\EdRV32-FPGA\EdRV32-B3V`（沿用卡 29 的工程，ROM/SRAM 已是卡 24 的版本）。
- 实现期间不要运行仿真虚拟机。
- 上板：JTAG、USB 串口、OV5640；PC 有线网卡 `192.168.1.2/24`，放行 UDP 6000。

## 4. 需要的 IP

| 部分 | 动作 | IP |
|---|---|---|
| A | 厂商例程工程内按 PG2L200H 重新生成（参数不改） | 例程自带 `ref_clock` |
| B | 按 `fpga/ip/ip_pll_eth.md` **重新生成** | `ip_pll_eth`：External Feedback，Feedback from CLKOUT0，CLKOUT0 125 MHz、0° |

B3V 的其余 IP 沿用卡 29。

## 5. 操作步骤

### A. 厂商 UDP 例程基线

| 步骤 | 执行者 | 内容 |
|---|---|---|
| A0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261101-30-rgmii-fb origin/zc100116/b3`；整理用户清单。从例程源码（`ethernet_test.v` 等）和教程 2 第 11 章，查出例程板端的 IP/MAC、UDP 端口、PC 端需要的设置和测试方法，写进清单。 |
| A1 | 用户（U） | 把例程工程目录**复制**到仓库外的本地目录（不改资料包原件）。例程标的器件是 PG2L100H；如果不是 PG2L200H-6 FBB676，就把器件改成 PG2L200H-6 FBB676，重新生成 `ref_clock`（参数保持不变），然后综合、布局布线、生成 bitstream。RTL 和 FDC 不改。 |
| A2 | U + C | 下载例程 bitstream，按 A0 查到的方法测试：`arp -a`、`ping`（如果例程支持），以及教程中的 UDP 收发测试，连续约 60 秒。记录 PC 发出和收到的包数、有没有丢包或错包。如果例程有回环功能，同时用 Wireshark 抓一段，检查回传内容和发出的是否一致。 |
| A3 | C | 记录例程 bitstream 的 PLL/全局缓冲站点（PRR）和时序汇总。 |

例程不通，同样如实记录，然后继续做 B。

### B. B3V 外部反馈

| 步骤 | 执行者 | 内容 |
|---|---|---|
| B1 | U | 在 B3V 工程中按 `fpga/ip/ip_pll_eth.md` 重新生成 `ip_pll_eth`。生成后确认模块有 `clkfb` 输入端口；把 GUI 上实际显示的反馈模式、反馈源、相位和分频截图。重新导入 `edrv32_fpga_rgmii.v` 和 FDC。 |
| B2 | U 或 C | `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。**任何阶段报错（例如 `clkfb` 不允许由全局缓冲驱动），或者有约束不被接受**，就停下，回传原文，不要自行改 RTL、约束或 IP。 |
| B3 | C | 收集：<br>1. 各时钟域 WNS/TNS/WHS/THS；<br>2. PRR 中 `u_rgmii/u_pll_eth`、`u_pll_sys`、`u_rgmii/u_eth_clk` 的站点；<br>3. RGMII RX：用卡 29 同样的定向命令（`-from {rgmii_rxd_i* rgmii_rx_ctl_i}`），取 slow/fast 两个角 setup、hold 各最差 20 条逐级明细，上升沿、下降沿捕获都要有；<br>4. **重点**：逐级明细里时钟路径怎么体现 PLL 外部反馈，例如有没有负的补偿延迟、反馈路径的条目。原样摘录一条完整的时钟路径。 |
| B4 | U + C | 上板（时序不满足也照做，如实记录）：<br>1. 串口（`--baud 115200`）烧录 `eth_diag.bin`；另开终端运行 `py tools/board/eth_probe.py --local-ip 192.168.1.2 --listen 6000`；<br>2. 做 5 次：输入 `r`，等 `link=1 speed=1000`，输入 `s`，等 10 秒后再输入 `s`。PERF1 增加 ≥ 8 且 PERF3 不增加，记为成功；<br>3. 断电，重新下载 bitstream，再烧录 `eth_diag.bin`，再做 5 次；<br>4. 烧录 `demo_vision.bin`，在调试工具中建立网口连接，输出设为 ETH 保持 60 秒，记录视频帧率、丢失计数和 `Video skips`。 |

## 6. 产物

放在 `tasks/win/20261101-30-rgmii-fb/artifacts/`：

| 产物 | 内容 |
|---|---|
| `vendor/` | 例程的测试方法摘要、PC 侧输出原文、抓包（如有）、站点和时序汇总 |
| `ip_pll_eth_gui.png` | B1 截图 |
| `timing_summary.txt`、`clock_sites.txt`、`flow_summary.txt` | 同卡 29 |
| `rgmii_rx_setup_top20.txt`、`rgmii_rx_hold_top20.txt` | B3 第 3 项 |
| `rgmii_rx_clock_path.txt` | B3 第 4 项的原样摘录 |
| `uart/*.log`、`probe.txt`、`video_eth/` | B4 |

## 7. 通过判据

| 部分 | 判据 |
|---|---|
| A | 例程 ARP/UDP 正常，说明板子和 PC 没有问题（只记录） |
| B 时序 | RGMII RX setup、hold 两个角都不违例 |
| B 上板 | 10 次 PHY 复位全部成功；ETH 视频有画面，丢失计数不持续增长 |

所有数字取自报告和日志原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261101-30-rgmii-fb 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| A 例程：器件/是否重新生成 IP/是否通 | |
| B ip_pll_eth 实际反馈模式、反馈源、相位 | |
| B 约束是否被接受 | |
| B PLL / 缓冲站点 | u_pll_eth / u_pll_sys / u_eth_clk |
| B RGMII RX 最差 setup / hold | slow / fast，上升沿 / 下降沿 |
| B 全部时钟域 WNS / WHS | |

## A. 厂商例程
- 测试方法（来自例程源码/教程）
- PC 侧结果

## B. 时钟路径中的外部反馈体现（原文摘录）

## B. 上板
| 轮 | 次 | PERF1 增量 | PERF3 增量 | 成功 |
|---|---|---|---|---|
- 网口视频：帧率、丢失计数、Video skips

## 问题与偏离
```
