# CPU v2 FPU 规格

| 项 | 内容 |
|---|---|
| 版本 | v0.3 |
| 日期 | 2026-11-28 |
| 状态 | 已确认（用户 2026-11-28 决定）；F03、F06 仍待实测 |
| 范围 | CPU v2可选F/FD算术、独立FP RF及与整数后端集成契约 |
| 关联文档 | cpu-v2-spec.md、fpu-testplan.md、cpu-v2-plan.md；docs/design/2026-11-27-cpu-v2-fpu.md 第二版；docs/design/2026-11-27-cpu-v2-architecture.md“FPU接口”及第四轮 |

## 1. 概述

1.1 FPU必须是CPU v2的可选扩展，工作在CPU同一clk_sys域。FPU_FORMAT=NONE必须不实例化FPU、FP RF、FP CSR；F必须实现FLEN=32，FD必须实现FLEN=64及F、D两种精度。本文采用RISC-V F/D 2.2的软件行为，范围仅RV32，不增加Zfh、Zfa、Zfinx、RV64指令。

1.2 FPU必须通过执行管线0进入全核共享顺序完成队列，双发射时可与另一程序槽的独立整数ALU配对，槽到管线必须按cpu-v2-spec 2.3分配。算术内部可多周期并行，寄存器、flags和访存副作用必须按序提交。

## 2. 功能描述

### 2.1 完整指令范围

下表中S必须在F/FD实现；D必须仅在FD实现，未启用的编码必须非法指令。f0必须与其他FP寄存器相同可读写。

| 类别 | 必须实现 |
|---|---|
| 访存 | FLW/FSW；FD另有FLD/FSD |
| 算术 | FADD/FSUB/FMUL/FDIV/FSQRT的.S/.D |
| 融合 | FMADD/FMSUB/FNMADD/FNMSUB的.S/.D；完整乘积加数后只舍入一次 |
| 符号 | FSGNJ/FSGNJN/FSGNJX的.S/.D |
| 最值 | FMIN/FMAX的.S/.D |
| 比较 | FEQ/FLT/FLE的.S/.D，结果写整数域 |
| 分类 | FCLASS.S/.D，十类位图写整数域 |
| 整数转换 | FCVT.W.S、FCVT.WU.S、FCVT.S.W、FCVT.S.WU；FD另有对应.D形式 |
| 精度转换 | FD另有FCVT.S.D、FCVT.D.S |
| 位搬移 | FMV.X.W、FMV.W.X，原样保留32位编码 |

不得实现RV32中不存在的FMV.X.D/FMV.D.X及FCVT.L/LU。转换的越界、NaN整数饱和值和NV/NX必须按F/D 2.2，不得使用主机浮点转换结果替代架构规则。

### 2.2 舍入、特殊值和异常标志

必须实现RNE、RTZ、RDN、RUP、RMM五种舍入。静态rm=000..100必须选择对应方式；rm=111必须采样按程序顺序生效的frm。静态rm=101/110，或动态舍入时frm=101/110/111，必须产生非法指令异常。CSR写frm/fcsr必须原样保存3位frm，写入本身不得因保留编码陷阱（协调者2026-11-27确认）。

硬件必须处理输入/输出非规格化数、渐进下溢和舍入后tininess；合法subnormal不得软件陷入或FTZ。必须正确处理正负零、无穷、qNaN/sNaN。算术NaN结果必须规范化为S=0x7fc00000、D=0x7ff8000000000000；位搬移/符号操作必须保留指令规定的payload。

必须按指令生成NV/DZ/OF/UF/NX，精确结果不得置NX；算术数值异常不得陷阱。FMA必须只舍入一次，0×∞即使加数为qNaN也必须置NV。FADD/FMUL旁路必须按原opcode判定NaN、零符号和flags，不能直接套用FMA特殊值逻辑。

FMIN/FMAX必须按2.2 minimumNumber/maximumNumber：单NaN返回数值、sNaN置NV、−0小于+0。FEQ仅sNaN置NV，FLT/FLE遇任意NaN必须置NV。FCLASS/FSGNJ及搬移必须不做算术舍入、不产生浮点flags。

### 2.3 NaN-boxing

FD中窄FP结果、FLW和FMV.W.X必须把高32位写为全1。窄非搬移运算（包括比较、分类、符号注入）必须检查源高32位全1，否则将源视为canonical NaN。FSW和FMV.X.W必须保留原始低32位，不应用算术boxing检查。FLD/FSD必须原样搬移64位。

### 2.4 微结构与构建参数

