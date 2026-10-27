# DISP 显示规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-27 |
| 状态 | 已确认（v0.1，2026-10-27） |
| 范围 | `edrv32_disp`：单层 RGB565 Surface 扫描、跨时钟域扫描 FIFO、720p60 显示时序、TMDS 编码、DISP 寄存器块。TMDS 10:1 串化、差分输出和 PLL 在 FPGA 层（`fpga/rtl/`）；图层合成在 RND 阶段与 RND 一起确定（SoC 8.8） |
| 关联文档 | SoC 规格 v0.9 3.3、4.2、5.1、5.2（X5、X6）、7.1、7.3、8.8、8.11；`dma2d-spec.md` v0.1；设计记录 `2026-10-27-image-path.md`（Q3、Q6）；旧工程盘点 `2026-10-27-image-path-legacy-inventory.md` 1.2、2 |

---

## 1. 概述

DISP 每帧从 DDR 读一张 1280×720 RGB565 Surface，经扫描 FIFO 送到 clk_pix 域，按 CEA-861 720p60 时序输出 TMDS 符号（SoC 3.3 `tmds_sym_o`）。软件通过"下一 Surface"寄存器交接帧（设计记录 Q6），新 Surface 在帧边界生效。

```
clk_mem:  寄存器块 ─ 读控制 ─ dma2d_rd ─ mem_xbar P0
                         │          │
                         │      async_fifo（X5）
clk_pix:  帧请求(X6) ── 显示时序 ─ 扫描 ─ TMDS 编码 ─ tmds_sym_o
```

时钟域：寄存器块、读控制、`dma2d_rd` 在 clk_mem；显示时序、扫描、TMDS 编码在 clk_pix（SoC 5.1）。复位：`rst_mem_n`、`rst_pix_n`（系统子系统规格 2.10）。

## 2. 功能描述

### 2.1 显示时序（按旧工程移植）

与旧工程 `edrv32_hdmi_timing.v` 相同（盘点 1.2、2），参数固定，不提供寄存器：

| 项 | 水平（像素） | 垂直（行） |
|---|---:|---:|
| 有效 | 1280 | 720 |
| 前沿 | 110 | 5 |
| 同步 | 40 | 5 |
| 后沿 | 220 | 20 |
| 总计 | 1650 | 750 |

像素时钟 74.25 MHz，帧率 60 Hz；HS、VS 高有效。行、场计数从 `rst_pix_n` 释放后立即开始，与 `CTRL.ENABLE` 无关，始终输出完整时序（显示器不失锁）；未扫描的帧输出黑色。

### 2.2 TMDS 编码（按旧工程移植）

- 三个通道 B、G、R 各一个 8b/10b TMDS 编码器，算法与旧工程 `edrv32_tmds_encoder.v` 相同（最小化跳变 + 直流平衡，运行差异计数）。
- 有效区编码像素；消隐区输出控制符号：B 通道的 `{c1, c0}` = `{VS, HS}`，G、R 通道为 `{0, 0}`。
- DVI 编码方式：不发送数据岛（无 InfoFrame、无音频）。
- `tmds_sym_o[9:0]` = B，`[19:10]` = G，`[29:20]` = R（SoC 3.3）。时钟通道符号（`10'b1111100000`）、10:1 串化、`GTP_OSERDES_E2`、`GTP_OUTBUFDS` 在 FPGA 层（盘点 8 移植清单）。

### 2.3 像素格式

RGB565 展开为每通道 8 位：R、B `{v[4:0], v[4:2]}`，G `{v[5:0], v[5:4]}`（与 PIX 相同）。

### 2.4 帧请求与 Surface 生效

1. 每帧最后一个有效行结束时（进入场消隐，第 720 行开始），显示时序在 clk_pix 采样同步后的 `CTRL.ENABLE`：为 1 则本帧之后的下一帧**扫描**，并向 clk_mem 发一个帧请求脉冲（X6）；为 0 则下一帧输出黑色，不发请求。
2. 读控制收到帧请求后：若上一帧已经全部读完，立即开始读新的一帧；否则记下这个请求，在上一帧读完后立即开始。
3. 开始读一帧时锁存 `NEXT_BASE`、`STRIDE` 为本帧的 `CUR_BASE`、`CUR_STRIDE`（SoC 8.8"新 Surface 只在 VBlank 生效"：锁存发生在场消隐开始之后，新内容从下一帧第一个像素起显示）。
4. 锁存的同一拍置 `IRQ_STAT.FRAME`、`FRAME_CNT` 加 1。若 `CUR_BASE` 与上一帧不同，同时置 `IRQ_STAT.SWITCH`，`REL_BASE` = 上一帧的 `CUR_BASE`：此时上一帧的全部读事务已经完成，旧 Surface 已释放（SoC 7.3 R3、R4），软件可以把它交给生产者。
5. 软件不改 `NEXT_BASE` 时，每帧重复显示同一张 Surface（SoC 8.8"无新帧"），不置 SWITCH。
6. 场消隐 30 行（约 0.67 ms）是新帧的预取时间。

