# EdRV32 SoC 规格说明书

| 项 | 内容 |
|---|---|
| 版本 | v0.22（草案） |
| 日期 | 2026-10-31 |
| 状态 | SoC 层已确认；标有 **[模块规格]** 的条目，由对应模块的规格补全 |
| 范围 | SoC 层：`edrv32_soc_top` 及其内部。FPGA 板级层（PLL、DDR 控制器/PHY、TMDS 串化、RGMII IO、引脚）不在本文范围内 |
| 关联文档 | 开发规则 `CLAUDE.md`；设计决策记录 `docs/design/2026-10-25-soc-architecture-decisions.md`；DDR 带宽分析 `docs/design/2026-10-25-ddr-bandwidth-analysis.md` |

本文中"必须"表示强制要求，"应"表示推荐要求，"可"表示允许。

---

## 1. 系统概述

### 1.1 系统功能

EdRV32 SoC 是一个以自研 RISC-V 处理器为控制核心的边缘视觉系统，运行在紫光同创 PG2L200H 上，提供以下功能：

| 功能 | 说明 |
|---|---|
| 通用计算 | EdRV32 CPU（RV32IM，顺序双发射，带 I/D Cache）运行系统软件和 CoreMark |
| 视频采集 | 两路 OV5640 DVP 输入，720p，默认 30 fps，可配置为 60 fps |
| 图像处理 | 采集通路上的流式点运算和 3×3 空间滤波（PIX）；DDR 到 DDR 的几何变换（GEO） |
| 目标检测 | YOLOv8n 推理加速（NPU），描述符驱动 |
| 图形渲染 | 2D 绘制加速（RND），作为 LVGL 等图形库的绘制后端；多图层合成 |
| 显示输出 | HDMI 720p60，单路输出 |
| 网络 | 千兆以太网，硬件 UDP 收发直通 DDR（ETH） |
| 系统外设 | UART、GPIO（按键/LED）、I2C（摄像头 SCCB）、中断控制器（CLINT 定时器、PLIC） |

### 1.2 演示场景

单个 bitstream 包含全部功能。演示程序分三个场景运行，**每个场景的画面都经过渲染器的图层合成后输出**。

| 场景 | 数据流 |
|---|---|
| S1 目标检测 | 摄像头 → DDR 底图 Surface（L0）；摄像头 → NPU 输入适配 → NPU → 检测结果 → CPU → RND 把检测框和标签绘制到 UI 层（L1）→ DISP 两层叠加 → HDMI |
| S2 图像处理 | 摄像头 → PIX → DDR → （可选）GEO → DDR（L0）；RND 绘制菜单和参数（L1）→ DISP 两层叠加 → HDMI |
| S3 图形界面 | CPU 运行 LVGL → RND 绘制到显示缓冲（L0，RGB565）→ DISP → HDMI |

场景由 GPIO 按键或上位机串口命令切换。

### 1.3 硬件平台约束

| 资源 | 规格 |
|---|---|
| FPGA | PG2L200H（约 160K LUT，415 个 DRM，740 个 APM） |
| DDR3 | 2 × x16 = 32 位，1000 MT/s，1 GB；控制器用户接口 256 位 @125 MHz，理论 4.0 GB/s |
| 外设 | 2 × OV5640、HDMI TX、RTL8211F（RGMII）、2 × 16 MB QSPI flash、按键、LED、UART |

---

## 2. 系统架构

### 2.1 结构图

```
 ┌──────────────────────────────── edrv32_soc_top ────────────────────────────────┐
 │  clk_sys 域                                                                     │
 │  ┌──────────┐  I$ AXI64(RO)  ┌─────────────────────────────────────────┐         │
 │  │ EdRV32   ├───────────────►│ sys_xbar  64 位系统 AXI，2 主 × 7 从      │         │
 │  │ CPU      ├───────────────►│                                         │         │
 │  └──────────┘  D$ AXI64(RW)  └┬──────┬──────┬──────┬──────┬──────┬──────┘         │
 │                             ROM   SRAM  CLINT  PLIC  sys_apb  media_  ddr_         │
 │                                                     │       apb_brg gateway       │
 │                                  UART GPIO I2C                   │       │          │
 │                                  CACHE_CTRL SYSCTRL             │       │          │
 │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─│─ ─ ─ ─ ─ │
 │  clk_mem 域                              media_apb（16 槽）◄──────┘       │ P2     │
 │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                             │        │
 │  │ VIN │ │DISP │ │NPU* │ │ RND │ │ GEO │ │ ETH │                             │        │
 │  │+PIX │ │     │ │     │ │     │ │     │ │     │                             │        │
 │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘                             │        │
 │     P1      P0      P3      P4      P5         P6                            │        │
 │  ┌──▼───────▼───────▼───────▼───────▼──────────▼───────────────────────────▼──┐     │
 │  │ mem_xbar  256 位 DDR 交叉开关，7 主 × 1 从                                    │     │
 │  └────────────────────────────────────┬────────────────────────────────────────┘     │
 └───────────────────────────────────────│──────────────────────────────────────────────┘
                                         ▼  DDR AXI256 主口（SoC 边界）
```

\* NPU 在独立的 clk_npu 域，与 mem_xbar、媒体 APB 之间经异步桥连接（5.2 X9、X10）。

### 2.2 子系统

| 子系统 | 组成 | 时钟域 | 本文章节 |
|---|---|---|---|
| CPU | EdRV32 核、I$、D$ | clk_sys | 8.1、8.2 |
| 系统总线 | sys_xbar、Boot ROM、SRAM、CLINT、PLIC、系统 APB 及外设 | clk_sys | 6.1、8.3 |
| 存储 | DDR 网关、mem_xbar、性能监视器 | clk_mem | 6.3–6.5、8.4 |
| 媒体 | VIN（采集 + PIX + NPU 输入适配）、GEO、RND、DISP | clk_mem、clk_pix、camN_pclk | 8.5–8.8 |
| NPU | YOLO 推理加速器 | clk_npu（与 clk_mem 之间的异步桥在 NPU 边界） | 8.9 |
| 网络 | ETH 引擎 | clk_mem、eth_rx_clk、eth_tx_clk | 8.10 |

### 2.3 架构原则

1. **控制面和数据面分离**：CPU 通过 APB 配置各引擎；像素、特征图、网络数据由引擎自己的 DMA 经 mem_xbar 访问 DDR。CPU 不搬运大块数据。
2. **引擎之间通过 DDR Surface 交接**：除 VIN 内部的流式通路外，模块之间不直接传数据，按第 7.3 节的 Surface 协议交接。
3. **DDR 统一仲裁**：所有 DDR 访问汇集到 mem_xbar，按第 6.4 节的规则保证实时流量。
4. **软件编排帧级流程**：帧级的启动、交接、释放由 CPU 响应中断来完成（第 7 节）。硬件保证帧内正确性和帧边界原子性。

---

## 3. SoC 顶层端口契约

`edrv32_soc_top` 的端口如下。所有输入在 SoC 内部同步到使用它的时钟域；双向 IO 在 SoC 边界拆成 `_o / _oe / _i` 三个信号，三态缓冲在 FPGA 层。

### 3.1 时钟与复位

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| `clk_sys_i` | in | 1 | CPU 和系统总线时钟，频率由 CPU 规格确定 |
| `clk_mem_i` | in | 1 | 125 MHz，必须与 DDR 控制器用户接口时钟同源同相 |
| `clk_pix_i` | in | 1 | 74.25 MHz 像素时钟（720p60） |
| `clk_npu_i` | in | 1 | NPU 时钟，频率由 NPU 规格确定 |
| `cam0_pclk_i`、`cam1_pclk_i` | in | 1 | 摄像头像素时钟 |
| `eth_rx_clk_i`、`eth_tx_clk_i` | in | 1 | 125 MHz，千兆 MAC 侧收发时钟 |
| `rst_n_i` | in | 1 | 全局异步复位，低有效 |
| `mem_ready_i` | in | 1 | DDR 控制器初始化完成，任意时钟域 |

### 3.2 DDR 主口（clk_mem 域，AXI256 规范见 4.2）

| 通道 | 信号 |
|---|---|
| AW | `ddr_awid_o[3:0]`、`ddr_awaddr_o[31:0]`、`ddr_awlen_o[3:0]`、`ddr_awvalid_o`、`ddr_awready_i` |
| W | `ddr_wdata_o[255:0]`、`ddr_wstrb_o[31:0]`、`ddr_wlast_o`、`ddr_wvalid_o`、`ddr_wready_i` |
| B | `ddr_bid_i[3:0]`、`ddr_bresp_i[1:0]`、`ddr_bvalid_i`（无 BREADY，SoC 必须随时接收） |
| AR | `ddr_arid_o[3:0]`、`ddr_araddr_o[31:0]`、`ddr_arlen_o[3:0]`、`ddr_arvalid_o`、`ddr_arready_i` |
| R | `ddr_rid_i[3:0]`、`ddr_rdata_i[255:0]`、`ddr_rresp_i[1:0]`、`ddr_rlast_i`、`ddr_rvalid_i`（无 RREADY，SoC 必须随时接收） |