必须采用FMA核心加ADD/MUL旁路，按精度共享尾端；DIV/SQRT必须使用独立基4digit recurrence入口。D必须独立扩展S数据通路和乘法资源，不串行复用S两颗APM，不把S全部送入宽D核心。

FPU必须只由FPU_FORMAT选择格式；CPU的ISSUE_WIDTH必须选择cpu-v2-spec 2.2的单发射精简或双发射满配结构；FP读口与队列深度不得独立配置。

| 固定结构 | NONE | F | FD |
|---|---|---|---|
| 精度/FLEN B | 无，整数数据32 | S / 32 | S+D / 64 |
| FP RF读口 R | 无 | 3 | 2 |
| 完成项 N / tag T | 4 / 2，FF记录 | 8 / 3，数据/PC LUTRAM | 16 / 4，数据/PC LUTRAM |
| 单/双发射统一源数 S | 2 / 4 | 3 / 5 | 2 / 4 |
| FP RF/算术/CSR | 不实例化 | 实例化F | 实例化F/D |

任意项转发必须固定启用。F必须同拍捕获三源；FD必须先捕获rs1/rs2、次拍rs3。D算术II初值4 **[待定]**（F03）。板级必须为双发射+F，CPU必须采用单发射精简或双发射满配（cpu-v2-spec 2.2），与NONE/F/FD交叉共6种且全部完整回归；本表内部结构和源副本数不随整数精简结构改变。

## 3. 接口

### 3.1 同域与握手

所有接口必须同属clk_sys；每模块必须有clk_i/rst_n_i各1位，控制复位、数据不复位。标准外部总线必须沿cpu-v2-spec 3.9。T在F/FD分别3/4，B分别32/64；NONE必须不实例化FP接口。valid&&ready的上升沿必须接受一次，背压必须保持valid及全部负载；ready必须来自寄存容量。


下表以整数端为A、FPU为B；FPU端必须用相同词干和反向_i/_o后缀，例如fp_req_valid_i、fp_req_ready_o、fp_resp_valid_o、fp_resp_ready_i、fp_cancel_valid_i、fp_cancel_tag_i、fp_age_head_i。

| A端端口 | 方向 | 位宽 | 语义 |
|---|---|---:|---|
| fp_req_valid_o / fp_req_ready_i | A→B / B→A | 各1 | 三源全部捕获后一次接受，等待负载保持 |
| fp_req_instr_o / fp_req_tag_o | A→B | 32/T | 原始编码/共享tag |
| fp_req_src1_o / fp_req_src2_o / fp_req_src3_o | A→B | 各B | FP原始位，FD保留boxing高32 |
| fp_req_int_src_o / fp_req_rm_o | A→B | 32/3 | 整数源/已解析合法舍入，进入后不重采frm |
| fp_resp_valid_i / fp_resp_ready_o | B→A / A→B | 各1 | 本地结果完成，仲裁背压保持 |
| fp_resp_tag_i / fp_resp_data_i / fp_resp_flags_i / fp_resp_int_dest_i | B→A | T/B/5/1 | 每条结果，int_dest1整数、0FP |
| fp_cancel_valid_o / fp_cancel_tag_o / fp_age_head_o | A→B | 1/T/T | 包含边界取消；age_head是C05比较必需字段 |

FPU内部 top→fma32/fma64/divsqrt/convert/short 使用 `unit_req_valid/ready/instr/tag/src1/src2/src3/int_src/rm`，位宽和握手逐项同fp_req；各单元→top使用 `unit_resp_valid/ready/tag/data/flags/int_dest`，逐项同fp_resp，32位算术结果在FD由top按boxing扩展。每单元都有 `age_head/cancel_valid/cancel_tag` 同上，完成前后均可取消；未用源由译码确定，不设空预留接口。NONE不实例化这些接口。


### 3.2 RF、LSU、共享完成与CSR

FP RF读写、统一source、allocate、完成源/head/提交、CSR flags/FS、LSU逐beat接口必须逐信号沿cpu-v2-spec 3.4、3.5、3.7，位宽必须使用本文2.4固定表；NONE无FP域。FP load/store必须经过单LSU，不增加整数RF端口或D$副本。FP→整数比较/转换/分类必须使用整数提交写口0，另一整数写口在双发射中保留；整数→FP源必须使用已有整数读口。

FP load和算术必须竞争单FP目的完成写口。FPU不得直接改fcsr/FS，必须仅返回每指令flags，由commit按程序顺序生效。无rd branch/store也必须参与完成PC写仲裁。

### 3.3 模块与技术包装

