# CPU v2 IP 规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1-draft |
| 日期 | 2026-11-27 |
| 状态 | 草案，供协调者审核；未冻结，不作为现有 SoC 的替换授权 |
| 范围 | 独立可移植 CPU v2 IP：整数核、L1 I$/D$ 及控制器、可选 FPU 集成 |
| 关联文档 | 本目录 fpu-spec.md、cpu-v2-testplan.md、fpu-testplan.md、cpu-v2-plan.md；docs/design/2026-11-27-cpu-v2-architecture.md 第四轮；docs/design/2026-11-27-cpu-v2-fpu.md 第二版；docs/spec/edrv32-soc-spec.md |

## 1. 概述

1.1 CPU v2 必须是可移植的独立 IP；在 EdRV32 SoC 中必须工作于 clk_sys，作为控制和通用计算核心，通过两个 AXI64 主口访问系统总线。

1.2 本规格定义新 IP。`docs/spec/cpu-spec.md` v0.23 和 `docs/spec/cache-spec.md` v0.14 继续描述正在使用的旧核，不因本草稿改变。本文明确引用的旧规格仅作为兼容契约，不继承其旧流水实现和时序数字。

1.3 FPU 内部算术和流水必须符合 `fpu-spec.md`；CPU 集成必须符合本文 3.2、4.2、5.6。

## 2. 功能描述

### 2.1 ISA 与配置

必须实现 RV32IM、Zicsr、Zicntr、Zifencei 和 M 态；不实现 C、A、Zbb、PMP、S/U、调试模式、触发器和 NMI。指令必须 4 字节对齐，整数 load/store 必须自然对齐。可启用 Zba，仅包含 RV32 的 SH1ADD/SH2ADD/SH3ADD。

FPU_FORMAT 必须为 NONE、F 或 FD；F/FD 的完整软件可见行为见 fpu-spec 2、4、6。NONE 必须不实现 FP 状态和 FP CSR，F 必须不接受 D 指令。

### 2.2 有意义的可配置参数

下表是草稿拟保留的构建参数；未列出的探索方案不得保留为实现开关。缓存容量、单 LSU、单 MUL、控制指令每组至多一条是固定结构。

| 参数 | 合法值 | 小配置 | 默认 | 满配 |
|---|---|---:|---:|---:|
| ISSUE_WIDTH | 1、2 | 1 | 2 | 2 |
| BP_KIND | GSHARE、TAGE | GSHARE | GSHARE | TAGE |
| GSHARE_ENTRIES | 1024、4096；三主档均4096 | 4096 | 4096 | 4096 |
| BTB_ENTRIES | 64、128、256 | 64 | 128 | 128 |
| RAS_DEPTH | 4、8 | 4 | 4 | 8 |
| TAGE_TABLES | 3、4、5；仅 TAGE 有效 | — | — | 4 |
| TAGE_ENTRIES | 128、256、512、1024；每表相同 | — | — | 512 |
| IB_DEPTH | 4、8、16 | 4 | 4 | 8 |
| IF_DUAL_BANK | 0、1 | 0 | 0 | 1 |
| LATE_EXECUTE | 0、1；1 含两槽晚简单 ALU 及晚条件分支 | 0 | 0 | 1 |
| MUL_DUAL_SLOT | 0、1；共享一套 MUL | 0 | 0 | 1 |
| JALR_DUAL_SLOT | 0、1 | 0 | 0 | 1 |
| DIV_IMPL | RADIX2_EARLY、RADIX4_EARLY | RADIX2_EARLY | RADIX2_EARLY | RADIX4_EARLY |
| HPM_COUNT | 0、2、8 | 0 | 2 | 8 |
| EXT_ZBA | 0、1 | 0 | 0 | 0 |
| FPU_FORMAT | NONE、F、FD | NONE | NONE | NONE |
| FMA_READ_PORTS | 2、3；仅 F/FD 有效 | — | F 推荐3 **[待定]** | F/FD 可选3 |
| COMPLETION_DEPTH | NONE 固定4；F/FD 为8、16 | 4 | 4；F推荐8 | 4；FD推荐16 |

本 SoC 的板级构建必须为满配档加 FPU_FORMAT=F（FMA_READ_PORTS、COMPLETION_DEPTH 按 F01 定稿，初值3/8），EXT_ZBA=0；其他档位作为IP可选配置交付并参与参数回归。

