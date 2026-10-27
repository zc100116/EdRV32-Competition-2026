# VIN 视频输入规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-27 |
| 状态 | 草案 |
| 范围 | `edrv32_vin`：两路 DVP 采集前端、内存源、选路、CH0/CH1 Surface 写通道、CH2 NPU 输入通道、P1 端口内部仲裁、VIN 寄存器块。PIX 只规定它在 CH0 上的位置，功能见 `pix-spec.md`；传感器初始化由软件经 I2C0 完成，不在本模块 |
| 关联文档 | SoC 规格 v0.9 草案 4.2、4.5、5.2（X4）、7.1–7.3、8.5、8.11；`dma2d-spec.md` v0.1；`npu-spec.md` v0.3 2.2；设计记录 `2026-10-27-image-path.md`（Q5、Q6、Q7、NPU 输入适配）；旧工程盘点 `2026-10-27-image-path-legacy-inventory.md` 1.1、2、3 |

---

## 1. 概述

VIN 把摄像头或 DDR 中的图像整理成逐帧的像素流（SoC 4.5），经选路分给三个通道写回 DDR：

- CH0：经 PIX 处理后写入 Surface 环（S2 的处理图像、S1 的显示底图）；
- CH1：不经 PIX 写入 Surface 环（硬件完整实现，为两路拼接预留，SoC 8.5）；
- CH2：NPU 输入通道，把图像缩放、letterbox、转换为 INT8_C4 后写入 NPU 输入环（本阶段只写规格，RTL 在 S1 联调中实现，见设计记录"NPU 输入适配"）。

三个输入源：cam0、cam1（DVP 采集）和内存源（从 DDR 读一张 RGB565 Surface，用于网口送来的图像，设计记录 Q7）。

```
cam0 DVP ─ 前端(cam0_pclk) ─ async_fifo ─ 帧整形 ─┐
cam1 DVP ─ 前端(cam1_pclk) ─ async_fifo ─ 帧整形 ─┼─ 选路 ─┬─ PIX ─ CH0 写 FIFO ─ dma2d_wr ─┐
DDR ─ dma2d_rd ─ 输入缓冲 ─ 拆包 ──────────────────┘        ├─────── CH1 写 FIFO ─ dma2d_wr ─┼─ P1 仲裁 ─ mem_xbar P1
                                                             └─ NPU 适配 ─ CH2 FIFO ─ dma2d_wr ┘   （内存源的 AR/R 也经 P1）
```

时钟域：DVP 前端在各自的 camN_pclk 域，到异步 FIFO 为止（SoC 5.2 X4）；其余全部在 clk_mem。复位：前端用 `rst_cam0_n` / `rst_cam1_n`，其余用 `rst_mem_n`（系统子系统规格 2.10）。

## 2. 功能描述

### 2.1 DVP 采集前端（cam0、cam1 各一个，按旧工程移植）

行为与旧工程 `edrv32_ov5640_capture.v` 一致（盘点 1.1、2），只改输出接口：

- 在 camN_pclk 上升沿采样 `data[7:0]`、`href`、`vsync`。
- `vsync` 下降沿是一帧的开始；`vsync` 上升沿是一帧的结束。
- `href` 为高期间每 2 个字节组成一个 RGB565 像素，先到的字节是高字节：`pixel = {byte0, byte1}`。`href` 拉低时字节相位清零，行内多出的半个像素丢弃。
- 每 2 个像素组成一个 32 位字，低 16 位是左边的像素（SoC 4.5）。前端向异步 FIFO 写三种项：像素字（带"行末"标记）、帧开始、帧结束。行末标记打在 `href` 下降沿前的最后一个完整字上。
- 前端不能反压摄像头。异步 FIFO 满时，前端丢弃到本帧结束为止的全部像素，帧结束项照常写入（FIFO 有空位后）；该帧由帧整形补齐并标记为不完整（2.2）。

异步 FIFO 用 `rtl/common/edrv32_async_fifo.v`，深度 16。

### 2.2 帧整形（clk_mem，每路摄像头一个）

帧整形把前端的项变成严格的 `WIDTH × HEIGHT` 像素流（SoC 4.5），`WIDTH`、`HEIGHT` 取自 `CAMn_SIZE`（4 节），在帧开始项处锁存：

