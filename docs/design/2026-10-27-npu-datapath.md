# NPU 数据通路微架构设计记录（N-D0）

| 项 | 内容 |
|---|---|
| 日期 / 状态 | 2026-10-27 / 已决定（第 10 项 8 处经用户确认写入 NPU 规格 v0.2，2026-10-27） |
| 输入版本 | 仓库 `2238f559c612bbf7dc03018d21517ade50154f63`；NPU 规格 v0.1，SoC 规格 v0.7，NPU 实施方案 v0.5，验证方案 v0.1 草案 |
| 范围 | C0+D2+D3b 的设计和开发接口；不包含 RTL、IP 创建说明或规格修改 |
| 主要依据 | [NPU 规格](../spec/npu-spec.md)、[SoC 规格](../spec/edrv32-soc-spec.md)、[架构 Q1–Q8](2026-10-26-npu-architecture.md)、[N-E1](../reports/2026-10-26-perf-npu-legacy.md)、[N-E2](../reports/2026-10-26-perf-npu-datapath.md)；只读 `legacy/rtl/vision/yolo/`、旧权重/量化脚本、`fpga/ip/` 和 `rtl/tech/` |
| 数字口径 | 除明确标出的旧工程测量外，本文全部资源、逻辑级数、周期和 fps 为**估算 / 开发初值**；KiB=1024 B；MAC 按一次乘加计 |

## 1. 背景和问题

第一版保留 512 MAC/拍（C32 输出×C8 输入×2 像素）、256 个 MAC APM 和 150 MHz 开发时钟，实现 W1 行预取、W2 行尾不等 B、W3 权重/参数装载重叠、W4b 行优先且全层权重常驻、W5 C4 首层、W6 融合残差、D2 半块和 D3b 直接滑窗。旧工程验证过算术，但其 activation tile、按输出块重读输入、整链 CE 背压不能直接保留。

N-IP1、N-M1、N-M2、N-D1、N-C1 将消费本记录。下面的信号、位序和装载顺序是这些任务的**建议开发契约**；协调者评审、补入规格并确认后才是并行开发的冻结接口。本记录本身不替代规格。

## 2. 约束

