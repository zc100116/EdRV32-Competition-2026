# CPU v2 FPU 规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1-draft |
| 日期 | 2026-11-27 |
| 状态 | 草案，供协调者审核 |
| 范围 | CPU v2可选F/FD算术、独立FP RF及与整数后端集成契约 |
| 关联文档 | cpu-v2-spec.md、fpu-testplan.md、cpu-v2-plan.md；docs/design/2026-11-27-cpu-v2-fpu.md 第二版；docs/design/2026-11-27-cpu-v2-architecture.md“FPU接口”及第四轮 |

## 1. 概述

1.1 FPU必须是CPU v2的可选扩展，工作在CPU同一clk_sys域。FPU_FORMAT=NONE必须不实例化FPU、FP RF、FP CSR；F必须实现FLEN=32，FD必须实现FLEN=64及F、D两种精度。本文采用RISC-V F/D 2.2的软件行为，范围仅RV32，不增加Zfh、Zfa、Zfinx、RV64指令。

1.2 FPU必须通过槽0进入全核共享顺序完成队列，独立整数指令可在槽1执行。算术内部可多周期并行，寄存器、flags和访存副作用必须按序提交。

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

必须采用FMA核心加ADD/MUL旁路，按精度共享尾端；DIV/SQRT必须使用独立基4digit recurrence入口。D必须独立扩展S数据通路和乘法资源，不串行复用S两颗APM、不把S全部送入宽D核心。

| 参数 | 合法值 | 推荐初值 |
|---|---|---|
| FPU_FORMAT | NONE/F/FD | IP按应用构建；图形F、通用双精度FD |
| FMA_READ_PORTS | 2/3 | F默认3 **[待定]**（协调者评审建议）；FD初值2、满配3 |
| COMPLETION_DEPTH | F/FD为8/16，NONE固定4 | F=8、FD=16 |

端口数量、FLEN、队列tag宽度必须由上述参数派生。任意项转发必须固定启用，不保留仅末级/头旁路比较方案开关。D算术II初值4 **[待定]**，不因此删减D硬件资源。

## 3. 接口

3.1 所有接口必须与CPU同域，无新增外部总线或跨时钟域。顶层外部标准接口必须沿cpu-v2-spec 3.1。FPU端口最终拼写随F05冻结，以下逻辑字段必须存在，方向以FPU为准；N=共享完成深度、T=ceil(log2 N)、B=FLEN。

| 信号/字段 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| clk_i / rst_n_i | in | 1/1 | clk_sys | 控制复位，数据阵列不复位 |
| fp_req_valid_i / fp_req_ready_o | in/out | 1/1 | clk_sys | 槽0接受握手 |
| fp_req_instr_i / fp_req_tag_i | in | 32/T | clk_sys | 指令、全核年龄tag |
| fp_req_src1_i / src2_i / src3_i | in | 各B | clk_sys | 已捕获FP源；2R需rs3捕获相位 |
| fp_req_int_src_i / fp_req_rm_i | in | 32/3 | clk_sys | 整数源、按序解析的舍入编码 |
| fp_resp_valid_o / fp_resp_ready_i | out/in | 1/1 | clk_sys | 完成握手，背压保留本地结果 |
| fp_resp_tag_o / data_o / flags_o | out | T/B/5 | clk_sys | 对应tag结果、该条flags |
| fp_resp_int_dest_o | out | 1 | clk_sys | 结果写整数域 |
| fp_cancel_valid_i / fp_cancel_tag_i | in | 1/T | clk_sys | 取消年龄边界，年轻项不得提交 |

3.2 FP load/store必须通过单整数LSU；FSW/FSD数据来自FP RF，返回写FP域。FP→整数转换、比较/分类必须竞争槽0整数写口；整数→FP必须使用槽0整数读口。不得增加整数RF端口。

3.3 单FP完成写口必须仲裁FP load和算术；两个完成bank必须按顺序tag奇偶分bank，各bank单写。冲突必须年龄优先并保留年轻源结果。fcsr/FS必须由整数特权/提交部分维护，FPU返回每指令flags而不直接更改架构状态。

## 4. 寄存器

