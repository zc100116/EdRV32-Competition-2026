# ip_pll_eth

| 项 | 内容 |
|---|---|
| IP | IP Compiler → Clock → 28nm PLL（Logos2，v1.5；B1 已生成的同族 PLL） |
| 器件 | PG2L200H-6，FBB676；PDS 2022.2-SP6.4 或兼容现有 B1 的版本 |
| 生成模块名 | `ip_pll_eth` |
| 使用者 | B2 `edrv32_fpga_board_b2_top` / `edrv32_fpga_rgmii` 直接例化 |
| 依据 | 设计记录 `docs/design/2026-11-01-rgmii-rx-clock.md`；反馈选项见 UG041001 表 2-4（PDF19–20） |
| 初始化文件 / 读写延迟 | 无 / 无，连续时钟输出；lock 为锁定状态 |

## 用户 GUI 生成步骤

1. 在已创建的 B2 工程打开 IP Compiler，新建 Clock → 28nm PLL，实例名填 `ip_pll_eth`。
2. Basic 页输入频率填 **125.000 MHz**，输入选择 CLKIN1，来源 **No Buffer**。
   **Feedback Clock Mode 选 External Feedback**（生成 `clkfb` 端口），**Feedback from 选 CLKOUT0**。
   不使能第二输入、输入动态切换、APB、SSC、动态相移、门控、互补输出。
3. 输出按下表勾选；其余 CLKOUT 全部不勾选。相位单位是度，占空比单位是百分数。
4. 输出缓冲选择 **No Buffer**；板级显式例化 `GTP_CLKBUFG`，其输出同时接回 `clkfb`。内部复位 `RST_INNER_EN=false`，
   不生成 reset 端口；保留 lock，锁定模式保持 0，其余高级选项保持默认。
5. 点击计算分频后生成，保留生成的 IP 源及其本地依赖在 FPGA 工程中；不提交 git。
   实际频率、端口及相位在 Windows result.md 回传，实际不符就明确报错并交协调者处理。

| 输出 | 频率 MHz | 相位 ° | 占空比 % |
|---|---|---|---|
| CLKOUT0 | 125.000 | 0 | 50 |

## 期望端口

| 端口 | 方向 | 位宽 | 用途 |
|---|---|---|---|
| `clkin1` | in | 1 | 125.000 MHz 参考 |
| `clkfb` | in | 1 | 外部反馈，接 `GTP_CLKBUFG` 输出 |
| `clkout0` | out | 1 | 125.000 MHz |
| `lock` | out | 1 | 高有效锁定指示 |

反馈取自全局缓冲输出，PLL 把 IDDR 处的时钟对齐到 RXC 输入，CLKOUT0 之后的走线延迟
不再随布局和工艺角移动采样点。PHY strap 为 rgmii-id，数据已在 RXC 沿上居中，所以相位为 0°，
RX 不再使用 IODELAY；TXC 仍固定 100 步。厂商例程（内部反馈、30°、RX 247 步）在本 SoC 中
时钟插入延迟 2.5–5.0 ns，采样点不可控，见设计记录。
两路 MAC clk 共用此输出，进入 SoC 后 X7 FIFO 处理 clk_mem 跨域。
lock 不参与全局复位，防止 PHY 复位导致 RX 时钟停止时锁住 CPU/PHY_CTRL。
仅支持 ETH 规格的 1000M；软件负责 PHY MDIO 配置及 PHY_CTRL 复位释放。