LATE_EXECUTE、MUL_DUAL_SLOT、JALR_DUAL_SLOT、IF_DUAL_BANK 为 1 时必须 ISSUE_WIDTH=2；参数合法组合的冻结见 C01。RF 端口必须随 ISSUE_WIDTH 派生为 2R1W 或 4R2W，不能独立任意拼接；主档必须使用异步 RAM，双发射采用 F2 owner 预解码 LVT。同步 RF 不纳入本版参数，若选择须另定 D1/D2 规格和性能。

### 2.3 发射与执行能力

必须顺序发射和按序提交，槽0为较老指令。单 LSU 每组至多一个访存，单 MUL 每拍至多接受一条乘法，单组至多一个控制转移。CSR、系统指令、FENCE/FENCE.I 必须单独发射，并等待更老指令达到规定的有序边界。

普通独立整数 ALU、条件分支及 JAL 必须能使用两个整数槽；LSU、DIV、CSR 和系统指令必须使用共享专用路径。MUL_DUAL_SLOT/JALR_DUAL_SLOT 为1时必须能从任一程序槽按年龄选择输入，不增加第二套 MUL 或 JALR 单元。关闭时专用操作只占槽0，槽1可配独立整数 ALU。具体类型配对矩阵见 C01 **[待定]**。

## 3. 接口

### 3.1 IP 外部接口

外部标准总线必须逐信号沿用 SoC 规格 4.1 AXI64、4.3 APB，信号方向以 IP 为准；下表向量表示标准接口各通道，不新增协议字段。AXI 地址32位、数据64位、WSTRB8位、响应2位，其他字段宽度按 SoC 4.1 原表。

| 信号/组 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| clk_i / rst_n_i | in | 1 / 1 | clk_sys | 低有效复位、本域同步释放 |
| irq_meip_i / irq_msip_i / irq_mtip_i | in | 各1 | clk_sys | 已同步 M 外部/软件/定时中断 |
| mtime_i | in | 64 | clk_sys | time/timeh 来源 |
| ic_axi_ar* / ic_axi_r* | out请求/in响应 | AXI64标准 | clk_sys | I$ 只读主口，ID固定0 |
| dc_axi_aw* / dc_axi_w* / dc_axi_b* / dc_axi_ar* / dc_axi_r* | out请求/in响应 | AXI64标准 | clk_sys | D$ 读写主口，ID固定0 |
| apb_* | in请求/out响应 | 地址/数据32，控制按APB | clk_sys | cache APB 从口，系统槽5 |
| cache_irq_o | out | 1 | clk_sys | 写回错误，PLIC源6 |
| debug_o | out | 64 | clk_sys | 位分配 C04 **[待定]**，初值沿旧核可对应字段 |

AXI 可缓存行事务必须为32字节行对齐、INCR、LEN=3、SIZE=3；设备/不可缓存必须按原大小发出单拍事务。外部 AXI64/APB 契约若必须变动，必须先在 C03 单列并由协调者确认。

### 3.2 核内 FPU 逻辑接口

下表定义必须传递的信息和握手，不冻结 RTL 最终拼写；最终逐信号端口见 C05 **[待定]**。时钟域均为 clk_sys，方向以整数后端为准，N=COMPLETION_DEPTH，T=ceil(log2 N)，B=32或64。

| 信号/字段 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| fp_req_valid_o / fp_req_ready_i | out / in | 各1 | 槽0发射接受；等待期间负载保持 |
| fp_req_instr_o / fp_req_tag_o | out | 32 / T | 原指令和共享完成项tag |
| fp_req_src1_o / src2_o / src3_o | out | 各B | 已捕获 FP 源；2R时rs3次拍捕获 |
| fp_req_int_src_o / fp_req_rm_o | out | 32 / 3 | 转换/搬移的整数源、采样舍入模式 |
| fp_resp_valid_i / fp_resp_ready_o | in / out | 各1 | 本地完成结果交付，冲突保留结果 |
| fp_resp_tag_i / data_i / flags_i / int_dest_i | in | T / B / 5 / 1 | tag、原始结果、该指令flags、整数目的域 |
| fp_cancel_valid_o / fp_cancel_tag_o | out | 1 / T | 年龄边界取消年轻项；tag环回语义随C05冻结 |