- 只使用规格 2.1 的算子和 2.2 的布局；不增加 1024 MAC 预留、运行时可选数据流或额外错误检查。CONV 数据通路不检查派生字段自洽性、装载完整性、地址或内部协议。
- 业务模块按 `edrv32_npu_<功能>` 命名；固定 IP 包装使用 `edrv32_ram_npu_<用途>`、`edrv32_mul_npu_<用途>`。仅 `rtl/tech/` 可以含构建条件分支。数据寄存器和 RAM 不复位。
- 本文全部端口都在 `clk_npu`；不在数据通路内跨域。APB、AXI256、X9/X10、IRQ 和 AXI 错误处理属于 N-C1/N-C0。DDR 地址 32 B 对齐、INCR 1–16 beat、不得跨 4 KiB；最后 B 才构成层间栅栏。
- Logos2 DRM 按 N-E2 引用的 [UG040002 V1.2 表 9-1](https://www.pangomicro.com/en/uploads/49630285_1729131726.pdf) 的 SDP 512×64、1024×32、4096×8 组合计算，未借用奇偶位。不能用总 bit 数除 36 Kibit 替代端口/宽深映射。
- LUT ≤50K（含 VIN 输入适配）、APM ≤300、DRM ≤170。资源和时序最终以 Windows PDS 布局布线报告为准；本文未使用 Yosys 作为资源结论，也未运行仿真。
- 协调者经 Orca ask 确认的开发初值：HALF_TAIL 与 IN_C4 组合语义（4.7）；C4 宽度为 8 的倍数（SoC 7.3）；29/27 拍流水细化，且层内不按块排空流水（4.3）。这些仍列入第 10 项，待协调者提交用户确认。

## 3. 可选方案

| 问题 | 方案 | 优点 | 代价 / 选择理由 |
|---|---|---|---|
| 行缓存组织 | 保持旧 2 bank、像素对奇偶分 bank；或复制存储增加读口 | 前者对 S1/S2 都可每拍取两个像素，64 KiB/16 DRM | 复制没有本任务的吞吐收益；选择前者，增加输出寄存器 |
| 权重 | 逐块装载双缓冲；或 288 KiB 全层常驻 | 双缓冲通常较省 DRM | 全层常驻满足 W4b、每层输入只读一遍；选择 8×1152×256 的逻辑池，96 DRM |
| 供数 | 显式 patch/activation RAM；或 D3b 直接滑窗 | 旧 tile 易移植 | D3b 省 8 DRM、消除 chunk 填充；选择后者 |
| 量化 | 16 lane、4/2 组；或 32 lane、2/1 组 | 32 lane 小 K 更快 | 固定计划普通 K≥4，收益为零（N-E2）；33×16 每 lane 2 APM，32 lane 会使总 APM=320，超预算。选择 16 lane |
| 参数存储 | N-E2 的 FF 参数数组；或 8 个 SDP bank | FF 少 8 DRM | 8 个独立通道 bank 每拍读 8 个参数并供两个像素复用，避免 8 块参数的大型异步选择。选择 8 DRM，读两级，提前发起参数读 |
| 输出控制 | 全流水 ready/CE；或 pair 级信用预留 | CE 易沿用旧代码 | 选择预留，消除全局背压使能；只有结果 RAM 读侧和 DMA 握手 |
| 命令切换 | 每个输出块排空；或两个命令上下文和随数据标签 | 前者控制较少 | 后者使深流水只在描述符尾部暴露；按协调者确认选后者 |

## 4. 决策

### 4.1 第 1 项：旧模块盘点

表内名字省略共同的 `edrv32_yolo_`；“直接移植”仍须改文件名、端口后缀、技术包装和语言风格，不表示引用 legacy 文件。

| 旧模块 | 处置 / 新归属 | 原因及 D3b、D2、W4b、W5 影响 |
|---|---|---|
| `line_cache` | 修改后移植 → `edrv32_npu_line_cache` | 保留 2 bank 映射；读变两级、IP 移到 tech；去掉通用 bank 冲突检测/ready（合法窗口天然不冲突）。W4b 生命周期跨全部输出块；W5 由 unpack 写同一组织 |
| `patch_gen` | 重写 → `edrv32_npu_window` | 保留坐标/增量思路；删除 activation 地址和半区写入，直接送阵列；D2 跳过 C8 半块循环；W5 每核位置只取 C4；跨 pair/命令连续发射 |
| `tile_store` | 重写 → `edrv32_npu_weight_store` | 删除 activation RAM；权重每 bank 从 512 深扩大到逻辑 1152 深；W4b 常驻、W3 写未计算的块；D2/首层格式在离线镜像中重排 |
| `conv_tile` | 重写 / 拆入 datapath、window、accum | 旧 tile/chunk/activation 控制不再存在；替换全局 CE 为信用；保留局部激活复制和权重寄存的物理布局思路 |
| `mac_array` | 修改后移植 → `edrv32_npu_mac_array`、`edrv32_npu_accum` | 保留 256 个双乘法 APM、三拍 8 路归约；去 CE 背压；D2 重选高低 C8 并增加合并级；累加独立，配置随 tag 流动 |
| `apm_mul2` | 算术直接移植 → tech 的 `edrv32_mul_npu_int8_pair` | 原生 SIMD 两路有符号打包不变；删除业务 ifdef/数据复位和可停 CE，固定两级，详见 4.6 |
| `result_quant` | 修改后移植 → `edrv32_npu_result_quant`、参数存储、激活 LUT | 保留 33 位偏置和、49 位乘积及舍入规则；去掉输入/输出两项队列及全链停顿；分级量化乘法/移位；半块只处理前两组；W4b 参数按 block 存储 |
| `c16_residual_add` | 修改后移植 → `edrv32_npu_residual_add` | 保留 10 位带符号 `y+r-zp` 和饱和；融合到 WB，扩为两平面并行，拆成两拍；取消独立 ready 链 |
| `axi_writer` 中的 tile 输出缓冲 | 重写 → `edrv32_npu_writeback` + N-C1 写 DMA | 保留两组 16 pair 的容量和分平面 burst 思路；缓冲改 DRM 环，读索引本地寄存；B credit 只由 N-C1 管理，不阻塞行边界 |
| `feature_loader` | 重写，N-C1 读 DMA + `edrv32_npu_input_unpack` | 行标签/五行轮转思路保留；跨 C32 共用输入，预取独立；C4 的 1 个 DDR beat 展开 4 个缓存项 |
| `weight_loader` | 重写，N-C1 装载路由 | 按镜像顺序 256 位写；W3 不再用两个完整 tile，直接写最终常驻地址 |
| `quant_cfg_dma` | 修改后移植其记录拆解，N-C1 | 512 B 记录仍拆 32 个参数和 256 LUT 字节；新记录没有每通道 zp；写目标增加 block，不要求量化器全局静止 |
| `axi_reader` | 重写，N-C1 | SoC AXI256/ID/错误/ABORT 接口不同；不得直接带入旧四在途假设、错误后需复位规则 |
| `conv_layer`、`conv_group`、`v8n_exec`、`v8n_core`、`v8n_program` | 重写，N-C1 描述符调度 | 固定程序、输出块优先、行尾等 B 与新规格不符；不进入数据通路子顶层 |
| `c16_residual_dma` | 删除独立 ADD 执行路径；只参考残差读缓冲 | W6 只读 shortcut，取消 A 读/临时结果写；新增 `edrv32_npu_residual_buffer` |
| `maxpool5_dma`、`upsample2x_dma` | 修改后移植，N-C1 非卷积执行器 | 算法、−128 补边和复制保留；控制和 AXI 适配重写。POOL 保持三状态采样，非早期文档的两拍；缓存改 DRM，共用暂存见 4.5 |
| `c2f`、`sppf` | 不移植层序封装 | 离线工具展开为描述符；免拷贝拼接只由地址表达 |
| `v8n_post`、`post_lut`、`dfl16`、`nms` | 不移植 | Q7 第一版软件后处理 |
| `uart_boot`、`serial_dma`、`ddr_test_system`、`v8n_test_system`、`ddr_background_reader`、`v8n_reporter`、`v8n_profiler` | 不进入新数据通路 | 旧板级/测试/串口包装；不移植 CRC/哈希/门禁。N-C1 仅按新规格实现 PERF |

### 4.2 第 2 项：模块和端口契约

#### 4.2.1 共同约定与数据标签

端口表中的方向均相对表头模块。`N` 时钟域表示 `clk_npu`，所有位宽为常数。除纯 RAM 包装外，每个业务模块共同具有以下端口；后表不重复列出。`cancel_i` 是规格 5.5 / 第 6 节要求的中止清空控制：只清 valid、队列所有权、计数器，不清数据。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `clk_i` | in | 1 | — | clk_npu |
| `rst_n_i` | in | 1 | N | 本域同步释放复位，只用于控制 |
| `cancel_i` | in | 1 | N | 1 拍；该沿取消全部未交给 AXI 的内部工作，优先于 valid 握手 |

有效/就绪接口在上升沿 `valid && ready` 接受；发送者的 valid 不依赖 ready，等待期间保持负载。无 ready 的 `*_wr_valid_i` 是每拍装载使能，每拍必收一项（局部写寄存延迟见4.3.2）；无 ready 的流水 valid 表示不可阻塞的数据拍。各内部契约由控制/离线工具保证，验证端检查，接收 RTL 不重复检查。

统一 `term_tag[48:0]` / `result_tag[48:0]` 位序如下。仅 suffix 随方向改变，跨模块不换词干。`half` 表示只写一个 C16 平面，`d2` 表示算术折叠，两者不同。

| 位 | 字段 | 含义 |
|---|---|---|
| [11:0] | row | 输出行 |
| [14:12] | block | C32 输出块号 |
| [25:15] | pair | 行内像素对号，左像素 x=2×pair |
| [26] | half | HALF_TAIL 且为最后输出块 |
| [27] / [28] | lut / res | 本层 LUT_EN / RES_EN |
| [36:29] | zp | INT8 OUT_ZP |
| [37] | last_pair | 该行该块的最后一个 pair |
| [42:38] | result_slot | 发射时预留的结果环项号 |
| [47:43] | residual_addr | 本 pair 的残差低平面缓存地址；高平面为其 +1 |
| [48] | d2 | half && !IN_C4；由发射端译码后随数据传递 |

累加向量 `[32*(pixel*32+c)+:32]` 为像素 pixel、通道 c；MAC 乘积 `[16*((pixel*32+c)*8+k)+:16]`。量化的第 phase 组处理通道 `8*phase+j%8`、像素 `j/8`（j=0..15）；普通 phase=0..3，half phase=0..1。结果 RAM 位序为 `[plane][pixel][channel-within-C16]`：低 256 位低 C16 平面，平面内低 128 位左像素。不是旧 quant 的 `[pixel][C32]` 排列。

#### 4.2.2 `edrv32_npu_datapath` 对 N-C1 的完整接口

子顶层只执行 CONV。POOL/UPSAMPLE 是 N-C1 的串行非卷积执行器，不为它们在这里预留空端口。所有端口均为 N 域。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `cfg_valid_i` / `cfg_ready_o` | in / out | 1 / 1 | N | 层影子寄存器一次接受；仅上一描述符内部清空后 ready |
| `cfg_k3_i` / `cfg_s2_i` | in / in | 1 / 1 | N | 核大小、步长 |
| `cfg_lut_en_i` / `cfg_res_en_i` | in / in | 1 / 1 | N | 激活、残差 |
| `cfg_in_c4_i` / `cfg_half_tail_i` | in / in | 1 / 1 | N | 输入格式、最后块单平面 |
| `cfg_in_w_i` / `cfg_out_w_i` | in / in | 12 / 12 | N | 输入宽、输出宽；pair 总数为 OUT_W>>1 |
| `cfg_cin_blocks_i` | in | 6 | N | C16 组数；C4 为 1 |
| `cfg_cout_blocks_i` | in | 4 | N | C32 块数 1..8（不是 3 位块号） |
| `cfg_k_count_i` | in | 11 | N | 普通块 K_COUNT；D2 实际取一半 |
| `cfg_out_zp_i` | in | 8 | N | INT8 层输出零点 |
| `line_wr_valid_i` / `line_wr_ready_o` | in / out | 1 / 1 | N | 输入 DMA 行数据；C16 连续接受，C4 每 4 拍最多接受 1 beat |
| `line_wr_bank_i` / `line_wr_addr_i` | in / in | 1 / 10 | N | C16 的最终 bank/地址；C4 时 bank 输入为 0、addr 为首两个像素的规范化地址 |
| `line_wr_data_i` | in | 256 | N | DDR 原始 beat；C4 按低字节开始为连续 8 像素 |
| `line_wr_row_last_i` / `line_wr_row_done_o` | in / out | 1 / 1 | N | 输入行最后beat标记 / 该行最后缓存写完成脉冲；N-C1按此顺序标行ready |
| `line_wr_idle_o` | out | 1 | N | unpack 没有剩余写项，用于本地idle，不用它代替逐行完成标记 |
| `weight_wr_valid_i` | in | 1 | N | 顺序权重写使能，无 ready |
| `weight_wr_addr_i` / `weight_wr_data_i` | in / in | 14 / 256 | N | 相对本层镜像的 beat 号 0..9215、数据；地址不截成 13 位 |
| `quant_wr_valid_i` | in | 1 | N | 单通道参数写使能 |
| `quant_wr_block_i` / `quant_wr_channel_i` | in / in | 3 / 5 | N | 目标输出块 / 通道 |
| `quant_wr_bias_i` / `quant_wr_mult_i` / `quant_wr_shift_i` | in / in / in | 32 / 16 / 6 | N | 有符号 bias、mult；无符号 shift |
| `lut_wr_valid_i` | in | 1 | N | 广播写 16 份激活表 |
| `lut_wr_block_i` / `lut_wr_addr_i` / `lut_wr_data_i` | in / in / in | 3 / 8 / 8 | N | 表块、下标、INT8 值 |
| `cmd_valid_i` / `cmd_ready_o` | in / out | 1 / 1 | N | 一行一个输出块；可在当前命令发射时预存下一个命令 |
| `cmd_row_i` / `cmd_block_i` | in / in | 12 / 3 | N | 输出行、块号；按行→块顺序送入 |
| `cmd_row_base0_i` / `cmd_row_base1_i` / `cmd_row_base2_i` | in / in / in | 10 / 10 / 10 | N | ky 对应行槽的每 bank 基址；1×1 只用 base0 |
| `cmd_row_valid_i` | in | 3 | N | 对应输入行在图内且已装好；越界行位为 0；1×1 只用位 0 |
| `cmd_weight_base_i` | in | 11 | N | 常驻池中的首 K 行，N-C1 预算 `block*WEIGHT_BLOCK_BYTES/256` |
| `issue_enable_i` | in | 1 | N | 正常执行为 1；停止发射/中止时撤销，只控制新 pair 首拍 |
| `result_credit_o` | out | 6 | N | 0..32 个尚未预留的结果项；已在途/已完成/借给 DMA 都不计空位 |
| `cmd_issued_o` | out | 1 | N | 当前命令最后一个归约项已在 A1 接受，脉冲 |
| `cmd_issued_row_o` / `cmd_issued_block_o` | out / out | 12 / 3 | N | 与 issued 同沿的命令标签 |
| `cmd_read_done_o` | out | 1 | N | 最后归约项到达 A3，行缓存访问完成 |
| `cmd_read_done_row_o` / `cmd_read_done_block_o` | out / out | 12 / 3 | N | 与 read_done 同沿的标签；N-C1 据此回收旧行槽 |
| `cmd_done_o` | out | 1 | N | 最后 pair 已写结果 RAM；不代表 W/B 完成 |
| `cmd_done_row_o` / `cmd_done_block_o` | out / out | 12 / 3 | N | 与 done 同沿的标签 |
| `mac_beat_o` | out | 1 | N | M1 有效归约拍，供 PERF[1] |
| `idle_o` | out | 1 | N | 命令上下文、所有流水、结果环和残差缓冲均空；不含 AXI 在途数 |

残差装载接口采用两个 16-beat 半区；读 DMA 可以按平面连续 burst 返回后散写最终地址，无需另加残差重排 RAM。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `residual_begin_valid_i` / `residual_begin_ready_o` | in / out | 1 / 1 | N | 申请一个空半区；同一时刻最多一个装载批次 |
| `residual_begin_bank_i` | in | 1 | N | 半区号；就绪仅取决于该半区空闲 |
| `residual_begin_pairs_i` | in | 5 | N | 该批次 pair 数，普通 1..8、half 1..16；不跨命令 |
| `residual_begin_half_i` | in | 1 | N | 本批次输出单平面标志，决定每 pair 1/2 beat |
| `residual_wr_valid_i` / `residual_wr_bank_i` | in / in | 1 / 1 | N | 已申请半区的数据写使能 / 半区 |
| `residual_wr_index_i` / `residual_wr_data_i` | in / in | 4 / 256 | N | index=`pair_in_chunk*planes+plane`，数据保持 C16 beat 位序 |
| `residual_commit_i` | in | 1 | N | 当前申请批次所有数据已写，变为可预留；可与最后写同沿 |

批次 begin/commit 按消费顺序，第二半区装载可覆盖第一半区的计算时间。begin 在接受沿占有半区，commit 后才允许 pair 发射；最后一次残差 RAM 读取被采样后回收半区。RES_EN=0 时不使用该接口。

结果接口直接让 N-C1 写 DMA 读取同一结果环，避免又加一份 writer tile。块描述符顺序授予，最多一个已授予尚未 release 的 chunk；chunk 不跨命令，长度最多 16 pair。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `result_chunk_valid_o` / `result_chunk_ready_i` | out / in | 1 / 1 | N | 已完成的 16 pair 或命令尾不足 16 pair 可被授予 DMA；valid 后不改长度 |
| `result_chunk_base_o` / `result_chunk_pairs_o` | out / out | 5 / 5 | N | 结果环基项 / 长度 1..16 |
| `result_chunk_row_o` / `result_chunk_block_o` | out / out | 12 / 3 | N | 输出行 / 块号 |
| `result_chunk_pair_o` / `result_chunk_half_o` | out / out | 11 / 1 | N | 行内首 pair / 是否只写低平面 |
| `result_chunk_last_o` | out | 1 | N | 该命令的尾 chunk |
| `result_rd_en_i` / `result_rd_index_i` / `result_rd_plane_i` | in / in / in | 1 / 5 / 1 | N | 已授予 chunk 内，读环项 `(base+j) mod 32`、平面 0/1；每拍可请求一次 |
| `result_rd_valid_o` / `result_rd_data_o` | out / out | 1 / 256 | N | 请求经两级 RAM 后返回；无 ready，DMA 必须先为 W 侧寄存预留位置 |
| `result_release_i` | in | 1 | N | 已授予 chunk 的全部有效平面均已被 DMA 接收、不会再读该 RAM，归还整个 chunk 的 pair 信用 |

`result_release_i` 最早可在本 chunk 最后 W 被桥接受后发出，**不需要等 B**。DMA 若先复制到自身必有的 W 保持寄存，也可在复制完成后释放，但不因此另建整块 RAM。DMA 的 WVALID、WDATA、WSTRB、WLAST 在 WREADY=0 时保持；result RAM 的无 ready 返回不直接接组合 W 通道。

N-C1 输出地址公式（所有加法在 DMA 请求准备级，不在 A1）：

```
OUT_BASE + OUT_OFFSET + (2*block+plane)*OUT_PLANE_STRIDE
  + row*(OUT_W/2)*32 + (chunk_pair+j)*32
```

每个有效平面按连续 pair 做 INCR，按 16 beat 和 4 KiB 拆分；整 beat 的 WSTRB 全 1。残差地址把 OUT 基址/偏移换为 RES 基址/偏移，平面跨距相同。半块不读/不写第二平面，首层同样如此。

#### 4.2.3 层字段分工与时序

| 描述符 / 寄存器字段 | N-C1 责任 | datapath 消费 |
|---|---|---|
| OP、四基址、IN/OUT/RES_SEL、各 OFFSET、WEIGHT_OFFSET、QUANT_OFFSET | 解码/检查规定错误、算 DDR 地址、选择 CONV 或非卷积 | 不传这些 DDR 地址 |
| K3/S2/LUT_EN/RES_EN/IN_C4/HALF_TAIL、IN_W/OUT_W、CIN/COUT_BLOCKS、K_COUNT、OUT_ZP | cfg 握手锁存影子，本描述符不再改 | 对应 cfg 端口；使用方近端寄存副本 |
| IN_H/OUT_H | 判断输入行越界、总命令数量、调度结束 | cmd 的 row_valid、row 和命令序列 |
| ROW_SLOT_BEATS | 五/二槽容量检查、预算槽基址 `slot*ROW_SLOT_BEATS`、规范化行写地址 | cmd 的三个 base 和 line_wr_addr；没有闲置的 ROW_SLOT_BEATS 端口 |
| WEIGHT_BLOCK_BYTES | 容量检查、顺序装载长度和块首 K 行 | cmd_weight_base；datapath 不重复乘除或检查 |
| IN_PLANE_STRIDE / OUT_PLANE_STRIDE | 输入/输出/残差 DMA 平面地址 | 不传给 MAC |
| CTRL.ABORT、AXI 错误 | 停止新 AXI/描述符、cancel 数据通路、收完所有已发事务后 IDLE | cancel 清控制；不增加 datapath 错误码或 watchdog |

推荐时序：cfg 接受 → 权重/参数/首批输入行装载；块 0 完备即可提交首命令，后续块继续装入最终地址。N-C1 只有在该块权重、32 个参数及必要 LUT 均完成、输入行 ready 后才送该命令；这些是生产者所有权，不是接收端新检查。

两个命令上下文（当前/下一条）在接受时锁存字段并复制到地址、MAC 标签、参数读等局部寄存器。`cmd_ready_o` 只表示下一上下文空，**不依赖当前块 WB 排空**。当前最后项发射后，下一条在下拍接替；局部影子必须已在之前一个拍准备完。若在交接沿才接受下一条，则多一个命令准备拍，调度器应提前提交。当前块的末项在 A3 之后不再访问行缓存；N-C1 收到该行所有块的 read_done 后才覆盖不用的旧行槽，不等 WB/B。

#### 4.2.4 各子模块端口

以下每张表列出该模块除 4.2.1 公共控制端口外的全部端口。`weight_store`、`quant_param_store`、`activation_lut` 也具有公共控制端口，只复位/取消本地装载写使能寄存，不复位存储或读数据；读有效性由调用方延迟链承担。`line_cache` 只含公共 clk_i，不含 rst_n_i/cancel_i。其余业务模块具有全部公共控制端口。

`edrv32_npu_input_unpack`：C16 原样写，C4 每次接收后锁存并依次发四项，不与下一 beat 混写。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `cfg_in_c4_i` | in | 1 | N | 本层输入格式副本 |
| `line_wr_valid_i` / `line_wr_ready_o` | in / out | 1 / 1 | N | 同顶层 |
| `line_wr_bank_i` / `line_wr_addr_i` / `line_wr_data_i` | in / in / in | 1 / 10 / 256 | N | 同顶层 |
| `line_wr_row_last_i` / `line_wr_row_done_o` | in / out | 1 / 1 | N | 同顶层；row_last随当前beat锁存，最后缓存写沿后发完成脉冲 |
| `line_wr_idle_o` | out | 1 | N | 剩余项为零 |
| `cache_wr_valid_o` / `cache_wr_bank_o` / `cache_wr_addr_o` / `cache_wr_data_o` | out / out / out / out | 1 / 1 / 10 / 256 | N | 最终缓存单拍写，接 line_cache |

`edrv32_npu_line_cache`：2×1024×256，两个独立物理 bank。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `cache_wr_valid_i` / `cache_wr_bank_i` / `cache_wr_addr_i` / `cache_wr_data_i` | in / in / in / in | 1 / 1 / 10 / 256 | N | 单项写入 |
| `cache_rd_en_i` | in | 2 | N | 每 bank 独立读使能 |
| `cache_rd_addr0_i` / `cache_rd_addr1_i` | in / in | 10 / 10 | N | bank0 / bank1 读地址 |
| `cache_rd_data0_o` / `cache_rd_data1_o` | out / out | 256 / 256 | N | 两级同步返回，不返回 ready |

`edrv32_npu_window`：拥有两个命令上下文、循环和 A1–A5；包含行缓存选择、激活复制、权重读对齐。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `cfg_k3_i` / `cfg_s2_i` / `cfg_in_c4_i` / `cfg_half_tail_i` | in / in / in / in | 1 / 1 / 1 / 1 | N | 本层几何/模式副本 |
| `cfg_lut_en_i` / `cfg_res_en_i` / `cfg_out_zp_i` | in / in / in | 1 / 1 / 8 | N | 标签字段 |
| `cfg_in_w_i` / `cfg_out_w_i` / `cfg_cin_blocks_i` / `cfg_cout_blocks_i` / `cfg_k_count_i` | in / in / in / in / in | 12 / 12 / 6 / 4 / 11 | N | 与顶层相同 |
| `cmd_valid_i` / `cmd_ready_o` | in / out | 1 / 1 | N | 与顶层相同 |
| `cmd_row_i` / `cmd_block_i` / `cmd_weight_base_i` | in / in / in | 12 / 3 / 11 | N | 与顶层相同 |
| `cmd_row_base0_i` / `cmd_row_base1_i` / `cmd_row_base2_i` / `cmd_row_valid_i` | in / in / in / in | 10 / 10 / 10 / 3 | N | 与顶层相同 |
| `issue_enable_i` / `pair_ready_i` | in / in | 1 / 1 | N | 执行使能 / 顶层已具备结果和残差信用 |
| `pair_result_slot_i` / `pair_residual_addr_i` | in / in | 5 / 5 | N | 下一 pair 的预留地址 |
| `pair_fire_o` | out | 1 | N | A1 首项接受，消费一项结果信用和相应残差 |
| `pair_half_o` | out | 1 | N | 当前候选 pair 是单平面，供残差信用选择 |
| `cache_rd_en_o` / `cache_rd_addr0_o` / `cache_rd_addr1_o` | out / out / out | 2 / 10 / 10 | N | A1 寄存的 RAM 请求 |
| `cache_rd_data0_i` / `cache_rd_data1_i` | in / in | 256 / 256 | N | A3 返回 |
| `weight_rd_en_o` / `weight_rd_addr_o` / `weight_rd_data_i` | out / out / in | 1 / 11 / 2048 | N | 与 cache 并行读权重；A3 返回，A4/A5 再对齐 |
| `term_valid_o` / `term_first_o` / `term_last_o` | out / out / out | 1 / 1 / 1 | N | A5 输出归约项 / pair 首末项 |
| `term_tag_o` / `term_activation_o` / `term_weight_o` | out / out / out | 49 / 1024 / 2048 | N | 标签、4 份各 256 位激活、32×8 权重 |
| `cmd_issued_o` / `cmd_issued_row_o` / `cmd_issued_block_o` | out / out / out | 1 / 12 / 3 | N | 同顶层 |
| `cmd_read_done_o` / `cmd_read_done_row_o` / `cmd_read_done_block_o` | out / out / out | 1 / 12 / 3 | N | 同顶层 |
| `idle_o` | out | 1 | N | 上下文和 A1–A5 valid 为空 |

`term_activation_o` 每份为低 128 位像素0、上 128 位像素1。普通块每像素低 64 位是选中的 C8，其余置零；D2 是完整 C16；C4 是低 32 位 C4、其余零。每份服务 8 个物理输出通道。所有 first/last/tag/地址随各自数据逐级延迟。

`edrv32_npu_weight_store`：8 bank 常驻池，装载本地寄存加纯RAM。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `weight_wr_valid_i` / `weight_wr_addr_i` / `weight_wr_data_i` | in / in / in | 1 / 14 / 256 | N | 同顶层，bank=addr[2:0]、行=addr[13:3] |
| `weight_rd_en_i` / `weight_rd_addr_i` / `weight_rd_data_o` | in / in / out | 1 / 11 / 2048 | N | 两级读，输出 bank b 放 `[256*b+:256]` |

`edrv32_npu_quant_param_store`：8 bank，每个 bank 存 channel%8 相同的参数。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `quant_wr_valid_i` / `quant_wr_block_i` / `quant_wr_channel_i` | in / in / in | 1 / 3 / 5 | N | 同顶层，bank=channel[2:0] |
| `quant_wr_bias_i` / `quant_wr_mult_i` / `quant_wr_shift_i` | in / in / in | 32 / 16 / 6 | N | 打包为 64 位参数项 |
| `param_rd_en_i` / `param_rd_block_i` / `param_rd_phase_i` | in / in / in | 1 / 3 / 2 | N | 同时读 8 通道；地址 `{block,phase}` |
| `param_rd_data_o` | out | 512 | N | 8×64 位，按 lane=channel%8 递增；两级返回 |

`edrv32_npu_mac_array`：M1/M2 和 R1/R2/R3，固定吞吐 1 项/拍，无 ready。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `term_valid_i` / `term_first_i` / `term_last_i` | in / in / in | 1 / 1 / 1 | N | A5 数据 |
| `term_tag_i` / `term_activation_i` / `term_weight_i` | in / in / in | 49 / 1024 / 2048 | N | 同 window 输出 |
| `sum_valid_o` / `sum_first_o` / `sum_last_o` / `sum_tag_o` | out / out / out / out | 1 / 1 / 1 / 49 | N | R3 结果及对齐控制 |
| `sum_data_o` | out | 1216 | N | 2×32×19 位有符号 8 路和 |
| `mac_beat_o` | out | 1 | N | M1 valid，同顶层 |
| `idle_o` | out | 1 | N | 本模块有效链为空 |

`edrv32_npu_accum`：R4 合并和 ACC；普通块也经过同一 R4 寄存边界。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `sum_valid_i` / `sum_first_i` / `sum_last_i` / `sum_tag_i` / `sum_data_i` | in / in / in / in / in | 1 / 1 / 1 / 49 / 1216 | N | MAC 输出 |
| `quant_prepare_valid_o` / `quant_prepare_tag_o` | out / out | 1 / 49 | N | R4 沿前由 R3 的 last/tag 组合驱动，在 R4 同一沿启动参数 phase0 读 |
| `accum_valid_o` / `accum_tag_o` / `accum_data_o` | out / out / out | 1 / 49 / 2048 | N | ACC 仅 last 输出；D2 的高16通道填零 |
| `idle_o` | out | 1 | N | R4/ACC 有效链为空 |

`edrv32_npu_result_quant`：Q0–Q12，持有一个 pair 的累加向量，按组发出，不因输出停顿。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `quant_prepare_valid_i` / `quant_prepare_tag_i` | in / in | 1 / 49 | N | 依次发起 G 个参数组读；G=half?2:4 |
| `accum_valid_i` / `accum_tag_i` / `accum_data_i` | in / in / in | 1 / 49 / 2048 | N | 最终累加向量，进入 hold 寄存 |
| `param_rd_en_o` / `param_rd_block_o` / `param_rd_phase_o` / `param_rd_data_i` | out / out / out / in | 1 / 3 / 2 / 512 | N | 参数提前读，Q0 时与对应组累加值对齐 |
| `lut_rd_en_o` / `lut_rd_block_o` / `lut_rd_addr_o` / `lut_rd_data_i` | out / out / out / in | 1 / 3 / 128 / 128 | N | 16 个独立 8 位下标，同一 block；LUT 两级返回 |
| `residual_rd_en_o` / `residual_rd_addr_o` | out / out | 1 / 5 | N | 最后一组到 Q10 时请求低平面，下拍请求高平面（若非 half） |
| `quant_valid_o` / `quant_tag_o` / `quant_data_o` | out / out / out | 1 / 49 / 512 | N | Q12 完成 pair，按平面位序打包；half 高平面为零 |
| `idle_o` | out | 1 | N | hold、组发射及 Q 流水均空 |

`edrv32_npu_activation_lut`：16 份独立读的全层 LUT，装载本地寄存加纯RAM。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `lut_wr_valid_i` / `lut_wr_block_i` / `lut_wr_addr_i` / `lut_wr_data_i` | in / in / in / in | 1 / 3 / 8 / 8 | N | 写地址 `{block,addr}` 广播16份 |
| `lut_rd_en_i` / `lut_rd_block_i` / `lut_rd_addr_i` / `lut_rd_data_o` | in / in / in / out | 1 / 3 / 128 / 128 | N | 每 lane 独立地址、两级返回；关闭 LUT 的 q 旁路也延迟两级 |

`edrv32_npu_residual_buffer`：两个半区的占有/提交/预留和数据 RAM。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `residual_begin_valid_i` / `residual_begin_ready_o` / `residual_begin_bank_i` | in / out / in | 1 / 1 / 1 | N | 与顶层相同 |
| `residual_begin_pairs_i` / `residual_begin_half_i` | in / in | 5 / 1 | N | 与顶层相同 |
| `residual_wr_valid_i` / `residual_wr_bank_i` / `residual_wr_index_i` / `residual_wr_data_i` | in / in / in / in | 1 / 1 / 4 / 256 | N | 与顶层相同 |
| `residual_commit_i` | in | 1 | N | 与顶层相同 |
| `pair_half_i` / `pair_reserve_i` | in / in | 1 / 1 | N | 候选模式 / A1 pair_fire 预留脉冲 |
| `pair_residual_ready_o` / `pair_residual_addr_o` | out / out | 1 / 5 | N | 顺序头 pair 已提交 / 低平面地址 |
| `residual_rd_en_i` / `residual_rd_addr_i` | in / in | 1 / 5 | N | Q10 提前读，采样后释放相应 beat 的存储占有 |
| `residual_rd_valid_o` / `residual_rd_data_o` | out / out | 1 / 256 | N | 两级返回，低/高平面顺序 |
| `idle_o` | out | 1 | N | 半区均空且无未返回读 |

`edrv32_npu_residual_add`：组合 low/high 两个 C16 残差返回并延迟到 WB；WB1 求和，WB2 饱和。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `quant_valid_i` / `quant_tag_i` / `quant_data_i` | in / in / in | 1 / 49 / 512 | N | Q12 pair |
| `residual_rd_valid_i` / `residual_rd_data_i` | in / in | 1 / 256 | N | 两拍返回，按 quant 的读计划装配，无额外请求仲裁 |
| `writeback_valid_o` / `writeback_tag_o` / `writeback_data_o` | out / out / out | 1 / 49 / 512 | N | WB2，RES_EN=0 走等延迟旁路 |
| `idle_o` | out | 1 | N | WB 有效链为空 |

`edrv32_npu_writeback`：32 项结果环和 chunk 描述符，WB2 写 RAM，不再多加一拍。它的 `result_chunk_*`、`result_rd_*`、`result_release_i` 端口与 4.2.2 同名同方向同宽；该引用为完整端口集的一部分，另外只有下表端口。

| 信号 | 方向 | 位宽 | 域 | 含义 |
|---|---|---:|---|---|
| `writeback_valid_i` / `writeback_tag_i` / `writeback_data_i` | in / in / in | 1 / 49 / 512 | N | 在 WB2 沿写入预留项（同沿 residual_add 的组合饱和结果） |
| `pair_reserve_i` | in | 1 | N | A1 pair_fire，预留 next slot |
| `pair_result_slot_o` / `result_credit_o` | out / out | 5 / 6 | N | 分配项号 / 空位计数 |
| `cmd_done_o` / `cmd_done_row_o` / `cmd_done_block_o` | out / out / out | 1 / 12 / 3 | N | 同顶层 |
| `idle_o` | out | 1 | N | 没有预留、已完成项、chunk 或正在返回的读 |

残差读同样在 Q10 沿前由 Q9 的最后组控制发出，使RAM在Q10同沿采样。双平面时，WB1用前一拍保留的低平面和当前返回的高平面直接求和；单平面时用已保留的低平面。不能先将高平面再寄存一次才做WB1，否则多一拍。读返回没有背压，量化组日历保证相邻pair的残差请求不冲突。

WB2 的饱和输出连到 RAM 写输入：`writeback_valid_o/data_o` 为 WB2 沿前的信号，WB2 寄存边界就是 RAM 写寄存；不得先在 residual_add 再寄存一次而使端到端多一拍。

### 4.3 第 3 项：流水级、控制复制与尾部

#### 4.3.1 逐级边界

以下 LUT 级数都是对 LUT4/进位链的**估算**，不是 STA；带进位链的加法另列算术宽度。目标每级约 ≤8 级，PDS 若暴露长布线再改开发初值。约定归约最后项在 A1 接受沿为 n，A1 寄存输出在该沿后有效，后级依次在 n+1、n+2…；不把同一接受沿重复计为一拍。

| 级 / 对最后项的沿 | 寄存边界和组合工作 | 估计 LUT 级数 |
|---|---|---:|
| A1 / n | 寄存循环计数、两个像素坐标/补边、bank/地址/权重行和 tag；地址只有预算量加法 | 4–7 |
| A2 / n+1 | 行缓存及权重 DRM 同步读阵列，寄存读地址的分段和路由选择 | 0–2 + DRM |
| A3 / n+2 | DRM 输出寄存器；权重深度段选择及行缓存 bank 选择信息对齐 | 1–2 + DRM |
| A4 / n+3 | beat 中选像素、普通 C8 / D2 C16 / C4、边界清零；权重对齐寄存 | 3–5 |
| A5 / n+4 | 激活复制4份，每份供8输出通道；权重分32份本地寄存 | 0–1 |
| W1/W2 | 与 A2/A3 并行的权重读，**不再串加两拍**；A4/A5 对齐 | 同上 |
| M1 / n+5 | APM X_REG/Y_REG 接受两路有符号操作数 | 0–1 + APM |
| M2 / n+6 | APM MULT_REG 输出两个 INT16 乘积，P_REG=0 | 0 + APM |
| R1 / n+7 | 8→4，每路 17 位和 | 1–3 + carry |
| R2 / n+8 | 4→2，每路 18 位和 | 1–3 + carry |
| R3 / n+9 | 2→1，每路 19 位和 | 1–3 + carry |
| R4 / n+10 | D2 将物理 c 与 c+16 相加为20位；普通块符号扩展直通；last 同时准备参数读 | 2–4 + carry |
| ACC / n+11 | 64路 INT32 累加；first 用本项替换旧值，不清数据 RAM；last 把最终向量交给量化 hold | 2–4 + 32位 carry |
| Q0 / n+12+g | 取第g组16个acc、两像素共用8个参数；参数读由 R4 的准备脉冲提前两级发起 | 2–4 |
| Q1 / n+13+g | 有符号 acc+bias，33位；shift/mult/zp/tag 寄存 | 1–3 + carry |
| Q2 / n+14+g | 两个量化 APM 的输入寄存（低17位无符号、高16位有符号） | 0–1 + APM |
| Q3 / n+15+g | 两个 APM MULT_REG 输出 | 0 + APM |
| Q4 / n+16+g | 两个部分积按17位偏移合成为49位有符号乘积 | 2–4 + carry |
| Q5 / n+17+g | 加49位舍入常数；shift=0 时加0 | 3–5 + carry |
| Q6 / n+18+g | 算术右移 shift[2:0]（0/1/2/4 组合） | 3–4 |
| Q7 / n+19+g | 算术右移 8×shift[5:3]（0/8/16/32 组合），shift最大47 | 3–4 |
| Q8 / n+20+g | 加符号扩展zp，50位暂存 | 1–3 + carry |
| Q9 / n+21+g | clamp[-128,127]，寄存16个8位下标 | 3–5 |
| Q10 / n+22+g | 16份 LUT DRM 同步读；最后一组同时请求残差低平面 | 0–1 + DRM |
| Q11 / n+23+g | LUT 输出寄存或等延迟 q 旁路；最后一组的下一拍请求残差高平面 | 0–2 + DRM |
| Q12 / n+24+g | 组装到 pair 的对应平面/通道；最后组产生 pair valid | 1–2 |
| WB1 / n+25+(G−1) | 逐字节10位 `y+r-zp`，RES_EN=0 等延迟旁路 | 3–5 + carry |
| WB2 / n+26+(G−1) | 饱和、打包并写结果环 RAM；同步更新完成指针 | 3–5 |

G=4（双平面）/2（单平面），g=0..G−1。所以**最后归约项 A1 → WB2 为 29 / 27 个周期**；若把 A1 本身也计为寄存边界，共 30 / 28 个边界。一个 pair 从首项 A1 到结果写入为 `K_eff−1+29`（普通）或 `K_eff−1+27`（half）拍；首层 half 也为27拍，K_eff仍9。结果 RAM 读再经两级，与上述计算尾部不同，不把 DDR W/B 等待计进固定流水。

参数 read 的 phase0 使能由 R3 输出的 last/tag 在 R4 沿前组合产生，RAM 与 R4 在同一沿采样；不能先寄存 prepare_valid 再晚一拍读。后面每拍一个 phase，R4/ACC/Q0 的时距使参数与每组 Q0 对齐。量化 hold 捕获最终向量，防止后一个 pair 的 ACC 更新覆盖当前组。普通/D2 的 G 不同，在交接处也按前一 pair 的量化占用日历发射；不只比较新块的 K。

R4/ACC 使用每项 tag[48]，Q/LUT/WB 使用随组流动的 block、zp、half、res、lut；**不能读已经切换到下一命令的全局字段**。下一块 first 到 ACC 时立即替换前一块累加值，前一块 last 已在上一拍交给量化，不需要清空全流水。

#### 4.3.2 高扇出和复位

- A1 地址寄存分为每个行缓存 bank、8 个权重 bank 的本地副本；权重 bank 再分别驱动三个512深分段，段号随读延迟，输出选择由寄存段号驱动。地址加法不串接大扇出译码。
- A5 激活有4份物理寄存，每份仅驱动8个物理输出通道；D2 每份仍为256位。权重按通道各64位寄存，禁止一根组合权重选择线贯穿全阵列。
- valid/first/last 在A5复制到32个输出通道的本地有效链；它们只选累加/输出有效，不构成全阵列停钟 CE。APM CE 常开，空拍数据任意，valid屏蔽意义。
- cmd切换脉冲仅更新当前/下一上下文有效位；模式、地址和参数块号已在接受时各寄存本地副本。LUT配置地址/数据在16份RAM附近复制寄存，保证写使能与数据同拍，装载完成由N-C1按这一级延迟计算。
- result读索引按8个64位数据片本地复制，plane选择也延迟到读返回；不从 WREADY 组合驱动计算链。权重/参数/LUT写均有固定一级局部装载寄存：输入写使能在沿e接受，实际RAM在e+1写入，N-C1最早在e+2认定该块装载完成并提交命令。行写另计：C16在握手沿e直接写缓存，C4在e+1..e+4写四项；带row_last的beat在最后缓存写沿后产生row_done脉冲。下一行可与上一行末项写同沿接受，N-C1按row_done而非全局idle提交行ready。不能在最后输入写使能沿就启动同一块计算。
- rst/cancel仅清有效链、命令和队列控制；APM输入/乘积、累加数据、量化数据、RAM内容不复位。各业务的cancel为同一域寄存驱动的局部复制，不同步成多个域。

#### 4.3.3 尾部暴露位置和 N-E2 敏感性

正常且供数/信用连续时，跨 pair、输出块、输出行都不排空；每个 CONV 描述符只在最后一个有效 pair 到 WB2 后结束计算。固定旧计划是63个CONV、3个POOL、2个UP（6个ADD由W6消去）；因此每帧**计算流水完整尾部最多暴露63次，位置均在CONV描述符边界**，单平面末块12条、双平面51条，尾部和=`12×27+51×29=1803`拍。POOL/UP沿用各自执行时序，不算成29/27拍尾部。描述符之间还必须等最后B，不能用跨层发射隐藏这个依赖。

层内可暴露的等待只在下一 pair 入口：首块/第一行未装好、W3后续块装载未赶上、W1后续行未赶上、RES_EN残差批次未提交、结果环信用耗尽或短K的量化间隔。它们可以让已有流水自然流空，但不是控制器在每行/每块固定等待尾部。消除办法依次是提前装载、最终槽位预取、五/二槽预取、残差双半区、结果RAM双chunk和命令提前入队；不能通过拉全局CE冻结已发数据。DDR反压期间可能多次自然流空，次数由服务轨迹决定，不能用63声称其全部被隐藏。

用同一输入commit的N-E2模型，仅改变尾部常数的**阶段模型敏感性估算**如下。输入仍为L=94、150MHz、共享4.0/1.4GB/s、旧74命令和原模型DDR字节，不把本节算成新RTL预测：

| 尾部处理 | 4.0GB/s 周期 / fps | 1.4GB/s 周期 / fps |
|---|---|---|
| 原N-E2，逐行逐块14/15 | 6,576,004.896 / 22.810202 | 7,154,007.679 / 20.967269 |
| 机械改成逐行逐块29/27（对照，**不采用**） | 6,638,826.229 / 22.594356 | 7,205,998.220 / 20.815992 |
| 本设计，29/27只在每个CONV末尾计一次 | 6,517,512.917 / 23.014914 | 7,105,387.908 / 21.110740 |

输入形状共4032个双平面行块、636个单平面行块；原固定项65796拍，逐行新固定项=`4032×29+636×27=134100`拍，描述符末尾新固定项1803拍。模型还会重算writer到达时刻、W1窗口和共享载荷下限，因此全网差值不等于固定项差值：逐行替换相对原模型为+62821.333/+51990.542拍，连续发射估算为−58491.979/−48619.771拍（4.0/1.4）。

复现下面命令只在内存中替换模型函数，不写 `tools/`、规格或报告：

```sh
python3 - <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path('tools/npu/eval').resolve()))
import datapath_model as d
import legacy_plan as p
rows = p.analysis()  # YAML默认路径及依赖见N-E2“复现”
changes = d.C0 + ('D2', 'D3b')
old = d.datapath_stages
source = Path('tools/npu/eval/datapath_model.py').read_text()
source = source.replace('merge = int(half)',
    "merge = 13 if c['last_c16_only'] and block == b-1 else 15")
ns = dict(d.__dict__)
exec(compile(source, 'tail_sensitivity_in_memory', 'exec'), ns)
new = ns['datapath_stages']
def streaming(c, latency, bandwidth, changes):
    s = new(c, latency, bandwidth, changes)
    b, h = c['output_blocks'], c['output_height']
    one = int(c['last_c16_only'])
    s['patch_pipeline'] -= h*((b-one)*29+one*27) - (27 if one else 29)
    return s
for bw in (4.0, 1.4):
    for name, fn in [('old', old), ('row', new), ('stream', streaming)]:
        d.datapath_stages = fn
        cy = sum(r['cycles'] for r in d.network(rows, 94, bw, changes))
        print(bw, name, f'{cy:.6f}', f'{150e6/cy:.6f}')
PY
```

这仍保留旧模型逐行writer重启、四B credit和配置/row_prepare阶段，不是跨行信用环的逐拍仿真；也未加入C4展开、尾块镜像紧缩和新增参数RAM装载拍。因此不能据此承诺21.11fps或20.97fps。N-D1/N-C1联调后须更新模型常数，再以规格7的条件测量。

### 4.4 第 4 项：D3b 循环、地址和行槽

#### 4.4.1 增量循环

N-C1 外循环为 `output_row → output_C32_block`，window 内循环固定如下：

```
for pair in 0 .. OUT_W/2-1:
    for ky in 0 .. kernel-1:
        for kx in 0 .. kernel-1:
            for c16 in 0 .. CIN_BLOCKS-1:
                for c8_half in 0 .. 1:  # 普通C16模式
                    issue one term for two pixels
```

D2 不遍历 c8_half，一拍取完整 C16；C4 不遍历 c16/c8_half，一拍取 C4 并在 C8 输入高4通道补零。定义 `s=S2?2:1`、`pad=K3?1:0`：

```
y  = output_row*s + ky - pad
x0 = 2*pair*s + kx - pad
x1 = x0 + s
bank(x) = x[1]
addr(x) = row_base[ky] + c16*(IN_W/4) + (x >> 2)
pixel_in_beat = x[0]
weight_row = cmd_weight_base + k_index
```

公式用于说明映射；RTL 地址路径不做乘法。命令接受时登记 `IN_W>>2`，通道组偏移每组加该常量，pair源x每pair加2或4，kx/ky递增，k_index逐拍加1；每个pair末尾回到权重块首地址。负坐标使用有符号14位坐标（覆盖12位宽、高、步长2及±1），先生成pad位，再选有效像素的bank/addr；无效读不发请求或与另一个有效像素共用读地址，不让负坐标的截断值形成实际访问。

边界清零由 `cmd_row_valid[ky] && 0<=x<IN_W` 控制。1×1不补边，按合法输出几何取样；CONV的边界值始终是字节0，不改成OUT_ZP。POOL的−128边界属于非卷积执行器。

| 模式 | 每拍选出的激活 / 权重 | 行缓存物理读 | 地址特点 |
|---|---|---|---|
| 1×1 S1 | 两像素各C8，普通K=2×CIN_BLOCKS | 同beat时1×256，否则2×256；每bank≤1读 | ky=kx=0，两个像素相邻；无chunk填充 |
| 1×1 S2 | 同上 | 两个bank各256 | x1=x0+2；输入行跳过不用的行，不为其发DDR读 |
| 3×3 S1 | 每个(ky,kx,c16,half)两像素各C8 | 0/256/512位，由补边和是否同beat决定 | x相邻；同bank必同beat，可一次读后抽两个像素 |
| 3×3 S2 | 同上 | 内部有效像素时2×256 | 相隔2像素，必不同bank；上下左右补零 |
| D2，IN_C4=0且half | 两像素各完整C16，物理输出0..15乘低C8、16..31乘高C8 | 与普通块相同，上限512位/拍 | 不遍历half；R4合并对应输出部分和，归约拍减半 |
| IN_C4 | 两像素各C4，扩为C8的高4输入为0，K=kernel²（首层9） | 仍最多2×256；取每像素低32位 | 缓存规范化，不增加计算的C16/C8迭代；HALF_TAIL只决定写回平面数 |

S1同bank冲突的证明：两个相邻x若x[1]相同，则它们的x>>1也相同，即同一个两像素beat；若x[1]不同，则各读一个bank。S2两点差2，x[1]必不同。此证明覆盖1×1/3×3各kx，D2不改变x。因此不保留旧line_cache的冲突检测门。

A4后普通有效数据16B/拍、D2 32B/拍、C4 8B/拍；毛读最大64B/拍，估计片上读带宽=`64×150MHz=9.6GB/s`，不等于DDR带宽。权重固定256B/拍，即38.4GB/s片上毛读。

#### 4.4.2 写地址和槽轮转

C16行DMA的第c16平面、第beat号j（每beat两个像素）写：

```
cache_bank = j & 1
cache_addr = slot_base + c16*(IN_W/4) + (j >> 1)
```

C4行每个DDR beat含8个像素，N-C1给定 `line_wr_addr=slot_base+2*j`。unpack将其拆成4个两像素beat，各像素低4字节保留，其余12字节补0，按 `(bank,addr)=(0,a),(1,a),(0,a+1),(1,a+1)` 顺序写。DDR beat0的第4字节是固定零通道，不交换RGB；缓存内不改变低字节R的约定。规范化只增加缓存写带宽，不把首层归约补成C16。

3×3固定五个槽，槽base=`slot*ROW_SLOT_BEATS`（0..4）；S1窗口后移一行释放一旧槽、可预取至少一行，S2后移两行保留一行并预取两行。负/超末行只置row_valid=0、不占DMA载荷。N-C1保存slot对应的输入行号和ready；同一输出行的所有C32块都读完A3之前，不回收其仍需的输入行。逻辑轮转可在软件预算的五个base中选择，不在A1做模5除法。

1×1固定两个槽，当前输入行和下一条会被使用的输入行交替，S2直接预取下一条被使用的行，不为中间未采样行浪费DDR。第一个新行的命令可以在旧行读结束后立即发射，只要它用的槽已ready。

**规格5.2完全匹配此组织**：ROW_SLOT_BEATS实际是“每个bank的行槽地址项数”，不是DDR beat总数。C16每行有 `CIN_BLOCKS×IN_W/2` 个256位DDR beat，奇偶均分后每bank为 `CIN_BLOCKS×IN_W/4`。所以五槽/双槽分别满足 `5×ROW_SLOT_BEATS≤1024` / `2×ROW_SLOT_BEATS≤1024`，两bank合计容量64KiB。C4按上述规范化后也每bank占IN_W/4项（CIN_BLOCKS=1），无需修改这两个不等式。建议只补清字段名称的含义，不改公式。

#### 4.4.3 无空拍条件、首层展开成本

同一固定模式连续pair的首拍间隔 `II=max(K_eff,G)`，G=4或2。只有K_eff≥G、行/权重/参数已装好、残差已提交且结果有信用时，两个pair之间能每拍连续发归约项；否则只在下一个pair首项之前插空拍。固定整网普通1×1最小K=4、D2最小K=5、首层K=9，量化不造成该网络的额外pair间隙。小形状普通Cin16 1×1的K=2、D2 Cin16 1×1的K=1会分别产生2/1拍入口间隙，这属于实际吞吐限制，不是D3b填充。

跨模式/块时，令上一pair最后归约项接受时刻为L，下一pair拟首项时刻为T、归约长度为K'，发射还须满足 `T+K'−1 ≥ L+G_previous`。用一个最多4拍的量化占用倒计数和K'比较即可；不能只按G_new计算。当前pair首项已经通过后，余下K'−1项连续发，不在中间受信用背压。流水填充为4.3固定29/27拍尾部与最初A1–A5/M/R/ACC/Q延迟，不存在 `tile_pairs*K` 预填或每pair重新填充。

C4的合法宽为8的倍数（协调者确认，来自SoC7.3的stride规则）；不实现半beat行首提取或新的宽度检查。实际640×384：每行80个DDR beat、规范化320个缓存写拍；整幅30720个DDR beat、122880个缓存写拍。相对每原beat写一次，多出 `3×30720=92160` 个局部写拍，但大部分由W1隐藏：每个输出行160pair×9=1440个归约拍，S2下一行所需两输入行只需640个缓存写拍。

只估算展开的增量、保持AXI首拍延迟不变：在源口4.0GB/s下，80个C4 beat载荷需 `80×32/(4e9/150e6)=96`拍，展开下界320拍，差224拍/输入行；1.4GB/s对应274.286拍，差45.714拍/行。若后续行均按期预取，初始两行新增可见开销估算448拍/91.429拍（2.987μs/0.610μs）；极保守地全部展开增量都串行则≤92160拍（0.6144ms）。这些不是仲裁/突发延迟保证，首层实际增量由N-C1限带宽仿真确认。

另有独立的DDR字节修正：N-E2 W5模型实际沿用C3载荷737280B，规格C4为983040B，差245760B（1.4GB/s载荷时间175.543μs，4GB/s为61.440μs）。上面展开增量是相对**C4原beat**计算，不把C3→C4增量重复当成展开写拍；4.3敏感性表未改这一流量假设。

### 4.5 第 5 项：片上存储和 DRM 估算

所有数据RAM同域、无初始化文件、无内容/输出复位。SDP为1W+1R，可同拍写预取内容、读当前内容；正常所有权保证没有读写同址。（2026-10-27 补记：PDS SDP IP 没有 Read First 选项，ModelSim 实测同拍同址读出值不确定；数据通路单元测试 12 个用例实测同址读写 0 次，因此不依赖冲突读出值，行为模型保留读旧数据写法。）表中的读延迟“2级”表示同步RAM阵列一级+输出寄存一级；例如A2取样、A3输出，后续A4使用。

每个逻辑bank的计算式为 `ceil(宽/原语宽)×ceil(深/原语深)`，各独立端口bank再求和。

| 存储 | 逻辑组织 / 容量 | 端口和延迟、输出寄存 | 固定物理映射与DRM估算 |
|---|---|---|---|
| 行缓存 | 2×1024×256，64KiB | 每bank1W256+1R256；2级、开输出寄存；DMA逻辑每拍总写1bank | `2×ceil(256/32)×ceil(1024/1024)=16` |
| 常驻权重 | 8×1152×256=294912B（288KiB），整层共享池 | 8bank各1W256+1R256；总读2048bit/拍；2级、开输出寄存；逻辑总写256bit/拍 | 每bank三段512×256，每段4个512×64；`8×3×4=96`；物理8×1536×256=384KiB |
| 量化参数 | 8bank×32×64=2048B；bank=channel%8，addr={block,phase} | 每bank1W64+1R64，8个独立参数/拍供两个像素；2级、开输出寄存 | `8×ceil(64/64)×ceil(32/512)=8`；物理32KiB；有效54bit/项 |
| 激活表 | 16bank×2048×8=32768B（16路副本×8块×256） | 16个独立R8；广播W8；2级、开输出寄存；地址{block,q} | `16×ceil(8/8)×ceil(2048/4096)=16`；物理64KiB，不能把16个独立读端口合成一块 |
| 残差缓冲 | 1×32×256=1024B，两个16深半区 | 1W256+1R256；2级、开输出寄存；每个pair提前读1/2拍 | `ceil(256/64)×ceil(32/512)=4`；物理16KiB |
| 结果环 | 1×32×512=2048B（32个pair） | WB2 1W512，DMA 1R512选平面；2级、开输出寄存 | `ceil(512/64)×ceil(32/512)=8`；物理32KiB；标签/描述符另存FF |
| **CONV datapath合计** | 不含外围AXI/CDC、非卷积 | 以上固定映射 | **16+96+8+16+4+8=148 DRM** |
| 非卷积输入平面暂存 | 1×120×256=3840B，POOL最大20×12×C16 | 1W256+1R256；1级、不加输出寄存，保留三状态采样 | `1×4×ceil(120/512)=4` |
| 非卷积行暂存 | 1×20×256=640B，POOL只用10项，UP最多20项，共用 | 1W256+1R256；1级、不加输出寄存 | `1×4×ceil(20/512)=4` |
| **含串行非卷积已分配部分** | 两个scratch只例化一份，不按算子叠加 | 不含N-C0/N-C1尚待细化的FIFO | **156 DRM；距170尚余14** |

32项结果环由在途量推出，而不是任意放大：最短合法K_eff可为1，量化至少每2拍接受一个pair；统一用较长29拍尾部作保守上界，在途pair上界 `ceil((K_eff−1+29)/max(K_eff,2))≤15`。一个已借给DMA的chunk最多16pair，计算侧需再容纳15个在途/完成pair，最小31项，取二次幂32项，即2KiB。credit计数严格包括这些占有者。RAM完成前不会向DMA授予未写好的项。

结果tag和chunk元数据是小型FF存储：结果项保留row/block/pair/half/last等，最多32项；chunk描述符最坏每命令只1pair，也可能有32个待处理头，使用32项FF队列，不假设永远只有两个命令。49位tag不全部常驻结果RAM（slot/address只用于流水），结果数据不因元数据再加宽DRM。参数组/乘积/累加hold均为流水FF，不另加累加RAM或activation RAM。量化512B原始记录由N-C1拆解后即可丢弃，不在这里永久保存8份原始记录。

资源比较：N-E2的155是“旧79 + 替换增量”的全旧网表估算，包含旧网表未分解的控制/测试/缓冲，且参数采用FF；本文148/156是逐项存储重算，两者不能直接视为−7/＋1的实测变化。旧PDS基线APM289、DRM79来自 `legacy/doc/architecture/2026-09-23-yolo-v8n-exec.md` 2026-09-24板测段，PDS执行commit在该归档中未记录；N-E1被测legacy版本为 `2bdcaf1ef3f324c4633e4a879b155fb04fd5d45e`，不能把它冒充该次PDS执行commit。150MHz当时WNS−0.048ns，不能作为新结构已收敛证据；原始Windows工程报告位置旧文未给出，只能引用仓库归档摘要。

因此**数据通路148≤170、已明确NPU存储156≤170，但完整NPU尚未证明≤170**：余14块需由N-C1与N-C0给出读返回、写保持和X9 FIFO映射，VIN输入适配占用也需按SoC预算归口；不能在未见映射前预占成已验证结论。LUT只引用旧约45K的量级，不从文本推导新LUT≤50K。

### 4.6 第 6 项：APM 映射和符号处理

#### 4.6.1 512 个 INT8 乘法

按旧 `edrv32_yolo_apm_mul2.v` 的**原生SIMD**配置移植：每个物理输出通道c和输入项k一个APM，同一权重分别乘两个像素。`32×8=256 APM`，每APM输出2个INT16积，总计512乘法/拍。D2改为物理c=0..15用输入低C8、c=16..31用同一逻辑输出的高C8，两像素仍分别占SIMD两路；R4将c/c+16相加，APM数不变。

旧包装的准确打包如下（s8的符号位是[7]）：

```
X[29:0] = {6'b0, {4{a1[7]}}, a1[7:0], {4{a0[7]}}, a0[7:0]}
Y[17:0] = {b1[7], b1[7:0], b0[7], b0[7:0]}
p0 = P[15:0]
p1 = P[39:24]
```

12位X子字、9位Y子字分别对各自INT8做符号扩展；这就是本结构所需的符号修正。两个SIMD乘积位于两个24位结果槽，各取低16位，不能把整个X×Y当作普通宽乘法再截位，也不能额外给p1加“低路负积进位修正”（那属于另一种共享操作数打包算法，旧RTL没有这条加法）。行为模型直接分别做两个有符号8×8，全范围−128和127都适用。

包装配置沿用旧源码：USE_SIMD=1、USE_POSTADD=0、USE_PREADD=0、X_REG=1、Y_REG=1、MULT_REG=1、P_REG=0，MODEY=001、MODEZ=0000、MODEIN=00010，Z及级联输入置0；时钟使能恒1，数据复位接无效。二级为M1/M2。N-IP1必须用Windows供应商模型核对这套端口/模式与2路符号扩展，不把普通单乘IP或未经验证的算术打包当成等价替换。

#### 4.6.2 量化乘法与合计

acc与bias各INT32，求和保留33位；乘有符号16位mult须保留49位，沿用旧量化链的全精度。一个APM的25×18乘法宽度不够33×16，固定每lane拆两个APM：

```
b = signed33(acc) + signed33(bias)
lo = unsigned17(b[16:0])        # 零扩为有符号18位送APM
hi = signed16(b[32:17])
b = hi*2^17 + lo
product49 = signed(hi*mult)*2^17 + signed(zero_extend(lo)*mult)
```

两个乘法均为正常有符号乘法；lo必须补0，不能误当signed17。Q2/Q3为输入/乘积内部寄存，Q4合成，Q5舍入（shift=0常数为0；其余1<<(shift−1)），Q6/Q7算术移位，再加zp/饱和。bias和不得先截成32位；mult允许负数，shift0..47，不添加范围检查。

16lane×2=32个量化APM；MAC256+量化32=**288 APM，距≤300余12**。地址增量、D2合并、INT32累加、残差和饱和使用普通加法/比较推断进位链，不分配APM；非卷积执行器无乘法。IP生成若把两个小乘法另拆出APM，应在N-IP1记录实际映射并重新核算；本文288是固定配置估算，不是新PDS报告。旧289仅作可实现性参照。

### 4.7 第 7 项：权重镜像格式（开发初值）

#### 4.7.1 共同长度和装载映射

令 `J=K3?9:1`、`C=CIN_BLOCKS`、`B=COUT_BLOCKS`：

```
K_COUNT = IN_C4 ? J : 2*C*J
WEIGHT_BLOCK_BYTES = 256*K_COUNT
D2(b) = HALF_TAIL && b==B-1 && !IN_C4
K_eff(b) = D2(b) ? K_COUNT/2 : K_COUNT
实际块字节(b) = 256*K_eff(b)
块b在DDR/常驻池的起点 = b*WEIGHT_BLOCK_BYTES
整层实际镜像长度 = (B-1)*WEIGHT_BLOCK_BYTES + 实际块字节(B-1)
```

末尾只有一个紧缩块，故后续块起点公式不受紧缩影响。块首/每拍均256B对齐；每个256B的K行包含8个32B beat。顺序DMA不重排字节：相对DDR beat号m写 `weight_wr_addr=m`，bank=`m&7`、bank内行=`m>>3`。权重读地址r在同拍读8bank，重新拼回256B。常驻池按层重新从0写，W3直接将尚未开算块写到其最终槽位，不另加W3权重池。

容量检查仍严格按规格第6节的上界 `B*WEIGHT_BLOCK_BYTES<=294912`，**不因尾块紧缩放宽检查**。离线镜像可比该上界小；最大L7无半块，C=8/J=9/K=144/B=8，`8×144×256=294912`，每bank有效深1152。

每字节是INT8二进制补码；“低位在前”指beat最低字节对应DDR最低地址。权重不使用多字节整数字段，不存在额外字节交换。

#### 4.7.2 普通 C32 块

完整嵌套顺序为 `[b][ky][kx][c16][h][physical_oc][k8]`，physical_oc=0..31、k8=0..7、h=0/1，等价为旧 `[bank][oc_in_bank][k8]`（bank=physical_oc/4）。

```
r = (((ky*kernel+kx)*C+c16)*2+h)
j = 8*physical_oc+k8                 # K行内字节0..255
image[b*WEIGHT_BLOCK_BYTES + 256*r + j]
  = W[32*b+physical_oc, 16*c16+8*h+k8, ky, kx]
```

无效逻辑输出通道/输入补齐通道的权重为0，合法输出的真实权重不填充到别的核位置。

#### 4.7.3 非 C4 的 HALF_TAIL 块

最后块只有逻辑输出c=0..15，物理通道前半对应低C8、后半对应高C8：顺序 `[ky][kx][c16][h][logical_oc16][k8]`。注意h成为K行内部维度，不再增加r。

```
r = (ky*kernel+kx)*C+c16
physical_oc = 16*h+c                 # c=0..15
j = 8*physical_oc+k8
image[b*WEIGHT_BLOCK_BYTES + 256*r+j]
  = W[32*b+c, 16*c16+8*h+k8, ky, kx]
```

每K行仍256B，归约拍数和实际块字节均为普通块一半；读出的2048bit直接喂物理阵列，无运行时权重转置。物理c和c+16的积在R4合并成同一个逻辑输出。对Cout80，b0/b1普通，b2紧缩，首字节偏移仍是2×WEIGHT_BLOCK_BYTES。

#### 4.7.4 IN_C4 首层（3×3×4）

顺序为 `[b][ky][kx][physical_oc32][k8]`，K_COUNT=9，每核位置一行256B。k8=0..3对应输入C4（R、G、B、0），k8=4..7的权重0；第4输入固定0，其权重也写0。首层Cout16时，物理oc16..31的权重为0。

```
r = ky*3+kx
image[b*WEIGHT_BLOCK_BYTES + 256*r+8*physical_oc+k8]
  = W[32*b+physical_oc, k8, ky, kx]   # k8<4，否则0
```

**IN_C4=1、HALF_TAIL=1允许同时置位**：HALF_TAIL仍使最后块只写一个C16平面，但不触发D2、不再把9除以2，首层实际块大小2304B。IN_C4=0的HALF_TAIL才按4.7.3折叠。首层描述符为IN_C4=1、HALF_TAIL=1、COUT_BLOCKS=1；硬件译码组合，不检查或写死网络Cout。多个首层输出块按同一格式各自处理。

#### 4.7.5 小例子和参数格式差异

普通Cout32/Cin16/3×3：K_COUNT=18、WEIGHT_BLOCK_BYTES=4608，8个bank读地址0..17。下表偏移相对WEIGHT_OFFSET：

| DDR字节偏移 | 对应W(cout,cin,ky,kx) / 说明 |
|---|---|
| 0..7 | (0,0..7,0,0) |
| 8..15 | (1,0..7,0,0) |
| 16..23 / 24..31 | (2,0..7,0,0) / (3,0..7,0,0)，首beat即bank0 |
| 32..39 / 40..47 | (4,0..7,0,0) / (5,0..7,0,0)，第二beat即bank1 |
| 248..255 | (31,0..7,0,0)，bank7末段 |
| 256..263 / 264..271 | (0,8..15,0,0) / (1,8..15,0,0)，下一K行回bank0 |
| 512..519 | (0,0..7,0,1) |
| 1536..1543 | (0,0..7,1,0) |
| 4600..4607 | (31,8..15,2,2)，整块末字节 |

相同Cin16、Cout16的D2块只有9行/2304B：0..7仍W(0,0..7,0,0)，120..127为W(15,0..7,0,0)，128..135改为W(0,8..15,0,0)，256..263已是W(0,0..7,0,1)。C4首层的0..3为W(0,0..3,0,0)、4..7为0、8..11为W(1,0..3,0,0)，256..259为W(0,0..3,0,1)。

量化512B记录严格用新规格4.2：8B little-endian项为bias[31:0]、mult[47:32]、shift[53:48]、[63:54]=0；后256B是激活表。**旧脚本每通道项的第7字节为zero_point，新格式此字节必须为0，zp来自描述符**；N-M1不能直接复制旧struct.pack格式。记录每输出块仍512B，HALF_TAIL无效高16通道参数写0，IN_C4同样；LUT_EN=0不要求装载LUT，无意义内容不得参与结果。N-M2应独立实现上面三种权重解码，不能把普通块的reshape套在D2尾块。

### 4.8 第 8 项：发射信用与不阻塞流水

计数单位是**一个两像素输出pair**，不是归约项，也不是DDR beat：

```
free = 32 - reserved_or_completed_or_dma_owned_pairs
pair_fire => free -= 1
result_release => free += granted_chunk_pairs
WB2完成 => free不变                   # 从预留变成完成，不是释放
```

同拍分配/释放按加减净值更新，计数宽6位。pair_fire同时分配结果slot和（RES_EN时）残差地址。信用是在**first项之前**占有；不能到last项才检查，因为写DMA反压时已发出的pair一定会完成。`result_credit_o`直接来自寄存计数；释放信用下一拍可用，不把AXI READY组合回A1。

pair发射条件为：已取得当前命令、issue_enable、该命令输入/权重/参数所有权已满足、free>0、量化占用日历可容纳、且RES_EN时残差头pair已commit。前述行/权重ready由N-C1提交cmd保证，数据通路只实现结果计数/残差队列/量化时序所需的控制，不增加“装载完整”检测位图。

一个pair已首发后，K_eff个项连发；MAC/R/ACC/Q/WB中的valid只移位，不因free变零或WREADY/BREADY停顿。Q0按G组连续运行，residual已预留且Q10提前读完，WB2目的slot已经占有，所以没有内部ready链。结果环满时只延迟新的pair首项，已有流水最后仍能写入自己的slot。写DMA可以无限期反压，输出RAM及头描述符保持；恢复后按原顺序读/释放再发射。

描述符尾部条件：所有cmd已发、最后WB2完成、结果chunk都已交给DMA、全部读/写事务已完成且最后B返回，才允许下一描述符依赖读/报告DONE。datapath idle只涵盖本地部分，不能替代N-C1的B计数。ABORT/AXI错误则停止新事务，cancel本地有效控制，已发AXI由N-C1收完；被中止输出未定义，不做回滚/补写。

### 4.9 第 9 项：N-IP1 清单

以下为创建说明的输入，N-IP1仍须填供应商实际生成端口名并做包装。所有RAM独立读写时钟都连clk_npu，固定配置，不参数化。RAM内容无初始化/无复位，若IP强制带复位接无效；读使能关时输出保持；Read First；**全部关闭字节写使能**，每次写都是完整逻辑word（参数reserved位补0、C4由unpack展开）。采用SDP即可，不需TDP或额外读口。

| 建议IP / tech包装 | 类型 / 固定宽深 / 个数 | 读延迟、输出寄存、写使能 | DRM/APM、使用者 |
|---|---|---|---|
| `ip_ram_npu_line` / `edrv32_ram_npu_line` | DRM SDP，1024×256，2实例 | 2级，开输出寄存，单word WE；底层8×1024×32 | 16 DRM；line_cache |
| `ip_ram_npu_weight` / `edrv32_ram_npu_weight` | DRM SDP，512×256，24实例（8bank×3段） | 2级，开输出寄存，单word WE；底层4×512×64 | 96 DRM；weight_store；段号延迟和复用器在包装外固定逻辑 |
| `ip_ram_npu_quant` / `edrv32_ram_npu_quant` | DRM SDP，512×64，8实例，业务只用地址0..31 | 2级，开输出寄存，单word WE | 8 DRM；quant_param_store |
| `ip_ram_npu_lut` / `edrv32_ram_npu_lut` | DRM SDP，4096×8，16实例，业务只用0..2047 | 2级，开输出寄存，单word WE | 16 DRM；activation_lut |
| `ip_ram_npu_residual` / `edrv32_ram_npu_residual` | DRM SDP，512×256，1实例，业务只用0..31 | 2级，开输出寄存，单word WE | 4 DRM；residual_buffer |
| `ip_ram_npu_result` / `edrv32_ram_npu_result` | DRM SDP，512×512，1实例，业务只用0..31 | 2级，开输出寄存，单word WE | 8 DRM；writeback |
| `ip_ram_npu_scratch` / `edrv32_ram_npu_scratch` | DRM SDP，512×256，2实例 | 1级，关闭输出寄存，单word WE | 8 DRM；N-C1 POOL平面、POOL/UP共用行暂存 |
| `ip_mul_npu_int8_pair` / `edrv32_mul_npu_int8_pair` | APM原生SIMD，独立两路8×8，256实例 | X/Y寄存+MULT_REG，两级；P_REG=0；CE恒1，复位无效 | 256 APM；mac_array；4.6列出了原语模式/打包全部常量 |
| `ip_mul_npu_quant_low` / `edrv32_mul_npu_quant_low` | 有符号18×16，输出34位，16实例（lo补0） | 输入寄存+MULT_REG，两级，P_REG=0；CE恒1、复位无效 | 16 APM；result_quant |
| `ip_mul_npu_quant_high` / `edrv32_mul_npu_quant_high` | 有符号16×16，输出32位，16实例 | 同上 | 16 APM；result_quant |

RAM包装端口统一为 `clk_i, wr_en_i, wr_addr_i, wr_data_i, rd_en_i, rd_addr_i, rd_data_o`；地址位宽分别10/9/9/12/9/9/9，数据宽按表。业务逻辑负责把逻辑地址零扩到包装地址，不截断非法输入以“兜底”。APM pair包装端口 `clk_i,a0_i[7:0],b0_i[7:0],a1_i[7:0],b1_i[7:0],p0_o[15:0],p1_o[15:0]`；量化包装为 `clk_i,operand_a_i,operand_b_i,product_o`，宽度见表。不暴露动态CE或数据复位。

若IP Compiler没有独立两路SIMD GUI入口，N-IP1应在固定tech包装中沿用已验证的GTP_APM_E2配置，创建说明完整列出该原语参数和端口，并由协调者确认供应商模型；不得改成普通宽乘法。这里只要求所需的现有双乘法能力，不扩展另一种打包模式。

新建行为模型需与FPGA分支同延迟/读使能/同址旧数据语义；RAM输出寄存和深度段选择、SIMD符号扩展、量化部分积在Windows ModelSim核对。纯RAM不带业务rst/cancel。N-C0异步FIFO与N-C1总线缓冲IP不在此清单的已分配156中，需消耗剩余预算并独立列明。

## 5. 影响

### 5.1 第 10 项：规格不一致或未写清事项

**本任务不改规格。以下共8项，均交协调者评审；只列问题和建议，不引入额外硬件检查。**

| # / 条款 | 问题 | 建议修改或后续处理 |
|---|---|---|
| 1 / 4.1 HALF_TAIL、5.1首层/半块 | 未定义IN_C4与HALF_TAIL同时为1时是否再将K减半，首层输出16通道又需单平面 | 写明half控制有效输出/写平面数，D2=`half&&!IN_C4`；首层K=9不减半。协调者ask已确认该开发初值，前一条禁止组合的答复已被明确撤销 |
| 2 / 4.1 K_COUNT、WEIGHT_BLOCK_BYTES，4.2和2.5 | 普通K、紧缩尾块长度/偏移、C4权重顺序未定；2.5称布局见5.3，但5.3实际为非卷积 | 按4.7定义普通跨度、D2紧缩尾块和C4格式；容量检查仍用普通跨度上界。修正2.5引用到权重格式段/工具格式说明；协调者初步认可，整体格式仍须用户确认 |
| 3 / 2.2与SoC7.3 | NPU仅写输入宽4倍数，但C4行跨距IN_W×4与Surface32B stride共同要求8倍宽 | 2.2补IN_C4时IN_W为8倍数，工具保证；硬件不新增检查、半beat行首处理。协调者ask已确认 |
| 4 / 5.2、4.1 ROW_SLOT_BEATS | 名称容易误作整行DDR beat数，实际为每bank项数；C4缓存展开未写 | 补每bank语义及C4规范化说明，保持原公式和五/二槽约束；4.4证明匹配，不要求扩容 |
| 5 / 2.3、5.4量化 | 算术公式未明示acc+bias及乘积中间位宽；APM规格只明确MAC256个 | 补33位偏置和、49位乘积/舍入、50位加zp和16lane×2量化APM；允许负mult；以4.6为开发初值，对齐旧参考的全精度语义 |
| 6 / 5.4、9待定2、7性能 | 推荐级表/N-E2每行14/15拍与细化29/27拍不同；层内排空会反复暴露尾部 | 记录并确认4.3的开发初值，命令可提前排队，层内不因命令切换排空；后续模型用实装延迟/信用和实际C4字节重算，不声称20.97fps已保证；敏感性数值和C4展开影响见4.3/4.4 |
| 7 / 5.2、7/9待定3/6 | 新数据通路参数改用8个DRM，完整新NPU的DMA/CDC尚未逐项映射，旧155不能直接沿用 | 记录CONV148、含串行非卷积已分配156，N-C0/N-C1必须给剩余14块的实际映射再判断完整NPU≤170；不先改预算，不把旧PDS总数当作新实测 |
| 8 / 5.1常驻/W3、5.4接口 | “本层开始时全部装入”与“第一行重叠”缺少逐块ready/所有权时点；内部接口尚未在规格冻结 | 补块0完备即可算第一行，其余块写最终槽位，使用某块前保证其参数/权重/LUT已写完；采用4.2接口与读完成回收时点，协调者确认后冻结供并行开发；不增加装载完整位图或接收端检查 |

### 5.2 第 11 项：N-D1 并行拆分建议

这些是对后续任务的建议，不增改现有验证方案条目；各worker单元自检覆盖相应OP/TL/CP/SQ/ER条款，独立模块级验证仍按N-T1执行。共享include/filelist/tech/IP由协调者维护。

| 建议子任务 / 文件归属 | 模块和可独立完成内容 | 单元验证内容（对应现有验证项） | 依赖 |
|---|---|---|---|
| D1-A 输入/窗口 | input_unpack、line_cache、window；2上下文和地址/局部复制 | OP-01..04/07：S1/S2、1×1/3×3、首末边、非2幂宽、D2两C8、C4连续8像素；逐项检查bank/addr/权重行和tag；CP-02五/二槽边界；跨pair/块/行无chunk填充 | 冻结4.2/4.4；N-IP1行/权重RAM模型；权重读可由测试驱动 |
| D1-B 常驻存储 | weight_store、quant_param_store、activation_lut | TL-03/OP-05/CP-01/03：顺序DMA写后读出普通/尾块/C4；L7有效1152行和512/1024段界；8块不同参数/表；16独立LUT地址；读使能和两级延迟；装载不同块与读取重叠 | 冻结镜像4.7、N-IP1 RAM包装；可与A/C/D并行 |
| D1-C MAC/累加 | mac_array、accum，接固定APM包装 | OP-01/02/07/08：−128/127有符号积、8路归约、D2合并、first替换/last输出、空valid拍、连续不同块tag；每拍1项、无CE背压；prepare比最终向量早一拍 | 冻结tag/位序；N-IP1 SIMD模型；与A/B/D并行 |
| D1-D 量化 | result_quant（不修改B的参数/LUT存储） | TL-01/OP-05/08：bias/acc极值、mult负/零、shift0/47、舍入与饱和、LUT四边界、旁路等延迟；G4→G2→G4切换、参数提前读/tag对齐、普通4拍/half2拍持续吞吐 | N-IP1量化APM；B存储接口可先由测试按契约供数；与A/C/E并行 |
| D1-E 残差/写回 | residual_buffer、residual_add、writeback，含结果信用计数 | OP-06/07、SQ-01、ER-05相关本地行为：双半区散写commit、单/双平面、正负饱和、结果环绕、尾chunk、长DMA反压、全部在途仍写入已预留槽；release后信用正确；cancel清控制 | 冻结4.2/4.8；N-IP1结果/残差RAM；可用测试直接注入量化结果 |
| D1-F 集成 | datapath子顶层、跨模块对齐和数据通路单元测试 | OP组合小层与独立参考逐位一致；精确29/27拍尾部、连续命令跨行不等待WB；C4末拍row_done/行ready、量化日历、W3装载重叠、写DMA停顿后恢复；运行既有单元smoke | A–E、N-M2小用例；协调者处理共享文件；完成后单独PDS任务再接N-C1 |

N-M1消费4.7和新量化记录格式，N-M2独立解码权重并按规格公式计算；两者不等待MAC RTL。N-C1消费4.2接口，负责所有DDR偏移、行槽所有权/预取、残差批次和结果chunk DMA；不得再做一份16pair×双平面写RAM。N-IP1消费4.9固定配置，先用行为模型支撑并行开发，供应商IP在Windows生成和核对。

### 5.3 可复现检查和后续测量

本记录的模型输入为表头commit，旧测量来源/条件在4.5及N-E1/N-E2原文，未新增测量报告。本文4.3内嵌命令可复现尾部敏感性，4.4/4.5/4.6/4.7给出其余公式与输入；没有生成哈希或额外签收文件。

本任务提交前运行 `git diff --check`；仅Markdown变更，Verilog风格扫描 `python3 tools/check/verilog_style.py docs/design` 为0个RTL文件、0告警，RTL lint/仿真/PDS不适用。N-D1应按现有验证方案运行真实单元检查并以PDS确认每级布线/资源，不把本文LUT级数估计当作时序通过。

## 6. 状态

**已决定（2026-10-27）。** 第 10 项 8 处由用户确认，写入 NPU 规格 v0.2；以下为评审时的原始状态说明。已形成供协调者评审的完整接口、映射和格式开发初值；第10项8处规格补充、整体权重格式和N-IP1供应商配置由协调者确认，完整NPU的DMA/CDC资源及PDS时序尚待后续任务。本文未修改规格、实施方案、验证方案或任何RTL/工具/legacy文件。
