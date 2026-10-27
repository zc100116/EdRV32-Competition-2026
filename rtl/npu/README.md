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
`DESC_COUNT=0` 的门铃直接完成空列表，CUR_DESC 按 COUNT−1 回绕为 0xFFFF_FFFF。
非空列表门铃将 CUR_DESC 置 0；正常完成/出错后保持最后序号。

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
未完成全部平面的 chunk 不发正常 result_release，保持借用直到 cancel。
被中止输出未定义，DONE_COUNT 不增加。没有超时、看门狗或额外错误检查。

IDLE SOFT_RST 将全部架构寄存器及内部控制恢复硬复位值，数据 RAM 不复位；
BUSY 写 SOFT_RST 忽略。这是协调者在 N-C1 ask 中确认的开发初值，待其补入规格。
PERF[0..7] 分别计 busy 总周期、MAC 拍、R 拍、W 拍、行准备等待、块装载等待、
存在未回 B 的周期、非卷积执行周期；门铃清零，[8..15] 保持 0。
4/5 统计下一条待提交命令的就绪等待，6 统计本地未回 B 的 burst 占有；
这些事件可以与计算及彼此重叠，不是总周期的互斥分解。

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

2026-10-27，RTL 和全部测试来源 commit **`df7751f`**；以下为该版本的 Linux
仿真结果。工具为 Verilator 5.020（Debian 5.020-1），SIM_MODE；构建 `-j 1`，
每次只运行一个本任务的仿真进程。Python 使用环境指南第 6 节的虚拟环境，
ultralytics 使用仓库子模块。所有生成物都在 `build/`，未入库。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/npu
verilator --lint-only -Wall +define+SIM_MODE -Irtl/include \
    --top-module edrv32_npu -F rtl/filelists/npu.f
verilator --xml-only -Wall +define+SIM_MODE -Irtl/include \
    --top-module edrv32_npu -F rtl/filelists/npu.f \
    --xml-output build/npu_ctrl/npu.xml
```

风格扫描 **21 个 RTL 文件、0 告警**；完整顶层 lint **0 告警**。
XML 层次中 RAM 包装为 line×2、weight×24、quant×8、LUT×16、residual×1、
result×1、scratch×2；乘法包装为 int8_pair×256、quant_low×16、quant_high×16，
对应前表 156 DRM 和 288 个显式 APM。日志为 `build/npu_ctrl/style.log`、
`build/npu_ctrl/lint.log`，层次为 `build/npu_ctrl/npu.xml`。

### 单元回归

下表每行的实际命令为
`make smoke REGRESS_ARGS='-j 1 --path verif/unit/<目录>'`；汇总日志
`build/npu_ctrl/all_units_final.log`，每项目日志位于
`build/regress/smoke/unit/<目录>/`。**22 个目录、27 个回归结果全部 PASS**。

| 新模块目录 | 结果 | 自检内容 |
|---|---|---|
| `npu_regs` | PASS | 复位、ID、RW/RO、忽略 pstrb、未定义偏移、触发位、忙时门铃/软复位、IRQ、PERF |
| `npu_descriptor` | PASS | 两 beat 字段、四基址选择、OP 3/15、三项容量的合法/超限边界、忽略非 CONV 派生字段 |
| `npu_read_dma` | PASS | 四在途、tag/index、16/1/3 beat、R 反压、错误、AR 未就绪时中止与恢复 |
| `npu_write_dma` | PASS | WSTRB、AW/W 保持、八个 B credit、行间不等 B、错误、中止完整 W/B 与恢复 |
| `npu_conv` | PASS | 四个独立参考用例：K3/Cin48/Cout80/LUT/RES、C4 半块、K1 S2、D2 残差；非零偏移、宽松跨距、512 B/4 KiB 边界 |
| `npu_conv_write` | PASS | 环项回绕、两平面/半块、跨命令行/块地址、短 burst、长 W 反压、部分 chunk 中止只用 cancel 回收 |
| `npu_nonconv` | PASS | POOL 20×12×48；UPSAMPLE 宽 2/40、多平面；逐拍检查两 scratch 同址读写为 0 |
| `npu_top` | PASS | 两次空列表、ENABLE=0 门铃、CUR_DESC=COUNT−1、无 AXI 请求、软复位；另运行独立 NB RG-02 三描述符 |

算子期望值均由 `gen_case.py --config` 与独立 `npu_ref.py` 生成。
单层用例还独立按几何求和检查 DDR 拍数：CONV 的 R/W 分别为
1464/210、126/20、224/400、336/160，非卷积为 360/360、3/12、160/640。
这覆盖输入行跨输出块复用、1×1 S2 跳行、C4 不扩充 DDR 输入、紧缩尾权重及残差平面数。

| 原有目录（未修改） | 回归结果 |
|---|---|
| `npu_accum` | 1 PASS |
| `npu_activation_lut` | Verilator / Icarus，2 PASS |
| `npu_axi256_mem` | zero / latency / bw，3 PASS |
| `npu_datapath` | 1 PASS |
| `npu_input_unpack` | 1 PASS |
| `npu_line_cache` | 1 PASS |
| `npu_mac_array` | 1 PASS |
| `npu_quant_param_store` | Verilator / Icarus，2 PASS |
| `npu_residual_add` | 1 PASS |
| `npu_residual_buffer` | 1 PASS |
| `npu_result_quant` | 1 PASS |
| `npu_weight_store` | Verilator / Icarus，2 PASS |
| `npu_window` | 1 PASS |
| `npu_writeback` | 1 PASS |

### NB 逐项结果

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/npu'
make full REGRESS_ARGS='-j 1 --path verif/block/npu'
python3 tools/regress.py perf -j 1 --path verif/block/npu/net_02
```

