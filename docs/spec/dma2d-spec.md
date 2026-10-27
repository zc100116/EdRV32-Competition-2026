# 公共 2D DMA 单元规格（dma2d_rd、dma2d_wr）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-27 |
| 状态 | 已确认（v0.1，2026-10-27） |
| 范围 | `edrv32_dma2d_rd`、`edrv32_dma2d_wr`：把一块二维区域的读写拆成符合 AXI256 的事务。引擎内部多客户端仲裁、Surface 环形缓冲和帧交接不在本单元 |
| 关联文档 | SoC 规格 v0.8 4.2（AXI256）、7.3（Surface）、8.11；`docs/design/2026-10-27-image-path.md` |

---

## 1. 概述

所有引擎访问 DDR 都经过这两个单元（SoC 规格 8.11）。`dma2d_rd` 接受一个读描述符，输出按行组织的 256 位数据流；`dma2d_wr` 接受一个写描述符和 256 位数据流，产生写事务，最后一个写响应返回后报告完成。两者都在使用它的引擎的时钟域（clk_mem），单时钟，放在 `rtl/common/`。

使用者：VIN（`dma2d_wr` × 2：CH0、CH1；`dma2d_rd` × 1：内存源）、DISP（`dma2d_rd`）、GEO（各 1）。NPU 的 DMA 由 NPU 规格单独规定。

## 2. 功能描述

### 2.1 描述符

| 字段 | 位宽 | 规定 |
|---|---|---|
| `base` | 32 | 区域首字节的 DDR 物理地址，32 B 对齐 |
| `stride` | 32 | 相邻两行首地址之差（字节），32 B 的整数倍 |
| `width_bytes` | 16 | 每行字节数，1–65535 |
| `height` | 12 | 行数，1–4095 |

描述符字段由使用者保证满足上表；单元不检查（使用者的规格负责检查软件配置）。

### 2.2 事务拆分

- 每行占 `ceil(width_bytes / 32)` 个 beat，从行首地址开始连续。
- 一行按地址递增拆成若干突发：每个突发最多 16 beat，不跨 4 KiB 边界；在不违反这两条的前提下突发尽量长。
- 行与行之间不合并突发。
- 事务 ID 固定为 0（SoC 4.2 本地 ID 1 位）。

### 2.3 dma2d_rd 输出流

- 每个 beat 一个 256 位字，字节 0 对应最低地址。
- `sol` 标在每行第一个 beat，`eol` 标在每行最后一个 beat，`eof` 标在最后一行的最后一个 beat。
- 行末 beat 中超出 `width_bytes` 的字节内容不确定，使用者丢弃。
- 输出顺序与地址顺序相同。

### 2.4 dma2d_wr 输入流

- 使用者每行恰好提供 `ceil(width_bytes / 32)` 个 beat，按地址顺序；字节使能 `strb` 由使用者给出（行末部分 beat 的无效字节 strb = 0）。
- 单元按 2.2 拆分产生 AW，W 数据按到达顺序填入各突发，`wlast` 由单元产生。

### 2.5 完成

- `dma2d_rd`：最后一个 R beat 被使用者接收后，`done_o` 拉高一个周期。
- `dma2d_wr`：全部写响应返回后，`done_o` 拉高一个周期（SoC 7.3 R2 的完成依据）。
- 完成后才接受下一个描述符。

## 3. 接口

两个模块共有：

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `clk_i` | in | 1 | — | 使用者的时钟（clk_mem） |
| `rst_n_i` | in | 1 | clk_i | 本域同步释放的复位 |
| `desc_valid_i` / `desc_ready_o` | in / out | 1 / 1 | clk_i | 描述符握手；`desc_ready_o` 只在空闲时为 1 |
| `desc_base_i` | in | 32 | clk_i | 2.1 |
| `desc_stride_i` | in | 32 | clk_i | 2.1 |
| `desc_width_bytes_i` | in | 16 | clk_i | 2.1 |
| `desc_height_i` | in | 12 | clk_i | 2.1 |
| `abort_i` | in | 1 | clk_i | 第 5.3 节 |
| `idle_o` | out | 1 | clk_i | 没有描述符在执行、没有未完成的 AXI 事务 |
| `done_o` | out | 1 | clk_i | 2.5，单周期脉冲 |
| `err_o` | out | 1 | clk_i | 与 `done_o` 同周期有效：本描述符有过非 OKAY 响应（第 6 节） |

`edrv32_dma2d_rd` 另有：

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `data_valid_o` / `data_ready_i` | out / in | 1 / 1 | clk_i | 输出流握手 |
| `data_o` | out | 256 | clk_i | 2.3 |
| `data_sol_o`、`data_eol_o`、`data_eof_o` | out | 1 | clk_i | 2.3 |
| `axi_ar*`、`axi_r*` | — | — | clk_i | AXI256 读通道（SoC 4.2）：`arid`(1) `araddr`(32) `arlen`(4) `arvalid` `arready` `rid`(1) `rdata`(256) `rresp`(2) `rlast` `rvalid` `rready` |