FP根必须为rtl/cpu2/fpu/；模块必须为edrv32_cpu2_fpu_top（路由）、edrv32_cpu2_fpu_rf（FP RF）、edrv32_cpu2_fpu_fma32、edrv32_cpu2_fpu_fma64（按精度ADD/MUL/FMA及共享尾端）、edrv32_cpu2_fpu_divsqrt（独立S/D基4入口）、edrv32_cpu2_fpu_convert、edrv32_cpu2_fpu_short。S辅助必须沿已有edrv32_cpu2_fpu_lz24/edrv32_cpu2_fpu_lza32；D辅助必须依真实数据通路确定，不预留空模块。F必须不实例化D算术；NONE必须不实例化上述模块。FP RF及共享完成宏端口/几何必须沿cpu-v2-spec 3.10；F06的FP乘法宏实际打包仍待测。

## 4. 寄存器

| CSR/状态 | 地址 | 访问 | 复位值 | 位域 |
|---|---|---|---|---|
| f0–f31 | FP寄存器编号0–31 | RW | 数据不复位 | FLEN=32或64，f0非硬零 |
| fflags | 0x001 | RW | 0 | [4:0]=NV/DZ/OF/UF/NX，对应bit4..0；高位0 |
| frm | 0x002 | RW | 0 | [2:0]舍入编码，高位0；保留编码照存 |
| fcsr | 0x003 | RW | 0 | [7:5]frm，[4:0]fflags，高位0 |
| mstatus.FS/SD | 0x300 | 见CPU CSR | Off(00) | FS[14:13]，SD[31]由Dirty状态生成 |
| misa.F/D | 0x301 | 写忽略 | 按构建 | NONE均0、F仅F、FD两者1 |

4.1 每条已提交FP指令必须将自身flags OR入fflags；CSR显式写清/置flags必须与长运算按程序顺序生效，年轻取消项不得影响fflags。三CSR必须互为别名。

4.2 含F/FD复位FS=Off(00)，Initial=01/Clean=10/Dirty=11，SD=(FS==11)；SD只读。NONE的FS/SD读0写忽略、FP CSR非法。FS=Off时FP指令（含访存/搬移）和FP CSR访问均非法，mtval=指令。

仅在提交时：任何FP目的寄存器写（包括FLW/FLD/FMV）置Dirty；FP指令flags非0所致fflags写置Dirty；对fflags/frm/fcsr的实际CSR写访问置Dirty，即使写回相同值。只读CSR（CSRRS/RC零源）、FSW/FSD、无flags的整数目的比较/转换/分类不置Dirty。取消项无效；FP RF数据不复位，不以FS=Initial偷偷清空寄存器。

软件写mstatus.FS按2bit原值保存（含主动置Clean/Initial/Off），同拍陷阱优先沿CPU CSR规则；写fcsr三别名有序、flags OR与CSR显式写按指令年龄依次作用。所有CSR/系统单发并等待更老完成，动态rm在FP源接受前采样已生效frm；保留frm原样保存，使用非法编码时才陷阱。

## 5. 行为与时序

### 5.1 RF、发射和依赖

FP RF必须独立32×B、单写；FD FMA必须先读rs1/rs2并捕获，次拍读rs3，连续FMA接受间隔至少2；额外源捕获周期只加一次。F必须同拍捕获三源，本体II不受rs3捕获限制。双发射捕获期间可配独立整数，但不得开始新FP读取；未读rs3期间必须保持RAW/WAW版本正确。

必须独立跟踪FP/整数域RAW/WAW；同组FP相关不得配。等待最老FP指令必须阻止年轻越序发射；FPU长运算不得统一停顿整数流水，有容量且不相关的后继整数可继续按序发射。

### 5.2 算术流水与技术包装

S必须保留完整48位积，D必须保留106位积及低位舍入信息；FMA对齐、相消和sticky必须在单次舍入前完成。LZA应与加减并行，不能接在长carry后形成新最长段。

FPGA乘积必须通过rtl/tech APM包装；S按24×(16+8)为2颗APM、全寄存链4拍；D按(24+24+5)×(16+16+16+5)为12颗、链14拍。D同权e=48两项必须直通Δe=0，其他位差8/16，不能以shift8代替直通。规格化末拍必须直接采样入APM X/Y内部寄存，不另增加同值外部FF；APM内部MULT/P/CPO不能重复计入CLM FF。

ADD/MUL/FMA必须共享各精度尾端入口，按入口周期预约冲突，S两拍/D三拍尾端每拍仍可接一个结果；不得把尾端长度误作II。短操作必须独立流水但竞争完成写口。

### 5.3 延迟和吞吐初值

