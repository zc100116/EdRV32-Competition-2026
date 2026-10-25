# 设计记录：EdRV32 SoC 总体架构重构决策

> 状态：**已决定**（2026-10-25）。本文是决策过程的记录，不是规格。
> 结论已经分别写入：系统规格 `docs/spec/edrv32-soc-spec.md`；开发规则（目录、工具、IP、仿真、任务交接）`CLAUDE.md`。
> 本文与上述文件冲突时，以上述文件为准。

- 日期：2026-10-25（v0.1 写于 2026-10-24）
- 状态：**讨论/规划稿，不是正式 spec**。本文用来逐项确定架构决策。全部确认后，按第 15 节拆分成 `docs/spec/` 下的正式规范；本文归档到 `docs/design/`，作为决策记录。
- 配套文档：《DDR 带宽与流量控制规划》`ddr-bandwidth-plan-v0.1.md`
- 范围：只包括 SoC 层，FPGA 板级层（PLL、DDR PHY/IP 本体、TMDS 串化原语、RGMII IO、引脚约束）不在范围内。SoC 内用到的存储器、乘法器等硬件资源，都要提供 FPGA IP 后端和 RTL 行为模型，用宏切换。
- 标记：**[保留]** 沿用旧设计；**[重构]** 保留目标但换实现；**[新增]**；**[删除]**；**[模块阶段]** 留到对应模块的 spec 讨论时再定。

---

## 0. 已确认的决策

| # | 决策 | 日期 |
|---|---|---|
| D1 | CPU **保留顺序双发射，重写并精简** | 10-24 |
| D2 | C 扩展在评估阶段可选，实测选定后**删掉这个参数** | 10-24 |
| D3 | **参数收敛原则**：探索用的配置参数在决策后必须删除。最终 RTL 只保留真正需要的参数 | 10-24 |
| D4 | 显示合成方式、渲染器和 NPU 的内部结构，**留到模块阶段**再定 | 10-24 |
| D5 | **单 bitstream 包含全部功能**。一个演示程序分三个场景：YOLO 识别、图像处理、渲染器（LVGL）。所有场景都经过渲染器的图层叠加输出。带宽按场景预算 | 10-24 |
| D6 | **删除 ITCM/DTCM** | 10-25 |
| D7 | 两路摄像头**只做采集和选路**，不做双目深度，删除 STEREO 槽位。**预留两路独立的 DDR 写通道**，为以后两路拼接打基础 | 10-25 |
| D8 | 输入设备：**GPIO 板载按键 + 上位机串口控制**。删除 PS/2 | 10-25 |
| D9 | **新增 ETH 引擎**（千兆 RGMII，硬件 UDP ↔ DDR DMA），用于下载权重和测试图、回传结果；SPI flash 和 UART 也保留 | 10-25 |
| D10 | NPU 是**描述符驱动**的命令式引擎；内部结构（MAC 规模、后处理分工、时钟域）留到模块阶段 | 10-25 |
| D11 | clk_sys **不预设频率**。CPU 阶段先在 PG2L200H 上实测基本单元的时序，再定流水划分和频率目标。规划中暂用 150 MHz 估算 | 10-25 |
| D12 | 仿真用 **Verilator 为主、Icarus 补充**；RTL 用 **Verilog-2001**。需要 ModelSim、PDS 或上板的工作，写成**Windows 任务卡**交给 Windows 端的 agent 执行 | 10-25 |
| D13 | 首版**不做通用系统 DMA** | 10-25 |
| D14 | IP 用 **PDS IP Compiler 手动生成**。每个 IP 一个包装模块，内部用 `ifdef FPGA_MODE` 宏切换 IP 和行为模型。**业务 RTL 不写 ifdef**；仿真和综合用**同一份文件列表** | 10-25 |
| D15 | 旧代码整体移入 `legacy/`，**不做分支或 tag 处理**，直接在新的 `rtl/` 下工作 | 10-25 |
| D16 | 仿真分**单元级、模块级、SoC 级**三层；带 CPU 的仿真要规范软件加载 | 10-25 |
| D17 | 摄像头默认 **720p30**，寄存器可切到 **60 fps**；显示输出 720p60 | 10-25 |
| D18 | YOLO 帧率**尽量高**，先按约 15 fps 预算，NPU 阶段细化 | 10-25 |
| D19 | DDR 交叉开关用 **7 个主设备端口**，见 7.4 和带宽规划第 6 节 | 10-25 |

---

## 1. 对旧设计的评估

### 1.1 保留的部分

