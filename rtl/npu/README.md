# NPU RTL

依据 `docs/spec/npu-spec.md` v0.3、SoC v0.7 和已决定的
`docs/design/2026-10-27-npu-datapath.md` 4.2.2。完整顶层文件列表为
`rtl/filelists/npu.f`；数据通路原有文件保持不变。

## 模块和所有权

| 模块 | 职责 | 主要接口 |
|---|---|---|
| `edrv32_npu` | X9/X10、描述符逐条执行、算子选择、层间 B 栅栏、错误/ABORT 排空 | 规格第 3 节全部外部端口 |
| `edrv32_npu_regs` | 公共/私有寄存器、门铃、IRQ、PERF | 本地 APB；start/abort/soft_reset；四基址、描述符地址/条数；完成/错误/统计事件 |
| `edrv32_npu_descriptor` | 两 beat 描述符影子、基址选择、规定的 OP/容量检查 | data/index；decode/done；desc 与五个实际 DDR 地址 |
| `edrv32_npu_read_dma` | 4 个有序 burst 上下文、寄存返回保持级、R 错误与排空 | req(addr,beats,tag)；data(tag,index,last)；AXI AR/R |
| `edrv32_npu_write_dma` | AW/W 寄存保持、8 个本地 B credit、W/B 排空 | req(addr,beats)；data/strb；stream_idle/idle；AXI AW/W/B |
| `edrv32_npu_conv` | W1/W3/W4b/W5/W6 装载与行优先调度，集成冻结数据通路 | 层描述符、实际地址；读 DMA；写 DMA；完成和 PERF |
| `edrv32_npu_conv_write` | chunk 所有权、两平面 burst、结果 RAM 读预留和释放 | 冻结 result_chunk/result_rd/release；写 DMA |
| `edrv32_npu_nonconv` | 串行 POOL/UPSAMPLE，两块共用 scratch | 描述符/地址；读写 DMA；done/writer_idle |
| `edrv32_npu_datapath` | 已评审的 CONV 数据通路子顶层 | 设计记录 4.2.2，不改接口 |
| `edrv32_npu_input_unpack` / `edrv32_npu_line_cache` | C4 展开与两 bank 行缓存 | line_wr/cache_rd |
| `edrv32_npu_window` | 双命令上下文、D3b 滑窗和量化发射日历 | cmd、pair credit、term |
| `edrv32_npu_weight_store` | 8 bank 常驻权重池 | weight_wr/weight_rd |
| `edrv32_npu_quant_param_store` / `edrv32_npu_activation_lut` | 常驻量化参数与 16 路激活表 | quant_wr/param_rd、lut_wr/lut_rd |
| `edrv32_npu_mac_array` / `edrv32_npu_accum` | MAC、D2 合并、累加 | term/sum/accum/prepare |
| `edrv32_npu_result_quant` | 16 路分组量化、激活、残差提前读 | accum/param/lut/residual/quant |
| `edrv32_npu_residual_buffer` / `edrv32_npu_residual_add` | 残差半区信用与融合加 | begin/wr/commit、reserve/read、quant/writeback |
| `edrv32_npu_writeback` | 32 pair 结果环及 chunk 队列 | reserve、writeback、result_chunk/read/release |

除边界桥外全部在 `clk_npu`。媒体 APB 通过公共
`edrv32_apb_async_bridge` 从 `clk_mem` 进入；AXI256 通过公共
`edrv32_axi256_async_bridge` 到 `clk_mem`。`irq_o` 为 NPU 域电平。

## 内部接口和时序

读 DMA 的请求为一个已拆分的 burst：`req_beats` 取 1..16，地址 32 B 对齐。
生产者按下一个 512 B 边界及剩余长度取最小值，因此同时满足不跨 4 KiB。
描述符自身为 64 B 对齐的两 beat 请求。所有 AXI 本地 ID 固定为 0，以同 ID
有序返回支撑四个读上下文。32 位 tag 与请求一起保存，返回另带 0..15 的
beat index 和 last；R 到内部消费者经过一个寄存保持级，允许反压。
CONV 仲裁结果另寄存一次，生产者在入此寄存器时前移地址/计数。

CONV tag 的 [31:29] 为 weight/quant/LUT/line/residual（0..4）；[28] 表示
该 burst 最后响应同时结束记录、输入行或残差批次。weight 的 [13:0] 是本层
权重 beat 基址；quant/LUT 的 [7:4]/[2:0] 是记录 beat/块号；line 的
[13:11]/[10]/[9:0] 是行槽/首 beat 奇偶/每 bank 基址；residual 的
[7:3]/[2]/[1]/[0] 是批内首 pair/平面/half/半区。非卷积 tag 的 [8:0]
为 scratch 写起点，[28] 为本次装载结束。tag 只表达生产者所有权，不作合法性检查。