1. `CTRL.ENABLE` 从 0 变 1 之后，丢弃最先到来的 2 个完整帧（旧工程 `DISCARD_FRAMES = 2`，盘点 1.1），从第 3 个帧开始项起输出。`ENABLE` 为 0 时丢弃全部输入。
2. 行内像素多于 `WIDTH`：多出的丢弃。行内像素少于 `WIDTH`：在行末用 0 补齐。
3. 行数多于 `HEIGHT`：多出的行丢弃。到帧结束项时行数少于 `HEIGHT`：用全 0 行补齐。
4. 第 2、3 条发生任何一项，或者前端在本帧丢过像素（2.1），本帧标记为**不完整**：照常输出，帧完成状态中 `INCOMPLETE` = 1（4.3），并按第 6 节上报。
5. 每个被输出的帧在帧开始时分配 frame_id：本源的 32 位帧计数（只计被输出的帧），随帧传到各通道的完成状态（SoC 7.3 R6）。

帧整形输出不受反压：摄像头源的下游（PIX、各通道）对摄像头帧始终接收（2.5）。补齐期间以每拍 1 个字输出。

### 2.3 内存源

- 软件写 `MSRC_BASE/STRIDE/SIZE` 后写 `MSRC_CTRL.START`，内存源读一张 RGB565 Surface，输出一帧 `WIDTH × HEIGHT` 的像素流。内存源空闲时才接受 START；忙时的 START 被忽略。
- 读取：每行发出一个 `dma2d_rd` 描述符（`height` = 1），只有在输入缓冲有一整行的空位时才发出，因此读数据通道不会被反压（避免占住 mem_xbar 的读返回缓冲，SoC 6.4.4）。输入缓冲至少容纳 2 行（160 beat）。
- 拆包：每个 256 位 beat 拆成 8 个字，按地址顺序输出；行末超出 `WIDTH` 的字丢弃。`sof/eol/eof` 按 SoC 4.5 产生。
- frame_id：内存源自己的 32 位帧计数。
- 内存源帧可以被反压：选中内存源的通道 FIFO 满时停止接收，内存源暂停（设计记录 Q7：内存源不是硬实时）。
- 全部行读完（最后一个 `dma2d_rd` 的 `done_o`）后置 `IRQ_STAT.DONE`：输入 Surface 可以被软件回收。
- 帧开始时没有通道选择内存源，本帧照常读出并丢弃。

### 2.4 选路

- 每个通道的 `CHn_CTRL.SRC` 选择 cam0、cam1 或内存源。通道在所选源的帧开始处决定是否接收该帧：`CTRL.ENABLE` = 1、`CHn_CTRL.EN` = 1、通道空闲或正在完成上一帧的写响应（2.6），且该帧的配置检查通过（第 6 节）。
- `SRC`、`EN` 和通道的 Surface 环配置都在通道接收一帧时锁存（SoC 4.5"配置变化只能在 sof 生效"），帧中间修改不影响本帧。
- 同一个源可以同时送往多个通道。

### 2.5 流控规则

| 源 | 通道接收行为 |
|---|---|
| cam0、cam1 | 通道始终接收（`ready` = 1）。通道写 FIFO 满时，该通道丢弃本帧余下部分（2.7），不影响其他通道 |
| 内存源 | 通道写 FIFO 满时 `ready` = 0；同时选中内存源的多个通道中任一个不接收，内存源暂停 |

PIX 在 CH0 上：摄像头帧下 PIX 的输出始终被接收；PIX 自身在帧末冲刷行缓存期间可能暂不接收输入，持续时间由 PIX 规格限定，必须短于摄像头的场消隐，由前端异步 FIFO 吸收。

### 2.6 写通道（CH0、CH1、CH2）

每个写通道：打包 → 写 FIFO → `dma2d_wr`，加 Surface 环状态。