| 内容 | 理由 |
|---|---|
| 控制面和数据面分离："APB 传命令，DMA 搬数据，DDR 统一仲裁" | 方向正确 |
| 拓扑：CPU → 64 位系统 AXI → APB；64 位 → 网关 → 256 位多主单从 DDR AXI | 和你的设计意图一致 |
| DDR 双视图：`0x8000_0000` 可缓存，`0xC000_0000` 非缓存别名；软件维护一致性 | 代价最低 |
| 256 位 DDR 事务：1–16 拍，32 B 对齐，不跨 4 KiB，INCR | 与 DDR IP 一一对应（IP 的突发长度字段只有 4 位） |
| DDR 仲裁思路：urgent/饿死保护 → 等级 → 加权轮询，以突发为粒度 | 合理，在带宽规划里细化 |
| 帧缓冲（Surface）所有权协议，以及"最后一个写响应回来后才发布 READY" | 正确且必要 |
| 地址映射以 JSON 为唯一来源，自动生成头文件 | 扩展到寄存器描述 |
| `FPGA_MODE` / `SIM_MODE` 宏和"两个都定义就报错"的机制 | 按 D14 统一使用 |
| CLINT + PLIC，只有 M 模式 | 保留 |
| 验证过的小模块和算法：UART、异步 FIFO、复位同步、AXI 异步桥、TMDS 编码器、OV5640 采集、Pixel 3×3 窗口、YOLO MAC 阵列和量化器 | 作为参考或移植，要经过新规范评审 |

### 1.2 需要重构的部分

**CPU**

- 标量 8 级：100 MHz，2.805 CoreMark/MHz，**20,842 LUT**。双发射只把 CoreMark/MHz 提升到 3.115（+11%），频率仍是 100 MHz。
- 级数多，却没有换来频率。
- 顺序核里放了乱序核的机制：各级弹性 FIFO、epoch、LQ/SQ、提交缓冲、寄存式重定向。cache 却是阻塞的，这些机制换不来吞吐。
- 在 FPGA 上手写门级加法器和 Wallace 树。
- HPM 有 40 个 64 位计数器加 98 种事件。
- 板上 CoreMark 用的是 `-O2` 编译。

**SoC**

- 集成层缺失：视觉模块的数据通路不在 `soc_top` 里；有三套独立的 HDMI/DDR 子系统。
- 50 个视觉 RTL 文件各自实现 AXI 主设备。
- 控制面跨时钟域做法不统一。
- YOLO 网络程序和地址硬编码，没有寄存器接口，也没有中断。
- 摄像头用硬件 ROM 做 SCCB 初始化。
- 文档、源码、仿真散乱。

---

## 2. 设计目标与约束

### 2.1 目标（按优先级）

1. 比赛 CPU 指标：CoreMark/MHz、Fmax、CoreMark/LUT 三项一起优化。
2. 比赛应用指标：YOLO 的识别率、延迟和帧率；模型部分的资源、时序和频率。
3. 完整的单 bitstream 演示（D5），画面流畅不卡顿。
4. 工程质量：模块化、时序约束、注释、可复现的回归、ILA 流水线效率分析。

### 2.2 平台约束

- PG2L200H：约 160K LUT，415 个 DRM，740 个 APM。
- DDR3：2 × x16，共 32 位，1000 MT/s，1 GB；UI 是 256 位 @125 MHz；理论 4.0 GB/s，规划用有效带宽 2.6 GB/s。
- 两路 OV5640；HDMI 输出；RTL8211F 千兆网口（RGMII）；2 × 16 MB QSPI flash；板载按键和 LED；UART。

### 2.3 非目标

乱序执行、寄存器重命名、MMU/S/U 模式、PMP、浮点、原子指令、JTAG 调试模块、硬件 cache 一致性、双目深度、为未来功能预留空端口。D7 的双写通道是明确要求的例外。

---

## 3. SoC 总体架构

```
                    ┌──────────────────────────── edrv32_soc_top ─────────────────────────────┐
 clk_sys 域         │ ┌───────────────┐                                                       │
                    │ │ EdRV32 CPU    │ I$ ── AXI64 只读      D$ ── AXI64 读写                 │
                    │ └──────┬────────┘                                                       │
                    │ ┌──────▼─────────────────────────────────────────────────┐              │
                    │ │ sys_xbar：64 位系统 AXI，2 个主设备                       │              │
                    │ └─┬──────┬──────┬──────┬─────────────┬──────────────┬─────┘              │
                    │  ROM   SRAM  CLINT  PLIC    系统 APB(clk_sys)   媒体 APB 桥  DDR 网关     │
                    │                         UART GPIO SPI TIMER      (异步)    (CDC 在     │
                    │                         I2C CACHE_CTRL SYSCTRL      │      64 位侧)     │
 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─┤
 clk_mem 域         │                                   媒体 APB(clk_mem)▼        64→256 ▼    │
 (125 MHz)          │ ┌───────────────────────────────────────────────────────────────────┐   │
                    │ │ VIN：cam0/cam1 采集 → PIX（内联）→ 写通道 ×2 + NPU 输入适配写   →P1 │   │
                    │ │ DISP：扫描读 + 图层（合成方式在模块阶段定）                        →P0 │   │
                    │ │ RND 渲染器 →P4    GEO 几何 →P5    NPU →P3    ETH + 性能监视器 →P6  │   │
                    │ └───────────────────────────────────────────────────────────────────┘   │
                    │ ┌───────────────────────────────────────────────────────────────────┐   │
                    │ │ mem_xbar：256 位，7 主 1 从；QoS / urgent / 限流 / 读写分组 / credit │◄─P2│
                    │ └───────────────────────────────┬───────────────────────────────────┘   │
                    └─────────────────────────────────│───────────────────────────────────────┘
                                                      ▼ 256 位 AXI 主口（SoC 边界，clk_mem）
                                           FPGA 层：DDR 适配器 + DDR3 IP
 外部接口：cam0/1 DVP、SCCB(I2C)、TMDS 符号 3×10 位 @clk_pix、ETH MAC 侧 8 位 GMII 风格接口、
           UART、GPIO（按键/LED）、QSPI、debug_o
```

