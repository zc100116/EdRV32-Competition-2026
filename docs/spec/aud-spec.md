# AUD 放音规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-11-23 |
| 状态 | 草案（待用户确认） |
| 范围 | `edrv32_aud`：从 DDR 环形缓冲读取 16 位立体声样本，作为 I2S 主机以 48 kHz 输出；AUD 寄存器块 |
| 关联文档 | `gpu-soc-spec.md` v0.1 3、5.2（X11）、6.1、6.2；视觉规格 4.2、4.3、7.1；设计记录 `2026-11-23-gpu-architecture.md` R8、`2026-11-23-audio-pmod-pins.md` |

---

## 1. 概述

CPU 把混好的样本写进 DDR 环形缓冲并推进写指针；AUD 按需读入样本 FIFO，在 clk_aud 域以 I2S 格式移位输出给 ES8156。ES8156 的寄存器由软件通过 I2C0 配置为 I2S 从机。

```
媒体 APB 槽 1 ─ 寄存器块 ─ DMA ─ mem_xbar P1（只读）
                             │
                       样本 FIFO（async_fifo，X11）
                             │ clk_aud
                       I2S 发送 ─ aud_bclk_o / aud_lrck_o / aud_sdata_o
```

- 时钟域：寄存器块和 DMA 在 clk_mem（复位 `rst_mem_n`）；I2S 发送在 clk_aud（复位 `rst_aud_n`）。
- 中断：PLIC 源 8。寄存器块的 ID.TYPE = 1。

## 2. 功能描述

### 2.1 样本格式

- 每个样本帧 4 B：低 16 位为左声道，高 16 位为右声道，各为 16 位有符号小端。
- 采样率固定 48 kHz。

### 2.2 环形缓冲

- 缓冲位于 DDR，基址 `RING_BASE` 为 512 B 对齐，大小 `RING_SIZE` 为 512 B 的整数倍。
- 软件写入样本后推进写偏移 `WR_PTR`；AUD 读入后推进读偏移 `RD_PTR`。两者都是相对基址的字节偏移，32 B 对齐，到 `RING_SIZE` 回绕到 0。
- `RD_PTR` = `WR_PTR` 表示缓冲为空。软件不得写到使 `WR_PTR` 追上 `RD_PTR` 的位置，即至少留 32 B 空隙。
- 可读数据量 avail = (`WR_PTR` − `RD_PTR`) mod `RING_SIZE`。

### 2.3 DMA

- 当 avail > 0，且样本 FIFO 的空位不少于一次读取的量时，发起读取。每次最多 512 B（16 拍），不超过 avail，不跨越缓冲末尾，不跨 4 KiB（视觉规格 4.2）。
- 在途读事务最多 1 个。读回的数据按地址顺序写入样本 FIFO。

### 2.4 样本 FIFO

- `async_fifo`，宽 32 位（一个样本帧），深度 512 **[待定]**（A-1），约 10.7 ms。
- `urgent_o`：`CTRL.ENABLE` = 1 且 FIFO 水位低于 64 **[待定]**（A-2）时为 1。

### 2.5 I2S 发送（clk_aud）

- BCLK = clk_aud / 4 = 3.072 MHz；LRCK = BCLK / 64 = 48 kHz。每个声道 32 个 BCLK。
- 标准 I2S 格式：LRCK 低电平为左声道；数据在 LRCK 跳变后的第 2 个 BCLK 开始，MSB 在前，16 位有效，其余位输出 0；数据在 BCLK 下降沿更新。
- 每个 LRCK 周期开始时，从 FIFO 取一个样本帧；FIFO 为空时输出 0，并产生一次欠载事件（X11，`cdc_pulse`）。
- 放音使能（`CTRL.ENABLE` 经 `cdc_sync_bit`）为 0 时，BCLK、LRCK 照常输出，数据为 0，不从 FIFO 取数，也不计欠载。

