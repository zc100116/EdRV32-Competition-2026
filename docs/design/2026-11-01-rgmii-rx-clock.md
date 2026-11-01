# RGMII RX 采样时钟：PLL 外部反馈

## 背景和问题

B3N/B3R/B3V 的网口在不同 bitstream 上时好时坏：板→PC 发送一直正常，接收端 PERF3（FCS/帧长/RX_ER）随收到的帧同步增加。卡 29 在 B3V 上把 ETH PLL 固定到 RXC 引脚旁（GPLL_7_1381）后，原本正常的 B3V 也变成 5 次 PHY 复位中只有 1 次无错。

`edrv32_fpga_rgmii` 照搬厂商 2_11_ethernet_test：RXC → `ip_pll_eth`（内部反馈 CLKOUTF，30°）→ `GTP_CLKBUFG` → IDDR；RX 数据经 IODELAY 247 步（端口设置）。厂商 FDC 没有输入延迟约束，PDS 从未检查这条接收路径。

## 约束

- RTL8211F Rev1.4 Table 60（延迟集成在发送端，即 PHY strap rgmii-id）：TsetupR/TholdR ≥ 1.0 ns，DDR 半周期 4 ns。
- PHY strap 读回 RXDLY=1/TXDLY=1，所有工程使用同一固定设置，不按工程调延迟。
- IP 由用户在 PDS 中生成；PLL 反馈选项见 UG041001 表 2-4（Feedback Clock Mode / Feedback from）。

## 卡 29 实测（b3 5af1c8a7，B3V，PDS 2022.2-SP6.1）

`tasks/win/20261101-29-rgmii-b3v/artifacts/rgmii_rx_{setup,hold}_top20.txt`：

| 角 | RXC 引脚→IDDR 时钟 | RXD 引脚→IOL | setup 最差 | hold 最差 |
|---|---|---|---|---|
| slow | 4.21（下降沿）/ 5.05（上升沿）ns | 0.90 / 0.68 ns | -0.265 ns | 0.387 ns |
| fast | 2.52 ns | 0.52 ns | -1.224 ns | 2.022 ns |

- 时钟路径：IBUF → PLL（GPLL_7_1381）→ 全局缓冲 USCM_383_930 → IOL；其中 PLL 输出到全局缓冲 1.2–1.4 ns，全局网络 1.5–1.8 ns。
- 慢角 setup + hold 合计只有 0.12 ns，快角 0.8 ns；两角需要的平移量分别是 0.27–0.39 ns 和 1.22–2.02 ns，没有交集。也就是说，任何固定的相位或 IODELAY 都无法同时满足两个角，布局一变，采样点也随之移动。
- 报告的数据路径终止在 IOL 的 DI，没有计入端口设置的 IODELAY，所以实际板上的采样点不在报告的分析范围内。

## 可选方案

1. **按工程调相位/IODELAY**：用户已否决（2026-11-01），而且即使调了，也解决不了跨工艺角的漂移。
2. **IO 专用时钟（不经 PLL 和全局网络）**：插入延迟最短，但 Logos2 IO 用户指南（UG040006）没有找到（卡 28），原语用法无法确认。
3. **PLL 外部反馈，反馈取自全局缓冲输出**（选定）：PLL 把反馈输入对齐到参考输入，CLKOUT0 之后的走线延迟（约 2.7–3.2 ns，慢角）被抵消。剩余未补偿的部分只有 RXC 引脚 → PLL 输入（IBUF + 0.5–0.6 ns 走线），与数据路径的 IBUF 相近。

方案 3 的估算（假设补偿完全，RXC 到 PLL 输入不补偿；IDDR 建立/保持取卡 29 报告值）：

- 慢角：时钟比数据晚约 1.3–1.6 − 0.7–0.9 ≈ 0.6 ns，setup ≈ 0.6 + 1.0 − 1.03 − 0.15 ≈ +0.4 ns，hold ≈ 1.0 − 0.6 + 0.54 − 0.15 ≈ +0.8 ns。
- 快角：时钟比数据晚约 0.35 ns，setup ≈ 0.35 + 1.0 − 0.67 − 0.15 ≈ +0.5 ns。
- 以上均为估算，以 PDS 报告为准。

## 决策

- `ip_pll_eth`：External Feedback，Feedback from CLKOUT0，CLKOUT0 125 MHz、0°；`clkfb` 接 `u_eth_clk` 输出。
- RX 数据和 RX_CTL 由 INBUF 直接进 IDDR，不经 IODELAY。TX 不变（TXC IODELAY 100 步，SAME_EDGE ODDR）。
- FDC：`clk_eth` 的 edge_shift 改为 0；保留 RX 输入延迟（±1.0 ns）和 ETH PLL 位置约束（GPLL_7_1381，让未补偿的 RXC→PLL 走线尽量短）。

## 影响

- `fpga/rtl/edrv32_fpga_rgmii.v`、`fpga/ip/ip_pll_eth.md`（需要重新生成 IP）、五个板级 FDC、`verif/soc/board_vision/ip_pll_eth.sv`。
- 规格不变：eth-spec 只规定 RGMII 1000M，不规定板级时钟结构。
- 待验证：PDS 时序分析是否计入了外部反馈补偿。如果没有计入，报告里时钟路径仍是 4–5 ns，会出现约 −3.5 ns 的 hold 违例；这种情况由卡 30 回传原文后再判断。

## 卡 30 结果（b3 921ca8fc，B3V，win f599f103）

- PDS 计入了反馈补偿：捕获时钟路径中 GPLL CLKOUT0 一级为 −2.807 ns；PRR 显示 CLKFB 由 `u_eth_clk` 驱动。慢角 RXC 引脚到 IDDR 的时钟延迟从 4.2–5.0 ns 降到 2.17 ns。
- RX 最差裕量：

| 角 | setup 上升 / 下降沿 | hold 上升 / 下降沿 |
|---|---|---|
| slow | 0.319 / 0.232 ns | −0.361 / −0.260 ns |
| fast | 0.516 / 0.513 ns | 0.136 / 0.141 ns |

- 慢角 setup + hold 合计 −0.03 ~ −0.13 ns：在 PHY 最小 1.0 ns 窗口下，任何平移都无法让两项同时为正。数据整体延后约 0.3 ns 时，四项最差值最好，约为 −0.07 ns。
- 上板：PHY 复位 10/10 次无错（PERF3 增量全为 0，其中 5 次在断电重下之后）；ETH 视频 60 s 有画面，接收 30.5 fps、丢弃帧 0。厂商例程在本板 ping 5/5、UDP 60/60。
- 其余时钟域全部满足。

## 状态

已决定，卡 30 在 B3V 上验证通过（上板）；慢角 RX hold 仍有残余违例，见上。
