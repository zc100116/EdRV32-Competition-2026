# EdRV32 系统子系统规格

| 项 | 内容 |
|---|---|
| 版本 | v0.4（草案） |
| 日期 | 2026-10-28 |
| 状态 | 已确认（2026-10-25）。标 **[待定]** 的条目给出了开发初值 |
| 范围 | sys_xbar、Boot ROM、SRAM、系统 APB 桥、媒体 APB 桥、CLINT、PLIC、UART0、GPIO0、I2C0、SYSCTRL、复位控制 `reset_ctrl` |
| 关联文档 | SoC 规格 3.1、3.5、4.1、4.3、4.4、5.3、6.1、6.2、7.5、8.3；`docs/spec/cache-spec.md`（CACHE_CTRL）；`docs/testplan/sys-subsys-testplan.md`；`docs/plan/sys-subsys-plan.md` |

---

## 1. 概述

系统子系统是 CPU 子系统（`edrv32_cpu_subsys`）与片上存储、中断控制器、低速外设之间的连接层，全部位于 clk_sys 域，媒体 APB 桥的从侧除外（clk_mem 域）。

```
 edrv32_cpu_subsys ── I$ AXI64 ──┐
                   ── D$ AXI64 ──┤
                                 ▼
                     edrv32_bus_sys_xbar（2 主 × 7 从）
   ┌──────┬──────┬───────┬──────┬─────────────┬──────────────┬───────────┐
   S0     S1     S2      S3     S4            S5             S6
  ROM    SRAM   CLINT   PLIC   系统 APB 桥    媒体 APB 桥     DDR 网关（存储子系统规格）
                               │ 16 槽         │ clk_sys→clk_mem
                 UART0 GPIO0 I2C0 CACHE_CTRL SYSCTRL      媒体 APB（各引擎）
```

| 模块 | 文件 | 说明 |
|---|---|---|
| `edrv32_bus_sys_xbar` | `rtl/bus/` | 系统 AXI64 交叉开关 |
| `edrv32_bus_rom` | `rtl/bus/` | Boot ROM 的 AXI64 从接口，例化 `edrv32_rom_boot` |
| `edrv32_bus_sram` | `rtl/bus/` | SRAM 的 AXI64 从接口，例化 `edrv32_ram_sram` |
| `edrv32_bus_apb_bridge` | `rtl/bus/` | AXI64 从口 → 单个未译码的 APB 主口（`paddr[15:0]`）；在 AXI 侧检查不合规访问 |
| `edrv32_bus_apb_decoder` | `rtl/bus/` | APB 16 槽译码、预留槽 SLVERR、256 拍超时；输出槽内 12 位地址和每槽 `psel` |
| `edrv32_apb_async_bridge` | `rtl/common/` | APB 异步桥（公共原语，SoC 规格 5.2 X1） |
| `edrv32_periph_clint` | `rtl/periph/` | CLINT，AXI64 从接口 |
| `edrv32_periph_plic` | `rtl/periph/` | PLIC，AXI64 从接口 |
| `edrv32_periph_uart` | `rtl/periph/` | UART0，APB 从设备 |
| `edrv32_periph_gpio` | `rtl/periph/` | GPIO0，APB 从设备 |
| `edrv32_periph_i2c` | `rtl/periph/` | I2C0，APB 从设备 |
| `edrv32_periph_sysctrl` | `rtl/periph/` | SYSCTRL，APB 从设备 |
| `edrv32_soc_reset_ctrl` | `rtl/soc/` | 各时钟域复位的生成和软复位 |
| `edrv32_rom_boot` | `rtl/tech/` | Boot ROM 存储 IP 包装：2048 × 64 位，带初始化文件 |
| `edrv32_ram_sram` | `rtl/tech/` | SRAM 存储 IP 包装：8192 × 64 位，8 位字节写使能 |

系统 APB 路径：`edrv32_bus_apb_bridge` → `edrv32_bus_apb_decoder`（均在 clk_sys）。媒体 APB 路径：`edrv32_bus_apb_bridge`（clk_sys）→ `edrv32_apb_async_bridge` → `edrv32_bus_apb_decoder`（clk_mem）。槽译码、预留槽检查和超时计数都在 decoder 所在的时钟域完成。

---

## 2. 功能描述

### 2.1 sys_xbar