`edrv32_dma2d_wr` 另有：

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `data_valid_i` / `data_ready_o` | in / out | 1 / 1 | clk_i | 输入流握手 |
| `data_i` | in | 256 | clk_i | 2.4 |
| `data_strb_i` | in | 32 | clk_i | 2.4 |
| `axi_aw*`、`axi_w*`、`axi_b*` | — | — | clk_i | AXI256 写通道（SoC 4.2）：`awid`(1) `awaddr`(32) `awlen`(4) `awvalid` `awready` `wdata`(256) `wstrb`(32) `wlast` `wvalid` `wready` `bid`(1) `bresp`(2) `bvalid` `bready` |

参数（每个实例固定，由使用者的规格给出取值）：

| 参数 | 范围 | 说明 |
|---|---|---|
| `OUTSTANDING` | 1–8 | 未完成突发数上限：`dma2d_rd` 为已发 AR 但未收完 R 的突发数，`dma2d_wr` 为已发 AW 但未收到 B 的突发数 |

## 4. 寄存器

无。描述符由使用者从自己的寄存器或描述符给出。

## 5. 行为与时序

### 5.1 dma2d_rd

1. 接受描述符后，按 2.2 依次发出 AR；未完成突发数达到 `OUTSTANDING` 时暂停。
2. R 数据按到达顺序加上 `sol/eol/eof` 后送到输出流；`axi_rready_o` = `data_ready_i`（mem_xbar 的读返回缓冲吸收反压，SoC 4.2）。
3. 最后一个 beat 输出被接收后 `done_o`。

### 5.2 dma2d_wr

1. 接受描述符后，突发的第一个 beat 在输入流上可用时发出该突发的 AW；未完成突发数达到 `OUTSTANDING` 时暂停。
2. W 按到达顺序发出，每个突发的最后一拍置 `wlast`；`data_ready_o` 在当前突发的 AW 已发出（或同拍发出）时跟随 `axi_wready_i`。
3. 收齐全部 B 后 `done_o`。

### 5.3 ABORT

`abort_i` 拉高一个周期后：已置 VALID 的 AR/AW 视为已发出，保持负载直到握手（SoC 4.2 握手规则）；不再发出新的 AR/AW；`dma2d_rd` 继续接收已发 AR 的全部 R 并丢弃，不再向输出流送数据；`dma2d_wr` 已置 VALID 的 W beat 保持原数据和 `wstrb` 直到握手，已发 AW 中其余尚未发出的 beat 以 `wstrb` = 0 补齐，并等待其 B。全部完成后 `idle_o` = 1，不产生 `done_o`。ABORT 不留下未完成的总线事务（SoC 7.1）。

### 5.4 吞吐

在 `arready/awready/wready/rvalid` 不阻塞时，数据流每拍 1 beat（32 B/拍 @125 MHz = 4 GB/s），突发之间不插空拍。

## 6. 错误处理

| 错误 | 检测 | 上报 | 恢复 |
|---|---|---|---|
| `rresp` 或 `bresp` 非 OKAY | 每个 R/B | 记录到本描述符结束，与 `done_o` 同拍 `err_o` = 1；数据照常传递 | 无需恢复，使用者决定 ERR_CODE |

单元不检查描述符字段，也不检测超时。

## 7. 性能与资源指标

| 项 | 指标 |
|---|---|
| 吞吐 | 5.4 |
| 资源 | 每个实例应不超过 600 LUT、800 FF，不用 DRM **[待定]**，以 PDS 实测定稿 |

## 8. 验证要点

1. 拆分：各种 `base`（含距 4 KiB 边界 32 B、512 B）、`width_bytes`（1、32、33、512、513、5120）、`stride`、`height` 组合下，AR/AW 地址、长度与 2.2 逐一相符，不跨 4 KiB，最长 16 beat。
2. 数据：读出流与存储模型逐字节一致，`sol/eol/eof` 位置正确；写入内容与字节使能逐字节一致。
3. 反压：随机 `arready/rvalid/awready/wready/bvalid/data_ready/data_valid`；`OUTSTANDING` 取 1 和 8 时未完成突发数从不超过上限。
4. 完成：`done_o` 时刻（读：最后一个输出 beat 接收后；写：最后一个 B 后）。
5. 错误：注入 SLVERR/DECERR，`err_o` 与 `done_o` 同拍；数据不受影响。
6. ABORT：在各阶段（AR 发出中、R 返回中、W 部分发出）中止，最终无未完成事务、`idle_o` = 1、无 `done_o`。

## 9. 待定事项

| # | 事项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | 资源指标 | 7 节 | PDS 实测 |

## 10. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-27 | v0.1 | 初稿，依据 SoC 规格 8.11 和图像通路设计记录；2026-10-27 用户确认 |
| 2026-10-27 | v0.1 | 5.3 澄清：ABORT 时已置 VALID 的 AR/AW/W 保持到握手（V-D1 问答，AXI 握手规则的直接推论，不改变行为） |