| CSR/状态 | 地址 | 访问 | 复位值 | 位域 |
|---|---|---|---|---|
| f0–f31 | FP寄存器编号0–31 | RW | 数据不复位 | FLEN=32或64，f0非硬零 |
| fflags | 0x001 | RW | 0 | [4:0]=NV/DZ/OF/UF/NX，对应bit4..0；高位0 |
| frm | 0x002 | RW | 0 | [2:0]舍入编码，高位0；保留编码照存 |
| fcsr | 0x003 | RW | 0 | [7:5]frm，[4:0]fflags，高位0 |
| mstatus.FS/SD | 0x300 | 见CPU CSR | Off初值 **[待定]** | FS[14:13]，SD[31]由Dirty状态生成 |
| misa.F/D | 0x301 | 写忽略 | 按构建 | NONE均0、F仅F、FD两者1 |

4.1 每条已提交FP指令必须将自身flags OR入fflags；CSR显式写清/置flags必须与长运算按程序顺序生效，年轻取消项不得影响fflags。三CSR必须互为别名。

4.2 NONE必须使FP CSR访问非法。FS=Off时的FP指令/FP CSR非法访问、Dirty写入和上下文保存恢复必须由CPU特权集成负责；具体FS复位和Dirty触发事件 F02 **[待定]**。推荐复位Off，写FP架构状态/flags/frm后Dirty，允许软件保存恢复全部f0–f31和fcsr。

## 5. 行为与时序

### 5.1 RF、发射和依赖

FP RF必须独立32×B、单写；2R FMA必须先读rs1/rs2并捕获，次拍读rs3，连续FMA接受间隔至少2；额外源捕获周期只加一次。3R必须同拍捕获三源，本体II不受rs3捕获限制。捕获期间可配独立整数，但不得开始新FP读取；未读rs3期间必须保持RAW/WAW版本正确。

必须独立跟踪FP/整数域RAW/WAW；同组FP相关不得配。等待最老FP指令必须阻止年轻越序发射；FPU长运算不得统一停顿整数流水，有容量且不相关的后继整数可继续按序发射。

### 5.2 算术流水与技术包装

S必须保留完整48位积，D必须保留106位积及低位舍入信息；FMA对齐、相消和sticky必须在单次舍入前完成。LZA应与加减并行，不能接在长carry后形成新最长段。

FPGA乘积必须通过rtl/tech APM包装；S按24×(16+8)为2颗APM、全寄存链4拍；D按(24+24+5)×(16+16+16+5)为12颗、链14拍。D同权e=48两项必须直通Δe=0，其他位差8/16，不能以shift8代替直通。规格化末拍必须直接采样入APM X/Y内部寄存，不另增加同值外部FF；APM内部MULT/P/CPO不能重复计入CLM FF。

ADD/MUL/FMA必须共享各精度尾端入口，按入口周期预约冲突，S两拍/D三拍尾端每拍仍可接一个结果；不得把尾端长度误作II。短操作必须独立流水但竞争完成写口。

### 5.3 延迟和吞吐初值

所有本表数字为规划估算，均 **[待定]**（F03）。本体延迟从最后一个源已捕获到本地结果可转发，不含2R FMA额外的一次源捕获，不含真实完成竞争。

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

F/FD必须采用8/16项全核共享完成队列，不增加FP专用第二队列。数据和PC必须用LUTRAM，flags/目的/年龄控制用FF；整数NONE原4项独立FF不承受两bank伪争用。无rd的branch/store也必须写其PC完成记录并参与bank仲裁。

任意完成未提交项必须可按最新源tag转发；R个源读取加一个提交读取必须使用M=R+1结果副本，PC每bank一份。队列异步读结果必须本地捕获，不得直接串入EX最长选择；若真实实现多一拍必须改F03并重跑模型。每拍最多两条退休、最多一条FP目的写，架构RF/fflags/store必须按序生效。取消必须覆盖在途算术、排队完成和flags，tag环回不得误读旧RF版本。

### 5.5 浮点访存边界

FLW/FSW必须使用一个32位beat，FLD/FSD必须低地址字再高地址字两beat；FD两beat之间不得退休或响应中断。FLD必须全部返回才提供64位源；FLD/FSD不得承诺64位原子性。推荐FLW/FSW四字节、FLD/FSD八字节自然对齐，未对齐产生CPU普通访存异常 **[待定]**（F04）。第二beat访问故障和跨行store副作用必须由F04与CPU C05共同冻结，初值沿总线已完成事务不可撤销、单指令精确退休契约，不假定事务回滚。

## 6. 错误处理

6.1 数值异常必须只置本条flags并于提交累计，不引起M态陷阱；合法subnormal必须由硬件处理。