### 2.5 读取

- 每帧 720 行，每行发出一个 `dma2d_rd` 描述符：`base = CUR_BASE + y × CUR_STRIDE`，`stride = CUR_STRIDE`，`width_bytes = 2560`，`height = 1`；每行 80 beat。
- 只有扫描 FIFO 的空位不少于一整行（80 beat）时才发出下一行的描述符；因此 `dma2d_rd` 的输出始终被接收，P0 的读数据通道不反压（不占住 mem_xbar 读返回缓冲，SoC 6.4.4）。
- `dma2d_rd` 的 `OUTSTANDING` = 4。
- 扫描 FIFO 的水位在 clk_mem 侧由写入计数减去同步过来的读出计数得到（读出计数经 `cdc_gray_cnt`，X6）；同步延迟只会使水位偏高、空位偏少，不会溢出。

### 2.6 扫描 FIFO

- `rtl/common/edrv32_async_fifo.v`，宽 256 位，深度 512 **[待定]**（6.4 行；SoC 8.8 要求至少 2 行）。
- `urgent_o`：读控制正在读一帧且 FIFO 水位低于 80 beat（1 行）时为 1（SoC 8.8）。

### 2.7 扫描与读空

- 被扫描的帧在有效区每 16 个像素从 FIFO 取一个 beat（低地址像素先显示，SoC 4.5 像素顺序）。
- 需要取 beat 时 FIFO 为空：本组 16 个像素输出黑色，**欠账**计数加 1，本帧记为读空（ERROR、计数，见第 6 节）。
- 欠账不为 0 时，FIFO 中到达的 beat 先丢弃（每丢一个欠账减 1），再用于显示。欠账跨帧保留。由于各帧按请求顺序完整读出（2.4 第 2 条），丢弃的正好是迟到的、已经错过显示位置的 beat，后续像素位置保持对齐。
- 未扫描的帧（2.4 第 1 条为 0）输出黑色，不为显示从 FIFO 取数，也不计读空；欠账偿还（丢弃迟到 beat）不受此限制，在消隐和未扫描帧中照常进行。

## 3. 接口

`edrv32_disp` 端口：

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `clk_mem_i` | in | 1 | — | 125 MHz |
| `rst_mem_n_i` | in | 1 | clk_mem | |
| `clk_pix_i` | in | 1 | — | 74.25 MHz |
| `rst_pix_n_i` | in | 1 | clk_pix | |
| `apb_*` | — | — | clk_mem | 媒体 APB 槽 5 从口（SoC 4.3） |
| `p0_ar* p0_r*` | — | — | clk_mem | AXI256 读通道（SoC 4.2），本地 ID 固定为 0 |
| `p0_urgent_o` | out | 1 | clk_mem | 2.6 |
| `tmds_sym_o` | out | 30 | clk_pix | 2.2 |
| `irq_o` | out | 1 | clk_mem | PLIC 源 12 |

## 4. 寄存器

媒体 APB 槽 5。公共寄存器按 SoC 7.1；寄存器块忽略 `pstrb`，按整字写。未列出的偏移读为 0、写忽略。

### 4.1 公共寄存器

| 偏移 | 名称 | 规定 |
|---|---|---|
| 0x000 | ID | 0x0005_0001 |
| 0x004 | CTRL | bit0 ENABLE（2.4 第 1 条，下一帧生效）；bit1 START 无作用；bit2 ABORT（5.2）；bit3 SOFT_RST：先按 5.2 停止接受帧请求，等到 STATUS.IDLE（已请求的帧读完、欠账归零），再把 clk_mem 侧寄存器和控制状态回到复位值；扫描 FIFO 和跨域计数器不复位，PERF0–2 以 SOFT_RST 时的值为基线清零；clk_pix 侧由媒体软复位复位（系统子系统规格 2.10） |
| 0x008 | STATUS | BUSY = 读控制正在读一帧或有记下的请求，或已发出的帧请求数不等于同步到 clk_mem 的 PERF0（扫描侧还有已请求未扫完的帧），或扫描 FIFO 写入计数不等于同步后的读出计数（FIFO 未排空，含欠账待丢弃的 beat）；不另设跨域信号；IDLE = 非 BUSY；ERROR = IRQ_STAT.ERROR |
| 0x010 | IRQ_STAT | bit1 ERROR；bit2 FRAME（2.4 第 4 条）；bit8 SWITCH |
| 0x014 | ERR_CODE | 第 6 节 |
| 0x020–0x028 | DESC_BASE、DESC_COUNT、DOORBELL | 不使用 |
| 0x02C | DONE_COUNT | 等于 FRAME_CNT |
| 0x040–0x07C | PERF | 4.3 |

### 4.2 私有寄存器

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x100 | NEXT_BASE | RW | 0 | [31:12]，[11:0] 读为 0（4 KiB 对齐，SoC 7.3）。下一帧开始读取时锁存 |
| 0x104 | STRIDE | RW | 0x0A00 | [15:5]，[4:0] 读为 0。同上锁存 |
| 0x108 | CUR_BASE | RO | 0 | 正在读取或最近读取的帧所用的基址 |
| 0x10C | REL_BASE | RO | 0 | 最近一次 SWITCH 释放的基址 |
| 0x110 | FRAME_CNT | RO | 0 | 已开始读取的帧数，32 位回绕 |