FP RF 必须独立，f0可写。整数转换/比较必须共用槽0整数写口；槽1保留整数写口。FP load 和 FPU 算术必须竞争单 FP 完成写口；不得增加整数 RF 端口或复制 D$。

### 3.3 核与 L1 内部接口

核与 L1 必须传递请求地址、读写类型、大小、写数据/掩码、完成tag、错误、取消及提交信息；每一级必须依本地 valid/credit 推进。旧 core↔cache 的全局停顿接口不是 v2 端口冻结依据。逐信号定义、双 bank 两行响应和提前查询事务关联见 C05 **[待定]**；初值采用请求/响应 valid-ready 加完成tag，保留提交后设备访问契约。

## 4. 寄存器

### 4.1 整数 CSR

必须继承旧 cpu-spec v0.23 第5节 CSR 的地址、访问规则、复位和 WARL 语义；下表列出完整地址组。CSR 使用地址编号，无 MMIO 偏移。

| 地址 | 名称 | 访问/复位/位域 |
|---|---|---|
| 300 | mstatus | RW；MPP=3，其余0；MIE/MPIE，FP时新增FS/SD见4.2 |
| 301 | misa | WARL只读实际配置，写忽略；MXL=RV32，I/M及启用F/D |
| 304 / 344 | mie / mip | RW / RO，0；MEIE/MTIE/MSIE及MEIP/MTIP/MSIP |
| 305 | mtvec | RW，0；BASE/MODE，MODE=2/3写为0 |
| 320 | mcountinhibit | RW，0；CY、IR、实际HPM使能，其余0 |
| 323–32A | mhpmevent3–10 | 实现数量由HPM_COUNT决定，RW，0，低5位事件编码 |
| 340 / 341 / 342 / 343 | mscratch/mepc/mcause/mtval | RW，0；mepc低2位0，mtval规则见6.1 |
| B00/B80、B02/B82 | mcycle/h、minstret/h | RW，0，64位低/高32；minstret每拍加0..ISSUE_WIDTH |
| B03–B0A/B83–B8A | mhpmcounter3–10/h | RW，0，HPM_COUNT个64位计数器 |
| C00/C80、C01/C81、C02/C82 | cycle/h、time/h、instret/h | RO别名；time来自mtime_i |
| C03–C0A/C83–C8A | hpmcounter3–10/h | 已实现HPM的RO别名 |
| F11–F14 | mvendorid/marchid/mimpid/mhartid | RO，0 |

HPM_COUNT=2必须实现3、4，=8必须实现3–10，=0必须不实现HPM CSR。不存在CSR或写RO CSR必须非法指令，misa写忽略例外。计数器软件写与自动增加同拍必须软件写优先。HPM事件1–16必须沿旧 cpu-spec 7.1编码，事件延迟一拍，配对失败优先级5>6>7>8；局部等待对应事件10等语义澄清见 C04 **[待定]**。

### 4.2 相对旧核的软件可见差异

| 差异 | v2 规定 |
|---|---|
| Zba | EXT_ZBA=1支持三个RV32 shift-add；0时非法 |
| F/D | 按配置增加misa位、FP寄存器和001/002/003 CSR，见fpu-spec |
| mstatus | 含FP时增加FS[14:13]及SD[31]；复位和Dirty细则见fpu-spec待定项 |
| HPM裁剪 | 未配置的HPM CSR非法；cycle/instret/time必须保留 |
| 精确异常/中断实现位置 | 从旧M级改为完成队列提交边界；异常码、优先年龄、mepc/mtval和M态入/返陷阱语义必须一致 |

### 4.3 cache APB 寄存器

必须沿用 cache-spec v0.14 第4节，无新增寄存器。

| 偏移 | 名称 | 访问 | 复位 | 位域/行为 |
|---|---|---|---|---|
| 000 | ID | RO | 00050001 | 类型5、版本1 |
| 008 | STATUS | RO | 0 | bit0 BUSY |
| 00C | IRQ_EN | RW | 0 | bit1写回错误使能 |
| 010 | IRQ_STAT | RW1C | 0 | bit1错误，新错误优先于同拍清除 |
| 014 | ERR_ADDR | RO | 0 | 最近写回错误行地址 |
| 020 / 024 | OP_ADDR / OP_SIZE | RW | 0 | 范围起始地址/字节数 |
| 028 | OP_CMD | WO | — | 1 clean、2 invalidate、3 clean+invalidate、4全D$ clean；其他值/BUSY写无效 |

