# ETH 以太网引擎规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-28 |
| 状态 | 已确认（v0.1，2026-10-28）。标 **[待定]** 的条目给出了开发初值 |
| 范围 | `edrv32_eth`：千兆 MAC（MAC 侧 8 位接口）、硬件 UDP 接收直写 DDR 窗口、硬件分包 UDP 发送、硬件 ARP 应答、MDIO 管理；ETH 寄存器块 |
| 关联文档 | SoC 规格 v0.13 3.4、4.2、4.3、5.2（X3、X7）、6.4（P6）、7.1、7.2、8.10、9.3；`dma2d-spec.md` v0.1；设计记录 `2026-10-25-soc-architecture-decisions.md` D9、9.9，`2026-10-27-image-path.md` Q7，`2026-10-28-eth.md` |

---

## 1. 概述

ETH 让 PC 通过千兆网口和板子交换大块数据：下载图像（作为 VIN 内存源的输入，设计记录 Q7）、NPU 权重和程序，回传处理结果和结果帧。

- 接收（流式）：PC 发来的 UDP 包，载荷开头是一个 8 字节的应用头（2.3），指明写到哪个接收窗口的哪个偏移；ETH 校验后把其余数据直接写入 DDR 中该窗口的对应位置（零拷贝，包可以乱序）。PC 在一块数据的最后发一个带通知位的包，ETH 写完后中断 CPU。
- 发送（命令式，SoC 7.2）：软件在 DDR 中准备发送描述符表，写 `DESC_BASE`、`DESC_COUNT`、`DOORBELL`；每条描述符指定 DDR 中一块任意长度的数据，ETH 把它切成多个 UDP 包，每包带与接收相同格式的应用头，发给软件配置的对端。
- ARP：ETH 自动应答询问本机 IP 的 ARP 请求。其他帧（ICMP 等）不处理，只计数。
- 只支持 1000 Mbps 全双工。不支持 IP 分片、IP 选项、VLAN 和巨型帧。
- DDR 端口为 mem_xbar P6（与 PERF_MON 共用，在 P6 内部仲裁，SoC 6.4.1）；寄存器在媒体 APB 槽 7；中断为 PLIC 源 14。
- 时钟域：接收前端在 `eth_rx_clk`，发送前端在 `eth_tx_clk`，到异步 FIFO 为止（SoC 5.2 X7）；其余（寄存器、协议处理、DMA、MDIO）在 clk_mem。

## 2. 功能描述

### 2.1 地址和字节序

- 本机 MAC 地址 `MAC_ADDR`、IP 地址 `IP_ADDR`、接收 UDP 端口 `RX_PORT` 由软件配置（4.2）。
- 线上所有多字节字段（以太网、ARP、IPv4、UDP 头和 2.3 应用头）都是网络字节序（高字节先发）。
- 寄存器中的 MAC 地址 `aa:bb:cc:dd:ee:ff`：`*_MAC_HI[15:8] = aa`、`[7:0] = bb`，`*_MAC_LO[31:24] = cc` … `[7:0] = ff`；IP 地址 `a.b.c.d`：`[31:24] = a` … `[7:0] = d`。
- 应用数据按到达顺序写入递增的 DDR 地址；发送时按 DDR 地址递增的顺序发出。

### 2.2 接收过滤

一帧（从前导码之后的目的 MAC 到 FCS）按顺序检查，第一条不满足的规则决定它的去向：

| # | 条件 | 不满足时 |
|---|---|---|
| 1 | `CTRL.ENABLE = 1` 且 `IRQ_STAT.ERROR = 0` | 丢弃，不计数（只计入 PERF0） |
| 2 | 接收期间 `eth_rx_er_i` 未置位；FCS 正确；帧长（含 FCS）64–1518 字节 | 丢弃，PERF3 |
| 3 | 目的 MAC 等于 `MAC_ADDR`，或为广播地址且 EtherType = 0x0806 | 丢弃，PERF5 |
| 4 | EtherType = 0x0806：HTYPE = 1、PTYPE = 0x0800、HLEN = 6、PLEN = 4、OPER = 1（请求）、目标 IP 等于 `IP_ADDR` → 按 2.5 应答 | 丢弃，PERF5 |
| 5 | EtherType = 0x0800；版本 4、IHL = 5；MF = 0 且分片偏移 = 0；协议 = 17；目的 IP 等于 `IP_ADDR`；总长度 ≤ 帧中 IP 部分的长度 | 丢弃，PERF5 |
| 6 | IPv4 头校验和正确；UDP 校验和为 0 或正确 | 丢弃，PERF4 |
| 7 | UDP 目的端口等于 `RX_PORT`；UDP 长度 = IP 总长度 − 20 且 ≥ 16 | 丢弃，PERF5 |
| 8 | 应用头指定的窗口范围内（2.4） | 丢弃，PERF6 |
| 9 | 片上接收缓冲有空间存下这一帧（5.2） | 丢弃，PERF7 |