### 3.1 子系统划分

| 子系统 | 包含 | 时钟域 |
|---|---|---|
| CPU | EdRV32 核、I$、D$ | clk_sys |
| 系统总线 | sys_xbar、Boot ROM、SRAM、CLINT、PLIC、系统 APB 及外设 | clk_sys |
| 存储 | DDR 网关、mem_xbar、DDR 性能监视器 | clk_mem |
| 媒体 | VIN（采集 + PIX + NPU 输入适配）、DISP、RND、GEO | clk_mem、clk_pix、cam_pclk |
| NPU | YOLO 加速器 | clk_mem，是否单独时钟域在模块阶段定 |
| 网络 | ETH 引擎 | clk_mem、eth_rx/tx_clk |
| 公共基础 | CDC 库、FIFO、仲裁器、AXI/APB 工具、2D DMA 库、IP 包装 | — |

---

## 4. SoC 边界与外部接口

| 接口组 | 信号 | 说明 |
|---|---|---|
| 时钟 | `clk_sys_i`、`clk_mem_i`（= DDR core_clk）、`clk_pix_i`、`cam0/1_pclk_i`、`eth_rx_clk_i`、`eth_tx_clk_i` | PLL 在 FPGA 层 |
| 复位 | `rst_n_i`（异步），`mem_ready_i`（DDR 初始化完成） | 各域复位释放在 SoC 内部完成 |
| DDR | 一个 256 位 AXI4 主口，clk_mem 域 | FPGA 层接适配器和 IP；仿真接 DDR 模型 |
| 摄像头 | 两组 DVP：`pclk/vsync/href/data[7:0]` | |
| 摄像头控制 | SCCB/I2C，拆成 `_o/_oe/_i` | 由 I2C 外设驱动，软件配置 |
| 显示 | 3 × 10 位 TMDS 符号 @clk_pix | 串化器在 FPGA 层 |
| 网口 | MAC 侧 8 位 GMII 风格收发（`rxd/rx_dv/rx_er`、`txd/tx_en`），加 MDIO | RGMII 的 DDR IO 转换在 FPGA 层 |
| 外设 | UART、GPIO（按键/LED）、QSPI（`_o/_oe/_i`）、定时器输出 | |
| 调试 | `debug_o`：固定宽度的流水线观察向量 | 供 ILA 使用 |

---

## 5. 时钟与复位

### 5.1 时钟域

| 时钟 | 频率 | 包含的逻辑 |
|---|---|---|
| clk_sys | CPU 阶段实测后定（D11），暂按 150 MHz 估算 | CPU、sys_xbar、ROM/SRAM、CLINT/PLIC、系统外设 |
| clk_mem | 125 MHz（DDR UI） | mem_xbar、网关的 256 位侧、所有媒体引擎的 DMA 和寄存器块、ETH 的 DMA |
| clk_npu | [模块阶段] | 先和 clk_mem 相同；证明受算力限制后再分出，CDC 只放在 NPU 的 AXI 口 |
| clk_pix | 74.25 MHz | 显示时序、扫描 FIFO 读侧、TMDS 编码 |
| cam0/1_pclk | 摄像头提供 | 采集前端，到异步 FIFO 为止 |
| eth_rx/tx_clk | 125 MHz（千兆） | MAC 收发前端，到异步 FIFO 为止 |

- clk_sys 与其他域都是异步关系，所以 CPU 频率怎么定都不影响 SoC 结构。
- DDR 网关的 CDC 放在 64 位侧，异步 FIFO 更窄。
- 媒体控制面只有一处 APB 跨域：`apb_async_bridge`。

### 5.2 复位

- 每个时钟域采用"异步置位、同步释放"，由 `reset_ctrl` 统一生成。
- 释放顺序：clk_mem 域等 `mem_ready_i` → 媒体子系统 → clk_sys 域的 CPU。
- 存储阵列不复位。

### 5.3 CDC 规则

- 只能使用公共库原语：`cdc_sync_bit`、`cdc_pulse`、`cdc_handshake`、`cdc_gray_cnt`、`async_fifo`、`apb_async_bridge`、`axi_async_bridge`、`reset_sync`。
- 每一处跨时钟域都登记到 CDC 清单，并配套约束模板。