- 打包：CH0、CH1 每 8 个字组成一个 256 位 beat，行末不足 8 个字的 beat 无效字节 `strb` = 0；每行 `ceil(WIDTH × 2 / 32)` 个 beat。CH2 见 2.8。
- 写 FIFO：256 位 + 32 位 strb，至少 512 项 **[待定]**（16 KiB，约 6 行 720p RGB565；以 SoC 级仿真的 P1 等待时间定稿）。
- 描述符：接收一帧时按 R5 选定槽号 `s`，`base = CHn_SURF_BASE[s]`，`stride = CHn_STRIDE`，`width_bytes = WIDTH × 2`（CH2 为 2560），`height = HEIGHT`（CH2 为 384）。
- 环形缓冲（SoC 7.3 R5）：`CHn_CTRL.RING_N` 块，槽号 0 至 `RING_N` − 1。接收新帧时，从上一次**分配**的槽号的下一个开始，按递增回绕的顺序找第一个 `CHn_SLOT_BUSY` 中未置位的槽；全部置位时不接收本帧，`SKIP` 计数加 1（不是错误）。复位后第一次分配从槽 0 开始找。
- 帧完成：`dma2d_wr` 的 `done_o`（最后一个 B 返回，SoC 7.3 R2）后，更新 `CHn_DONE_INFO`、`CHn_DONE_FRAME_ID`，置对应的帧中断位（4.3）。
- 背靠背：上一帧的数据已全部进入写 FIFO、正在等待写响应时，通道可以接收下一帧；下一帧的数据进入 FIFO，`dma2d_wr` 在上一帧 `done_o` 后接受下一描述符。
- `dma2d_wr` 的 `OUTSTANDING` = 4。

### 2.7 溢出丢帧

摄像头帧的数据到达通道而写 FIFO 已满时（SoC 8.5"实时性"）：

1. 通道丢弃本帧余下的全部数据，FIFO 中已有的数据照常写出；
2. 本帧的数据写完后，对 `dma2d_wr` 发 ABORT（`dma2d-spec` 5.3），等待 `idle_o`；
3. 本帧不报告完成，槽号不前进（下一帧重新从同一位置开始找）；
4. 置 `IRQ_STAT.ERROR`，`ERR_CODE` 为该通道的溢出代码（第 6 节），溢出计数加 1。

### 2.8 CH2：NPU 输入适配（S1 联调中实现）

| 项 | 规定 |
|---|---|
| 输入 | 所选源的像素流（不经 PIX），尺寸必须为 1280×720，否则按配置错误处理 |
| 缩放 | 2×2 块平均到 640×360：每个通道（R、G、B 展开到 8 位后）四点相加再 `(sum + 2) >> 2` |
| 展开 | R、B：`{v[4:0], v[4:2]}`；G：`{v[5:0], v[5:4]}`（与 PIX 相同） |
| letterbox | 上下各补 12 行到 640×384，补齐像素的 8 位通道值为 114 **[待定]** |
| 量化 | 每个 8 位通道值 `c` 输出 INT8 `c − 128`（即 `c ^ 0x80`）**[待定]** |
| 格式 | INT8_C4（NPU 规格 2.2）：每像素 4 字节 `{0, B, G, R}`，R 在最低字节；一行 2560 B = 80 beat |
| 流控 | 始终接收（含内存源帧）；FIFO 满时按 2.7 丢帧，不反压源和其他通道（SoC 8.5） |
| `urgent` | 不参与（2.9） |

补齐值和量化公式必须与 `tools/npu/` 离线工具使用的输入量化参数一致，在 S1 联调时与 NPU 工具链一起定稿。

### 2.9 P1 端口内部仲裁

- 写：三个 `dma2d_wr` 以突发为单位轮询。一个通道只有在其写 FIFO 中已经有本突发的全部 beat（`awlen + 1`）时才参与仲裁；获得授权后，该突发的 AW 和全部 W 连续送往 P1，不与其他通道交织（SoC 6.4.2：W 按 AW 顺序）。B 按授权顺序返回各通道（P1 本地 ID 固定为 0，mem_xbar 对同一端口按序返回 B）。
- 读：只有内存源的 `dma2d_rd`，直接连 P1 读通道，`OUTSTANDING` = 2。
- `urgent_o`：选中摄像头源且正在接收帧的 CH0 或 CH1，写 FIFO 占用达到一半（256 项）**[待定]** 时为 1。CH2 和内存源帧不产生 `urgent_o`（SoC 8.5、设计记录 Q7）。

### 2.10 帧率

VIN 不区分帧率：帧时序完全由传感器的 `vsync/href` 决定。30 fps 与 60 fps 的切换只是软件经 I2C0 写入不同的传感器寄存器表（设计记录 Q5）。