| 项 | 规定 |
|---|---|
| 主设备 | M0 = I$（只读），M1 = D$（读写） |
| 从设备 | S0 ROM、S1 SRAM、S2 CLINT、S3 PLIC、S4 系统 APB 桥、S5 媒体 APB 桥、S6 DDR 网关 |
| 地址译码 | 按 SoC 规格 6.1，用 `rtl/include/edrv32_soc_map.vh` 中的常量比较地址高位；DDR 网关同时响应 0x8000_0000 和 0xC000_0000 两个窗口 |
| 连接矩阵 | M0 只能访问 S0、S1、S6；M1 可以访问全部从设备 |
| 仲裁 | 每个从设备的读通道、写通道各自独立做两主轮询；一个事务从地址握手到最后一个响应握手期间占用该从设备的对应通道 |
| 并发 | SoC 规格 4.1：每个主设备每个方向至多 1 笔未完成事务。sys_xbar 依赖这一点，不做 ID 重排序 |
| 写通道 | W 跟随已被接受的 AW 送往同一个从设备 |
| 延迟 | 无竞争时，M0/M1 访问 SRAM：从 ARVALID 被接收到第一个 RVALID 不超过 3 个周期；访问 ROM 相同 |
| 错误 | 地址未映射、或连接矩阵禁止的访问，由 sys_xbar 自己回 DECERR：读回 ARLEN+1 拍 RRESP=DECERR（数据为 0，最后一拍 RLAST），写在接收全部 W 后回 BRESP=DECERR，不转发给任何从设备 |

### 2.2 Boot ROM 与 SRAM

| 项 | Boot ROM | SRAM |
|---|---|---|
| 容量 | 16 KiB（2048 × 64 位） | 64 KiB（8192 × 64 位） |
| 访问 | 只读。读 SIZE ≤ 3（I$ 单拍 SIZE = 3）；写回 SLVERR | 读写。单拍 SIZE ≤ 2、cache 行 4 拍 INCR SIZE = 3 |
| 上电内容 | bootloader 和启动 logo，由 `sw/` 构建的 bootloader ELF 生成初始化文件 | 应用程序，由应用 ELF 生成初始化文件；不需要上电内容的工程可以使用空文件 |
| 实现 | 单口同步读 ROM IP，读延迟 1 | 单口同步读写 RAM IP，读延迟 1，8 位字节写使能 |
| 仿真 | 行为模型在仿真开始时读入 `+ROM_HEX=`（CLAUDE.md 9.2） | 读入 `+SRAM_HEX=` |
| FPGA | PDS IP 的存储初始化文件，内容与仿真使用的文件来自同一个 ELF | 同左 |

SRAM 同一端口上的读和写不重叠：从接口按通道仲裁结果一次只服务一个事务。

### 2.3 APB 桥

| 项 | 系统 APB 桥（S4） | 媒体 APB 桥（S5） |
|---|---|---|
| 时钟 | clk_sys | AXI 侧 clk_sys，APB 侧 clk_mem |
| 槽 | 16 槽 × 4 KiB，`addr[15:12]` 选槽，`addr[11:0]` 送到从设备的 `paddr` | 同左 |
| 访问 | AXI 单拍、SIZE = 2、地址 4 B 对齐的访问转换为一次 APB 传输；`pstrb` 由 WSTRB 中对应 32 位半部的 4 位得到 | 同左 |
| 不合规访问 | 突发（LEN ≠ 0）、SIZE ≠ 2 或地址未 4 B 对齐：回 SLVERR，不发出 APB 传输；突发的读回 LEN+1 拍 | 同左 |
| 预留槽 | 访问回 SLVERR。decoder 与槽用途无关；预留槽在例化处把该槽的 `pready`、`pslverr` 接 1、`prdata` 接 0 | 同左 |
| 超时 | SoC 规格 4.3：256 个 PCLK 内没有 `pready`，回 SLVERR 并结束本次访问 | 同左（在 clk_mem 侧计数） |
| 并发 | 一次只有一笔 APB 传输 | 同左 |

### 2.4 CLINT