---

## 6. 地址映射

| 区域 | 基址 | 大小 | 属性 |
|---|---|---|---|
| Boot ROM | 0x0000_0000 | 16 KiB | 可执行、只读 |
| SRAM | 0x1000_0000 | 256 KiB | 可缓存、可执行、读写 |
| CLINT | 0x2000_0000 | 64 KiB | 设备 |
| PLIC | 0x3000_0000 | 4 MiB | 设备 |
| 系统 APB | 0x4000_0000 | 16 × 4 KiB | 设备，clk_sys 域 |
| 媒体 APB | 0x4100_0000 | 16 × 4 KiB | 设备，经异步桥到 clk_mem 域 |
| DDR 可缓存 | 0x8000_0000 | 1 GiB | 可缓存、可执行、读写 |
| DDR 非缓存 | 0xC000_0000 | 1 GiB | 非缓存、不可执行，与上一项为同一物理内存 |

**系统 APB 槽位**：0 UART0，1 GPIO0，2 SPI0（QSPI），3 TIMER0，4 I2C0（SCCB），5 CACHE_CTRL，6 SYSCTRL（芯片 ID、scratch、软复位、仿真结束码），其余预留。

**媒体 APB 槽位**：0 MEDIA_CTRL（全局使能、帧 ID、中断汇总），1 VIN，2 PIX，3 GEO，4 RND，5 DISP，6 NPU，7 ETH，8 MEM_XBAR（QoS 配置和统计），9 PERF_MON（DDR 性能监视器），其余预留。

**PLIC 源号**：1 UART，2 GPIO，3 SPI，4 TIMER，5 I2C，8 VIN，9 PIX，10 GEO，11 RND，12 DISP，13 NPU，14 ETH，15 MEM_XBAR（错误/超时）。

---

## 7. 互连与流量调度

### 7.1 sys_xbar：64 位系统 AXI

- 主设备：M0 是 I$（只读），M1 是 D$。不做系统 DMA（D13）。
- 从设备：ROM、SRAM、CLINT、PLIC、系统 APB 桥、媒体 APB 异步桥、DDR 网关。
- AXI4 子集沿用旧规范：只发对齐的 INCR 突发，不用 QoS/PROT/CACHE/USER。
- cache 行 32 B，一次突发 4 拍 × 64 位。
- 规范指标：命中 SRAM 时，从 AR 发出到第一个 R 返回 ≤ 3 拍。

### 7.2 APB 控制面

- 系统 APB：1 对 N 分发，空槽回 PSLVERR。
- 媒体 APB：clk_sys → `apb_async_bridge` → clk_mem 域分发。桥里带超时，超时回 SLVERR。

### 7.3 DDR 网关

- 64 位 AXI 从口转 256 位 AXI 主口：读、写各允许 1 笔父事务在途，窄写先打包。
- 两个 CPU 视图映射到物理地址 0。

### 7.4 mem_xbar：256 位多主单从（D19，详见带宽规划第 6 节）

| 端口 | 主设备 | 等级 | 持续带宽 |
|---|---|---|---:|
| P0 | DISP | 硬实时读，水位触发 urgent | 111–332 MB/s |
| P1 | VIN：cam0、cam1、NPU 输入适配 | 硬实时写，水位触发 urgent；NPU 输入可丢帧 | 55–280 MB/s（含 60 fps） |
| P2 | CPU 网关 | 低延迟，限速 10% | ≤ 50 MB/s |
| P3 | NPU | 尽力而为，保底 30% | 0.5–1.4 GB/s |
| P4 | RND | 软实时 | ≤ 390 MB/s |
| P5 | GEO | 软实时 | ≤ 242 MB/s（60 fps） |
| P6 | ETH + 性能监视器 | 尽力而为，限速 5% | ≤ 120 MB/s |

**调度规则**：
- 优先级从高到低：urgent → 低延迟（受令牌限速）→ 饿死保护 → 加权轮询。
- 读写分组：同方向最多连续 4 个突发后换向。
- 全局在途上限 8。
- 读返回缓冲按 credit 管理，原因是 DDR IP 的读数据不能反压。
- 所有参数都由 MEM_XBAR 寄存器配置，复位值就是 spec 规定的初值。

### 7.5 公共 2D DMA 库

- `dma2d_rd` / `dma2d_wr`：描述符为 `{base, stride, width_bytes, height}`。负责突发拆分（对齐到 512 B，一律用 16 拍）、4 KiB 切分、首尾字节写使能。写操作在最后一个 B 响应回来后才给出 `done`（写栅栏）。
- 所有引擎访问 DDR 都通过这两个模块。引擎内部有多个客户端时，先在本地仲裁，再汇成一个端口。

### 7.6 带宽

详见带宽规划。结论：三个场景都在准入上限以内（S1 约 1.3–1.5 GB/s，S2 约 0.6–0.75，S3 约 0.55）。硬实时流的最坏等待约 2 µs，远小于能容忍的约 22 µs。NPU 可用的 DDR 带宽天花板约 1.4 GB/s。