地址是 DDR 物理字节地址，范围 0 至 1 GiB − 1。FPGA 层的适配器负责把它映射到控制器的地址格式。

### 3.3 视频

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `camN_vsync_i`、`camN_href_i` | in | 1 | camN_pclk | N = 0、1 |
| `camN_data_i` | in | 8 | camN_pclk | |
| `camN_pwdn_o`、`camN_rst_n_o` | out | 1 | clk_sys | 由 GPIO0 输出 bit12–15 驱动（3.5 位分配；系统子系统规格 2.7） |
| `i2c0_scl_o`、`i2c0_scl_oe_o`、`i2c0_scl_i`、`i2c0_sda_o`、`i2c0_sda_oe_o`、`i2c0_sda_i` | — | 2 | clk_sys | I2C0 的两对开漏引脚，下标 0 接 cam0、1 接 cam1（系统子系统规格 2.8） |
| `tmds_sym_o` | out | 3 × 10 | clk_pix | 依次为 B/G/R 三个通道的 TMDS 符号，FPGA 层负责 10:1 串化 |

### 3.4 网络（MAC 侧）

| 信号 | 方向 | 位宽 | 时钟域 |
|---|---|---|---|
| `eth_rxd_i`、`eth_rx_dv_i`、`eth_rx_er_i` | in | 8 / 1 / 1 | eth_rx_clk |
| `eth_txd_o`、`eth_tx_en_o`、`eth_tx_er_o` | out | 8 / 1 / 1 | eth_tx_clk |
| `eth_mdc_o`、`eth_mdio_o`、`eth_mdio_oe_o`、`eth_mdio_i` | — | 1 | clk_mem |
| `eth_phy_rst_n_o` | out | 1 | clk_mem |

RGMII 与上述 8 位单沿接口之间的转换在 FPGA 层完成。

### 3.5 系统外设与调试（clk_sys 域）

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| `uart0_tx_o`、`uart0_rx_i` | out / in | 1 | |
| `gpio_o`、`gpio_oe_o`、`gpio_i` | — | 16 | 位分配见下表；引脚由板级约束决定 |
| `debug_o` | out | [CPU 规格] | CPU 流水线观察向量，供 ILA 使用 |

GPIO0 位分配（板级顶层和软件必须一致）：

| 位 | 方向 | 用途 | 开发板（MES-PG2L676 Mini Base） |
|---|---|---|---|
| 0 | 输入 | KEY1，低有效；Boot ROM 的 BIOS 键（7.5） | USER_BUTTON1，C23 |
| 1–3 | 输入 | KEY2–KEY4，低有效 | USER_BUTTON2–4，B22、A22、B20 |
| 4–8 | 输出 | LED0–LED4，高电平点亮 | USER_LED0–4，A20、C18、C19、E18、A17 |
| 9–11 | — | 不使用 | — |
| 12 | 输出 | `cam0_pwdn_o` | 摄像头接口 |
| 13 | 输出 | `cam0_rst_n_o` | 摄像头接口 |
| 14 | 输出 | `cam1_pwdn_o` | 摄像头接口 |
| 15 | 输出 | `cam1_rst_n_o` | 摄像头接口 |

USER_BUTTON0（C22）是全局复位 `rst_n_i`，不接 GPIO。`camN_pwdn_o`、`camN_rst_n_o` 与 `gpio_o` 的对应位相同（3.3）。

---

## 4. 标准接口规范

模块之间只使用本节定义的接口。

### 4.1 AXI64：系统总线接口（clk_sys 域）

| 项 | 规定 |
|---|---|
| 信号 | AW：`awid awaddr awlen awsize awburst awvalid awready`；W：`wdata wstrb wlast wvalid wready`；B：`bid bresp bvalid bready`；AR：`arid araddr arlen arsize arburst arvalid arready`；R：`rid rdata rresp rlast rvalid rready` |
| 位宽 | 地址 32，数据 64，WSTRB 8，主设备 ID 4，LEN 8，SIZE 3，BURST 2 |
| 突发 | 只用 INCR。单拍访问：SIZE ≤ 2（≤ 4 B），按 `addr[2]` 选择 64 位总线的高/低半部。例外：I$ 的 ROM 取指为单拍 SIZE = 3（8 B，地址 8 B 对齐），Boot ROM 从设备必须支持。cache 行访问：SIZE = 3，LEN = 3（4 拍 × 8 B = 32 B），地址 32 B 对齐 |
| 不使用 | LOCK、CACHE、PROT、QOS、REGION、USER，也不支持 exclusive 访问 |
| 并发 | 每个主设备每个方向至多 1 笔未完成事务 |
| 响应 | OKAY；从设备错误回 SLVERR；地址未映射或连接矩阵禁止的访问，由交叉开关回 DECERR |
| 握手 | VALID 拉高后，在 READY 到来之前，VALID 和负载都必须保持不变；VALID 不得依赖 READY |

### 4.2 AXI256：DDR 数据面接口（clk_mem 域）

| 项 | 规定 |
|---|---|
| 信号 | 与 4.1 相同的五个通道，去掉 `awsize/awburst/arsize/arburst`（固定为 32 B/拍、INCR） |
| 位宽 | 地址 32（DDR 物理字节地址），数据 256，WSTRB 32，LEN 4（1–16 拍） |
| ID | 主设备的本地 ID 为 1 位；mem_xbar 在下游拼接 3 位端口号，形成 4 位 ID |
| 对齐 | 地址 32 B 对齐，一个事务不得跨 4 KiB 边界 |
| 字节使能 | 允许任意 WSTRB，用于行首和行尾的部分写 |
| 写响应 | B 响应表示写数据已被 DDR 控制器接收。DDR 子系统保证：其后发出的读请求一定能读到这次写入的数据。各引擎以最后一个 B 响应作为写完成栅栏 |
| 读数据 | 主设备的 RREADY 允许拉低；mem_xbar 用读返回缓冲吸收（见 6.4.4） |
| 紧急信号 | 实时主设备额外输出 `urgent_o`（clk_mem 域电平信号），由 FIFO 水位产生 |

### 4.3 APB：控制面接口

| 项 | 规定 |
|---|---|
| 协议 | AMBA APB4，信号为 `paddr[11:0] psel penable pwrite pwdata[31:0] pstrb[3:0] pready prdata[31:0] pslverr`（每个槽 4 KiB，从设备只看到槽内偏移） |
| 访问 | 只支持 32 位对齐访问。窄写由 `pstrb` 表示；寄存器块可以忽略 `pstrb` 对整个字操作，但必须在寄存器描述里注明 |
| 时钟 | 系统 APB 在 clk_sys 域；媒体 APB 在 clk_mem 域 |
| 超时 | 桥在 256 个 PCLK 内没有收到 `pready`，就回 SLVERR 并结束本次访问 |
| 从设备本地寄存（媒体 APB） | 媒体 APB 的从设备寄存器块（VIN、PIX、GEO、RND、DISP、NPU（clk_npu 侧，异步桥之后）、ETH、mem_xbar 寄存器块）必须在 setup 拍（`psel && !penable`）把 `paddr`、`pwrite`、`pwdata`、`pstrb` 存入本地寄存器；access 拍的地址译码、寄存器写入、写副作用和 `prdata` 选择只用本地寄存值。公共的 `paddr`/`pwdata` 在每个从设备内只接这组本地寄存器。访问周期数不变，软件无感。原因：公共地址/数据直接扇出到各引擎的译码和写入，单个位数千负载（设计记录 2026-10-31-b3f-area-timing） |

### 4.4 中断

- 每个中断源一条**电平**信号，高有效，在源模块自己的时钟域产生。
- PLIC 入口负责同步到 clk_sys。
- 引擎中断的含义固定为 `|(IRQ_STAT & IRQ_EN)`，见 7.1。

### 4.5 像素流接口（VIN 内部）

| 项 | 规定 |
|---|---|
| 信号 | `valid ready data sof eol eof` |
| 负载 | 每拍 2 个 RGB565 像素，`data[31:0]`，低 16 位是左边的像素 |
| 帧标记 | `sof` 标在一帧第一拍，`eol` 标在每行最后一拍，`eof` 标在一帧最后一拍 |
| 约束 | 行宽必须是偶数像素；配置变化只能在 `sof` 生效 |

---

## 5. 时钟与复位

### 5.1 时钟域