- `mtime`：64 位，每个 clk_sys 周期加 1，复位为 0，软件可写。
- `mtimecmp`：64 位，复位为全 1。`MTIP = (mtime >= mtimecmp)`，组合比较后打一拍输出到 `irq_mtip_o`。
- `msip`：1 位，`MSIP = msip[0]`。
- `mtime_o[63:0]` 直接输出给 CPU 的 `mtime_i`（cpu-spec 3.1）。
- 软件根据 SYSCTRL 的 `CLK_SYS_HZ` 换算时间。

### 2.5 PLIC

- 15 个中断源，源号 1–15（源号分配见 SoC 规格 6.1，源号 0 表示无中断）；1 个 M 模式上下文，输出 MEIP。
- 优先级 3 位（0–7，0 表示永不触发）；阈值 3 位。
- 网关：电平触发。源信号先用 `cdc_sync_bit` 同步到 clk_sys（SoC 规格 5.2 X3；clk_sys 域的源也经同一级同步，统一延迟）。同步后的电平为 1 且该源不处于"已认领未完成"状态时，置 pending。
- 认领（claim）：读 claim 寄存器返回 pending 且使能、优先级大于阈值的源中优先级最高者的源号；同优先级取源号小者；没有则返回 0。返回非 0 时清除该源的 pending，并标记该源为"已认领"，此后不再置 pending。
- 完成（complete）：写 claim 寄存器，写入值为已认领的源号时解除"已认领"标记；写其他值无效果。
- MEIP = 存在 pending 且使能、优先级大于阈值的源。输出打一拍。

### 2.6 UART0

- 8N1，波特率可编程，最高不低于 3 Mbps（clk_sys = 150 MHz 时）。
- 波特率发生：位周期 = `BAUD_DIV / 16` 个 clk_sys 周期（定点数，小数部分累加），误差不超过 1/16 周期每位。`BAUD_DIV` 的最小合法值为 128（每位 8 个周期）。
- 接收：`uart0_rx_i` 经 `cdc_sync_bit` 同步；检测到起始位下降沿后，在每一位的中点采样；停止位为 0 时记为帧错误（该字节丢弃，置 FRAME_ERR）。
- `CTRL.TX_EN`、`RX_EN` 只决定是否开始新的一帧，已经开始的帧照常完成；`TX_CLR`、`RX_CLR` 只清空 FIFO，不打断正在移位的帧。
- 收、发各 16 字节 FIFO。接收 FIFO 满时新到的字节丢弃并置 RX_OVERRUN。发送 FIFO 满时写 TXDATA 无效果（软件必须先查 TX_FULL）。
- 复位后 `BAUD_DIV` 为 115200 波特率对应的值（由 `CLK_SYS_HZ` 在综合时算出），收发使能。

### 2.7 GPIO0

- 16 位，每位方向可设（`OE` 为 1 时输出）。
- 输入经 `cdc_sync_bit` 同步，再经去抖：输入连续 `DEBOUNCE` 个周期保持同一值后才更新 `IN`；`DEBOUNCE` = 0 时不去抖。
- 每位可分别使能上升沿、下降沿中断；边沿以去抖后的 `IN` 为准。
- 板上按键、LED 和摄像头 `pwdn` / `rst_n` 的引脚分配由板级约束决定；摄像头的 `pwdn`、`rst_n` 由 GPIO 输出驱动（SoC 规格 3.3）。

### 2.8 I2C0

- 主模式，100 kHz 和 400 kHz，7 位地址，支持重复起始位；用于两路摄像头的 SCCB 配置。
- 两对引脚：端口 0 接 cam0，端口 1 接 cam1。`CTRL.PORT_SEL` 选择当前驱动的端口；未选中的端口 SCL、SDA 均释放（`_oe` = 0）。只在 `STATUS.BUSY` = 0 时允许改变 `PORT_SEL`。
- 开漏输出：驱动低电平时 `_oe` = 1、`_o` = 0；释放时 `_oe` = 0。SCL、SDA 输入经 `cdc_sync_bit` 同步。
- 字节命令接口：软件每次写 CMD 执行一个字节传输，可选在前面加起始位（总线已被占用时即为重复起始位）、在后面加停止位。写字节后采样从设备的应答，NACK 记入 `STATUS.NACK`。读字节后由命令决定回 ACK 还是 NACK。
- 不支持时钟拉伸、多主仲裁、10 位地址。
- SCL 周期 = 4 × (`CLK_DIV` + 1) 个 clk_sys 周期；START/STOP 和数据位的建立、保持时间按四分之一周期划分。