---

## 8. 控制面规范

### 8.1 统一的引擎寄存器模型

| 偏移 | 寄存器 |
|---|---|
| 0x000 | ID（引擎类型和版本） |
| 0x004 | CTRL（enable、start、abort、soft_reset） |
| 0x008 | STATUS（busy、done、error、idle） |
| 0x00C / 0x010 | IRQ_EN / IRQ_STAT（写 1 清除） |
| 0x014 | ERR_CODE |
| 0x020–0x03F | 描述符或命令列表的基址、数量、门铃 |
| 0x040–0x07F | 性能计数器 |
| 0x100+ | 引擎私有寄存器 |

- 寄存器块由 JSON 描述，自动生成 RTL 寄存器块、C 头文件和文档表格。
- "下一帧生效"的参数统一用 shadow 寄存器，在 SOF 或 VBlank 原子提交。

### 8.2 两种工作模式

- **流式**（VIN、PIX、DISP）：配置后持续运行，按帧上报。
- **命令式**（GEO、RND、NPU、ETH 发送）：CPU 在 DDR 里写好描述符或命令列表，写门铃启动，完成后发中断。

### 8.3 中断

每个引擎一条电平中断，表示 `|(IRQ_STAT & IRQ_EN)`。在 clk_mem 域生成，同步到 clk_sys 后接入 PLIC。

### 8.4 软件与硬件的一致性约定

- CPU 先写描述符或数据，再执行 D$ clean，然后写门铃；或者直接用非缓存别名写。
- CPU 读 DMA 结果前，先对相应范围做 D$ invalidate，或者用非缓存别名读。
- 这些约定写进 spec，并由 HAL 封装。

---

## 9. 功能模块（SoC 视角，内部细节在各模块 spec 里定）

### 9.1 CPU：顺序双发射，精简重写（D1、D2、D3、D11）

**外部契约**：两个 AXI4 64 位主口（I$ 只读，D$ 读写，cache 行 32 B），MSIP/MTIP/MEIP 中断，mtime，`debug_o`。ISA 为 RV32IM + Zicsr + Zicntr + Zifencei，C 扩展先可选、评估后定死。

**微结构方向**（CPU 阶段逐项确认）：
- 非对称双管线：管线 0 全功能，管线 1 只有 ALU（是否加分支由实测决定）。
- 6 级左右，级数以实测为准。
- 配对规则从简：同组内不允许 RAW；LSU、MDU、CSR 各一个。
- 流水控制用全局 stall 加按级 flush，不用弹性 FIFO、epoch、LQ/SQ。
- 寄存器堆 4 读 2 写，用 FF 还是 LUTRAM + LVT 按实测选择。
- 预测器：BTB + gshare/bimodal + RAS。
- 乘法用 APM（IP 包装），除法用 radix-4。
- 算术用标准写法，交给综合工具映射。
- HPM 精简到 8 个计数器、约 16 种事件。

**指标**（初步）：CoreMark/MHz ≥ 3.6（冲刺 4.0），核心加 cache 控制 ≤ 10K LUT，Fmax 在 CPU 阶段实测后确定。

**CPU 阶段的第一步**：在 PG2L200H 上做时序标定实验（Windows 任务卡）。被测单元包括：32 位 ALU 加旁路选择、cache RAM 读出加 tag 比较、4R2W 寄存器堆、分支比较到重定向。同时分析旧版只到 100 MHz 的原因。

### 9.2 Cache

- I$：2 路组相联，默认 8 KiB，32 B 行。
- D$：2 路组相联，写回、写分配，默认 8 KiB，32 B 行。
- 维护操作：CACHE_CTRL 槽做按范围 clean/invalidate，FENCE.I 联动 I$ invalidate。
- 存储都走 IP 包装。

### 9.3 系统外设

| 外设 | 说明 |
|---|---|
| UART | 带收发 FIFO。上位机控制台和命令通道；开发期也可用来装载数据 |
| GPIO | 板载按键（带去抖和中断）、LED |
| SPI | 支持 Quad 模式，读写板载 QSPI flash（配置脚能否被用户逻辑接管待验证） |
| TIMER | 定时和 PWM |
| I2C | 由软件配置摄像头 SCCB，取代旧的硬件初始化 ROM |
| SYSCTRL | 芯片 ID、scratch、软复位、仿真结束码。仿真平台据此判定测试结束和结果 |
| CACHE_CTRL | cache 维护操作 |

### 9.4 VIN 视频输入（D7、D17）

- 两路 DVP 前端各自在 PCLK 域打包，经异步 FIFO 进入 clk_mem。
- 帧率默认 30 fps，寄存器可切到 60 fps。摄像头传感器本身的配置由软件通过 I2C 完成。
- PIX 内联在路径上，可旁路。
- **两路独立的写通道**，各有 FIFO、描述符和 Surface；首版通过选路只启用一路。
- NPU 输入适配从同一路流分出，做缩放、letterbox、量化和排布，写入 DDR，可丢帧。
- 三个写客户端在 VIN 内部仲裁后共用 P1 端口：摄像头优先，NPU 输入最低。