| 时钟 | 频率 | 包含的逻辑 |
|---|---|---|
| clk_sys | [CPU 规格] | CPU、sys_xbar、ROM、SRAM、CLINT、PLIC、系统外设、媒体 APB 桥的主侧、DDR 网关的 64 位侧 |
| clk_mem | 125 MHz | mem_xbar、DDR 网关的 256 位侧、媒体 APB 及全部媒体/ETH 引擎（另有规定的除外） |
| clk_pix | 74.25 MHz | DISP 的显示时序、扫描 FIFO 读侧、TMDS 编码 |
| clk_npu | [NPU 规格] | NPU 的计算、DMA 和寄存器块；AXI256 主口和 APB 从口的异步桥的 NPU 侧 |
| camN_pclk | 由摄像头决定 | VIN 采集前端，到异步 FIFO 为止 |
| eth_rx_clk / eth_tx_clk | 125 MHz | ETH 收发前端，到异步 FIFO 为止 |

所有时钟域两两异步，SoC 的功能不得依赖任何两个时钟之间的频率比或相位关系。

### 5.2 跨时钟域清单

| # | 起点 → 终点 | 内容 | 方式 |
|---|---|---|---|
| X1 | clk_sys → clk_mem | 媒体 APB | APB 异步桥 |
| X2 | clk_sys ↔ clk_mem | DDR 网关（AXI64） | AXI 异步桥，放在 64 位侧 |
| X3 | clk_mem、clk_npu → clk_sys | 媒体、ETH 中断（clk_mem），NPU 中断（clk_npu） | 电平同步 |
| X4 | camN_pclk → clk_mem | 采集像素 | 异步 FIFO |
| X5 | clk_mem → clk_pix | 显示像素（L0、L1 各一个扫描 FIFO）；DISP 扫描使能；DISP 停止确认请求；DISP 本帧扫描参数 | 异步 FIFO；电平同步；握手；握手 |
| X6 | clk_pix → clk_mem | DISP 帧请求；DISP 扫描侧仍可能发请求（scan_live）；两层的读空事件；两个扫描 FIFO 的读出计数、扫描侧性能计数 | 握手；电平同步；脉冲同步；格雷码 |
| X7 | eth_rx_clk → clk_mem，clk_mem → eth_tx_clk；eth_tx_clk → clk_mem | 网络帧；发送帧结束 | 异步 FIFO；脉冲同步（每帧一个脉冲，帧间隔远大于同步时间） |
| X8 | 任意 → 各域 | 复位释放、`mem_ready_i` | 复位同步器 / 电平同步 |
| X9 | clk_npu ↔ clk_mem | NPU DDR 主口（AXI256，mem_xbar P3） | AXI 异步桥，放在 NPU 边界 |
| X10 | clk_mem → clk_npu | NPU 寄存器（媒体 APB 槽 6） | APB 异步桥，放在 NPU 边界 |

新增跨时钟域必须先登记到本表。

### 5.3 复位

1. `rst_n_i` 拉低时，所有时钟域立即进入复位（异步置位）。
2. `rst_n_i` 释放后，各域的复位在本域时钟下同步释放，顺序如下：
   1. clk_mem 域等待 `mem_ready_i` 有效后释放 mem_xbar 和 DDR 网关的 256 位侧；
   2. 媒体、NPU、ETH 引擎释放，引擎在软件使能前保持空闲；
   3. clk_sys 域释放，CPU 从 `0x0000_0000` 开始执行。
3. SYSCTRL 提供软件复位：可以单独复位媒体子系统，或者复位整个 SoC（CPU 除外的部分加上 CPU）。
4. 存储阵列（cache、FIFO、RAM）不复位；它们的有效性由控制状态负责。
5. 复位副本：每个域的复位只在 reset_ctrl 中同步一次；使用方在子系统顶层经恰好一级寄存器副本（`edrv32_reset_copy`）按区域复制后使用。同一路复位的所有副本在同一个时钟沿释放，进入复位仍是异步的。跨域释放顺序以副本的释放为准（系统子系统规格 2.10）。

---

## 6. 地址映射与互连

### 6.1 地址映射

| 区域 | 基址 | 大小 | 可缓存 | 可执行 | 读 | 写 | 说明 |
|---|---|---|---|---|---|---|---|
| Boot ROM | 0x0000_0000 | 16 KiB | 否 | 是 | 是 | 否 | 复位入口 |
| SRAM | 0x1000_0000 | 64 KiB | 是 | 是 | 是 | 是 | 片上主存 |
| CLINT | 0x2000_0000 | 64 KiB | 否 | 否 | 是 | 是 | |
| PLIC | 0x3000_0000 | 4 MiB | 否 | 否 | 是 | 是 | |
| 系统 APB | 0x4000_0000 | 64 KiB | 否 | 否 | 是 | 是 | 16 槽 × 4 KiB |
| 媒体 APB | 0x4100_0000 | 64 KiB | 否 | 否 | 是 | 是 | 16 槽 × 4 KiB |
| DDR | 0x8000_0000 | 1 GiB | 是 | 是 | 是 | 是 | 物理地址 0 起 |
| DDR 非缓存别名 | 0xC000_0000 | 1 GiB | 否 | 否 | 是 | 是 | 与上一项为同一物理内存 |

- 访问未映射区域，或者违反该区域的属性（例如写 ROM、在非可执行区取指），CPU 产生对应的访问异常，不向总线发出请求。
- 地址映射以 `rtl/include/soc_address_map.json` 为唯一来源，RTL 和软件头文件都由它生成。

**系统 APB 槽位**（基址 + 槽号 × 0x1000）

| 槽 | 外设 | 槽 | 外设 |
|---|---|---|---|
| 0 | UART0 | 4 | I2C0 |
| 1 | GPIO0 | 5 | CACHE_CTRL |
| 2 | 预留 | 6 | SYSCTRL |
| 3 | 预留 | 7–15 | 预留 |

**媒体 APB 槽位**

| 槽 | 模块 | 槽 | 模块 |
|---|---|---|---|
| 0 | 预留 | 5 | DISP |
| 1 | VIN | 6 | NPU |
| 2 | PIX | 7 | ETH |
| 3 | GEO | 8 | MEM_XBAR |
| 4 | RND | 9 | 预留 |
| | | 10–15 | 预留 |

媒体 APB 预留槽（0、9–15）访问回 SLVERR。

**PLIC 中断源**

| 源号 | 来源 | 源号 | 来源 |
|---|---|---|---|
| 0 | 保留（无中断） | 8 | VIN |
| 1 | UART0 | 9 | PIX |
| 2 | GPIO0 | 10 | GEO |
| 3 | 预留 | 11 | RND |
| 4 | 预留 | 12 | DISP |
| 5 | I2C0 | 13 | NPU |
| 6 | CACHE_CTRL（D$ 写回错误） | 14 | ETH |
| 7 | 预留 | | |
| | | 15 | MEM_XBAR（错误、超时） |

预留槽的访问回 SLVERR，预留中断源接 0。CLINT 提供 `mtime`（每个 clk_sys 周期加 1）、`mtimecmp`（MTIP）和 `msip`（MSIP）；PLIC 提供 1 个 M 模式上下文（MEIP），共 15 个源、7 级优先级。细节见 `docs/spec/sys-subsys-spec.md`。

### 6.2 sys_xbar：系统 AXI 交叉开关

| 项 | 规定 |
|---|---|
| 主设备 | M0 = I$（只读），M1 = D$（读写） |
| 从设备 | S0 ROM、S1 SRAM、S2 CLINT、S3 PLIC、S4 系统 APB 桥、S5 媒体 APB 桥、S6 DDR 网关 |
| 连接 | M0 只能访问 S0、S1、S6；M1 可以访问全部从设备 |
| 仲裁 | 读、写通道分别独立做轮询 |
| 延迟 | M0/M1 访问 SRAM：从 ARVALID 被接收到第一个 RVALID 不超过 3 个 clk_sys 周期（无竞争时） |
| 错误 | 未映射、连接被禁止的访问回 DECERR，交叉开关自己完成响应，不得挂死 |

### 6.3 DDR 网关

| 项 | 规定 |
|---|---|
| 功能 | 把 AXI64 从口（clk_sys）转换为 AXI256 主口（clk_mem），接到 mem_xbar 的 P2 |
| 地址 | 0x8000_0000–0xBFFF_FFFF 和 0xC000_0000–0xFFFF_FFFF 都映射到 DDR 物理地址 `addr[29:0]` |
| 并发 | 读、写各至多 1 笔父事务在途 |
| 宽度转换 | 一个 32 B 的 cache 行正好是 256 位的一拍：AXI64 的 4 拍突发转换为一个单拍 AXI256 事务，WSTRB 全置位。单拍窄访问转换为单拍 AXI256 事务，WSTRB 只置对应字节 |
| CDC | 跨时钟域放在 64 位侧（X2） |