### 2.9 SYSCTRL

- 只读信息：芯片 ID、`CLK_SYS_HZ`、`mem_ready` 状态（`mem_ready_i` 经 `cdc_sync_bit` 同步）。
- SYSCTRL 整个模块用 `rst_sys_por_n` 复位（2.10），因此软复位不影响它。
- 2 个 32 位 scratch 寄存器：只在 `rst_n_i` 复位时清零，软复位不清除。bootloader 和应用程序可以用它在软复位前后传递信息（例如"软复位后进入 UART 下载"）。
- 软复位：写 `SOFT_RESET` 触发 `reset_ctrl`（2.10）。
- `SIM_EXIT`：写入任意值时，仿真平台结束仿真，写入值为 0 表示通过（CLAUDE.md 9.2）。硬件上写入无副作用。

### 2.10 复位控制 reset_ctrl

- 输入：`rst_n_i`（异步），`mem_ready_i`，SYSCTRL 的软复位请求（clk_sys 域单周期脉冲）；各域时钟（含 `clk_npu`）。
- 输出：`rst_sys_por_n`（clk_sys 域，只由 `rst_n_i` 控制，软复位不影响；用于 SYSCTRL）、`rst_sys_n`、`rst_mem_n`、`rst_pix_n`、`rst_cam0_n`、`rst_cam1_n`、`rst_eth_rx_n`、`rst_eth_tx_n`、`rst_npu_n`（clk_npu 域），每一路由 `reset_sync` 在本域同步释放（SoC 规格 5.3、5.2 X8）。
- 释放顺序（SoC 规格 5.3）：
  1. `rst_n_i` 释放后，`rst_mem_n` 等 `mem_ready`（同步到 clk_mem）有效后释放；
  2. `rst_pix_n`、`rst_cam*_n`、`rst_eth_*_n`、`rst_npu_n` 随 `rst_mem_n` 一起请求释放，各自在本域同步；
  3. `rst_sys_n` 在 `rst_mem_n` 释放（同步回 clk_sys）之后释放。
- 媒体软复位（`SOFT_RESET.MEDIA`）：拉低 clk_mem、clk_pix、cam、eth、clk_npu 各域的引擎复位 16 个 clk_sys 周期后释放；mem_xbar 和 DDR 网关不受影响（使用独立的 `rst_mem_core_n`，只由 `rst_n_i` 和 `mem_ready` 控制）。
- SoC 软复位（`SOFT_RESET.SOC`）：除 `rst_mem_core_n` 外所有复位（含 `rst_sys_n`）拉低 16 个 clk_sys 周期后按上面的顺序释放；SYSCTRL 的 scratch 寄存器不受影响。
- 触发 MEDIA 软复位的写照常完成并返回 B；触发 SOC 软复位的写事务允许被复位取消，不保证返回 B（发起它的 CPU 同时被复位）。
- 媒体 APB 异步桥（`edrv32_apb_async_bridge`）源侧使用 `rst_sys_por_n`、目标侧和媒体侧 decoder 使用 `rst_mem_core_n`：两端只由 `rst_n_i`（和 `mem_ready`）一起复位，软复位不影响，避免桥单边复位后重放或误应答。软复位时不会有媒体 APB 事务在途。
- 软复位期间 DDR 内容保持；mem_xbar 不复位，因此软复位前必须由软件保证各引擎已停止（SoC 规格 7.1 ABORT）。

---

## 3. 接口

### 3.1 sys_xbar

| 信号组 | 方向 | 时钟域 | 说明 |
|---|---|---|---|
| `clk_i`、`rst_n_i` | in | clk_sys | |
| `m0_*` | 从侧 | clk_sys | AXI64（SoC 规格 4.1），只有 AR、R 通道，接 I$ |
| `m1_*` | 从侧 | clk_sys | AXI64 五通道，接 D$ |
| `s0_*` … `s6_*` | 主侧 | clk_sys | AXI64 五通道；S0（ROM）同样带写通道，由 ROM 从接口回 SLVERR |

### 3.2 存储与外设