## 3. 接口

`edrv32_vin` 端口：

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| `clk_mem_i` | in | 1 | — | 125 MHz |
| `rst_mem_n_i` | in | 1 | clk_mem | |
| `cam0_pclk_i`、`cam1_pclk_i` | in | 1 | — | |
| `rst_cam0_n_i`、`rst_cam1_n_i` | in | 1 | 各自 pclk | |
| `camN_vsync_i`、`camN_href_i` | in | 1 | camN_pclk | SoC 3.3 |
| `camN_data_i` | in | 8 | camN_pclk | SoC 3.3 |
| `apb_*` | — | — | clk_mem | 媒体 APB 槽 1 从口（SoC 4.3） |
| `p1_aw* p1_w* p1_b*` | — | — | clk_mem | AXI256 写通道（SoC 4.2），本地 ID 1 位，固定为 0 |
| `p1_ar* p1_r*` | — | — | clk_mem | AXI256 读通道（SoC 4.2），内存源 |
| `p1_urgent_o` | out | 1 | clk_mem | 2.9 |
| `pix_*` | — | — | clk_mem | 到 PIX 的像素流输出和从 PIX 返回的像素流输入（SoC 4.5，信号 `valid ready data[31:0] sof eol eof`），前缀分别为 `pix_in_`（VIN → PIX）、`pix_out_`（PIX → VIN） |
| `irq_o` | out | 1 | clk_mem | PLIC 源 8，`|(IRQ_STAT & IRQ_EN)` |

PIX 是独立模块（媒体 APB 槽 2），在媒体子系统顶层与 VIN 连接；VIN 内部不例化 PIX。

## 4. 寄存器

媒体 APB 槽 1。公共寄存器按 SoC 7.1；寄存器块忽略 `pstrb`，按整字写（SoC 4.3）。未列出的偏移读为 0、写忽略。

### 4.1 公共寄存器

| 偏移 | 名称 | 规定 |
|---|---|---|
| 0x000 | ID | 0x0001_0001 |
| 0x004 | CTRL | bit0 ENABLE；bit1 START 无作用；bit2 ABORT（5.3）；bit3 SOFT_RST：VIN 全部寄存器和状态回到复位值（不影响 PIX） |
| 0x008 | STATUS | BUSY = 任一通道正在接收或写出一帧、内存源忙、或有未完成的 AXI 事务；IDLE = 非 BUSY；ERROR = IRQ_STAT.ERROR |
| 0x010 | IRQ_STAT | bit0 DONE：内存源读完一帧；bit1 ERROR；bit2 FRAME：CH0 完成一帧；bit8 CH1_FRAME；bit9 CH2_FRAME |
| 0x014 | ERR_CODE | 第 6 节 |
| 0x020–0x028 | DESC_BASE、DESC_COUNT、DOORBELL | 不使用：读为 0，写忽略 |
| 0x02C | DONE_COUNT | CH0 完成的帧数 |
| 0x040–0x07C | PERF | 4.4 |

### 4.2 源寄存器

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| 0x100 | CAM0_SIZE | RW | 0x02D0_0500 | [10:0] WIDTH（bit0 读为 0，即偶数；2–1280）；[27:16] HEIGHT（1–4095）。复位值 1280×720。在 cam0 帧开始时锁存 |
| 0x104 | CAM1_SIZE | RW | 0x02D0_0500 | 同上，cam1 |
| 0x110 | MSRC_BASE | RW | 0 | [31:12]，[11:0] 读为 0（SoC 7.3：4 KiB 对齐） |
| 0x114 | MSRC_STRIDE | RW | 0x0A00 | [15:5]，[4:0] 读为 0 |
| 0x118 | MSRC_SIZE | RW | 0x02D0_0500 | 格式同 CAM0_SIZE |
| 0x11C | MSRC_CTRL | WO | — | bit0 START：内存源空闲时锁存 0x110–0x118 并开始一帧 |
| 0x120 | MSRC_STAT | RO | 0 | bit0 BUSY |

### 4.3 通道寄存器