满足全部条件的包按 2.4 写入。帧长大于 IP 总长度的部分（以太网填充）忽略。

数据只在 FCS、IP 头校验和、UDP 校验和全部通过后才写入 DDR（存储转发）。

### 2.3 应用头

UDP 载荷的前 8 字节：

| 字节 | 字段 | 说明 |
|---|---|---|
| 0 | `WIN` | [1:0] 窗口号 0–3；[7:2] 忽略 |
| 1 | `FLAGS` | bit0 `NOTIFY`；其余位忽略 |
| 2–3 | — | 忽略 |
| 4–7 | `OFFSET` | 本包数据在窗口内的字节偏移（32 位，网络字节序，任意对齐） |

应用头之后是数据，长度 `LEN = UDP 长度 − 16`，可以为 0。发送时 ETH 产生同样格式的头，忽略的位和字节填 0。

### 2.4 接收窗口

- 4 个窗口，各有 `WINn_BASE`（32 B 对齐）、`WINn_SIZE`（字节）、`WINn_BYTES`（已写入的数据字节数）。
- 范围检查：`OFFSET + LEN ≤ WINn_SIZE`（按 33 位无符号比较）。`WINn_SIZE = 0` 的窗口不接收任何包。
- 写入：数据写到 `WINn_BASE + OFFSET` 起的连续字节，部分字节用 WSTRB 屏蔽（SoC 4.2）。写入后 `WINn_BYTES` 加 LEN（回绕）。同一偏移被写多次时，每次都计入 `WINn_BYTES`。
- 包按通过检查的顺序写入。`NOTIFY = 1` 的包：在它和此前所有包的写响应都返回之后，置 `IRQ_STAT.RX_NOTIFYn`（n 为该包的窗口号）。此时 `WINn_BYTES` 已包含该包。
- 每个被写入的包，把它的源 MAC、源 IP、UDP 源端口记入 `PEER_MAC`、`PEER_IP`、`PEER_PORT`。
- 窗口寄存器在 BUSY 期间被修改时，对此后开始写入的包生效。

典型用法：窗口 0、1 做图像双缓冲（PC 交替发往两个窗口，VIN 内存源读另一个），窗口 2 放权重或程序，窗口 3 放 PC 发给 CPU 的短消息。软件收到 `RX_NOTIFYn` 后比对 `WINn_BYTES` 和期望值，不一致时通过发送请求 PC 重发（应用层协议，见 `sw/`）。

### 2.5 ARP 应答

对满足 2.2 第 4 条的请求，ETH 发送一个 ARP 应答：目的 MAC = 请求的发送方 MAC，源 MAC = `MAC_ADDR`，OPER = 2，发送方 = (`MAC_ADDR`, `IP_ADDR`)，目标 = 请求的发送方 (MAC, IP)，补齐到最短帧长。

- ARP 应答在发送前端插在两个 UDP 包之间，不打断正在发送的帧。
- 最多保留 1 个待发的应答；已有待发应答时收到的新请求被丢弃（计入 PERF5）。

### 2.6 发送

描述符表在 DDR 中，起始地址 `DESC_BASE`（32 B 对齐），每条 32 B（8 个 32 位字，小端），连续存放。

| 字 | 位 | 字段 | 说明 |
|---|---|---|---|
| 0 | [31:5] | `SRC_ADDR` | 数据的 DDR 地址（[4:0] 忽略） |
| 1 | [23:0] | `LEN` | 数据字节数，0 表示只发一个 LEN = 0 的包 |
| 2 | [1:0] / [8] | `WIN` / `NOTIFY` | 写进应用头的窗口号；NOTIFY = 1 时只在本条的最后一个包置位 |
| 3 | [31:0] | `OFFSET` | 第一个包的应用头偏移 |
| 4–7 | — | — | 忽略 |