### 4.3 性能计数器

32 位，回绕；SOFT_RST 清零。clk_pix 侧的计数经 `cdc_gray_cnt` 送到 clk_mem（X6）。

| PERF | 内容 |
|---|---|
| 0 | 扫描的帧数（clk_pix），在该帧最后一个有效像素输出时加 1 |
| 1 | 读空的帧数（clk_pix） |
| 2 | 读空的 beat 数（输出黑色的 16 像素组数，clk_pix） |
| 3 | `p0_urgent_o` 为 1 的 clk_mem 周期数 |
| 4 | 帧请求到达时上一帧尚未读完的次数（2.4 第 2 条） |

## 5. 行为与时序

### 5.1 使能

- `CTRL.ENABLE` 置 1：下一个场消隐开始时发出第一个帧请求，再下一帧开始显示 Surface。
- 清零：已请求的帧照常读完并扫描完，之后输出黑色。

### 5.2 ABORT

DISP 没有可中止的命令。`CTRL.ABORT` 写 1 等同于把 `CTRL.ENABLE` 清零：不再接受新的帧请求，已请求的帧照常读完（保证扫描侧欠账能够归零，2.7），之后 STATUS.IDLE = 1，不留下未完成的总线事务（SoC 7.1）。

### 5.3 软件交接（设计记录 Q6）

1. 生产者（VIN CH0 或 GEO）报告某 Surface 完成；
2. 软件写 `NEXT_BASE`；
3. 下一次 FRAME 中断时，若 SWITCH = 1，`REL_BASE` 指向的 Surface 交还生产者（清除其 SLOT_BUSY 标记或放回空闲环）；
4. 显示中的 Surface（`CUR_BASE`）由软件在生产者侧标为占用（VIN `CHn_SLOT_BUSY`），满足 SoC 7.3 R3。

## 6. 错误处理

| ERR_CODE | 错误 | 检测 | 上报 | 恢复 |
|---|---|---|---|---|
| 1 | 读空 | 扫描侧（2.7），每个读空的帧上报一次（X6 脉冲） | IRQ_STAT.ERROR、PERF 1–2 | 欠账机制自动恢复对齐 |
| 2 | 读响应非 OKAY | `dma2d_rd` `err_o` | IRQ_STAT.ERROR | 数据照常显示 |

寄存器的对齐由位宽保证，不另行检查。

## 7. 性能与资源指标

| 项 | 指标 |
|---|---|
| 带宽 | 720p60 RGB565：110.6 MB/s |
| 实时性 | SoC 级仿真 S1、S2、S3 流量下读空次数为 0（SoC 9.2） |
| 时序 | clk_pix 74.25 MHz、clk_mem 125 MHz 收敛 |
| 资源 | DISP 应不超过 2.5K LUT；扫描 FIFO 用 DRM **[待定]**，以 PDS 实测定稿 |

## 8. 验证要点

1. 时序：HS/VS/DE 的位置和宽度与 2.1 逐项一致；TMDS 符号与参考编码器（Python 模型）逐符号一致，运行差异在消隐后正确复位。
2. 扫描：DDR 中的测试图（含每行不同内容、stride > 2560）逐像素与输出一致。
3. 交接：帧中写 NEXT_BASE 只在下一帧生效；FRAME、SWITCH、REL_BASE 的时刻与值；不改 NEXT_BASE 时重复显示。
4. 读空：P0 长时间不响应造成读空，输出黑色、计数正确，DDR 恢复后像素位置对齐（欠账）；帧请求到达时上一帧未读完。
5. 读取不反压：任何情况下 `p0_rready` 为 1。
6. 使能、关闭、ABORT 后无未完成事务；clk_pix 与 clk_mem 频率比变化。

## 9. 待定事项

| # | 事项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | 扫描 FIFO 深度 | 512 × 256 位 | SoC 级仿真 P0 最长等待 |
| 2 | 资源指标 | 7 节 | PDS 实测 |
| 3 | 板级 PLL（74.25 / 371.25 MHz）、HDMI 引脚和 IO 标准 | 盘点 2：仓库中无依据 | Windows 板级任务卡 |

## 10. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-27 | v0.1 | 初稿：依据 SoC 规格 8.8、设计记录 `2026-10-27-image-path.md`、旧工程盘点；用户确认（Q8 不完整帧补齐标记、ENABLE 后丢 2 帧、DISP 读空欠账） |
| 2026-10-27 | v0.1 | 澄清（V-R2 问答，不改变已确认的行为）：4.1 STATUS.BUSY 的扫描部分由帧请求数与 PERF0、FIFO 写入与读出计数比较得到；4.3 PERF0 的计数时刻；2.7 欠账偿还在未扫描帧中继续；4.1 SOFT_RST 先停机排空再复位 clk_mem 侧 |