## 3. 接口

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `clk_mem_i`、`rst_mem_n_i` | in | 1 | — | |
| `clk_aud_i`、`rst_aud_n_i` | in | 1 | — | |
| `s_apb_*` | — | — | clk_mem | APB 从口（视觉规格 4.3），本地寄存 |
| `m_axi_ar*`、`m_axi_r*` | — | — | clk_mem | AXI256 读通道（视觉规格 4.2），接 mem_xbar P1 |
| `urgent_o` | out | 1 | clk_mem | 2.4 |
| `irq_o` | out | 1 | clk_mem | `|(IRQ_STAT & IRQ_EN)` |
| `aud_bclk_o`、`aud_lrck_o`、`aud_sdata_o` | out | 1 | clk_aud | 2.5 |

## 4. 寄存器

公共寄存器按视觉规格 7.1（DESC_BASE、DESC_COUNT、DOORBELL、DONE_COUNT 不使用，读为 0）。私有寄存器：

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x100 | RING_BASE | RW | 0 | [31:9]，[8:0] 读为 0 |
| 0x104 | RING_SIZE | RW | 0 | [23:9]，[8:0] 读为 0 |
| 0x108 | WR_PTR | RW | 0 | [23:5]，[4:0] 读为 0 |
| 0x10C | RD_PTR | RO | 0 | [23:5] |
| 0x110 | LOW_LEVEL | RW | 0 | 字节数；avail 从 ≥ LOW_LEVEL 变为 < LOW_LEVEL 时置 IRQ_STAT.LOW（bit8） |
| 0x114 | UNDERRUN_CNT | RO | 0 | 欠载次数，32 位饱和 |

- `CTRL.ENABLE` 由 0 变 1 时，`RD_PTR` 清零。`RING_BASE`、`RING_SIZE` 只在 `CTRL.ENABLE` = 0 时写入有效。
- `CTRL.ENABLE` 变为 0：停止发起新读取；在途读取完成后丢弃 FIFO 中的样本；I2S 输出 0。

## 5. 行为与时序

- 软件典型用法：每次收到 LOW 中断，混一段样本写入缓冲，再推进 `WR_PTR`。
- 从样本写入 DDR 到被播放的延迟 = 缓冲中尚未播放的数据量 + FIFO 水位，由软件通过 `LOW_LEVEL` 和写入量控制。

## 6. 错误处理

| ERR_CODE | 错误 | 处理 |
|---|---|---|
| 1 | AXI 读错误响应 | 置 ERROR，停止 DMA（已发出的事务照常完成）；I2S 继续输出 FIFO 中剩余样本，之后输出 0 |

欠载不是错误，只计数（4、2.5）。

## 7. 性能与资源指标

| 项 | 指标 |
|---|---|
| 持续带宽 | 192 KB/s |
| 实时性 | 软件按时补充样本时，任何总线负载下不欠载（P1 为 RT 端口，带紧急信号） |
| 资源 | LUT ≤ 1K **[待定]**；DRM 1 块（样本 FIFO） |

## 8. 验证要点

1. I2S 波形：BCLK、LRCK 频率和相位，数据位置、MSB 在前、左右声道顺序，与参考模型逐位比对。
2. 环形缓冲：回绕、空缓冲、`WR_PTR` 推进后继续播放；4 KiB 和缓冲末尾处的读拆分。
3. LOW 中断的触发条件；欠载输出 0 并计数；ENABLE 关闭和重新打开。
4. AXI 错误响应。
5. P1 紧急信号的水位。

## 9. 待定事项

| 编号 | 事项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| A-1 | 样本 FIFO 深度 | 512 | 上板听感和 DDR 延迟测量 |
| A-2 | 紧急水位 | 64 | 同上 |
| A-3 | ES8156 寄存器配置表（从机、I2S、16 位） | 依据厂家例程 `ES8156_reg_config.v` 改为从机 | 上板 |

## 10. 变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-11-23 | v0.1 | 初稿。依据设计记录 R8：只做放音、FPGA 为 I2S 主机、CPU 软件混音 |