### 6.4 mem_xbar：DDR 交叉开关

#### 6.4.1 端口

| 端口 | 主设备 | 服务等级 | 方向 | 紧急信号 |
|---|---|---|---|---|
| P0 | DISP | RT（硬实时） | 读 | 有 |
| P1 | VIN（CH0、CH1、CH2 写，内存源读，在 VIN 内部仲裁） | RT（写）；内存源读不是实时 | 读写 | 有（只由摄像头写通道产生） |
| P2 | DDR 网关（CPU） | LAT（低延迟） | 读写 | — |
| P3 | NPU | BE（尽力而为，有保底份额） | 读写 | — |
| P4 | RND | SRT（软实时） | 读写 | — |
| P5 | GEO | SRT | 读写 | — |
| P6 | ETH | BEL（低优先级尽力而为，限速） | 读写 | — |

#### 6.4.2 调度

以**一个 AXI 事务**为调度粒度。读、写各自有请求队列，共享同一个 DDR 下游口。每次授权时按以下顺序选择：

1. **紧急**：`urgent_o` 有效的 RT 端口优先。同一端口在一次紧急期内最多连续授权 `URG_MAX` 个事务。
2. **低延迟**：P2 有请求，且限速令牌桶里有令牌。
3. **饿死保护**：等待时间超过 `STARVE_CYC` 的端口。
4. **加权轮询**：其余端口按权重 `WEIGHT[p]` 做赤字轮询（deficit round robin），计量单位是拍数。
5. **读写分组**：在不违反 1–3 的前提下，当前方向连续服务最多 `DIR_BATCH` 个事务后才切换方向。

写事务的 W 数据必须紧跟 AW 的授权顺序，不得交织。

#### 6.4.3 流量控制

| 项 | 规定 |
|---|---|
| 全局在途上限 | 下游在途事务（读 + 写）不超过 `OUTST_TOTAL` |
| 端口在途上限 | 每个端口的读、写在途数分别不超过 `OUTST_RD[p]` / `OUTST_WR[p]` |
| 限速 | P2、P6 用令牌桶限速，参数为 `RATE[p]`（占 DDR 下游拍数的比例上限） |
| 统计 | 每个端口：事务数、拍数、最长等待周期、累计等待周期、紧急授权次数。全局：读写换向次数、下游繁忙周期 |
| 错误 | 主设备违反 4.2 的规范（跨 4 KiB、LEN 超限、地址不对齐）时，丢弃该事务并回 SLVERR，记录到 MEM_XBAR 错误寄存器，并产生中断 |

#### 6.4.4 读返回缓冲

DDR 子系统的读数据不能反压。mem_xbar 必须为每个在途读事务预留完整的返回空间（最多 16 拍），读请求只有在缓冲 credit 足够时才能被授权。主设备可以对 R 通道施加反压，mem_xbar 在缓冲中暂存数据。

#### 6.4.5 参数复位值

| 参数 | P0 | P1 | P2 | P3 | P4 | P5 | P6 |
|---|---|---|---|---|---|---|---|
| `OUTST_RD` | 4 | 2 | 1 | 4 | 2 | 2 | 2 |
| `OUTST_WR` | 0 | 4 | 1 | 2 | 2 | 2 | 2 |
| `WEIGHT` | 4 | 4 | — | 3 | 2 | 2 | 1 |
| `RATE` | — | — | 10% | — | — | — | 5% |

全局参数复位值：`OUTST_TOTAL = 8`，`URG_MAX = 8`，`STARVE_CYC = 256`（2 µs），`DIR_BATCH = 4`。

所有参数由 MEM_XBAR 寄存器提供，运行时可写。复位值以本表为准，系统联调后由本规格统一修订。

### 6.5 DDR 访问规则（适用于所有 DDR 主设备）

1. 连续数据必须以 512 B 对齐的 16 拍事务访问。只有区域的首尾部分允许使用短事务。
2. Surface 和 NPU 缓冲区的基址必须按 4 KiB 对齐。
3. 不允许在 DDR 内整帧复制。Surface 只交换所有权。
4. 每个引擎的 DDR 访问都通过公共 2D DMA 单元（8.11）发出。

---

## 7. 模块间交互

### 7.1 引擎寄存器模型

所有引擎（VIN、PIX、GEO、RND、DISP、NPU、ETH、MEM_XBAR）都使用以下公共寄存器布局，偏移 0x100 以后是各模块私有寄存器，由模块规格定义。

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x000 | ID | RO | 模块规格 | [31:16] TYPE 模块类型码（等于媒体 APB 槽号），[15:0] VERSION 版本 |
| 0x004 | CTRL | RW | 0 | bit0 ENABLE，bit1 START（写 1 触发，读为 0），bit2 ABORT（写 1 触发，读为 0），bit3 SOFT_RST（写 1 触发，读为 0） |
| 0x008 | STATUS | RO | 0x2 | bit0 BUSY，bit1 IDLE，bit2 ERROR |
| 0x00C | IRQ_EN | RW | 0 | 中断使能，位定义与 IRQ_STAT 相同 |
| 0x010 | IRQ_STAT | RW1C | 0 | bit0 DONE，bit1 ERROR，bit2 FRAME，[31:8] 模块私有 |
| 0x014 | ERR_CODE | RO | 0 | 最近一次错误的代码，写 IRQ_STAT.ERROR 清零时一并清除 |
| 0x020 | DESC_BASE | RW | 0 | 描述符或命令列表的 DDR 物理地址（命令式引擎） |
| 0x024 | DESC_COUNT | RW | 0 | 描述符或命令条数 |
| 0x028 | DOORBELL | WO | — | 写入任意值启动执行描述符列表；读为 0 |
| 0x02C | DONE_COUNT | RO | 0 | 已完成的描述符或帧数（自增，回绕） |
| 0x040–0x07C | PERF[0..15] | RO | 0 | 性能计数器，定义由模块规格给出；模块规格没有定义的编号读为 0 |

规则：
- **复位值**：上表的复位值适用于所有引擎，模块规格另有规定的除外（例如 DISP 的 DONE_COUNT 等于 FRAME_CNT）。
- **只写寄存器**：访问类型为 WO 的寄存器（公共的 DOORBELL 和各模块私有的 WO 寄存器）读为 0。不使用的公共寄存器同样读为 0、写忽略。
- **ABORT**：引擎停止接收新工作，等待所有已发出的 AXI 事务全部完成后，回到 IDLE。ABORT 不得留下未完成的总线事务。
- **"下一帧生效"的寄存器**：采用影子寄存器，在模块规定的帧边界（SOF 或 VBlank）一次性生效，模块规格必须指明哪些寄存器属于这一类。
- **统计计数器打拍**：只用于统计的计数器（公共 PERF[0..15]、mem_xbar 统计计数器及其 SNAPSHOT/CLEAR、EDTM 采集的各项统计）必须先把事件寄存一拍再计数，计数相对事件滞后 1 个周期；SNAPSHOT、CLEAR 命令同样寄存一拍后作用于全部计数器。统计逻辑不得与功能逻辑处在同一条组合路径上。软件用于流程判定的功能计数（如 DONE_COUNT、CUR_DESC、FRAME_CNT、WINn_BYTES）不属于统计计数器，按模块规格；与功能计数同值的 PERF 编号（如 PIX 的 PERF0 与 DONE_COUNT）可直接读出该功能计数，不另设打拍计数器。CPU 的 HPM 计数已按 cpu-spec 7.1 滞后 1 周期。

### 7.2 两种工作模式

| 模式 | 引擎 | 行为 |
|---|---|---|
| 流式 | VIN、PIX、DISP | ENABLE 后持续运行。每完成一帧，置 IRQ_STAT.FRAME，并在状态寄存器中报告这一帧的缓冲索引和 frame_id |
| 命令式 | GEO、RND、NPU、ETH（发送） | 软件在 DDR 中准备描述符或命令列表，写 DESC_BASE/COUNT，再写 DOORBELL。执行完全部条目、最后一个写响应返回后，置 IRQ_STAT.DONE |

### 7.3 Surface 与帧交接

**Surface** 是 DDR 中一块二维图像缓冲区，由以下描述符定义：

| 字段 | 规定 |
|---|---|
| `base` | DDR 物理地址，4 KiB 对齐 |
| `stride` | 行跨度（字节），32 B 的整数倍 |
| `width`、`height` | 像素数，宽度为偶数 |
| `format` | 0 RGB565，1 ARGB8888（非预乘 alpha，`[31:24]` = α；设计记录 `2026-10-29-rnd-disp.md` 3.4），2 A8，3 INT8_C16（NPU 特征图），4 INT8_C4（NPU 首层输入），其余预留；INT8_C16、INT8_C4 的布局见 NPU 规格 2.2 |