smoke **24 PASS / 0 FAIL**；full **30 PASS / 0 FAIL**；NET-02 perf
**1 PASS / 0 FAIL**（包含三个整网时序档）。full 含全部 smoke 和环境 selftest；
下面为全部 30 项 NB 与额外的 selftest，均无未解决失败。
汇总日志为 `build/npu_ctrl/nb_smoke_final.log`、`nb_full_final.log`、
`nb_perf_final.log`；单项日志位于 `build/regress/<档位>/block/npu/<目录>/verilator/run.log`。
单项重跑使用上面命令的对应档位并将 `--path` 改为表中目录；perf 使用 Python 入口。

| 项目 | 目录（`verif/block/npu/` 下） | 档位 | 变体数 | 结果 |
|---|---|---|---:|---|
| RG-01 | `rg_01` | smoke | 1 | PASS |
| RG-02 | `rg_02` | smoke | 1 | PASS |
| RG-03 | `rg_03` | full | 1 | PASS |
| RG-04 | `rg_04` | smoke | 1 | PASS |
| OP-01 | `op_01` | smoke | 9 | PASS |
| OP-02 | `op_02` | smoke | 3 | PASS |
| OP-03 | `op_03` | smoke | 4 | PASS |
| OP-04 | `op_04` | smoke | 8 | PASS |
| OP-05 | `op_05` | smoke | 2 | PASS |
| OP-06 | `op_06` | smoke | 2 | PASS |
| OP-07 | `op_07` | smoke | 2 | PASS |
| OP-08 | `op_08` | smoke | 12 | PASS |
| OP-09 | `op_09` | smoke | 2 | PASS |
| OP-10 | `op_10` | smoke | 20 | PASS |
| OP-11 | `op_11` | smoke | 5 | PASS |
| OP-12 | `op_12` | full | 20 | PASS |
| CP-01 | `cp_01` | full | 1 | PASS |
| CP-02 | `cp_02` | full | 3 | PASS |
| CP-03 | `cp_03` | smoke | 1 | PASS |
| SQ-01 | `sq_01` | smoke | 1 | PASS |
| SQ-02 | `sq_02` | smoke | 1 | PASS |
| SQ-03 | `sq_03` | full | 3 | PASS |
| ER-01 | `er_01` | smoke | 1 | PASS |
| ER-02 | `er_02` | smoke | 1 | PASS |
| ER-03 | `er_03` | smoke | 2 | PASS |
| ER-04 | `er_04` | smoke | 8 | PASS |
| ER-05 | `er_05` | smoke | 3 | PASS |
| NET-01 | `net_01` | full | 1 | PASS |
| NET-02 | `net_02` | perf | 3 | PASS |
| NET-03 | `net_03` | smoke | 6 | PASS |
| selftest | `selftest` | smoke | 1 | PASS |

selftest 包含正常比对和故意损坏一个输出字节后必须失败的负例。
RG-03/04 均包含两帧；ER-01/02/05 在错误/中止后还检查重新启动。
CP-02 包含 3×3 的 1020 项、1×1 的 1024 项和 L15.split；
SQ-03 包含 150/125、125/125、100/125 三种 NPU/mem 时钟比。

### 整网周期与流量