未列偏移必须读0、写无效。

## 5. 行为与时序

### 5.1 流水、信用与提交

逻辑流水必须为 IF/ID/EX/MEM/WB；IF必须包含同步 RAM 取指的F1请求/F2响应物理边界。WB必须包含完成捕获和按序提交，不沿用旧W2全局停顿结构。

| 级 | 必须完成的工作 |
|---|---|
| IF | PC、BTB/快速方向、同步I$和可选TAGE F2、IB写入 |
| ID | 固定双头译码、RF/记分牌、配对、合格load提前地址 |
| EX | 早ALU、AGU、早分支/JALR、MUL入口、长单元发射 |
| MEM | 普通load返回捕获、晚简单ALU/晚条件分支、本地异常收集 |
| WB | 完成记录和转发捕获、按序写RF/flags及store提交 |

各级必须使用局部 valid/credit，无全局停顿。ID必须只使用已登记容量发射；D$ hit/miss必须本地产生，不能组合穿透到ID/RF/IF。最老指令不就绪时必须阻止年轻越序发射；完成队列满必须反压新发射；已完成结果和前端可依各自容量推进。长操作必须用目的记分牌，不得冻结整核。

NONE必须使用4项独立FF完成记录。含FP必须使用8/16项全核共享顺序完成队列，替换原4项；数据用LUTRAM、控制用FF。每拍最多提交ISSUE_WIDTH条、最多一个FP目的；store/设备副作用只能在最老且不可撤销时发生。冲刷必须按年龄取消年轻结果、flags和store。

控制根应按区域注册复制，根扇出目标≤8、局部叶≤16，数据保持使能按不超过16位分区；数值为实现预算 **[待定]**，最终按PDS定稿。

### 5.2 RF、提前地址与延迟

双发射RF必须为两个写owner bank×四个32×32读副本，共8192数据bit；31位FF LVT记录x1..x31 owner，x0硬零。同址双写必须年轻写生效，WB必须显式转发，不依赖RAM同址读写模式。

F2必须在物理取指bank后并行查询LVT，IB每指令必须保存两份候选owner/源和bank选择（共5bit）；存活IB项遇WB同寄存器必须同边沿更新两份候选，同址双写按年龄选择。ID必须选择注册owner，与RAM数据读并行。WB tag应分区域复制，不能晚一拍修正owner。小配置2R1W必须不增加LVT。

RAM/APM必须通过rtl/tech包装；ASIC必须以等价复制1R1W宏或原生4R2W寄存器堆宏替代，保持读延迟、年轻写优先及WB转发语义。宏名称/几何见 C06 **[待定]**。

ID提前地址必须仅使用RF或已完成WB值。若同组较老项、EX、MEM任一未提交生产者写rs1，或WB乘法结果尚未完成，必须不合格；x0不构成依赖。合格load在ID末给地址，EX返回先本地捕获再供消费者；不增加第二D$副本。store必须不提前。miss/设备/维护冲突必须按普通事务完成，未完成结果不得被消费者使用，局部等待/重放时序见 C05 **[待定]**。

| 结果 | 消费者最早进入EX的间隔（生产者进入EX为0） |
|---|---|
| 早ALU、链接地址 | 1 |
| 合格且实际命中的短load | 1 |
| 普通load | 2 |
| 晚简单ALU | 2 |
| MUL | 4，全流水II=1 |
| CSR读 | 2；有序边界仍必须满足 |
| DIV | 可变，依实际完成记分牌；参数见5.4 |

### 5.3 晚执行与同组相关

LATE_EXECUTE=1必须每槽各有EX早ALU和MEM晚简单ALU；只在等待一拍且操作受支持时选择晚执行。支持ADD/ADDI/SUB、AND/OR/XOR及立即数、SLT/SLTU及立即数；启用Zba时包含三个固定移位加法。移位、MUL/DIV、CSR、访存地址和JALR不得晚执行。