**所有权状态**：`FREE → FILLING → READY → IN_USE → FREE`。

| 规则 | 说明 |
|---|---|
| R1 | 生产者只写 FILLING 状态的 Surface；消费者只读 READY 或 IN_USE 状态的 Surface |
| R2 | 生产者在一帧的**最后一个写响应返回后**，才能报告该 Surface 完成（变为 READY） |
| R3 | 正在被 DISP 扫描的 Surface 不得被任何模块写入 |
| R4 | 所有权状态由软件维护。硬件只负责：在帧边界锁存下一块 Surface 的地址；报告完成；报告释放 |
| R5 | 流式生产者（VIN）使用软件配置的 N 块（2 ≤ N ≤ 4）环形缓冲；软件可以把某块标为"占用"，生产者遇到占用的块就跳过它写下一块，所有块都被占用时丢弃本帧并计数 |
| R6 | frame_id 由 VIN 在每帧 SOF 时分配（32 位自增），在后续所有引擎的完成状态中原样传递 |

### 7.4 软件与硬件的数据一致性

硬件不维护 cache 一致性。软件必须遵守：

1. CPU 写入、引擎读取的数据：CPU 写完后执行 CACHE_CTRL 的范围 clean，等待完成，然后写 DOORBELL 或 START；或者直接通过非缓存别名写入。
2. 引擎写入、CPU 读取的数据：CPU 在引擎完成后，对相应范围执行 invalidate，再读取；或者通过非缓存别名读取。
3. APB 写与 DDR 数据的先后顺序，由第 1 条的"clean 完成后再写 APB"保证。

### 7.5 系统级流程

**启动流程**
1. Boot ROM 和 SRAM 的上电内容由 FPGA bitstream 中的存储初始化文件提供：ROM 中是 bootloader 和启动 logo，SRAM 中是应用程序（系统子系统规格 2.2）。
2. 复位释放后，CPU 从 Boot ROM 执行 bootloader：初始化必要的外设（UART 115200 8N1、GPIO），通过 UART 打印启动 logo（文字 "EdRV32" 的 ASCII 字符画）和启动信息，读 SYSCTRL 的 `MEM_READY`。启动信息至少包括：CHIP_ID、clk_sys 频率（SYSCTRL `CLK_SYS_HZ`）、ROM/SRAM 容量、I$/D$ 容量、`MEM_READY` 状态、bootloader 的构建信息（git commit、编译器版本）。
3. 打印启动信息后，bootloader 在 **[待定]** 100 ms 的窗口内反复采样启动按键 KEY1（GPIO bit0，低有效）：窗口内始终按下，或 SYSCTRL `SCRATCH0` 为下载请求值 `0x55415254`（读取后清零），进入 BIOS（第 3a 条）；否则跳转到 SRAM 中的应用程序执行。用户操作为按住 KEY1 按复位键。
3a. **BIOS**：在 Boot ROM 中运行，通过 UART 提供菜单，每个选择是以 Enter（CR、LF 或 CR LF）结束的一行。提示文字固定如下（每行以 CR LF 结尾，供 PC 端调试工具识别）：
   - 进入时打印 `BIOS: EdRV32`，随后打印菜单行 `BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud`；每个操作结束后重新打印菜单行（跳转运行除外）。
   - 多字节数值一律小端；地址和长度以字节计。"可加载范围"指 SRAM 基址至 SRAM 末尾 − 4 KiB（BIOS 栈），以及整个 DDR 可缓存区（6.1），但不含下面的 ETH 暂存区。
   - **烧录会话描述块**（`1`、`2` 共用）：u32 段数 N（1–16）、u32 入口地址，随后 N 组 {u32 目标地址, u32 长度}，共 8 + 8N 字节。PC 工具对 ELF 取每个可加载段（PT_LOAD，文件长度不为 0）的 `p_paddr`/`p_filesz` 和 `e_entry`；对不带地址的镜像（如 `.bin`）由用户在工具中指定烧录地址和入口地址。BIOS 不解析 ELF。
   - **检查**：每段长度 ≥ 1 且整段落在可加载范围内的一个区域中，入口地址 4 字节对齐且落在可加载范围内。任一项不满足时打印 `Load result: FAIL range`，不接收段数据，回到菜单。
   - **完成后自动跳转**：段数据全部就位后，把 D$ 中的数据全部写回、作废 D$ 中被外部写入区域的行，打印 `Load bytes: <十进制总字节数> segments: <N>`、`Load result: PASS`、`Run: 0x<8 位十六进制入口>`，等 UART 发送完毕，作废 I$（`fence.i`），关中断后跳转。SRAM 程序跳转后在复位时仍按第 3 条从 SRAM 启动。
   - `1` 串口烧录：打印 `UART load ready`；PC 收到完整的这一行后发送描述块，BIOS 检查通过后 PC 依次发送各段数据（按描述块中的顺序，每段恰好"长度"字节）。
   - `2` 网口烧录（只用于带 ETH 的工程，BIOS 不探测 ETH 是否存在）：
     - BIOS 配置 ETH：MAC `02:45:44:52:56:32`、IP `192.168.1.10`、接收端口 5000；释放 PHY 复位并初始化 PHY，等链路建立后打印 `ETH link: up` 和 `ETH load ready 192.168.1.10:5000`。在此之前把 D$ 全部写回并作废，保证 ETH 写入的 DDR 不被旧的 D$ 行覆盖。
     - 接收窗口（eth-spec 2.4）：窗口 2 基址为 DDR 物理基址，大小覆盖整个 DDR，DDR 段按"目标地址 − DDR 基址"作为偏移写入；窗口 3 为 ETH 暂存区，DDR 物理地址 `0x0A000000` 起 68 KiB：偏移 0 放描述块，偏移 `0x1000` 起放 SRAM 段（偏移 = `0x1000` + 目标地址 − SRAM 基址）。
     - PC 先发全部段数据，最后发描述块，描述块的最后一包置 `NOTIFY`。BIOS 收到窗口 3 的通知后检查描述块（同上），并比对 `WIN2_BYTES` = 全部 DDR 段长度之和、`WIN3_BYTES` = 8 + 8N + 全部 SRAM 段长度之和。
     - 一致时把 SRAM 段从暂存区拷入 SRAM，按"完成后自动跳转"执行；不一致时打印 `ETH load result: FAIL bytes win2=<十进制> expect=<十进制> win3=<十进制> expect=<十进制>`，清零窗口计数后继续等待 PC 整份重发。
     - 等待期间（含等链路），UART 收到任意一行即停止 ETH 接收、回到菜单。
   - `3` 从指定地址启动：打印 `Run address:`，随后一行输入 `0x` 开头的十六进制入口地址。
     - 地址必须 4 字节对齐并落在可加载范围内，否则打印 `Run result: FAIL address`。
     - 合法时打印 `Run: 0x<8 位十六进制地址>`，等 UART 发送完毕，作废 I$（`fence.i`），关中断后跳转。程序自己设置栈和运行环境（BSP 启动代码）。
   - `4` 切换波特率：打印 `Baud:`，随后一行输入 `115200`、`921600` 或 `2000000`。
     - 其他值打印 `Baud result: FAIL`。
     - 合法时以原波特率打印 `Baud result: <值>`，等 UART 发送完毕再改 `BAUD_DIV`，改完后等 100 ms 再用新波特率发送（留给 PC 切换串口设置）；此后的收发都用新波特率，复位后恢复 115200。
   - 其他输入打印 `Input error: type 1-4 then Enter`。
   - 不按 KEY1 复位时，按第 3 条正常启动，运行 SRAM 中的程序。SRAM 内容在复位键复位和软复位后保持，重新配置 bitstream 或断电后恢复为初始化文件内容。
   - DDR 程序不能跨复位启动：复位键会使 DDR 控制器重新初始化和校准，DDR 内容不保证保留，而且板上没有用于记住启动位置的非易失存储。DDR 程序每次复位后进入 BIOS 用 `1` 或 `2` 重新烧录。
3b. SRAM 应用程序每次启动都由启动代码从镜像中的初值副本恢复 `.data`、把 `.bss` 清零，保证复位后再次运行与第一次相同。
4. SRAM 中的默认应用程序是监控程序（monitor）：通过 UART 输出菜单，按用户输入的选项执行测试或跑分，结束后回到菜单。菜单项至少包括：
   - CoreMark：运行后输出 CoreMark 分数、CoreMark/MHz、计时周期数和迭代次数、CRC 校验结果、全部 HPM 事件计数及由其导出的 IPC 等指标、编译器版本和编译选项、ISA 字符串；
   - 外设测试：GPIO/LED、CLINT 定时器中断、I2C 两个端口的设备探测；具体测试项 **[待定]**，开发初值由监控程序任务给出，经用户确认；
   - 系统信息：同启动信息，外加 cache 配置和 HPM 事件列表。