### 9.5 PIX 和 GEO

- PIX：流式，2 像素/拍，点运算加 3×3 空间算子。保留旧算法，接口重构。
- GEO：DDR 到 DDR 的命令式引擎，做旋转、缩放、双线性插值，使用公共 DMA 库。[模块阶段]

### 9.6 显示链路：图层叠加 + 扫描输出（D4、D5）

- 全系统只有一个显示输出。所有场景的画面都是底图层（摄像头、PIX、GEO 或 LVGL 帧缓冲）叠加 UI 层（渲染器绘制）。
- 扫描读是硬实时流量（P0），行 FIFO 至少 2 行。
- 页面和图层只在 VBlank 切换，遵守 Surface 所有权协议。
- [模块阶段] 合成方式：扫描时叠加（方式 A），还是离线合成（方式 B）。带宽规划第 4 节表明两者流量相同，区别在于硬实时流量的多少、延迟和逻辑复杂度。图层数和格式也在这一阶段定。

### 9.7 RND 渲染器（D4）

- 执行 CPU 提交的绘制命令列表，作为 LVGL 等图形库的硬件绘制后端，负责图层相关的合成工作。
- 接口：寄存器块、命令式模式、P4 端口、一条中断。
- 命令集以 LVGL 绘制后端实际需要为准。[模块阶段]

### 9.8 NPU（D10、D18）

- 接口：寄存器块、描述符列表加门铃、一条中断、P3 端口。权重、特征图、工作区地址全部由软件分配。
- 帧率尽量高。DDR 天花板约 1.4 GB/s，按每次推理 55 MB 估算约 25 fps。
- [模块阶段] MAC 阵列规模、时钟域、后处理分工、输入打包格式（C16 改 C4 可以减少约 3 MB/帧的输入流量）。

### 9.9 ETH 引擎（D9）

- MAC 侧接口：千兆 GMII 风格，加 MDIO 管理。
- 硬件 UDP：接收时，按端口号直接把载荷写入软件指定的 DDR 缓冲区（描述符环）；发送时，从 DDR 缓冲区读出、组帧发送。ARP 和 ICMP 等少量协议由 CPU 软件处理，或者在硬件里做最小实现。[模块阶段]
- 用途：下载权重和测试图到 DDR，回传识别结果和画面。
- 接口：寄存器块、P6 端口（和性能监视器共用）、一条中断。

### 9.10 调试与性能观测

- `debug_o`：流水线各级的 valid/stall/flush、退休、误预测、cache 缺失。
- mem_xbar 的端口统计；各引擎的性能计数器。

---

## 10. IP 包装与行为模型（D14）

```
ip/
  ip_manifest.json                      # 所有 IP 登记：名字、类型、深度×位宽、读延迟、初始化文件
  pango/<ip_name>/                      # PDS IP Compiler 的输出（.idf + 生成的 .v），由 PDS 工程导入
rtl/tech/
  edrv32_ram_icache_data.v              # 每个 IP 一个包装模块，固定配置，不做参数化
```

包装模块的写法：

```verilog
`include "edrv32_build_mode.vh"
module edrv32_ram_icache_data ( ...固定端口... );
`ifdef EDRV32_FPGA_MEMORY_MODE
    icache_data_128x128 u_ip ( ... );        // PDS 生成的 IP
`else
    // 行为模型：读延迟、写读冲突、上电值与 IP 完全一致
`endif
endmodule
```

规则：
- `ifdef` **只能出现在 `rtl/tech/` 的包装模块里**。
- 仿真和综合使用同一份文件列表，切换只靠宏：PDS 工程定义 `FPGA_MODE`，仿真定义 `SIM_MODE`，两个都定义就报错。
- PDS 生成的 IP 文件不进仿真文件列表，由 PDS 工程导入。
- APM 乘法器、ROM、FIFO RAM 都按同样方式处理；取消旧的 `MUL_USE_PANGO_APM` 参数。
- 新增 IP 的流程：先登记到 manifest → 写 Windows 任务卡（IP 配置参数）→ Windows 端生成并回传 → 入库到 `ip/pango/`。
- 每个包装模块都要有一个"行为模型 vs IP"的等价性测试，在 ModelSim 上跑，同样走 Windows 任务卡。

---

## 11. 资源预算（初版估计）

| 模块 | LUT 预算 |
|---|---:|
| CPU 核 + cache 控制 | ≤ 10K |
| 系统总线 + 外设 + CLINT/PLIC | ≤ 5K |
| DDR 网关 + mem_xbar | ≤ 8K |
| VIN + PIX + DISP | ≤ 10K |
| GEO | ≤ 8K |
| RND | ≤ 12K |
| ETH | ≤ 5K |
| NPU（含输入适配） | ≤ 50K |
| **合计** | **≤ 108K（约 68%）** |