| 生产者→年轻消费者 | 同组行为 |
|---|---|
| EX早ALU或合格短load→晚简单ALU/条件分支 | 可配，老结果先捕获，下一拍MEM使用 |
| 普通load→同组消费者 | 不可配 |
| 前组普通load→晚简单ALU | 可在消费者自身MEM使用前拍捕获结果 |
| 晚ALU→后继 | 必须按延迟2判定；不得同MEM段级联 |
| ALU/load→地址、MUL、JALR | 必须按实际可用时间等待 |

晚条件分支必须在MEM解析并按该级恢复，不能套用EX罚拍。无晚执行时组内RAW不得配对。同组WAW必须按年龄保持最后写入；其他类型矩阵见 C01。

### 5.4 乘除法与预测器

MUL/MULH/MULHSU/MULHU必须用33×33有符号乘法覆盖，APM输出必须直接进入本地结果寄存器，延迟4。DIV/DIVU/REM/REMU必须实现符号修正和ISA的除零/最小负数除-1语义。提前结束必须以幅值位数差k=max(0,bitlen(|a|)-bitlen(|b|)+1)为依据；radix2迭代轮数k、radix4为ceil(k/2)。除零/溢出必须直接给架构结果。预处理、修正及完成交付拍数 C07 **[待定]**，初值沿模型1+k/1+ceil(k/2)等待口径，基4预处理物理拆两拍；不得把该模型数冒充完整RTL延迟。

快速预测必须保留gshare两位计数表，GHR宽度log2项数，索引必须为(PC>>2)低GHR宽度位与GHR异或，计数器初值弱不跳；BTB必须保存目标、类型、有效和位置，RAS必须支持call/return、满覆盖最老、快照恢复。基本更新/复位沿旧核，TAGE例外如下。

TAGE必须在F1快速gshare外增加同步RAM基表4096×2和标签表；F2选择最长匹配provider、次长alternate，无匹配用基表，方向不同必须纠正一拍。历史长度随3/4/5表固定为(4,16,64)/(4,12,32,96)/(4,10,24,60,144)；每项tag10、计数3、usefulness2、valid1，共16bit。索引/标签必须采用分段XOR折叠，长历史必须注册折叠。

只有有F1查询token的存活条件分支必须训练TAGE和推进其过滤历史，BTB冷miss不得训练该状态；fast gshare必须按全部解析条件分支更新。每表及基表必须有独立1R1W训练副本，D预读当前行；EX/MEM按年龄更新并镜像写预测副本。每拍单写，一个待写项必须吸收老MEM/年轻EX碰撞；查询必须旁路待写项，index/tag命中在F1计算并注册，F2末级合并。误预测最多向更长表分配一项，分配压力下降低候选usefulness；具体编码/折叠和分配顺序见 C08 **[待定]**。

### 5.5 取指与 L1

IF_DUAL_BANK=0必须使用64位对齐取指组。=1必须以奇偶32位两个bank读取任意4字节对齐的PC及PC+4，再拼合固定逻辑双槽；跨行必须分别查询两行并保留各自错误信息。BTB必须改为字索引、奇偶分bank，总容量不得翻倍；两字分别查询方向/目标，选择最老taken。F2纠正必须按原快照修正第二条call/return的RAS动作。

IB必须用固定头寄存器；发请求只依据寄存信用，容量应计入IB_DEPTH+4物理条目和在途预留，不组合依赖本拍发射。

I$/D$必须各32KiB、2路、32B行、512组；tag=addr[31:14]。必须采用RAM元数据（valid/dirty/LRU/tag），本地hit/miss，写回/写分配D$，每侧至多一个miss；主档不得加入双load合并。元数据失效机制见 C02 **[待定]**，初值扫描512组，RAM数据不复位。

D$必须有1项地址/32位数据/4位掩码写缓冲；提交后下一拍写阵列，可同拍排空并接新项。load必须按字节合并同字较老store。PMA、AXI错误、非缓存和设备访问必须沿旧cache-spec 2.3、5.3、6，设备只在提交后发事务并等响应。

维护必须沿旧cache-spec 5.4：范围clean/invalidate/clean+invalidate、全clean；开始前排空写缓冲；invalidate必须允许丢弃脏数据；OP_SIZE=0仅命令1–3立即完成；范围每组至多访问一次；设备访问/状态轮询继续，可缓存请求延迟至维护结束。FENCE必须等写缓冲空；FENCE.I必须D$全clean→I$失效→从下一条重取。与在途填充重叠时失效优先，取消请求的填充可完成但不得回送已取消结果。RAM元数据引起的完成延迟改变必须在C02冻结，外部软件必须以done/BUSY判完成。