5. 应用程序按需通过 ETH 加载 NPU 权重和图像资源到 DDR。

**S1 目标检测，每帧流程**
1. VIN 把摄像头帧写入底图环形缓冲，同时 NPU 输入适配把缩放后的输入写入 NPU 输入环形缓冲，完成后报告 FRAME（带 frame_id）。
2. 如果 NPU 空闲，CPU 用最新的输入缓冲启动 NPU（DOORBELL）；如果 NPU 正忙，本帧输入被覆盖（丢弃）。
3. NPU 完成后报告 DONE，检测结果写入 DDR 结果区。
4. CPU 读取结果，生成检测框和标签的绘制命令，交给 RND。
5. 图层合成把最新完成的底图和 UI 层送往 DISP；DISP 在 VBlank 切换到新帧，并报告释放上一帧的缓冲。

**S2 图像处理，每帧流程**
1. VIN 采集，PIX 内联处理后写入 DDR，报告 FRAME。
2. 如果启用了 GEO，CPU 提交 GEO 描述符（输入 = 刚完成的 Surface，输出 = 一块空闲 Surface），GEO 完成后报告 DONE。
3. 合成和显示同 S1 第 5 步。

**S3 图形界面**
1. CPU 运行 LVGL，脏区域的绘制命令由 RND 执行。
2. 合成和显示同 S1 第 5 步。

**ETH 数据下载**
1. CPU 配置 ETH 的本机地址、接收端口号和接收窗口（DDR 基址、大小）。
2. PC 发送的每个 UDP 包带窗口号和偏移，ETH 把数据直接写入窗口中的对应位置；一块数据的最后一个包带通知位，写完后 ETH 中断 CPU。
3. CPU 核对窗口的已写入字节数，必要时通过 ETH 发送确认或重发请求。

---

## 8. 模块功能规范

本节规定各模块对外的功能和契约。内部微结构由各模块规格定义。

### 8.1 CPU：EdRV32

| 项 | 规定 |
|---|---|
| ISA | RV32IM + Zicsr + Zicntr + Zifencei，只有 M 模式。C 扩展是否支持由 CPU 规格确定 |
| 微结构 | 顺序双发射 |
| 外部接口 | I$ AXI64 主口（只读）；D$ AXI64 主口（读写）；`irq_msip_i`、`irq_mtip_i`、`irq_meip_i`；`mtime_i[63:0]`；`debug_o` |
| 复位向量 | 0x0000_0000 |
| 异常 | 精确异常。支持非法指令、地址不对齐、访问错误、ECALL、EBREAK |
| 中断 | MSI、MTI、MEI；优先级 MEI > MSI > MTI |
| CSR | 机器模式 CSR（mstatus、misa、mie、mip、mtvec（direct 和 vectored 模式）、mscratch、mepc、mcause、mtval、mvendorid、marchid、mimpid、mhartid），mcycle、minstret 及其高半部，加 8 个 mhpmcounter 和对应的事件选择寄存器 |
| 性能目标 | CoreMark/MHz ≥ 3.6；CPU 核 + cache 控制 ≤ 10K LUT；最高频率 [CPU 规格] |
| [模块规格] | 流水级划分、配对规则、旁路、分支预测、C 扩展、HPM 事件编号、`debug_o` 定义 |

### 8.2 Cache

| 项 | I$ | D$ |
|---|---|---|
| 组织 | 2 路组相联，伪 LRU | 2 路组相联，伪 LRU |
| 容量和行大小 | 8 KiB，32 B 行 | 8 KiB，32 B 行 |
| 写策略 | — | 写回、写分配 |
| 缺失处理 | 阻塞式，一次 AXI64 4 拍突发 | 阻塞式；脏行先写回，再填充 |
| 非缓存访问 | 取指访问 ROM 时直接单拍读 | 访问设备和非缓存区域时直接单拍读写，按程序顺序执行 |
| 维护 | FENCE.I 使整个 I$ 无效 | CACHE_CTRL：按地址范围 clean / invalidate / clean+invalidate，以及整个 D$ 的 clean；完成状态可以查询 |
| FENCE.I 语义 | 先 clean D$，再 invalidate I$，然后重新取指 | |

容量最终以 CPU 规格的评估结论为准。

### 8.3 系统外设

| 模块 | 功能规范 |
|---|---|
| UART0 | 8N1，波特率可编程（最高不低于 3 Mbps），16 字节收、发 FIFO，中断：接收达到阈值、发送为空、溢出、帧错误 |
| GPIO0 | 16 位，每位方向可设；输入经同步和去抖（去抖时间可编程），可以按上升沿或下降沿触发中断；驱动摄像头 `pwdn`、`rst_n` |
| I2C0 | 主模式，100/400 kHz，支持 7 位地址、重复起始位；一个协议引擎、两对引脚（cam0、cam1），寄存器选择端口，用于摄像头 SCCB 配置 |
| CACHE_CTRL | 见 8.2 |
| SYSCTRL | 芯片 ID 和版本；clk_sys 频率 `CLK_SYS_HZ`；scratch 寄存器（软复位不清除）；`mem_ready` 状态；媒体子系统软复位和整 SoC 软复位；`SIM_EXIT` 寄存器（仿真平台据此结束仿真并判定结果，硬件上写入无副作用） |

### 8.4 存储子系统

- DDR 网关见 6.3，mem_xbar 见 6.4。

### 8.5 VIN：视频输入（含 PIX、NPU 输入适配）

| 项 | 规定 |
|---|---|
| 输入 | 2 路 DVP，RGB565，1280×720；内存源：从 DDR 读一张 RGB565 Surface（网口送来的图像），与摄像头帧走同一通路（设计记录 Q7） |
| 帧率 | 默认 30 fps，可为 60 fps。VIN 不区分帧率，帧时序由传感器决定；切换帧率由软件经 I2C 写入对应的传感器寄存器表 |
| 选路 | 每个通道可以选择 cam0、cam1 或内存源，在 SOF 生效 |
| 写通道 | 2 个独立的 Surface 写通道（CH0、CH1），各有独立的 FIFO、环形缓冲配置和状态。首版只要求 CH0 工作，CH1 硬件完整实现，为两路拼接预留；NPU 输入适配为 CH2 |
| PIX | 位于 CH0 路径上，可以旁路（见 8.6） |
| NPU 输入适配 | 从选定的一路摄像头流分出：缩放和 letterbox 到 NPU 输入尺寸，转换为 NPU 输入格式，写入 NPU 输入环形缓冲。允许丢帧：FIFO 满时丢弃该通道的本帧，不得反压摄像头和其他通道。输入尺寸 640×384，格式 INT8_C4（NPU 规格 2.2）；量化、缩放和 letterbox 在适配器内完成 |
| 实时性 | 任何负载下摄像头写通道都不得溢出。溢出时丢弃本帧，置错误标志并计数。内存源不是实时的：通道 FIFO 满时内存源暂停 |
| 端口 | P1 读写口，带 `urgent_o`；媒体 APB 槽 1；中断源 8 |
| 模块规格 | `docs/spec/vin-spec.md` |

### 8.6 PIX：像素处理

| 项 | 规定 |
|---|---|
| 位置 | VIN CH0 路径上，接口为像素流（4.5） |
| 吞吐 | 2 像素/拍 @clk_mem（250 Mpixel/s），满足 720p60 |
| 功能 | 固定顺序级联：点运算 1（亮度、对比度、Gamma 查表）→ 3×3 第一级 → 3×3 第二级 → 点运算 2（灰度、二值化、反色）。两级 3×3 各自可选 Sobel、均值、高斯、锐化、腐蚀、膨胀。每一级可以单独旁路（设计记录 `2026-10-27-image-path.md` Q1） |
| 边界 | 输出像素数和输入相同，边界补零 |
| 配置 | 影子寄存器，在 SOF 生效 |
| 端口 | 无 DDR 端口；媒体 APB 槽 2；中断源 9（帧完成；PIX 没有错误条件） |
| 模块规格 | `docs/spec/pix-spec.md` |

### 8.7 GEO：几何变换

| 项 | 规定 |
|---|---|
| 功能 | 输入 Surface 经仿射变换（旋转、缩放、平移、镜像、错切）后写入输出 Surface 中的一个矩形，采用双线性插值，RGB565；均匀缩小上限为源尺寸 ÷ 输出尺寸 ≤ 2 |
| 模式 | 命令式，一个描述符完成一帧（输入、输出 Surface 描述符，输出矩形，逆映射矩阵，背景色）；矩阵由软件计算 |
| 性能 | 输出 1280 × 720、任意角度：缩放 s ≤ 1 时单帧不超过 16.7 ms，1 < s ≤ 2 时不超过 33 ms（测量条件见模块规格） |
| 端口 | P5；媒体 APB 槽 3；中断源 10 |
| 模块规格 | `docs/spec/geo-spec.md` |