- 每条描述符切成 `⌈LEN / 1024⌉` 个包（LEN = 0 时 1 个）：第 k 个包携带数据 `[1024k, min(1024(k+1), LEN))`，应用头 `OFFSET` 为描述符 OFFSET + 1024k。
- 每个包的格式：
  - 以太网：目的 MAC = `TX_DST_MAC`，源 MAC = `MAC_ADDR`，EtherType 0x0800；
  - IPv4：版本 4、IHL 5、DSCP/ECN 0、标识 = 每包加 1 的 16 位计数（SOFT_RST 时清零）、DF = 1、TTL 64、协议 17、源 IP = `IP_ADDR`、目的 IP = `TX_DST_IP`，头校验和由硬件计算；
  - UDP：源端口 = `TX_SRC_PORT`，目的端口 = `TX_DST_PORT`，校验和填 0（IPv4 允许）；
  - 载荷：2.3 应用头 + 数据。
  - 以太网层：前导码 7 字节 0x55、SFD 0xD5、不足最短帧长时补 0、FCS、帧间隔 ≥ 12 字节。
- 描述符依次执行；每条的最后一个包发送完毕后 `DONE_COUNT`、`CUR_DESC` 加 1；全部完成后置 `IRQ_STAT.DONE`。
- 发送相关寄存器（`MAC_ADDR`、`IP_ADDR`、`TX_*`）在 BUSY 期间不得修改，由软件保证。

### 2.7 MDIO

- MDIO 主控按 IEEE 802.3 第 22 条（Clause 22）帧格式访问 PHY 寄存器；MDC = clk_mem / 64（约 1.95 MHz）。
- 软件写 `MDIO_CMD` 启动一次读或写，`MDIO_STAT.BUSY` 清零后完成，读数据在 `MDIO_STAT.RDATA`。BUSY 期间写 `MDIO_CMD` 被忽略。
- `PHY_CTRL.PHY_RST` 直接驱动 `eth_phy_rst_n_o = ~PHY_RST`，复位值 1（PHY 保持复位），由软件按 PHY 手册的时序释放。

## 3. 接口

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `clk_mem_i` | in | 1 | — | 125 MHz |
| `rst_mem_n_i` | in | 1 | clk_mem | 媒体复位（系统子系统规格 2.10） |
| `clk_eth_rx_i` | in | 1 | — | 125 MHz，来自 PHY 的接收时钟（SoC 3.1 `eth_rx_clk_i`） |
| `rst_eth_rx_n_i` | in | 1 | eth_rx_clk | 由 reset_ctrl 在本域同步释放 |
| `clk_eth_tx_i` | in | 1 | — | 125 MHz（SoC 3.1 `eth_tx_clk_i`） |
| `rst_eth_tx_n_i` | in | 1 | eth_tx_clk | 由 reset_ctrl 在本域同步释放 |
| `eth_rxd_i[7:0]`、`eth_rx_dv_i`、`eth_rx_er_i` | in | 8 / 1 / 1 | eth_rx_clk | SoC 3.4 |
| `eth_txd_o[7:0]`、`eth_tx_en_o`、`eth_tx_er_o` | out | 8 / 1 / 1 | eth_tx_clk | SoC 3.4；`eth_tx_er_o` 恒为 0 |
| `eth_mdc_o`、`eth_mdio_o`、`eth_mdio_oe`、`eth_mdio_i` | — | 1 | clk_mem | 2.7 |
| `eth_phy_rst_n_o` | out | 1 | clk_mem | 2.7 |
| `apb_paddr_i[11:0]`、`apb_psel_i`、`apb_penable_i`、`apb_pwrite_i`、`apb_pwdata_i[31:0]`、`apb_pstrb_i[3:0]`、`apb_pready_o`、`apb_prdata_o[31:0]`、`apb_pslverr_o` | — | — | clk_mem | 媒体 APB 槽 7 从口（SoC 4.3）；`apb_pready_o` 恒为 1，`apb_pslverr_o` 恒为 0 |
| `axi_arid_o`、`axi_araddr_o[31:0]`、`axi_arlen_o[3:0]`、`axi_arvalid_o`、`axi_arready_i`、`axi_rid_i`、`axi_rdata_i[255:0]`、`axi_rresp_i[1:0]`、`axi_rlast_i`、`axi_rvalid_i`、`axi_rready_o` | — | — | clk_mem | AXI256 读通道（SoC 4.2）：发送描述符和数据；ID 固定为 0 |
| `axi_awid_o`、`axi_awaddr_o[31:0]`、`axi_awlen_o[3:0]`、`axi_awvalid_o`、`axi_awready_i`、`axi_wdata_o[255:0]`、`axi_wstrb_o[31:0]`、`axi_wlast_o`、`axi_wvalid_o`、`axi_wready_i`、`axi_bid_i`、`axi_bresp_i[1:0]`、`axi_bvalid_i`、`axi_bready_o` | — | — | clk_mem | AXI256 写通道（SoC 4.2）：接收数据；ID 固定为 0。接到 P6 内部仲裁器 |
| `irq_o` | out | 1 | clk_mem | PLIC 源 14，`|(IRQ_STAT & IRQ_EN)` |