6.2 未实现精度/指令、FS=Off非法访问、2.2非法舍入必须向CPU报告非法指令，mtval为编码；非法舍入项不得提交结果或flags。访存不对齐/访问错误必须按CPU cause4/5/6/7，故障项和年轻项不提交。

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

7.2 下表均为C2-F2结构估算，误差约±40%，为相对旧评估V5-default整数基础的集成增量；不将其CPU总数直接套到C2-I4主档。总LUT已含LUTRAM，CLM=ceil(max(LUT/4,FF/8)/.70)，APM不折算LUT。

| 配置/R/N | 增量总LUT/逻辑LUT估算 | FF估算 | APM估算 | LUTRAM估算 | 逻辑RAM bit估算 |
|---|---|---:|---:|---:|---:|
| NONE/—/4 | 0/0 | 0 | 0 | 0 | 0 |
| F/2/8 | 3709/3389 | 873 | 2 | 320 | 3072 |
| F/2/16 | 3821/3501 | 1049 | 2 | 320 | 4096 |
| F/3/8（推荐F默认） | 3805/3389 | 873 | 2 | 416 | 4352 |
| F/3/16 | 3917/3501 | 1049 | 2 | 416 | 5632 |
| FD/2/8 | 9858/9282 | 4633 | 14 | 576 | 5888 |
| FD/2/16（推荐FD） | 9970/9394 | 4809 | 14 | 576 | 7680 |
| FD/3/8 | 10050/9282 | 4633 | 14 | 768 | 8448 |
| FD/3/16 | 10162/9394 | 4809 | 14 | 768 | 10752 |

3R各行按C2-F2公式推算：相对2R增加3B个LUTRAM，逻辑位增加(32+N)B，未预减选择逻辑。公式必须包含RF R×32×B bit；共享队列N×((R+1)B+32)bit，物理LUTRAM=R×B+2×((R+1)B+32)，每单元按64bit物理容量计。flags/控制为FF，不能再加一份FP结果队列。资源/真实宏打包 F06 **[待定]**。

7.3 perf初值必须使用相同C2-F2软件和trace，比对实际调度的整数基础、结构、依赖、写回和额外beat互斥周期之和。F/3R/8的matrix_s/vertex_s/physics_s周期估算34929/15449/112742；FD/2R/16的matrix_d/whetstone_d周期估算88693/151235。F-only的软件double可能比NONE慢，不能承诺所有浮点软件加速。上述简化命中模型不能替代CPU v2完整前端/cache/错路性能测量。

## 8. 验证要点

必须逐位验证结果和每指令flags、累计fcsr、FS与陷阱。必须覆盖每指令/精度/五舍入、保留舍入非法、全部特殊值、subnormal、单次舍入反例、NaN-boxing例外。必须通过TestFloat/SoftFloat算术对照、Spike逐退休和F/D架构测试；流水必须覆盖2R源捕获、任意项转发、bank/单写口冲突、队列环回、冲刷和双beat异常，详见fpu-testplan。

## 9. 待定事项

| ID | 事项及推荐初值 | 定稿时机 |
|---|---|---|
| F01 | F默认读口推荐3（协调者评审建议），FD默认2、满配3；F队列8/FD16 | FP RF/集成任务前，协调者确认资源与负载收益 |
| F02 | FS复位Off、写架构FP状态/flags/frm置Dirty及SD生成细则 | 特权CSR任务前，按架构状态转移逐项冻结 |
| F03 | 延迟/II及读捕获时序：S5/7/8、D6/18/20、DIV/SQRT19/35、D II4 | FP32探针后暂定，D探针/RTL逐拍验证后定稿 |
| F04 | 自然对齐、两beat第二拍错误/跨行store：推荐S4B/D8B，已完成总线副作用不回滚，单指令退休 | LSU/FPU并行实现前，与CPU C05共同冻结 |
| F05 | 最终端口、年龄/取消tag环回、完成bank仲裁与本地捕获 | 后端/FPU/验证任务前；端口与周期模型一致 |
| F06 | 资源、技术包装几何和FPGA/ASIC乘法宏契约 | PDS探针和综合后，以实际打包替换估算 |

## 10. 变更记录

| 日期 | 版本 | 变更/依据 |
|---|---|---|
| 2026-11-27 | v0.1-draft | 依据C2-F2第二版和C2-I接口起草；F默认3R按协调者建议列待定；保留舍入非法行为经协调者ask确认 |