### 8.8 RND 渲染器与 DISP 显示

**RND**

| 项 | 规定 |
|---|---|
| 功能 | 执行 DDR 中的命令列表，在 Surface 上绘制，作为 LVGL 等图形库的绘制后端，并支持瓦片和精灵类游戏。命令：FILL（纯色、线性渐变、圆角）、BORDER、GLYPH（A1/A2/A4/A8 着色）、BLIT（格式转换、透明度、重新着色、颜色键、最近邻缩放、翻转、正常/相加/相减/相乘混合）、COPY、BOX_SHADOW、BLUR、TILEMAP。目标格式 RGB565、ARGB8888；源格式另含 A1–A8、索引色。线、弧、三角、矢量、任意角度旋转不由 RND 实现（设计记录 `2026-10-29-rnd-disp.md` 4.2） |
| 图层合成 | 不在 RND：由 DISP 扫描时两层叠加（见下方 DISP 层数）。RND 只绘制 |
| 端口 | P4；媒体 APB 槽 4；中断源 11 |
| [模块规格] | 命令格式、像素流水吞吐（`docs/spec/rnd-spec.md`） |

**DISP**

| 项 | 规定 |
|---|---|
| 输出 | 1280×720 @60 Hz，CEA-861 时序，TMDS 编码后输出符号 |
| 扫描 | 从 READY 的显示 Surface 按行读取。新 Surface 只在 VBlank 生效；切换后通过状态寄存器和中断报告上一块 Surface 已释放 |
| 实时性 | 扫描 FIFO 至少能容纳 2 行；低于 1 行时 `urgent_o` 有效；任何负载下不得读空。读空时输出黑像素，计数并置错误标志 |
| 无新帧 | 重复显示当前 Surface |
| 层数 | 两层，扫描时逐像素叠加：底图层 L0（RGB565，不透明，可开窗偏移实现卷轴）在下，UI 层 L1（ARGB8888 非预乘，位置、大小、全局透明度可设）在上；两层各自开关、各自在帧边界切换并报告释放 |
| 端口 | P0 读口，带 `urgent_o`；两层全屏打开时实时读 332 MB/s；媒体 APB 槽 5；中断源 12 |
| 模块规格 | `docs/spec/disp-spec.md` |

### 8.9 NPU：YOLO 推理加速器

| 项 | 规定 |
|---|---|
| 功能 | 执行 YOLOv8n 推理所需的算子：卷积（1×1、3×3，步长 1/2）、逐元素加、最大池化、上采样、通道拼接（零拷贝），以及 INT8 量化和激活 |
| 模式 | 命令式，描述符驱动：每个描述符描述一个算子（类型、输入/输出/权重/量化参数地址、形状）。权重、特征图和工作区的地址全部由软件分配 |
| 精度 | INT8 权重和激活，INT32 累加，每通道量化 |
| 性能 | 640×384 输入，卷积部分（不含后处理）≥ 20 fps，测量条件见 NPU 规格 7 |
| 端口 | P3；媒体 APB 槽 6；中断源 13 |
| 时钟 | clk_npu（5.1），跨时钟域 X9、X10 |
| 后处理 | DFL 解码和 NMS 由 CPU 软件完成，与 NPU 跨帧并行 |
| 模块规格 | `docs/spec/npu-spec.md`：MAC 阵列、描述符格式、特征图布局、寄存器、资源预算 |

### 8.10 ETH：以太网引擎

| 项 | 规定 |
|---|---|
| 物理接口 | 千兆 MAC 侧 8 位接口（3.4），MDIO 管理 |
| 速率 | 只支持 1000 Mbps 全双工 |
| 接收 | 存储转发，校验以太网 FCS 和 IP/UDP 校验和；目的端口匹配的 UDP 包，按载荷开头应用头中的窗口号和偏移，把数据直接写入 DDR 中 4 个接收窗口之一；带通知位的包写完后中断 |
| ARP | 硬件应答询问本机 IP 的 ARP 请求；其他帧（ICMP 等）丢弃并计数 |
| 发送 | 命令式：每条发送描述符指定 DDR 中一块数据，硬件切成多个 UDP 包（每包 1024 字节数据，带应用头）发给软件配置的对端；硬件记录最近一个接收包的源地址供软件使用 |
| 吞吐 | 接收、发送持续速率都不低于 100 MB/s |
| 端口 | P6；媒体 APB 槽 7；中断源 14 |
| MDIO | MDIO 主控和 PHY 复位在 ETH 寄存器块中（clk_mem 域） |
| 模块规格 | `docs/spec/eth-spec.md` |

### 8.11 公共 2D DMA 单元

所有引擎的 DDR 访问都通过两个公共单元发出：

| 单元 | 输入 | 输出 | 规定 |
|---|---|---|---|
| `dma2d_rd` | 读描述符 `{base, stride, width_bytes, height}` | 256 位数据流，带行首、行尾、帧尾标记 | 自动拆分为符合 4.2 的事务：首尾对齐、最长 16 拍、不跨 4 KiB；可以配置在途上限 |
| `dma2d_wr` | 写描述符和 256 位数据流加字节使能 | AXI256 写事务 | 同上；最后一个写响应返回后给出 `done` |

引擎内部有多个访问客户端时，先在引擎内仲裁，再汇入该引擎的 mem_xbar 端口。

---

## 9. 性能与资源指标

### 9.1 DDR 带宽

DDR 有效带宽的规划值 B_eff = 2.6 GB/s，待实测。各场景的持续流量必须不超过 0.75 × B_eff：

| 场景 | 持续流量规划值 |
|---|---:|
| S1 目标检测 | ≤ 1.5 GB/s |
| S2 图像处理（60 fps） | ≤ 0.75 GB/s |
| S3 图形界面 | ≤ 0.6 GB/s |

S2 使用内存源时另加内存源读：720p30 约 55 MB/s（60 fps 约 110 MB/s），仍在 S2 规划值内。

推导过程见 DDR 带宽分析文档。

### 9.2 实时性

- 三个场景下，DISP 不得读空，VIN 摄像头写通道不得溢出。
- 正常负载下紧急授权次数应接近 0。

### 9.3 资源预算（LUT）

| 模块 | 上限 |
|---|---:|
| CPU 核 + cache 控制 | 10K |
| 系统总线 + 外设 + CLINT/PLIC | 5K |
| DDR 网关 + mem_xbar | 8K |
| VIN + PIX + DISP | 12K **[待定]** |
| GEO | 8K |
| RND | 10K **[待定]** |
| ETH | 5K |
| NPU（含输入适配） | 50K |
| **合计** | **108K** |

DRM 和 APM 的预算由各模块规格确定。

---

## 10. 待各模块规格确定的事项

| 模块 | 事项 |
|---|---|
| CPU | 频率目标、流水级划分、配对规则、C 扩展、HPM 事件、`debug_o` |
| Cache | 最终容量 |
| mem_xbar | 依据 DDR 有效带宽实测结果修订 6.4.5 的参数复位值 |