| 模块 | 端口 |
|---|---|
| `edrv32_bus_rom`、`edrv32_bus_sram` | `clk_i`、`rst_n_i`；AXI64 从口 `axi_*` |
| `edrv32_bus_apb_bridge` | `clk_i`、`rst_n_i`；AXI64 从口 `axi_*`；APB 主口（未译码）`apb_paddr_o[15:0]`、`apb_psel_o`、`apb_penable_o`、`apb_pwrite_o`、`apb_pwdata_o[31:0]`、`apb_pstrb_o[3:0]`、`apb_prdata_i[31:0]`、`apb_pready_i`、`apb_pslverr_i` |
| `edrv32_apb_async_bridge` | `clk_s_i`、`rst_s_n_i`、APB 从口（`paddr[15:0]`）；`clk_m_i`、`rst_m_n_i`、APB 主口（`paddr[15:0]`） |
| `edrv32_bus_apb_decoder` | `clk_i`、`rst_n_i`；APB 从口（`paddr[15:0]`）；槽侧 APB 主口 `slot_paddr_o[11:0]`、`slot_psel_o[15:0]`、`slot_penable_o`、`slot_pwrite_o`、`slot_pwdata_o[31:0]`、`slot_pstrb_o[3:0]`、`slot_prdata_i[16×32-1:0]`、`slot_pready_i[15:0]`、`slot_pslverr_i[15:0]` |
| `edrv32_periph_clint` | `clk_i`、`rst_n_i`；AXI64 从口；`mtime_o[63:0]`、`irq_mtip_o`、`irq_msip_o` |
| `edrv32_periph_plic` | `clk_i`、`rst_n_i`；AXI64 从口；`irq_src_i[15:1]`（各源时钟域的电平）；`irq_meip_o` |
| APB 外设 | `clk_i`、`rst_n_i`；APB 从口（SoC 规格 4.3，前缀 `apb_`）；`irq_o`（UART、GPIO、I2C） |
| `edrv32_periph_uart` | `uart0_tx_o`、`uart0_rx_i` |
| `edrv32_periph_gpio` | `gpio_o[15:0]`、`gpio_oe_o[15:0]`、`gpio_i[15:0]` |
| `edrv32_periph_i2c` | `i2c0_scl_o[1:0]`、`i2c0_scl_oe_o[1:0]`、`i2c0_scl_i[1:0]`、`i2c0_sda_o[1:0]`、`i2c0_sda_oe_o[1:0]`、`i2c0_sda_i[1:0]`；下标 0 = cam0，1 = cam1 |
| `edrv32_periph_sysctrl` | `mem_ready_i`；`soft_reset_media_o`、`soft_reset_soc_o`（单周期脉冲）；`sim_exit_valid_o`、`sim_exit_code_o[31:0]`（仿真平台读取） |

### 3.3 中断连接

| PLIC 源 | 来源 | 时钟域 |
|---|---|---|
| 1 | UART0 `irq_o` | clk_sys |
| 2 | GPIO0 `irq_o` | clk_sys |
| 3、4、7 | 预留，接 0 | — |
| 5 | I2C0 `irq_o` | clk_sys |
| 6 | CACHE_CTRL `irq_o` | clk_sys |
| 8–15 | 媒体引擎、NPU、ETH、MEM_XBAR（SoC 规格 6.1） | clk_mem |

---

### 3.4 系统子系统顶层 edrv32_sys_subsys

`rtl/soc/edrv32_sys_subsys.v` 例化第 1 节的全部模块并连线，端口扁平，沿用子模块的信号词干。

