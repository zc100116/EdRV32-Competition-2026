# 任务卡 20261101-29-rgmii-b3v：RGMII 接收约束和 ETH PLL 位置的实验构建（只做 B3V）

## 1. 目标

卡 26/28 的结论：网口时好时坏，原因是 RGMII 接收采样落在窗口边缘。具体有两点：
- RGMII 输入没有时序约束；
- ETH PLL 被放在离接收时钟引脚最远的 GPLL_727_463，接收时钟要绕到芯片另一侧再回到 IO。

本卡在 B3V 上验证约束修改（`fpga/constraints/edrv32_fpga_board_vision_top.fdc`，B3R/B3N 已做相同修改）：
- ETH PLL 固定到接收时钟引脚旁边的 `GPLL_7_1381`，系统 PLL 改放到 `GPLL_727_463`；
- RGMII RX 输入时序约束：按 RTL8211F 手册表 60，PHY 保持默认 RXDLY=1，每个时钟沿前后数据至少稳定 1.0 ns。

要得到的是：PDS 是否接受这些约束、PLL 实际位置、RX 采样的 setup/hold 裕量。协调者据此确定 PLL 相位和 IODELAY 的最终固定值。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交），拉出 `win/20261101-29-rgmii-b3v`，记录完整哈希。
- **ROM/SRAM**：`tasks/win/20261101-24-b3-rnv/src/ip_rom_boot.dat`、`ip_ram_sram.dat`（含 BIOS 100 ms 波特率修复）。
- **程序**：`tasks/win/20261031-23-b3-converged/src/eth_diag.bin`，以及 `tasks/win/20261101-24-b3-rnv/src/demo_vision.bin`。

## 3. 环境

- PDS 2022.2-SP6.1；PG2L200H-6 FBB676；工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3V`（顶层 `edrv32_fpga_board_vision_top`，111 个源文件）。
- 实现期间不要在这台电脑上运行仿真虚拟机。
- 上板：JTAG、USB 串口、OV5640；PC 有线网卡 `192.168.1.2/24`，放行 UDP 6000。

## 4. 需要的 IP

| 动作 | IP |
|---|---|
| 用卡 24 的 `ip_rom_boot.dat` 重新生成 | `ip_rom_boot` |
| 用卡 24 的 `ip_ram_sram.dat` 重新生成 | `ip_ram_sram` |

其余 IP 沿用卡 23 的 B3V 工程。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261101-29-rgmii-b3v origin/zc100116/b3`；整理用户清单。 |
| 1 | 用户（U） | 按第 4 节重新生成两个 IP；确认工程使用的是更新后的 `edrv32_fpga_board_vision_top.fdc`，里面有 `GPLL_7_1381` 和 `set_input_delay`。 |
| 2 | U 或 C | `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。**任何阶段报错，或者有约束不被接受（包括 `set_input_delay` 的 `-clock_fall`、`-add_delay`、`PAP_LOC` 站点）**，就停下，回传报错或警告原文，不要自行改写约束。 |
| 3 | C | 收集：<br>1. 各时钟域 WNS/TNS/WHS/THS；<br>2. PRR 中 `u_rgmii/u_pll_eth`、`u_pll_sys`、`u_rgmii/u_eth_clk` 的实际站点；<br>3. **RGMII RX 路径**：起点为 `rgmii_rxd_i[*]`、`rgmii_rx_ctl_i` 端口的 setup 和 hold 各最差 20 条逐级明细（含时钟路径：引脚 → PLL → 时钟缓冲 → IDDR 的每一级延迟），并说明上升沿和下降沿两种捕获是否都被分析；<br>4. 时序报告里有没有“未约束输入”提到这些 RGMII 端口。 |
| 4 | U + C | 上板（即使时序未满足也做，如实记录）：<br>1. 用串口（`--baud 115200`）烧录 `eth_diag.bin`；另开终端运行 `py tools/board/eth_probe.py --local-ip 192.168.1.2 --listen 6000`；<br>2. 在串口终端做 5 次：输入 `r`，等 `link=1 speed=1000`，再输入 `s`，等 10 秒后再输入 `s`。PERF1 增加 ≥ 8 且 PERF3 不增加，记为成功；<br>3. 烧录 `demo_vision.bin`，在调试工具中建立网口连接，输出设为 ETH 保持 60 秒，记录视频帧率、丢失计数和 `Video skips`。 |

## 6. 产物

放在 `tasks/win/20261101-29-rgmii-b3v/artifacts/`：`timing_summary.txt`、`rgmii_rx_setup_top20.txt`、`rgmii_rx_hold_top20.txt`、`clock_sites.txt`（PLL 和缓冲站点）、`flow_summary.txt`、`uart/*.log`、`probe.txt`。

## 7. 通过判据

只采集数据。所有数字取自报告和日志原文；约束不被接受时回传原文即可。

## 8. result.md 模板

```markdown
# 20261101-29-rgmii-b3v 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 约束是否被接受 | |
| PLL / 缓冲站点 | u_pll_eth / u_pll_sys / u_eth_clk |
| RGMII RX 最差 setup / hold 裕量 | 上升沿 / 下降沿 |
| 全部时钟域 WNS / WHS | |
| 布局布线耗时 | |

## 上板
| 次 | PERF1 增量 | PERF3 增量 | 成功 |
|---|---|---|---|
- 网口视频：帧率、丢失计数、Video skips

## 问题与偏离
```