所有本表数字为规划估算，均 **[待定]**（F03）。本体延迟从最后一个源已捕获到本地结果可转发，不含FD FMA额外的一次源捕获，不含真实完成竞争。

| 操作 | S延迟 | D延迟 | 本体II初值 |
|---|---:|---:|---|
| ADD/SUB | 5 | 6 | S1/D4 |
| MUL | 7 | 18 | S1/D4 |
| FMA四变体 | 8 | 20 | S1/D4 |
| DIV/SQRT | 19/19 | 35/35 | S19/D35，共享一个迭代入口 |
| 转换 | 3 | 4 | 1 |
| 比较/最值/分类 | 2 | 2 | 1 |
| 符号/搬移 | 1 | 1 | 1 |

DIV/SQRT初值必须按基4每拍一轮：S准备2、迭代14、尾部3；D准备2、迭代28、尾部5。必须校正余数、末位和舍入，不用近似商替代正确舍入。

### 5.4 共享完成与转发

F/FD必须采用cpu-v2-spec 2.2固定表的全核共享完成队列（F单/双发射8/16项，FD 16项），不增加FP专用第二队列。数据和PC必须用LUTRAM，flags/目的/年龄控制用FF；NONE使用同一结构。无rd的branch/store也必须写其PC完成记录并参与bank仲裁。

任意完成未提交项必须可按最新源tag转发；低32位结果每bank必须复制S+1份（F单/双发射4/6份，FD单/双发射3/5份），FD高32位每bank必须3份，PC每bank1份。统一源口必须按域映射，不另设额外FP完成读口。队列异步读结果必须本地捕获，不得直接串入EX最长选择；若真实实现多一拍必须改F03并重跑模型。每拍最多ISSUE_WIDTH条退休、最多一条FP目的写，架构RF/fflags/store必须按序生效。取消必须覆盖在途算术、排队完成和flags，tag环回不得误读旧RF版本。必须以队头相对距离比较年龄，cancel_tag包含边界；取消同沿必须清算术/本地结果valid与flags，取消范围内的同拍接收必须不记完成。取消后的结果源必须不再回送旧tag，队列下一拍可复用tag；已发AXI必须收完并由cache抑制旧响应。两个bank必须按tag[0]选择，单写、年龄优先；异bank两个FP目的也必须只接收老者。FD未读rs3必须保留源版本/生产tag，生产者退休同沿必须捕获值，不得被年轻同目的写覆盖。三源全部捕获后才一次req握手；额外捕获拍必须只计一次。

### 5.5 浮点访存边界

S必须4B对齐，D必须8B对齐，不对齐在任何beat发出前报告cause4/6、mtval原地址；两beat低字后高字，共一个tag。FLD仅两字成功才完成64位结果；任一错误无FP寄存器/flags写回。第二beat访问错误cause5/7，mepc本条PC、mtval故障beat地址（原地址+4）。

可缓存FSD先完成两beat的地址/tag准备，再在不可撤销头依次写缓冲；设备/不可缓存从头授权后依次发单拍，低beat失败不发高beat。高beat失败不能撤销已完成低beat总线或存储副作用，不退休本条/年轻项，但明确允许部分存储；不得声称精确退休等于外部回滚。两个成功响应后才退休一次；两beat之间不退休年轻项/不响应中断。

自然对齐8B且行32B时 `(addr mod32)∈{0,8,16,24}`，高字偏移≤28，因此本版**不存在合法D指令跨cache行**，也不跨4KiB/PMA自然边界；行尾24/28必须覆盖。双bank跨行取指必须沿cpu-v2-spec 3/5.5。

## 6. 错误处理

6.1 数值异常必须只置本条flags并于提交累计，不引起M态陷阱；合法subnormal必须由硬件处理。

6.2 未实现精度/指令、FS=Off非法访问、2.2非法舍入必须由整数译码/CSR在进入FPU前生成CPU非法指令完成项；FPU不得增加异常响应通道；mtval必须为编码；非法舍入项不得提交结果或flags。访存不对齐/访问错误必须按CPU cause4/5/6/7，故障项和年轻项不提交。

6.3 冲刷必须取消年轻结果和flags，保留更老完成和已提交架构状态。完成竞争必须保留源结果，不能丢失、重复提交或静默降级。不得增加规格未要求的超时、重试和软件subnormal兜底。

## 7. 性能与资源指标

7.1 150MHz规划、135MHz整片压力目标均 **[待定]**（与CPU C10共同定稿）。每段估算含.450ns布局/时钟余量，不使用multicycle掩盖流水路径。