| 信号组 | 方向 | 时钟域 | 说明 |
|---|---|---|---|
| `clk_sys_i`、`clk_mem_i`、`clk_pix_i`、`cam0_pclk_i`、`cam1_pclk_i`、`eth_rx_clk_i`、`eth_tx_clk_i` | in | — | 各域时钟（reset_ctrl 需要） |
| `rst_n_i`、`mem_ready_i` | in | 异步 | SoC 规格 3.1 |
| `rst_sys_por_n_o`、`rst_sys_n_o`、`rst_mem_core_n_o`、`rst_mem_n_o`、`rst_pix_n_o`、`rst_cam0_n_o`、`rst_cam1_n_o`、`rst_eth_rx_n_o`、`rst_eth_tx_n_o` | out | 各自域 | reset_ctrl 产生，供 SoC 顶层其他子系统使用（2.10） |
| `m0_*` | AXI64 从侧，只读 | clk_sys | 接 I$ |
| `m1_*` | AXI64 从侧，五通道 | clk_sys | 接 D$ |
| `s6_*` | AXI64 主侧，五通道 | clk_sys | 接 DDR 网关 |
| `media_apb_*` | APB 主侧，已译码 16 槽（`paddr[11:0]`、`psel[15:0]`，`prdata/pready/pslverr` 各槽一组） | clk_mem | 接媒体 APB 各引擎 |
| `cache_apb_*` | APB 主侧，单槽 | clk_sys | 系统 APB 槽 5，接 CPU 子系统中的 CACHE_CTRL |
| `irq_cache_i` | in | clk_sys | PLIC 源 6 |
| `irq_src_i[15:8]` | in | clk_mem | PLIC 源 8–15 |
| `irq_meip_o`、`irq_msip_o`、`irq_mtip_o`、`mtime_o[63:0]` | out | clk_sys | 接 CPU 子系统 |
| UART、GPIO、I2C 引脚 | — | — | 3.2 |
| `sim_exit_valid_o`、`sim_exit_code_o[31:0]` | out | clk_sys | SYSCTRL，仿真平台读取 |

## 4. 寄存器

除 CLINT、PLIC 采用 RISC-V 标准布局外，APB 外设偏移 0x000 都是 ID 寄存器：[31:16] 模块类型码（等于系统 APB 槽号），[15:0] 版本。未列出的偏移读出 0，写入无效果。RW1C 位在同一周期既有新事件置位、又被软件写 1 清除时，新事件优先（该位保持为 1）。APB 外设对 `pstrb` 的处理：除 GPIO 的 OUT、OE 按字节写外，其余寄存器忽略 `pstrb`，按整字写入。

### 4.1 CLINT（基址 0x2000_0000）

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x0000 | MSIP | RW | 0 | bit0 MSIP |
| 0x4000 | MTIMECMP_LO | RW | 0xFFFF_FFFF | mtimecmp[31:0] |
| 0x4004 | MTIMECMP_HI | RW | 0xFFFF_FFFF | mtimecmp[63:32] |
| 0xBFF8 | MTIME_LO | RW | 0 | mtime[31:0] |
| 0xBFFC | MTIME_HI | RW | 0 | mtime[63:32] |

访问为 32 位（AXI SIZE = 2，按 `addr[2]` 选 64 位总线的半部）。合法写访问的 WSTRB 恒为所选半部全 1（D$ 的保证），寄存器整字写入，不按字节处理；PLIC 相同。写 MTIME_LO 或 MTIME_HI 时，该半部取写入值，另一半部继续计数。

### 4.2 PLIC（基址 0x3000_0000）

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x000004 + 4 × (n − 1) | PRIORITY[n] | RW | 0 | n = 1–15，[2:0] 优先级 |
| 0x001000 | PENDING | RO | 0 | bit n = 源 n 的 pending（bit0 为 0） |
| 0x002000 | ENABLE | RW | 0 | bit n = 源 n 的使能（bit0 只读为 0） |
| 0x200000 | THRESHOLD | RW | 0 | [2:0] 阈值 |
| 0x200004 | CLAIM | RW | 0 | 读：认领；写：完成（2.5） |

### 4.3 UART0（系统 APB 槽 0）

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x000 | ID | RO | 0x0000_0001 | |
| 0x004 | CTRL | RW | 0x3 | bit0 TX_EN，bit1 RX_EN；bit2 TX_CLR、bit3 RX_CLR（写 1 清空对应 FIFO，读为 0） |
| 0x008 | STATUS | RO | — | bit0 TX_EMPTY，bit1 TX_FULL，bit2 RX_EMPTY，bit3 RX_FULL，bit4 TX_BUSY（正在移位），[12:8] TX_LEVEL，[20:16] RX_LEVEL |
| 0x00C | IRQ_EN | RW | 0 | 位定义同 IRQ_STAT |
| 0x010 | IRQ_STAT | 见说明 | 见说明（复位后为 0x2：发送 FIFO 空） | bit0 RX_THRESH（RO：RX_LEVEL ≥ RX_THRESH 且 RX_THRESH ≠ 0），bit1 TX_EMPTY（RO：发送 FIFO 空且不在移位），bit2 RX_OVERRUN（RW1C），bit3 FRAME_ERR（RW1C） |
| 0x014 | BAUD_DIV | RW | 115200 对应值 | [23:0] 位周期 × 16（单位 clk_sys 周期），最小 128 |
| 0x018 | RX_THRESH | RW | 1 | [4:0]，0–16 |
| 0x020 | TXDATA | WO | — | [7:0] 写入发送 FIFO |
| 0x024 | RXDATA | RO | — | [7:0] 数据，bit8 VALID；读出时若 VALID 则弹出 |