CHn 基址 = 0x200 + 0x80 × n，n = 0、1、2。CH2 在本阶段未实现，0x300–0x37F 读为 0、写忽略，IRQ_STAT.CH2_FRAME 不置位。

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
|---|---|---|---|---|
| +0x00 | CHn_CTRL | RW | 0x0000_0030 | bit0 EN；[2:1] SRC（0 cam0，1 cam1，2 内存源，3 非法）；[6:4] RING_N（2–4，复位值 3）。接收帧时锁存 |
| +0x04 | CHn_STRIDE | RW | 0x0A00 | [15:5]，[4:0] 读为 0。接收帧时锁存 |
| +0x08 + 4 × s | CHn_SURF_BASE[s] | RW | 0 | s = 0–3；[31:12]，[11:0] 读为 0。接收帧时锁存所选槽的值 |
| +0x18 | CHn_SLOT_BUSY | RW | 0 | [3:0] 槽占用标记（SoC 7.3 R5），在通道选槽时采样，立即生效 |
| +0x20 | CHn_DONE_INFO | RO | 0 | 最近完成的一帧：[1:0] 槽号；[3:2] 源（同 SRC 编码）；bit4 INCOMPLETE（2.2）；bit5 BUS_ERR（本帧有非 OKAY 写响应）。与 +0x24 在同一拍更新 |
| +0x24 | CHn_DONE_FRAME_ID | RO | 0 | 最近完成的一帧的 frame_id |
| +0x28 | CHn_WR_STAT | RO | 0 | bit0 ACTIVE（正在写一帧）；[2:1] 正在写的槽号 |

软件在帧中断后一帧时间内读取 `DONE_INFO` 和 `DONE_FRAME_ID`；两者在下一帧完成时被覆盖。

### 4.4 性能计数器

32 位，回绕；SOFT_RST 清零。

| PERF | 内容 |
|---|---|
| 0、1 | cam0、cam1 输出的帧数（2.2 第 5 条） |
| 2 | 内存源输出的帧数 |
| 3、4、5 | CH0、CH1、CH2 完成的帧数 |
| 6、7、8 | CH0、CH1、CH2 溢出丢帧数（2.7） |
| 9、10、11 | CH0、CH1、CH2 因全部槽占用跳过的帧数（2.6） |
| 12、13 | cam0、cam1 不完整帧数（2.2 第 4 条） |
| 14 | `p1_urgent_o` 为 1 的 clk_mem 周期数 |
| 15 | 配置错误次数（第 6 节） |

## 5. 行为与时序

### 5.1 一帧的事务边界

- 一帧在通道上的开始 = 源的 `sof` 被通道接收；结束 = 该帧最后一个 B 返回（`dma2d_wr` `done_o`）。
- 中断：帧完成置位的同一拍更新 4.3 的完成状态。
- 一个源帧的 frame_id 在它送往的所有通道上相同（S1 中 CH0 底图与 CH2 NPU 输入据此对应）。

### 5.2 使能和关闭

- `CTRL.ENABLE` 或 `CHn_CTRL.EN` 清零：正在接收的帧照常写完并报告，之后不再接收新帧。
- `CTRL.ENABLE` 清零后，帧整形停止输出（下次置 1 时重新丢弃 2 帧，2.2 第 1 条）；内存源正在输出的帧照常输出完。

### 5.3 ABORT

`CTRL.ABORT` 写 1：所有通道停止接收数据（摄像头帧丢弃，内存源停止读取并对 `dma2d_rd` 发 ABORT），各通道对 `dma2d_wr` 发 ABORT；被中止的帧不报告完成，槽号不前进；全部单元 `idle_o` 后 STATUS.IDLE = 1。ABORT 不改变 ENABLE；ENABLE 仍为 1 时，各通道从所选源的下一个帧开始重新接收。

## 6. 错误处理