- DDR 访问经 `dma2d_rd` / `dma2d_wr`（`dma2d-spec.md`），满足 SoC 4.2、8.11 的事务规则。
- 跨时钟域只有 X7 的两个异步 FIFO（接收、发送各一个），以及 X8 的复位。
- RGMII 与 8 位单沿接口的转换、发送时钟相位在 FPGA 层完成（SoC 3.4）。

## 4. 寄存器

媒体 APB 槽 7。公共寄存器按 SoC 7.1；寄存器块忽略 `pstrb`，按整字写（SoC 4.3）。未列出的偏移读为 0、写忽略。

### 4.1 公共寄存器

| 偏移 | 名称 | 规定 |
|---|---|---|
| 0x000 | ID | 0x0007_0001 |
| 0x004 | CTRL | bit0 ENABLE：接收和 ARP 应答使能，不门控 DOORBELL；bit1 START 无作用；bit2 ABORT（5.3）；bit3 SOFT_RST：只在 IDLE 时生效，把全部寄存器和控制状态恢复到复位值，并清空片上缓冲中尚未写出或发出的帧 |
| 0x008 | STATUS | BUSY = 正在执行发送描述符表，或有未完成的 AXI 事务，或片上接收缓冲中有待写出的包；IDLE = 非 BUSY；ERROR = IRQ_STAT.ERROR |
| 0x00C | IRQ_EN | 复位 0 |
| 0x010 | IRQ_STAT | bit0 DONE（发送描述符表完成）；bit1 ERROR；[11:8] RX_NOTIFY0–3（2.4） |
| 0x014 | ERR_CODE | 第 6 节 |
| 0x020 | DESC_BASE | [31:5]，[4:0] 读为 0 |
| 0x024 | DESC_COUNT | [15:0] 发送描述符条数，其余位读为 0 |
| 0x028 | DOORBELL | 写任意值启动发送；STATUS.BUSY = 1 时写入被忽略；DESC_COUNT = 0 时立即置 DONE |
| 0x02C | DONE_COUNT | 已完成的发送描述符条数（自增，回绕） |
| 0x040–0x07C | PERF | 4.3 |