`irq_o = |(IRQ_STAT & IRQ_EN)`。

### 4.4 GPIO0（系统 APB 槽 1）

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x000 | ID | RO | 0x0001_0001 | |
| 0x004 | OUT | RW | 0 | [15:0] 输出值，按 `pstrb` 字节写 |
| 0x008 | OE | RW | 0 | [15:0] 输出使能，按 `pstrb` 字节写 |
| 0x00C | IN | RO | — | [15:0] 去抖后的输入 |
| 0x010 | RISE_EN | RW | 0 | [15:0] 上升沿中断使能 |
| 0x014 | FALL_EN | RW | 0 | [15:0] 下降沿中断使能 |
| 0x018 | IRQ_STAT | RW1C | 0 | [15:0] 已检测到使能的边沿 |
| 0x01C | DEBOUNCE | RW | 0 | [23:0] 去抖周期数，0 = 不去抖 |

`irq_o = |IRQ_STAT`。

### 4.5 I2C0（系统 APB 槽 4）

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x000 | ID | RO | 0x0004_0001 | |
| 0x004 | CTRL | RW | 0 | bit0 EN，bit1 PORT_SEL（0 = cam0，1 = cam1） |
| 0x008 | STATUS | RO | 0 | bit0 BUSY（命令执行中），bit1 NACK（最近一次写字节收到 NACK），bit2 BUS_HELD（已发起始位、未发停止位） |
| 0x00C | IRQ_EN | RW | 0 | bit0 DONE |
| 0x010 | IRQ_STAT | RW1C | 0 | bit0 DONE：一条命令执行完毕 |
| 0x014 | CLK_DIV | RW | 400 kHz 对应值 | [15:0]，SCL 周期 = 4 × (CLK_DIV + 1) 个 clk_sys 周期 |
| 0x018 | CMD | WO | — | [7:0] 写字节数据；bit8 START；bit9 STOP；bit10 READ（1 = 读字节，0 = 写字节）；bit11 NACK（读字节后回 NACK）。BUSY = 1 时写入无效果 |
| 0x01C | RXDATA | RO | 0 | [7:0] 最近一次读到的字节 |

`irq_o = |(IRQ_STAT & IRQ_EN)`。

### 4.6 SYSCTRL（系统 APB 槽 6）

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x000 | ID | RO | 0x0006_0001 | |
| 0x004 | CHIP_ID | RO | 0xED32_0001 **[待定]** | [31:16] 芯片标识，[15:0] SoC 版本 |
| 0x008 | CLK_SYS_HZ | RO | 综合常量 | clk_sys 频率（Hz） |
| 0x00C | STATUS | RO | — | bit0 MEM_READY |
| 0x010 | SCRATCH0 | RW | 0 | 只在 `rst_n_i` 时复位 |
| 0x014 | SCRATCH1 | RW | 0 | 同上 |
| 0x018 | SOFT_RESET | WO | — | bit0 MEDIA，bit1 SOC（写 1 触发） |
| 0x01C | SIM_EXIT | WO | — | 仿真结束码，0 = 通过 |

`CLK_SYS_HZ` 的值来自 `rtl/include/` 中由工具生成的常量 `EDRV32_CLK_SYS_HZ`，与 UART、I2C 复位值的计算使用同一个常量。

---

## 5. 行为与时序

- **sys_xbar 时序**：地址通道到从设备可以有一级寄存器；R、B 返回路径可以有一级寄存器；总延迟满足 2.1 的 SRAM 3 周期要求。实现必须保持 AXI 握手规则（VALID 不依赖 READY，负载在握手前保持）。
- **ROM / SRAM 从接口**：读突发按 INCR 逐拍读出，每拍一个周期；写突发逐拍写入，最后一拍后回 B。
- **APB 传输**：SETUP 一个周期、ACCESS 至少一个周期，等 `pready`；`pslverr` 原样转为 SLVERR。
- **媒体 APB 桥**：一笔 AXI 访问通过 `edrv32_apb_async_bridge` 转为 clk_mem 域的一次 APB 传输，结果返回 clk_sys 后再完成 AXI 响应。异步桥内部用握手同步（`cdc_handshake` 或等效的格雷码 FIFO 结构），只有一笔传输在途。
- **PLIC 认领时序**：读 CLAIM 的 AXI 读事务被接受的那个周期完成认领判定，返回的源号与清除的 pending 一致。