| ERR_CODE | 错误 | 检测 | 上报 | 恢复 |
|---|---|---|---|---|
| 1、2、3 | CH0、CH1、CH2 写 FIFO 溢出 | 摄像头帧数据到达时 FIFO 满 | IRQ_STAT.ERROR、PERF 6–8 | 本帧丢弃（2.7），下一帧自动恢复 |
| 4、5 | cam0、cam1 不完整帧 | 帧整形（2.2 第 4 条） | IRQ_STAT.ERROR、PERF 12–13、DONE_INFO.INCOMPLETE | 本帧照常写出；下一帧自动恢复 |
| 6 | 源配置非法：CAMn_SIZE 的 WIDTH 为 0 或大于 1280、HEIGHT 为 0 | 帧开始锁存时 | IRQ_STAT.ERROR、PERF 15 | 该源不输出本帧；改配置后下一帧生效 |
| 7 | 内存源配置非法：MSRC_SIZE 同上 | START 时 | IRQ_STAT.ERROR、PERF 15 | 不启动；改配置后重新 START |
| 8 | 通道配置非法：SRC = 3，RING_N 不在 2–4，或 CH2 的源尺寸不是 1280×720 | 通道接收帧时 | IRQ_STAT.ERROR、PERF 15 | 通道不接收本帧 |
| 9 | 写响应非 OKAY | `dma2d_wr` `err_o` | IRQ_STAT.ERROR、DONE_INFO.BUS_ERR | 本帧照常报告完成 |
| 10 | 内存源读响应非 OKAY | `dma2d_rd` `err_o` | IRQ_STAT.ERROR | 本帧照常输出 |

`ERR_CODE` 记录最近一次错误，写 IRQ_STAT.ERROR 清零时一并清除（SoC 7.1）。Surface 基址和跨距的对齐由寄存器位宽保证，不另行检查；跨距小于行字节数不检查（不影响硬件，只影响图像）。

## 7. 性能与资源指标

| 项 | 指标 |
|---|---|
| 吞吐 | 帧整形、内存源、通道打包每拍 1 个字（2 像素，250 Mpixel/s @125 MHz） |
| 实时性 | SoC 级仿真 S1、S2 流量下，摄像头源的 CH0 无溢出（SoC 9.2） |
| 内存源 | 720p 一帧在 P1 无竞争时不超过 8 ms（每行一个描述符，只受 DDR 延迟限制）**[待定]** |
| 资源 | VIN（不含 PIX、CH2）应不超过 4K LUT；写 FIFO 和内存源输入缓冲用 DRM **[待定]**，以 PDS 实测定稿；VIN + PIX + DISP 合计 ≤ 10K LUT（SoC 9.3） |

## 8. 验证要点

1. 前端：字节序、`href` 断续、行内半像素、`vsync` 边沿；两路 pclk 与 clk_mem 频率比变化（含 pclk 高于 clk_mem/2 的极限）。
2. 帧整形：ENABLE 后丢 2 帧；行长/行数多、少各种组合下输出严格 WIDTH × HEIGHT，INCOMPLETE 与 ERR_CODE 正确。
3. 选路：帧中修改 SRC/EN/环配置只在下一帧生效；一个源同时送 CH0 与 CH1。
4. 环形缓冲：RING_N = 2、3、4，各种 SLOT_BUSY 组合下槽号序列与 7.3 R5 一致；全部占用时 SKIP 计数。
5. 溢出：P1 长时间不响应时摄像头帧丢弃，ABORT 后无未完成事务，槽号不前进，下一帧恢复；其他通道不受影响。
6. 内存源：DDR 中 Surface 逐像素经 CH0（PIX 旁路）写回一致；CH0 FIFO 反压时内存源暂停且读通道无反压（`rready` 持续为 1）；DONE 时刻。
7. P1 仲裁：三个写通道同时工作时 W 不交织，B 按序返回；`urgent_o` 的产生条件。
8. ABORT、SOFT_RST、frame_id 连续性、完成状态寄存器与中断同拍更新。

## 9. 待定事项

| # | 事项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | 写 FIFO 深度 | 512 × 256 位 | SoC 级仿真 S1/S2 流量下 P1 最长等待 |
| 2 | `urgent_o` 阈值 | 写 FIFO 一半 | 同上 |
| 3 | 内存源单帧时间指标 | 8 ms | 模块级仿真实测 |
| 4 | CH2 letterbox 补齐值、量化公式 | 114；`c − 128` | S1 联调，与 `tools/npu/` 输入量化参数一致 |
| 5 | 资源指标、DRM 用量 | 7 节 | PDS 实测 |
| 6 | 摄像头 PCLK 频率、消隐、引脚 | 板级任务卡核对（盘点 2：仓库中无依据） | Windows 上板 |

## 10. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-27 | v0.1 | 初稿：依据 SoC 规格 8.5、设计记录 `2026-10-27-image-path.md`、旧工程盘点 |