## 11. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-25 | v0.1 | 初稿 |
| 2026-10-25 | v0.2 | PLIC 源号 6 分配给 CACHE_CTRL（D$ 写回错误中断），见 cpu-spec 4.7、cache 规格 |
| 2026-10-25 | v0.3 | 4.1 单拍 SIZE ≤ 2 增加例外：I$ 的 ROM 取指为单拍 SIZE = 3（K-RTL 开发中发现与 cache-spec 5.1 冲突） |
| 2026-10-25 | v0.4 | 系统子系统规格讨论（用户确认）：去掉 QSPI0 和 TIMER0（APB 槽 2、3，PLIC 源 3、4 改为预留，删除对应顶层端口）；PLIC 15 个源；mtime 每个 clk_sys 周期加 1，SYSCTRL 增加 CLK_SYS_HZ；I2C0 一个主机两对引脚；启动流程改为 ROM/SRAM 由存储初始化文件提供上电内容 |
| 2026-10-25 | v0.5 | 7.5 按用户要求细化启动软件：bootloader 初始化外设后打印 "EdRV32" logo 和启动信息；SRAM 默认应用为带 UART 菜单的监控程序（CoreMark 跑分并输出 HPM、跑分、工具链信息；外设测试；系统信息） |
| 2026-10-26 | v0.6 | 6.1 地址表 SRAM 容量由 256 KiB 改为 64 KiB（用户确认，见系统子系统规格 v0.3） |
| 2026-10-27 | v0.7 | 随 NPU 规格 v0.1 同步（用户确认，见 `docs/design/2026-10-26-npu-architecture.md` Q2、Q5、Q7）：2.2、3.1、5.1 增加 clk_npu，clk_mem 不再包含 NPU；7.1 公共寄存器适用范围不限于 clk_mem 域；5.2 X3 增加 clk_npu 中断源，新增 X9、X10；7.3 增加 INT8_C4；8.5 NPU 输入尺寸和格式；8.9 时钟、后处理分工、性能指标改引 NPU 规格；10 节 NPU 事项关闭 |
| 2026-10-27 | v0.8 | 图像通路方案（用户确认，见 `docs/design/2026-10-27-image-path.md`）：8.6 PIX 改为两级 3×3 的固定级联并增加 Gamma 查表；8.8 DISP 图像通路阶段为单层扫描；1.2 S2 注明本阶段全屏显示 |
| 2026-10-27 | v0.9 | 图像通路 VIN/DISP 规格（用户确认，设计记录 `2026-10-27-image-path.md` Q7、Q8）：5.2 X5 增加 DISP 扫描使能，X6 改为 DISP 帧请求、读空事件和计数；6.4.1 P1 改为读写（内存源读），6.4.5 P1 `OUTST_RD` = 2；8.5 增加内存源、CH2，帧率不再由 VIN 寄存器切换；8.5、8.8 引用模块规格；9.1 增加内存源流量 |
| 2026-10-27 | v0.10 | 5.2 X5、X6：DISP 帧请求改为握手同步，增加扫描侧 scan_live 电平和 clk_mem → clk_pix 停止确认握手，消除软复位/ABORT 时帧请求仍在跨域途中的窗口（用户确认，V-R2 问答；`disp-spec.md` v0.2 2.8） |
| 2026-10-28 | v0.11 | 8.6：PIX 中断源 9 只报帧完成，PIX 没有错误条件；模块规格见 `pix-spec.md`（用户确认） |
| 2026-10-28 | v0.12 | 8.7：GEO 写入输出 Surface 中的矩形，矩阵由软件计算，均匀缩小上限 s ≤ 2，性能按 s ≤ 1 / s ≤ 2 分档；模块规格见 `geo-spec.md`（用户确认） |
| 2026-10-28 | v0.13 | 3.4：MDIO 和 PHY 复位改为 clk_mem 域（在 ETH 寄存器块中）；8.10：接收改为按应用头写入 4 个窗口，硬件应答 ARP、其他帧丢弃，发送按描述符硬件分包，收发吞吐都 ≥ 100 MB/s；第 9 节 ETH 下载流程相应修改；第 10 节删除 ETH 行；模块规格见 `eth-spec.md`（用户确认，设计记录 `2026-10-28-eth.md`） |
| 2026-10-28 | v0.13 | 澄清（V-R5 问答，不改变已确认的行为）：5.2 X7 增加 eth_tx_clk → clk_mem 的发送帧结束脉冲 |
| 2026-10-28 | v0.14 | 7.5 启动流程：按键/SCRATCH0 下载请求改为进入 BIOS（Boot ROM 中的 UART 菜单，第一项烧录 SRAM 程序，完成后写回 D$，按复位运行），取代原来的下载后立即跳转；KEY1 采样窗口初值 100 ms；SRAM 应用每次启动恢复 `.data`、清零 `.bss`；启动信息不再报告启动方式（程序总是从 SRAM 启动）。原因：用户上板后要求不重新生成 bitstream 即可更换并反复运行 SRAM 程序（用户确认 2026-10-28） |
| 2026-10-28 | v0.15 | 6.1：媒体 APB 槽 0（原 MEDIA_CTRL，无寄存器定义、无使用者）改为预留，访问回 SLVERR（用户确认 2026-10-28，B2-1 准备时发现）；NPU 复位 `rst_npu_n` 由 reset_ctrl 产生（sys-subsys-spec v0.4 2.10） |
| 2026-10-29 | v0.15 | 3.3、3.5：固定 GPIO0 位分配（bit0–3 KEY1–4、bit4–8 LED0–4、bit12–15 两路摄像头 pwdn/rst_n），接上开发板全部 4 个用户按键和 5 个 LED（用户确认 2026-10-29，B2-1a 问答） |
| 2026-10-29 | v0.15 | 澄清（B2-1a 问答，不改变行为）：3.3、3.4 的三态缩写写全为 `_o`、`_oe_o`、`_i`，与系统子系统、ETH 端口一致 |
| 2026-10-29 | v0.16 | RND/DISP（设计记录 `2026-10-29-rnd-disp.md`，用户决定 Q1–Q4）：1.2 三个场景改为 DISP 两层叠加（S3 LVGL 画在 L0）；5.2 X5/X6 增加 L1 扫描 FIFO 和本帧扫描参数握手；7.3 format 1 改为非预乘 ARGB8888；8.8 RND 命令集 T2、图层合成由 DISP 完成、DISP 两层；9.3 VIN+PIX+DISP 12K [待定]、RND 10K [待定]，按 B3 PDS 实测定稿；第 10 节删去 RND/DISP 行（用户确认 2026-10-29） |
| 2026-10-29 | v0.16 | 寄存器复位值回填（B2-1f 调查 `docs/reports/2026-10-29-regs-reset-survey.md`，与 RTL 一致，用户确认 2026-10-29）：7.1 公共寄存器表增加复位值列；ID 位域命名 TYPE/VERSION；WO 寄存器、未定义的 PERF 编号读为 0 |
| 2026-10-29 | v0.17 | 7.5 第 3a 条 BIOS 升级：增加 `2` 加载到指定地址（SRAM 或 DDR，可多段）、`3` 从指定地址启动、`4` 切换波特率（115200/921600/2000000），菜单行和提示文字相应修改；明确 DDR 程序不能跨复位启动。原因：B3 的 LVGL 和游戏放不进 64 KiB SRAM，需要在 DDR 运行（用户确认 2026-10-29） |
| 2026-10-31 | v0.22 | 7.5 第 3a 条 BIOS `4` 切换波特率：改 `BAUD_DIV` 后等 100 ms 再用新波特率发送。原因：卡 23 B3N 上 2 Mbaud 切换后菜单乱码，PC 收完结果行再改串口设置存在 USB/调度延迟（T-BIOSETH 调试记录 2026-11-01-bios-eth-load）（用户确认 2026-10-31） |
| 2026-10-31 | v0.21 | 4.3 新增“从设备本地寄存（媒体 APB）”：媒体 APB 从设备在 setup 拍寄存 paddr/pwrite/pwdata/pstrb，access 拍只用本地值，周期数不变。原因：B3VN 中 `media_apb_paddr[2]` 1851 负载（1229 未布通）、`[3]` 1446（889 未布通）（设计记录 2026-10-31-b3f-area-timing T1）（用户确认 2026-10-31） |
| 2026-10-31 | v0.20 | 5.3 新增第 5 条复位副本：每域只在 reset_ctrl 同步一次，子系统顶层经一级寄存器副本按区域复制，同一路复位同拍释放，跨域顺序以副本为准。原因：复位网络扇出数千，B3VN 布线失败（系统子系统规格 v0.5 2.10，设计记录 2026-10-31-b3f-area-timing）（用户确认 2026-10-31） |
| 2026-10-31 | v0.19 | 删除 PERF_MON：结构图、媒体 APB 槽 9 改为预留、P6 由 ETH 独占、7.1 引擎列表、模块简述、ETH 端口行。原因同 mem-subsys-spec v0.6（用户确认 2026-10-31） |
| 2026-10-31 | v0.19 | 7.1 新增“统计计数器打拍”规则：统计计数器事件与 SNAPSHOT/CLEAR 寄存一拍后作用，功能计数及其 PERF 别名不受影响。原因：统计逻辑串入功能组合路径（卡 21/22 路径与扇出分析，设计记录 2026-10-31-b3f-area-timing T2）（用户确认 2026-10-31） |
| 2026-10-31 | v0.18 | 7.5 第 3a 条 BIOS：菜单改为 `1=UART load 2=ETH load 3=Run 4=Baud`；串口和网口共用烧录会话描述块（段数、入口、各段地址/长度），烧录地址和入口可由用户指定；SRAM、DDR 程序烧录完成后自动跳转；网口烧录用 ETH 窗口 2（DDR 直写）和窗口 3（描述块 + SRAM 暂存，DDR 物理 0x0A000000 起 68 KiB），以 WINn_BYTES 比对判定完整性，不一致时等 PC 整份重发；取代原 `1` 烧录 SRAM（按复位运行）和 `2` 单段加载。3b 删除"ETH 下载在 ETH 模块完成后加入"。原因：用户要求可选串口/网口烧录、手动指定地址、烧录后自动跳转（用户确认 2026-10-31） |