### 5.6 FPU 集成与精确边界

槽0必须承接FP算术、转换和FP访存，槽1只配独立整数ALU。2R FMA必须先捕获rs1/rs2、次拍读rs3，该拍可执行独立整数但不得再读新FP；3R必须同拍捕获三源。整数域/FP域必须独立跟踪RAW/WAW，FP组内相关不得配对。

共享队列必须按tag奇偶分两个单写bank，branch/store等无rd项也占PC完成写口；同bank和单FP写口冲突必须按年龄选择并保留年轻源本地结果。必须支持任意未提交完成项按tag转发，结果RAM必须具备R+1份读取副本（R源+1提交）；输出必须本地捕获，不能深队列异步读直串EX。

FLW/FSW必须占一个32位LSU beat；FLD/FSD必须低地址字再高地址字两个beat，共享一条指令和一个提交tag，FLD两字齐全才可使用，中间不得退休/响应中断。不承诺64位原子访存。第二beat错误、副作用与跨行细则见 F04/C05 **[待定]**。

## 6. 错误处理

6.1 必须按最老指令精确陷阱：故障项及年轻项不提交，已更老项可提交；mepc必须指故障PC，mtval必须按旧核规则。取指/跳转目标不对齐cause0、取指访问1、非法2、EBREAK3、load不对齐4/访问5、store不对齐6/访问7、M态ECALL11。非法mtval=编码、EBREAK=PC、地址异常=地址、其他0。

6.2 中断必须沿旧核MEIP/MSIP/MTIP、mie/mstatus使能、direct/vectored和MRET恢复语义，在提交头可中断边界进入；不得切开设备访问、除法退休事务、FENCE.I或D双beat指令。提交头中断采样与长算术取消的精确实现见 C09 **[待定]**；初值保持旧核不可中断操作边界，其余可取消年轻长操作。

6.3 WFI必须提交后停取指，任一使能中断等待（无论MIE）恢复。寄存重定向必须按年龄优先于年轻重定向，不能等待D$握手才冲刷。FP算术异常必须仅置fflags，不陷阱。

6.4 PMA违规必须不发总线；填充错误必须返回访问异常、不置行有效且收完剩余beat。脏写回B错误必须置APB错误状态、地址及中断，后续填充继续，遵循旧契约；不得新增超时、重试、校验或恢复路径。

## 7. 性能与资源指标

所有下列数字均为模型/结构估算，非RTL/PDS实测。主档不含FPU集成；资源误差约±30%，逻辑LUT已含LUTRAM，DRM按宏碎片计数。

| 主档 | CM/视觉/LVGL周期估算 | CM/MHz估算 | 视觉/LVGL IPC估算 | LUT/FF/CLM估算 | DRM36K/APM估算 |
|---|---|---:|---|---|---|
| 小 small/rf-async | 2698393/2078130/607096 | 3.7059 | 0.9149/0.8693 | 6406/3749/2288 | 18/4 |
| 默认 default/rf-head | 1776563/1294193/457058 | 5.6288 | 1.4691/1.1547 | 7994/4526/2855 | 18/4 |
| 满配 full/combo4-head | 1631722/1199481/421580 | 6.1285 | 1.5851/1.2519 | 11779/6550/4207 | 25.5/4 |

估算输入必须使用C2-I4提交1a26a7924、GCC15.2既有CoreMark/视觉/LVGL trace和第四轮独立回放；Zba软件必须使用对应ISA trace。启用Zba的满配四表估算为6.2536 CM/MHz、11907 LUT/6550 FF/25.5 DRM/4APM。不能把其收益计入关闭Zba主档。

规划频率150MHz、整片压力目标135MHz均 **[待定]**，由PG2L200H-6的PDS独立和整片setup/hold定稿，不改现有SoC时钟配置。预算常数为Q=.742、MUX=.793、ADD32=1.259、HFF=1.191、HDRM=2.574ns，另加.450ns布局/时钟余量；周期max段+.450，规划按1.05、压力按1.182折算并向下取5MHz档。