描述符第二 beat 写入后单独发 decode，随后两级完成地址准备和容量判定；仅检查
OP 及 CONV 的三项容量。上一层所有 R/W/B 返回后才读取下一条描述符。
`DESC_COUNT=0` 的门铃直接完成空列表。CUR_DESC 在正常完成/出错后保持，下一次门铃清零。

CONV 的 cfg 先被数据通路接受，再启动三个独立装载游标。输入行优先于模型的
后续 burst，残差已申请半区的读优先于输入；未就绪的残差半区不会占用 DMA。
3×3 轮转五槽，1×1 轮转两槽；1×1 S2 跳过不采样行。每个输入行的全部
C16 平面只从 DDR 装一次，C4 由冻结 unpack 每 beat 展开四拍。
槽号经一个小 FIFO 与逐行 row_done 配对，不能用 unpack idle 代替完成脉冲。
所有块的 A3 read_done 到达后才按下一窗口最早需要的行回收旧槽。

模型按块顺序装权重、32 个量化项及必要的 LUT，直接写最终常驻地址。
每个量化 beat 串行发四项，每个 LUT beat 串行发 32 字节。最后一个写输出后
再留足局部写寄存延迟才标记该块 ready。块 0 ready 后即可计算，其余块继续装载。
命令按 row→block 提前准备到寄存器；不在行/块切换处等待 WB 或 B。
结果和残差发射信用仍由原数据通路拥有，控制器不重复计数或检查其内部契约。

残差按命令顺序申请交替半区：普通块最多 8 pair、half 最多 16 pair。
各平面连续读、按 `pair*planes+plane` 散写，最后写可与 commit 同沿。
chunk 写 DMA 借用原结果环，通过四项 FF 队列预留无 ready 的 RAM 返回位置；
读使能、索引、平面均先寄存，W 反压不会传回 MAC 流水。
输出行/块地址按执行顺序累加，地址路径不使用行号乘法。
全部有效平面交给 W 保持级且该 burst 完成后释放 chunk，不等 B。
写 DMA 独立保留最多八个本地未回 B；mem_xbar P3 的在途上限继续由其自身仲裁。

POOL 将一个 C16 平面装入 plane scratch，按请求/采样/比较三拍遍历 5×5
邻域，边界为 −128；结果行写入 row scratch，再交给写 DMA。
UPSAMPLE 将源行装入 row scratch，一次读入、水平复制两份并垂直写两行。
两算子串行共用 scratch，测试平台逐拍检查两块 RAM 都没有同拍同址读写。

ABORT/规定错误立即停止新的本地请求和 pair 发射；已经呈现的 AXI 地址仍保持
直到握手，已经接受的 AW 始终有完整 W。控制器保留当前结果/行暂存，先完成
当前 W burst、全部 R/B，再发一拍 cancel 清内部 valid/所有权，随后报告 IDLE。
被中止输出未定义，DONE_COUNT 不增加。没有超时、看门狗或额外错误检查。

IDLE SOFT_RST 将全部架构寄存器及内部控制恢复硬复位值，数据 RAM 不复位；
BUSY 写 SOFT_RST 忽略。这是协调者在 N-C1 ask 中确认的开发初值，待其补入规格。
PERF[0..7] 分别计 busy 总周期、MAC 拍、R 拍、W 拍、行准备等待、块装载等待、
存在未回 B 的周期、非卷积执行周期；门铃清零，[8..15] 保持 0。

## 存储与算术资源

以下为 SIM_MODE 行为模型和固定 tech 实例的层次统计，不是 PDS 综合资源结果。

| 所有者 | 物理映射 | DRM / APM |
|---|---|---|
| 原 CONV 数据通路 | line 2、weight 24、quant 8、LUT 16、residual 1、result 1 个 RAM 包装 | 148 DRM；256 pair MAC + 16 low/16 high quant = 288 APM |
| 非卷积执行器 | 两个 `edrv32_ram_npu_scratch`，各 512×256、读延迟 1 | 8 DRM；0 APM |
| 新读/写 DMA 和控制 | 4×32 tag、256 位 R/W 保持、串行拆包、四项结果返回队列、小型行槽 FIFO | FF/分布式 RAM；无新增 DRM/APM 包装 |
| X9 | 8 深异步 FIFO：AW 37、W 289、B 3、AR 37、R 260 位，共 5008 数据位 | 异步读 FF/分布式 RAM；0 DRM/APM 包装 |
| X10 | 公共握手式 APB 桥 | FF；0 DRM/APM 包装 |
| 合计 | 所有 NPU RAM 均通过既有 tech 包装 | **156 DRM、288 个显式 APM 包装** |

余量为 14 DRM、12 APM；描述符容量乘法等普通算术的实际映射、LUT/FF 和完整顶层
150 MHz 时序仍需 Windows PDS 测量。数据通路原有 158 MHz 测量不能代替完整顶层 STA。

## 验证记录

测试结果、命令、NB 逐项结果及已处理的 ask 在完成验证后填入本节。