DRM 和 APM 的预算在各模块阶段确定。CPU 的 CoreMark 测评继续用独立的 CPU 最小顶层。

---

## 12. 仓库目录结构（D15）

```
docs/
  spec/         正式规范（唯一事实来源），编号排列
  design/       设计决策记录，带日期（本文最终放这里）
  guides/       教程和阅读指南
  reports/      时序、资源、性能报告，带日期和 commit
  reference/    外部资料，例如开发板资料（由 doc/fpga/pago_200 移入）
rtl/
  include/      自动生成的头文件（地址映射、寄存器）+ build_mode
  common/       CDC、FIFO、仲裁器、AXI/APB 工具、dma2d
  tech/         IP 包装模块（ifdef 只出现在这里）
  cpu/  cache/  bus/  mem/  periph/
  media/        vin/ pix/ geo/ rnd/ disp/
  npu/  eth/
  soc/          edrv32_soc_top 及各子系统顶层
  filelists/    每个子系统一个 .f，仿真和综合共用
ip/             ip_manifest.json + pango/<ip>/
verif/          见第 13 节
sw/             见第 13 节
tools/          地址/寄存器生成器、风格检查、回归脚本、YOLO 模型工具链
tasks/win/      Windows 任务卡，见第 14 节
legacy/         旧的 rtl、sim、sw、scripts、doc 整体移入，只读，不进任何文件列表
build/          所有生成物（不入库）
```

---

## 13. 仿真与软件体系（D12、D16）

### 13.1 三级仿真

| 级别 | 被测对象 | 典型内容 | 判定方式 |
|---|---|---|---|
| **单元级** `verif/unit/<模块>/` | 单个模块 | FIFO、CDC、仲裁器、dma2d、ALU、译码器、cache 阵列、寄存器块 | 自检 testbench，加随机激励和断言；输出 PASS/FAIL，以退出码返回 |
| **模块级** `verif/block/<子系统>/` | 一个子系统 | CPU 核 + cache + 存储模型；mem_xbar + DDR 模型 + 流量发生器；VIN/DISP + 视频模型；NPU 对照 Python 参考模型 | 记分板比对；CPU 用 ISA 测试和小程序；NPU 逐层逐位比对 |
| **SoC 级** `verif/soc/<测试>/` | `edrv32_soc_top` 加全部外部模型 | 启动流程、外设、CoreMark、场景流量回放、摄像头 → 显示画面导出 PNG | SYSCTRL 结束码加 UART 输出；画面与参考图比对 |

- **工具**：Verilator 5（`--timing`）为主，testbench 用 Verilator 能跑的 SV 子集。Icarus 用于复位、X 传播和四态检查，只跑选定的 case。需要 ModelSim 的（Pango 加密仿真库、IP 等价性测试）走 Windows 任务卡。
- **外部器件模型**放在 `verif/models/`：DDR（256 位 AXI 时序模型，带"读不能反压"约束和 bank/换行延迟）、OV5640 视频源（从图片生成 DVP 时序）、HDMI 接收端（TMDS 解码后导出图片）、UART 终端、QSPI flash、ETH 对端（收发 UDP 包）。
- **测试描述**：每个 case 有一个 `test.yaml`（顶层、文件列表、宏、参数、软件程序、超时、判定方式）和一个 `files.f`。
- **回归**：唯一入口是 `tools/regress.py` 或 `make`。分三档：smoke（每次提交）、full（合并前）、perf（CoreMark 周期数、带宽回放，与基线比对）。结果汇总到 `build/reports/`。

### 13.2 带 CPU 的仿真：软件加载规范

```
sw/<程序> ──riscv32-gcc──► ELF ──tools/elf2mem──► rom.hex / sram.hex / ddr.hex（按地址段切分）
                                                └► PDS 用的初始化文件（ROM/SRAM，同一个 ELF 生成）
```

**加载方式一：后门预加载**，默认方式，速度最快。
- 行为模型的存储器（ROM、SRAM、DDR 模型）在仿真开始时，根据 plusarg 读入镜像，例如 `+ROM_HEX=`、`+SRAM_HEX=`、`+DDR_HEX=`。
- 用于 ISA 测试、CoreMark、外设和引擎的驱动测试。

**加载方式二：前门启动**，用来验证真实的启动流程。
- Boot ROM 中的 bootloader 通过 QSPI flash 模型、UART 模型或 ETH 模型把程序搬进 SRAM/DDR，然后跳转执行。
- 只在启动类测试里使用。

**链接脚本**（`sw/bsp/ld/`）分三种：
- `rom.ld`：直接在 ROM 里执行。
- `sram.ld`：代码和数据都在 SRAM，由 bootloader 或预加载放入。CoreMark 默认用这个。
- `ddr.ld`：大程序（例如 LVGL 演示）放在 DDR。