### 4.2 私有寄存器

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x100 | MAC_LO | RW | 0 | 本机 MAC 低 32 位（2.1） |
| 0x104 | MAC_HI | RW | 0 | [15:0] 本机 MAC 高 16 位 |
| 0x108 | IP_ADDR | RW | 0 | 本机 IP |
| 0x10C | RX_PORT | RW | 0 | [15:0] 接收 UDP 端口 |
| 0x110 | TX_DST_MAC_LO | RW | 0 | 发送目的 MAC 低 32 位 |
| 0x114 | TX_DST_MAC_HI | RW | 0 | [15:0] 发送目的 MAC 高 16 位 |
| 0x118 | TX_DST_IP | RW | 0 | 发送目的 IP |
| 0x11C | TX_PORT | RW | 0 | [15:0] TX_DST_PORT；[31:16] TX_SRC_PORT |
| 0x120 | PEER_MAC_LO | RO | 0 | 最近一个被写入的包的源 MAC 低 32 位（2.4） |
| 0x124 | PEER_MAC_HI | RO | 0 | [15:0] 源 MAC 高 16 位 |
| 0x128 | PEER_IP | RO | 0 | 源 IP |
| 0x12C | PEER_PORT | RO | 0 | [15:0] UDP 源端口 |
| 0x130 | CUR_DESC | RO | 0 | 正在执行（或因错误、ABORT 停止时）的发送描述符序号，从 0 起；正常完成后为 DESC_COUNT |
| 0x140 + 16n | WINn_BASE | RW | 0 | n = 0–3；[31:5]，[4:0] 读为 0 |
| 0x144 + 16n | WINn_SIZE | RW | 0 | [27:0] 窗口字节数，其余位读为 0 |
| 0x148 + 16n | WINn_BYTES | RW | 0 | 已写入的数据字节数（2.4）；写任意值清零 |
| 0x180 | MDIO_CMD | WO | — | [4:0] REG；[9:5] PHY；[10] WRITE（1 写 0 读）；[31:16] WDATA。写入启动一次访问（2.7）；读为 0 |
| 0x184 | MDIO_STAT | RO | 0 | bit0 BUSY；[31:16] RDATA（最近一次读的结果） |
| 0x188 | PHY_CTRL | RW | 1 | bit0 PHY_RST（2.7） |

### 4.3 性能计数器

32 位，回绕。PERF0–8 只在复位和 SOFT_RST 时清零；PERF9–10 每次 DOORBELL 清零。

| 编号 | 内容 |
|---|---|
| PERF0 | 接收到的帧数（含错误帧） |
| PERF1 | 写入窗口的 UDP 包数 |
| PERF2 | 写入窗口的数据字节数 |
| PERF3 | 丢弃：FCS 错、帧长不合法、`eth_rx_er_i`（2.2 第 2 条） |
| PERF4 | 丢弃：IPv4 头或 UDP 校验和错（第 6 条） |
| PERF5 | 丢弃：不是发给本机的帧、不支持的协议或端口、ARP 应答已满（第 3、4、5、7 条和 2.5） |
| PERF6 | 丢弃：超出窗口范围（第 8 条） |
| PERF7 | 丢弃：接收缓冲已满（第 9 条） |
| PERF8 | 发出的 ARP 应答数 |
| PERF9 | 从 DOORBELL 到 DONE 或停止的周期；ABORT 或错误后计到发送停止且在途读事务排空为止 |
| PERF10 | 发出的 UDP 包数 |
| PERF11–15 | 读为 0 |

## 5. 行为与时序

### 5.1 接收流程

1. 接收前端（eth_rx_clk）去掉前导码和 SFD，把帧字节和帧尾状态（FCS 是否正确、是否出现 `rx_er`）送入接收异步 FIFO。
2. clk_mem 侧解析头部、按 2.2 检查，把通过检查的包的数据存入片上接收缓冲；帧尾确认 FCS 和校验和都正确后才把这个包交给写出，否则丢弃已存入的部分。
3. 写出按包的顺序进行（2.4）。
4. 接收前端必须能在千兆线速（帧间隔 12 字节、前导码 8 字节）下连续接收而不丢失字节；接收缓冲满时整帧丢弃（2.2 第 9 条），不影响后续帧。

`CTRL.ENABLE` 清零后，此后结束接收的帧全部丢弃（2.2 第 1 条）；已经通过检查的包照常写完。

### 5.2 片上缓冲 **[待定]**

| 参数 | 开发初值 | 约束 |
|---|---|---|
| 接收缓冲 | 4 KiB（至少容纳 2 个最长帧的数据） | 满足第 7 节接收吞吐 |
| 发送缓冲 | 4 KiB | 一个包的全部数据进入发送缓冲后才开始发送这一帧（帧中不得断流）；读下一个包与发送当前包重叠 |
| 异步 FIFO 深度 | 由开发者决定 | 满足 5.1 第 4 条和第 7 节 |

### 5.3 ABORT