| 关键段 | 含余量的估算ns | 实现约束 |
|---|---:|---|
| S FMA add/LZA | 6.206 | carry77+3普通级，LZA并行 |
| D sliced add/LZA | 5.554 | carry84+2普通级，跨两拍 |
| S/D normalize较长段 | 6.093 | 不超过6普通级 |
| D DIV/SQRT recurrence | 5.756 | carry57+3普通级 |
| APM寄存阶段代理 | 5.323 | X/Y、MULT/P/CPO和级联仍须PDS逐项验证 |

7.2 下表必须仅作为结构估算，误差约±40%；增量相对C2-F2旧V5-default整数基础，不得直接与CPU第四轮总数相加作为实测。逻辑LUT含义不含LUTRAM，总LUT包含LUTRAM；flags/控制为FF，不增加第二FP完成队列。

| 格式 | 单/双发射增量总LUT估算 | 逻辑LUT估算 | FF估算 | APM估算 | 单/双发射LUTRAM估算 | 单/双发射逻辑RAM bit估算 |
|---|---|---:|---:|---:|---|---|
| NONE | 0/0 | 0 | 0 | 0 | 0/0 | 0/0 |
| F（3读、N8） | 3805/3933 | 3389 | 873 | 2 | 416/544 | 4352/4864 |
| FD（2读、N16） | 9970/10098 | 9394 | 4809 | 14 | 576/704 | 7680/8704 |

估算必须采用固定源端口S：RF物理LUTRAM=R×B；队列物理LUTRAM=2×[32(S+1)+32×1_FD(R+1)+32]；逻辑bit=32RB+N×[32(S+1)+32×1_FD(R+1)+32]。每单元物理容量64bit；CLM=ceil(max(LUT/4,FF/8)/.70)。逻辑LUT/FF/APM沿C2-F2的F/3/N8及FD/2/N16；双发射按冻结统一源域口径比旧表增加128 LUTRAM，不能再采用旧R+1全宽复制口径。公式来源为接口冻结记录F05，旧逻辑资源来源为`python3 tools/cpu/eval/fpu_resources.py`及C2-F2；真实宏打包和集成资源仍为F06 **[待定]**。

7.3 perf初值必须使用相同C2-F2软件和trace，比对实际调度的整数基础、结构、依赖、写回和额外beat互斥周期之和。F/3R/8的matrix_s/vertex_s/physics_s周期估算34929/15449/112742；FD/2R/16的matrix_d/whetstone_d周期估算88693/151235。F-only的软件double可能比NONE慢，不能承诺所有浮点软件加速。上述简化命中模型不能替代CPU v2完整前端/cache/错路性能测量。

## 8. 验证要点

必须逐位验证结果和每指令flags、累计fcsr、FS与陷阱。必须覆盖每指令/精度/五舍入、保留舍入非法、全部特殊值、subnormal、单次舍入反例、NaN-boxing例外。必须通过TestFloat/SoftFloat算术对照、Spike逐退休和F/D架构测试；流水必须覆盖2R源捕获、任意项转发、bank/单写口冲突、队列环回、冲刷和双beat异常，详见fpu-testplan。

## 9. 待定事项

| ID | 事项及开发初值 | 定稿时机 |
|---|---|---|
| F03 | 延迟/II及源捕获：S5/7/8、D6/18/20、DIV/SQRT19/35、D II4 | 真实算术RTL逐拍与D探针测量后定稿 |
| F06 | 资源、宏实际打包、FPGA/ASIC乘法宏契约 | PDS/厂商等价/ASIC移植后，以实际打包替代估算 |

CPU C10及验证FT02的性能接受数值仍必须待测；不得把已冻结接口或局部探针频率当作整核验收。

## 10. 变更记录

| 日期 | 版本 | 变更/依据 |
|---|---|---|
| 2026-11-27 | v0.1-draft | 依据C2-F2第二版和C2-I接口起草；F默认3R按协调者建议列待定；保留舍入非法行为经协调者ask确认 |
| 2026-11-28 | v0.2 | 依据 docs/design/2026-11-28-cpu-v2-interface-freeze.md 已决定状态及更正 C01，冻结接口、行为和两种CPU×三种FPU格式，Zba固定启用，更新模型估算、验证和实施依赖 |
| 2026-11-28 | v0.2 | 按用户决定将单发射固定为精简结构+Zba；双发射满配及NONE/F/FD固定结构不变，同步接口、验证、实施和模型结论 |
| 2026-11-28 | v0.3 | 用户确认：F双发射完成队列改为16项，NONE改用同一共享队列结构（cpu-v2-spec v0.3） |