NET-01/02 使用 COCO128 图像 `000000000009.jpg` 的真实量化模型：
68 条描述符（63 CONV、3 POOL、2 UPSAMPLE，6 次残差融合），每档检测头
725,760 字节与独立参考逐字节一致。名义 clk_npu=150 MHz、clk_mem=125 MHz；
zero 首拍延迟 1，latency/bw 首拍延迟 94；B 延迟 1，存储模型在途上限 8。
带宽档为读写共享 1400 MB/s；另两档每 mem 周期最多一拍（4 GB/s）。

| 存储档 | RTL PERF0 周期 | 150 MHz 折算 fps | 旧阶段模型周期 | 偏差 |
|---|---:|---:|---:|---:|
| zero | 6,008,683 | 24.9639 | 6,116,162 | -1.76% |
| latency | 6,249,662 | 24.0013 | 6,576,005 | -4.96% |
| bw | 6,938,488 | 21.6185 | 7,154,008 | -3.01% |

三档每帧读 **512,472 beat**、写 **309,000 beat**，合计 **26,287,104 B**
（26.287104 MB，小于 27 MB）；按描述符几何独立求和也得到相同的 R/W 拍数。
在规定的 1.4 GB/s 条件下，RTL 周期折算 **21.6185 fps**，达到 ≥20 fps 的仿真目标。
这是 RTL 周期结果，完整顶层实际工作频率仍由 PDS 确认。

`build/npu/net_02_perf.csv` 保存三档全部 PERF、R/W 拍数、mem 周期、旧模型值与偏差；
逐档原始日志为 `build/npu/yolo/run_0.log`、`run_1.log`、`run_2.log`。
模型比较沿用 NB 运行器中的 `tools/npu/eval/datapath_model.py` 旧阶段模型口径，
后续模型常数/基线的统一由协调者处理，本任务未修改离线工具或模型。

| PERF | zero | latency | bw |
|---|---:|---:|---:|
| 0 | 6,008,683 | 6,249,662 | 6,938,488 |
| 1 | 5,347,440 | 5,347,440 | 5,347,440 |
| 2 | 512,472 | 512,472 | 512,472 |
| 3 | 309,000 | 309,000 | 309,000 |
| 4 | 1,363,305 | 1,588,410 | 2,115,345 |
| 5 | 206,705 | 380,739 | 520,842 |
| 6 | 738,460 | 738,424 | 2,008,942 |
| 7 | 538,435 | 585,440 | 601,045 |

PERF[8..15] 在三档中均为 0。

### 提出的 ask、修订来源与后续事项

1. **IDLE SOFT_RST 的范围**：协调者确认所有架构寄存器恢复硬复位值，内部控制取消，
   数据 RAM 不复位，BUSY 忽略。RTL/单元测试按此初值实现；待协调者补入 NPU 规格第 4 节。
2. **NB SYNCASYNCNET**：真实 DUT 异步复位与 TB 周期计数同步采样复位触发两条告警。
   协调者提交 `3d7df34`，本分支为 `1f34fd2`，仅在 NB testbench 的 lint.vlt 豁免。
   RTL lint 始终没有该豁免。
3. **RG-03 PERF0 窗口反向**：实测 W=8994、PERF0=8997；NPU 接受门铃早于源侧
   APB 写完成，原 W−16..W 上界错误。协调者提交 `7d90483`（本分支 `40bd80f`），
   同步修订验证方案和 TB 为 W−16..W+16。RTL 没有加入延迟或计数门禁，复跑 PASS。
4. **CP-02/L15_split 覆盖输入**：初始输入区 [0x01000000,0x010b4000) 与输出区
   [0x01020000,0x0105c000) 重叠，写行 0 覆盖尚未预取的输入行 6，首差异在
   0x01022002。协调者确认测试错误，提交 `370e67c`（本分支 `c949a24`），将输出
   偏移改为 0x200000；容量边界三用例全部 PASS。NPU 不支持原地计算，输入/残差源
   与输出不重叠由软件/工具保证，待协调者补入规格 2.4；RTL 未添加地址重叠检查。

首次 NET-03 的环境失败是本 worktree 未初始化 ultralytics，执行
`git submodule update --init third_party/ultralytics` 后恢复，最终六个真实代表层全部 PASS。
除上述协调者提供的验证修订外，未修改共享验证文件；原数据通路及其 12 个子模块均未修改。

协调者后续需要把两项开发初值写入规格并请用户确认，安排完整 `edrv32_npu` 的
Windows PDS 资源/150 MHz 时序测量，再统一性能模型基线。当前没有未解决 RTL 或回归失败。