`CTRL.ABORT` 写 1 只作用于发送：不再读取新的描述符和数据；正在线上发送的帧发完为止，尚未开始发送的包丢弃；已发出的 AXI 读事务全部完成后发送回到空闲（SoC 7.1）。正在执行的描述符不计入 DONE_COUNT，不置 DONE。接收不受 ABORT 影响，由 `CTRL.ENABLE` 控制。

## 6. 错误处理

| ERR_CODE | 错误 | 检测 | 上报 | 恢复 |
|---|---|---|---|---|
| 1 | 读响应非 OKAY（发送描述符或数据） | R 通道 | IRQ_STAT.ERROR，CUR_DESC 保持 | 发送停止执行后续描述符：已读入的包照常发完，在途读事务完成后发送回到空闲；软件清 ERROR 后可重新启动 |
| 2 | 写响应非 OKAY（接收数据） | B 通道 | IRQ_STAT.ERROR | ERROR = 1 期间丢弃新收到的帧（2.2 第 1 条）；已在接收缓冲中的包照常写出；软件清 ERROR 后恢复接收 |

网络上的错误帧不是 ETH 的错误，只丢弃并计数（2.2、4.3）。除上表外不做其他检查（不检查窗口或发送数据的地址是否越过 DDR、窗口之间是否重叠）。`ERR_CODE` 记录最近一次错误，写 IRQ_STAT.ERROR 清零时一并清除（SoC 7.1）。

## 7. 性能与资源指标

| 项 | 指标 |
|---|---|
| 接收吞吐 | PC 以千兆线速连续发送数据长度 1024 字节的包（帧间隔 12 字节）：全部写入窗口，不丢包；数据写入速率 ≥ 100 MB/s |
| 发送吞吐 | 接收空闲时，一条 LEN = 1 MiB 的描述符：数据发送速率 ≥ 100 MB/s（每包 1024 字节数据时线速约 116 MB/s） |
| ARP | 应答在请求帧接收结束后 10 µs 内开始发送（发送前端正在发送的帧除外） |
| 测量条件 | 模块级仿真，AXI 存储模型固定读延迟 40 个 clk_mem 周期，写响应延迟 40 个周期，无反压 |
| LUT | ≤ 5K（SoC 9.3） |
| DRM | **[待定]** 估算：接收、发送缓冲各 4 KiB，异步 FIFO 两个，共约 6 个 DRM18K |

## 8. 验证要点

1. 接收过滤 2.2 的每一条：正确的包被写入；每一种不满足条件的帧被丢弃并计入对应计数器，且不写任何 DDR。
2. 应用头和窗口：4 个窗口、任意对齐的 OFFSET 和 LEN（含 0）、乱序到达、窗口边界两侧、`WINn_SIZE = 0`；`WINn_BYTES` 累计和清零；PEER_* 记录。
3. NOTIFY：中断在该包和此前所有包写完之后产生。
4. ARP：应答的每个字段；应答插在发送的 UDP 包之间；连续请求时只保留 1 个待发应答。
5. 发送：分包边界（LEN 为 0、1、1023、1024、1025、多 MiB）、应用头、IPv4 头校验和、帧格式和帧间隔；NOTIFY 只在最后一个包；多条描述符；DONE、DONE_COUNT、CUR_DESC。
6. 收发同时进行；接收缓冲满时的丢包和恢复。
7. 第 6 节每种错误和 ABORT（含在途事务、正在发送的帧）；SOFT_RST；DESC_COUNT = 0；ENABLE 清零。
8. MDIO 读写帧格式；PHY_CTRL。
9. 性能：第 7 节接收、发送吞吐和 ARP 应答延迟。

## 9. 待定事项

| # | 事项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | 片上缓冲参数 | 5.2 表 | RTL 实现、性能仿真、PDS 资源 |
| 2 | DRM 用量 | 第 7 节估算 | PDS 资源 |

## 10. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-28 | v0.1 | 初稿。用户确认：接收按应用头的窗口号和偏移直写 DDR；硬件应答 ARP，其他帧丢弃；发送按描述符分包、带应用头；对端地址由硬件记录、软件配置；4 个接收窗口，包头通知位产生中断；只支持 1000M、发送每包 1024 B 数据且 UDP 校验和填 0、接收存储转发、MDIO 和 PHY 复位在 ETH 中、收发吞吐 ≥ 100 MB/s |