| 关键段 | 估算ns（另加.450） | 必须保持的边界 |
|---|---:|---|
| 保留ID/RF最坏段 | 5.796 | 固定头、注册信用 |
| RF owner预解码后ID→AGU | 5.736 | 注册owner与数据读并行 |
| 双bank F2→LVT/WB优先 | 5.746 | 物理bank前置查询、候选owner寄存 |
| TAGE F2/双bank方向 | 5.542 | 长历史折叠已注册 |
| 待写训练命中前置 | 5.643 | F1算index/tag，F2末级合并 |
| DRM load→操作数捕获 | 4.800 | 捕获后下一拍执行消费者 |
| 双早/晚ALU | 4.778 | EX/MEM不串两个carry |
| 晚条件分支 | 5.520 | 本地注册目标/比较 |
| MUL/JALR输入选择 | 4.159/5.418 | 不额外串入ALU环 |

FP32 FMA及其他FP预算见fpu-spec 7。L1命中必须每拍接受一个普通请求、接受后下一拍返回；短load仅在5.2资格与实际命中成立时满足1拍相关延迟。miss、维护和恢复完整负载周期阈值 C10 **[待定]**，不能用命中模型保证整程序周期。

## 8. 验证要点

必须按cpu-v2-testplan逐条检查本规格1–7的条款；CPU/Spike逐退休比对、架构测试、参数回归、配对/晚执行/提前地址/冲刷和精确异常交叉必须通过。L1必须验证PMA、字节转发、背压、维护、失效与在途填充。F/FD集成必须同时通过fpu-testplan。模型数字只能作为perf对照，不作为已完成RTL验证的证据。

## 9. 待定事项

下表是本规格唯一待定事项登记，正文相同标记不另计。

| ID | 事项及推荐初值 | 定稿时机/依据 |
|---|---|---|
| C01 | 配对矩阵和参数组合：推荐保留2.2主档及正交选项；晚执行仅双发射、每组单控制/单LSU | 后端任务前，协调者核对模型全矩阵 |
| C02 | RAM元数据复位/失效和维护周期：推荐两路并扫512组，I$失效改扫描完成握手、在途填充不置有效，组段16组 | L1任务前冻结行为，PDS/仿真定周期 |
| C03 | 外部AXI/APB是否改动：推荐完全不改，内部双bank跨行串行miss | SoC接入前；若有必须修改项逐信号列差异 |
| C04 | HPM/debug/退休trace：推荐保持原事件编码，局部DIV等待按原事件10计，trace扩展域/64位FP结果与flags | 验证环境/CSR任务前 |
| C05 | 核-L1/FP逐信号、tag环回、短load失败局部重放、FD第二beat错误/跨行：推荐valid-ready+年龄tag、本地捕获和精确提交 | 所有并行RTL任务前；与F04共同冻结 |
| C06 | FPGA/ASIC RF与缓存宏名称/几何：推荐异步2R1W、预解码4R2W及等延迟ASIC宏 | RF探针后、技术包装任务前 |
| C07 | 除法完整延迟/预处理：推荐显式分离幅值/位数/对齐、迭代、修正；用真实日程替代模型等待初值 | DIV单元方案冻结及回放后 |
| C08 | TAGE精确折叠/初始化/分配usefulness编码：推荐以RamTage模型固定行为，单待写旁路 | 前端任务前，功能模型与端口探针 |
| C09 | 中断提交头采样和长操作取消：推荐保留旧不可中断边界，其余按年龄取消年轻项 | 后端接口冻结前 |
| C10 | 150/135MHz、资源及perf阈值：初值本节估算；RTL命中周期应对照模型，完整负载单列miss/恢复差异 | 五项探针后暂定，整片PDS与上板后定稿 |
| C11 | 新IP的目录和模块前缀：推荐 rtl/cpu2/、edrv32_cpu2_*（顶层 edrv32_cpu2_top），FPU在 rtl/cpu2/fpu/，与旧核 rtl/cpu/ 并存 | 探针任务P00前 |

FMA_READ_PORTS的F默认3及FP状态待定项统一由fpu-spec F01–F06登记。

## 10. 变更记录

| 日期 | 版本 | 变更/依据 |
|---|---|---|
| 2026-11-27 | v0.1-draft | 按用户批准的CPU v2规格阶段起草新IP；依据C2-I第四轮、C2-F2第二版，供协调者定稿 |