---

## 6. 错误处理

| 错误 | 检测 | 上报 |
|---|---|---|
| 地址未映射、连接矩阵禁止 | sys_xbar 译码 | DECERR |
| 写 ROM | ROM 从接口 | SLVERR |
| APB 不合规访问（突发、SIZE ≠ 2、未对齐） | APB 桥（AXI 侧） | SLVERR，不发 APB 传输 |
| 预留槽 | 例化处的 tie-off（2.3） | SLVERR，不向任何实际外设发出 APB 传输 |
| APB 超时 | APB 桥计数 | SLVERR |
| CLINT、PLIC 的突发或 SIZE ≠ 2 访问 | 从接口 | SLVERR |
| UART 接收溢出、帧错误 | UART | IRQ_STAT.RX_OVERRUN / FRAME_ERR |
| I2C 从设备 NACK | I2C | STATUS.NACK；命令照常完成并置 DONE |

除上表外不设其他错误检测。

---

## 7. 性能与资源指标

| 指标 | 要求 |
|---|---|
| SRAM / ROM 读延迟 | 无竞争时从 ARVALID 被接收到第一个 RVALID ≤ 3 个 clk_sys 周期 |
| SRAM 突发吞吐 | 4 拍突发连续 4 个周期返回 |
| UART | 3 Mbps 下连续收发不丢字节（软件及时读写 FIFO 的前提下） |
| 资源 | 本规格全部模块合计 ≤ 5K LUT（SoC 规格 9.3）；ROM 和 SRAM 使用 DRM：16 KiB + 64 KiB |
| 频率 | 在 clk_sys 目标频率下满足时序（CPU 规格待定项 10，初值 150 MHz） |

---

## 8. 验证要点

见 `docs/testplan/sys-subsys-testplan.md`。

---

## 9. 待定事项

| # | 事项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | CHIP_ID 的值 | 0xED32_0001 | 用户确认 |
| 2 | clk_sys 频率（影响 CLK_SYS_HZ 和各复位值） | 150 MHz | CPU 规格待定项 10（C-W2 综合结果） |
| 3 | ROM、SRAM 的 IP 名称和创建说明 | 包装模块名见第 1 节 | 用户在 PDS 中生成后确认 |
| 4 | 软复位脉宽 | 16 个 clk_sys 周期 | 板级验证 |

---

## 10. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-25 | v0.1 | 初稿。与用户确认：mtime 每个 clk_sys 周期加 1、SYSCTRL 提供 CLK_SYS_HZ；PLIC 15 个源；去掉 QSPI0 和 TIMER0；Boot ROM 与 SRAM 由存储初始化文件提供上电内容；I2C0 一个主机两对引脚 |
| 2026-10-25 | v0.2 | 开发中澄清：APB 路径拆为 bridge（AXI→单个 APB 口）+ decoder（槽译码、预留、超时），媒体路径 decoder 在 clk_mem；增加 3.4 系统子系统顶层端口；CLINT/PLIC 合法写的 WSTRB 恒为全 1、整字写入；UART EN/CLR 不打断进行中的帧 |
| 2026-10-26 | v0.3 | SRAM 由 256 KiB 改为 64 KiB（8192 × 64 位）。用户确认：旧工程 FPGA 实际只用 32 KiB SRAM；现有 DDR 承担大块数据，SRAM 只放监控程序、CoreMark 和栈，省下的 DRM 留给 NPU 片上缓存 |
| 2026-10-28 | v0.4 | 2.10：reset_ctrl 增加 clk_npu 输入和 `rst_npu_n` 输出（与 `rst_mem_n` 一起请求释放，媒体软复位和 SoC 软复位覆盖），对应 npu-spec 3 节 `rst_npu_n_i` 和 SoC 5.3 第 2 条（用户确认 2026-10-28，B2-1 准备时发现遗漏） |