**结束与判定**：
- 模块级 CPU 测试：沿用 `tohost` 约定。
- SoC 级测试：软件写 SYSCTRL 的结束码寄存器，testbench 检测到后结束仿真，0 表示 PASS。UART 输出同时保存到日志。

### 13.3 软件目录

```
sw/
  bsp/        启动代码、链接脚本、陷阱处理、cache 维护
  drivers/    各外设和引擎驱动（寄存器头文件自动生成）
  lib/        printf、内存分配、后续的 LVGL 移植层
  tests/      isa/ cpu/ periph/ media/ npu/ soc/：仿真和上板共用的测试程序
  apps/       bootloader/  coremark/  demo/（三场景演示程序）
  Makefile    统一构建，输出到 build/sw/<程序>/
```

CoreMark 的编译选项作为 CPU 指标的一部分单独调优，目标是激进的 `-O3` 一类配置。选项和结果都记录在 reports 里。

---

## 14. Windows 任务交接规范（D12）

需要 ModelSim、PDS 或上板的工作，由我写任务卡，你在 Windows 端交给 agent 执行，结果回传后我负责解析和归档。

```
tasks/win/<YYYYMMDD>-<序号>-<简名>/
  task.md      # 我写
  result.md    # Windows 端回填
  artifacts/   # 回传的报告、日志、波形截图、生成的 IP 文件
```

`task.md` 固定包含以下内容：
1. 目标（一句话）
2. 输入：基于哪个 commit、要用的文件
3. 环境：PDS 或 ModelSim 版本、器件型号、速度等级
4. 逐步操作（可以直接执行的命令或 Tcl）
5. 需要采集的产物清单，以及每个产物的存放位置
6. 通过判据
7. `result.md` 模板：结论、关键数字（WNS/TNS、LUT/FF/DRM/APM、频率、带宽等）、异常和备注

已知的首批任务：
- T1：在 PDS 上测 DDR 有效带宽 B_eff（带宽规划第 7 节）
- T2：QSPI 配置脚能否被用户逻辑接管
- T3：CPU 基本单元时序标定（9.1）
- T4：生成首批 IP 并做等价性测试（第 10 节）

---

## 15. 重构路线与 spec 拆分

| 阶段 | 内容 | 退出条件 |
|---|---|---|
| P0 基础设施 | 迁移 legacy、新目录、spec 骨架、构建/仿真/lint/回归流程、寄存器生成器、IP 包装框架、CDC 库、Windows 任务 T1–T2 | 空 SoC 能编译；lint 为 0；回归框架可以运行 |
| P1 CPU | 时序标定（T3）、CPU spec、双发射核 + cache、CPU 最小顶层 | ISA/ACT 全部通过；CoreMark CRC 正确；上板测得 Fmax、LUT、CoreMark/MHz |
| P2 SoC 骨架 | sys_xbar、外设、CLINT/PLIC、网关、mem_xbar、DDR 模型、软件 BSP | SoC 级 CoreMark 和 DDR 测试通过；CDC 清单完整 |
| P3 实时通路 | dma2d、VIN、DISP（含图层方案的模块级讨论） | 摄像头 → HDMI 闭环，无 underflow/overflow |
| P4 图像处理 | PIX、GEO | 像素级比对通过 |
| P5 渲染 | RND、LVGL 移植 | UI 画面比对通过 |
| P6 NPU | NPU 模块级讨论与重构 | 逐层与 Python 参考逐位一致；帧率达标 |
| P7 ETH 与集成 | ETH、三场景演示程序、混合流量压测、性能报告、ILA 分析 | 带宽规划和资源预算的指标全部达标 |

**正式 spec 拆分**：

| 编号 | 内容 |
|---|---|
| 00-overview | 总览 |
| 01-soc-architecture | 第 3–4 节 |
| 02-memory-map | 第 6 节，由 JSON 生成表格 |
| 03-clock-reset-cdc | 第 5 节 |
| 04-interconnect | 第 7 节 + 带宽规划 |
| 05-control-plane | 第 8 节 |
| 10-cpu、11-cache | |
| 20-media-common | dma2d、Surface 协议 |
| 21-vin、22-pix、23-geo、24-rnd、25-disp | |
| 26-npu | |
| 27-eth | |
| 30-periph | |
| 40-ip-tech | 第 10 节 |
| 50-verification | 第 13 节 |
| 51-software | 第 13.2–13.3 节 |
| 60-coding-style | |
| 70-win-task-protocol | 第 14 节 |

---

## 16. 待确认事项

SoC 层的架构项已全部确认。剩余未定事项都标为 [模块阶段]，会在对应模块的 spec 讨论时逐项确认：
- CPU：微结构细节、频率目标、C 扩展的去留
- DISP/RND：图层合成方式、图层数和格式、命令集
- NPU：MAC 规模、时钟域、后处理分工、输入格式
- GEO、ETH：内部结构
- DDR：B_eff 实测结果和仲裁参数初值的修正
