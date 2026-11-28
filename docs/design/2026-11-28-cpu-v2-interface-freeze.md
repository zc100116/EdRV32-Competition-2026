# CPU v2 / FPU 接口冻结提案（S01-D）

## 背景和问题

CPU/FPU v0.1 草稿仍缺并行 RTL 所需的端口和逐拍契约。本记录提出 C01–C09、F01/F02/F04/F05、T02/T03、FT01/FT03 的推荐条文，**不是规格修改或用户确认记录**。C10、F03/F06 的实测定稿不在本任务内；C11 已确认采用 `rtl/cpu2/`、`edrv32_cpu2_*` 和 `rtl/cpu2/fpu/`。

阅读基线为 `cb103bd2b2289a730dfdd1b162e0195ac38fe48c`；依据 CPU/FPU spec v0.1、两 testplan v0.1、cpu-spec v0.23、cache-spec v0.14、SoC 4.1/4.3，及 2026-11-27 architecture 第四轮、FPU 第二版、probes 设计记录。卡110第3轮（源码 `aafe7b7eb`，整数RTL `fd048ddf3`、FMA RTL `8344727fc`）在6.061ns约束下得到168.4/179.2MHz，见 `docs/reports/2026-11-28-timing-cpu2-probes.md`，原始报告在卡110的 `artifacts/{int,fma}/`。探针没有证明整核、miss 控制或 FD 时序。

性能比较均引用已有模型，未重新运行负载，也不当作 RTL 测量。整数模型输入/预算提交 `1a26a7924`，复现：`python3 tools/cpu/eval/run_v2_round4.py coremark`（vision/render 同理），`python3 tools/cpu/eval/v2_round4_estimates.py`；输入在 `build/v017/input/`，Zba 在 `build/cpu-v2/isa/zba/`。FP 数字来自 FPU 设计记录“接口端口和队列深度”表；复现 `python3 tools/cpu/eval/fpu_eval.py measure`（先按该记录第3节 `run` 准备 GCC15.2 ELF/Spike trace），结果 `build/c2f/results.json`。本记录新增的结构/周期推导均注明“估算”和公式。

## 约束

只新增本记录；正式 spec/testplan/plan、RTL 和公共头文件由协调者在用户确认后修改。端口只承载既有规格功能；不增加超时、重试、校验、非法状态标志或检查门禁。异常仅沿 CPU/FPU 第6节和 cache 第6节，验证断言只放 verif。

所有模块同属 clk_sys，均有 `clk_i`、`rst_n_i` 各1位；控制异步复位、本域同步释放，数据 RAM/流水数据不复位。无新增 CDC。下文所有“必须”均是**拟写入规格的条文**。端口后缀表示各自模块方向，连线保持词干；表中 `a/b` 是分别列出的信号，不能实现为含糊的总线包。

## 可选方案

### C01：参数组合和配对矩阵

按推荐值冻结，但必须与第四轮模型一致。第四轮所有主档都用模型变体 `V3s`（`tools/cpu/eval/run_v2_round4.py` 第 81 行），即旧核 v0.16 起的"程序槽 / 执行管线分离、可互换"规则。下面的条文按 `pipe_model.py` 第 783–830 行转录，**不另行收紧**（协调者审核更正：S01-D 初稿把 LSU/DIV/FP/CSR 限定为只能在程序槽 0、禁止互换，这会使年轻 load/store 永远不能与较老 ALU 配对；旧核卡 40 中类型配对失败就占 31.4% 周期，与模型口径不符）。

术语：**槽**表示程序顺序（槽 0 老、槽 1 年轻），**管线**表示执行位置（管线 0、管线 1）。退休、异常、中断、冲刷、WAW 都按槽判定，与所在管线无关。拟替换 CPU 2.3 第二段及"具体类型配对矩阵…待定"：

| 管线 | 可执行的类型 |
|---|---|
| 管线 0 | 全部：A 早整数 ALU（含移位、Zba）、B 条件分支/JAL、J JALR、L 整数 LSU、M MUL、D DIV、P FP 算术/转换/FP 访存、S CSR/系统/FENCE |
| 管线 1 | A、B；MUL_DUAL_SLOT=1 时加 M，JALR_DUAL_SLOT=1 时加 J（共享单元从两个管线按年龄选输入，不增加单元） |

两条指令可以同组发射，当且仅当：
1. 存在一种分配，使其中一条进入管线 1、另一条进入管线 0。槽 1 能由管线 1 执行时，槽 0→管线 0、槽 1→管线 1；否则若槽 0 能由管线 1 执行，两条互换（槽 0→管线 1、槽 1→管线 0）。
2. 每组至多一条控制转移（B/J）、一条 LSU、一条 MUL、一条 DIV、一条 P。
3. S 类两个方向都不配对。P 只能与 A 同组（FPU 5.1："槽 0 承接 FP，槽 1 只配独立整数 ALU"改为"P 进管线 0，另一条只能是 A"）。
4. RAW：槽 1 的源等于槽 0 的目的（x0 除外）时不配对，CPU 5.3 列出的早 ALU/实际短 load→晚简单 ALU/条件分支例外；FP 组内相关不配对。WAW 可配，年轻写生效；WAR 不阻塞。
5. 槽 1 可以产生异常，槽 0 照常提交（旧核 v0.16 4.5）。

参数合法组合：ISSUE_WIDTH=1 时 LATE_EXECUTE、MUL_DUAL_SLOT、JALR_DUAL_SLOT、IF_DUAL_BANK 必须为 0；NONE 时 COMPLETION_DEPTH 固定 4、FMA_READ_PORTS 不适用；TAGE 几何仅 BP_KIND=TAGE 有效。合法组合的验证范围见 T02。

验证：CV02 按"类型对 × 两种管线分配 × RAW/WAW/WAR/x0 × 参数开关"枚举，并检查互换后的退休、异常、WAW 仍按槽。

### C02：元数据初始化、失效和维护

按推荐值冻结。替换 CPU5.5“元数据失效机制…待定”及维护末句：两路同拍扫描512组；复位释放后第1至512个上升沿清各组valid/dirty/LRU，随后接受阵列请求；I/D并行扫描，数据不复位。I$整失效用相同512组扫描，末组清除后给done，不再继承旧I$一拍失效。失效期间重叠填充收完、不置有效；取消只抑制结果回送。

组段固定16组，共32个脏标志；维护开始前排空写缓冲。范围扫描次数 `min(ceil((addr+size)/32)-floor(addr/32),512)`，两路并查，OP_SIZE=0仅命令1–3立即完成。无写回范围周期预算估算为访问组数+8，全clean干净预算为32+8；这些是开发日程预算，不能冒充已测上限。BUSY/done才是完成依据，写回附加拍数等 L1 仿真后记录。

选项“保留FF有效位一拍失效”违反草稿RAM元数据方向，不作为本版分支。512拍失效相对旧1拍增加511拍（估算150MHz为511/150=3.407μs），换掉I$1024有效FF和两侧LRU的FF阵列；实际LUT差额须综合。扫描增加验证时间，避免全阵列复位扇出。

### C03：外部总线

按推荐值冻结：完全不改旧cache的外部AXI64/APB协议、寄存器和PMA，CPU3.1替换“若必须变动…”为“外部逐信号按本记录决策表转录，行为沿SoC4.1/4.3和cache2.3/4/5.3/5.4/6”。双bank跨行仅在内部拆成两行查询，miss串行，外部仍每侧一个miss、每方向一事务。

逐信号差异为**无**。APB槽内 `apb_paddr_i` 是12位，CPU3.1概括“地址/数据32”应改成“槽内地址12/数据32”，遵循该段已指定的SoC4.3；不是把系统地址扩展到cache端口。该12位解释已经协调者本次ask确认，仅作为提案口径，不代表用户已批准改规格。无需协议选型比较或新错误信号。

### C04：HPM、debug 和退休观察

按推荐值冻结。替换 CPU3.1 debug 行、4.1末句；增补 CPU8 的验证观察表。事件0–16编码/一拍延迟及5>6>7>8优先级沿旧核7.1；事件1/2/3是双/单/零退休周期，4是退休控制条数；5–8只在老槽发射、年轻未发射时计；9最老ID因load源未就绪，10最老ID因DIV源/入口或提交头DIV事务未完成而等待（每拍布尔OR一次），11不可撤销设备事务等待，12可发射但IB空，13/14每次I/D miss分配，15写回AW握手，16寄存分支/跳转误预测恢复。不把“DIV在后台运行但未阻塞”计入10。

`debug_o` 沿旧核7.2位图；[4:2]改为 `min(IB驻留数,7)`，[11:12]改为两条退休valid，[13]ID局部等待，[14]提交头访存等待，[16]EX/MEM解析的寄存重定向，[17]F2纠正，其余同义字段保持，保留[31:30]=0。该截断只用于观察，不影响信用。

trace按决策接口表定义为顶层内部 `_w` 信号，不加外部端口、构建宏或调试模式。宽化到64位结果并增加目的域、flags、CSR和访存记录，使Spike可以观察D结果、无rd项和第二beat错误。资源只涉及验证观察连线；综合未使用的内部观察不要求保留。准确日程比模糊“整核停顿”更易核对，无额外性能开关。

### C05：核内握手、年龄和 LSU 关联

需要选取可并行实现的年龄表示。方案A为T位槽号+共享head相对序（推荐）；方案B为T+1位含epoch序号。A保持CPU3.2/FPU3.1的T位端口；B每条在途记录多1位、每结果/取消链也多1位，仍必须正确清除取消valid，不能单靠epoch解决无限迟返。两者正常命中吞吐相同；A需验证满队列/环回/同拍取消，B多验证epoch翻转，均无已测频率差。

拟替换 CPU3.2/3.3 待定及5.2重放末句、5.6双beat末句：采用决策节端口，T=log2(N)，按分配序mod N；head相对距离判断年龄，取消边界包含自身，接收边沿原子清除所有年轻valid。取消后的执行/完成源不得再回送旧tag；D$/I$在内部保存取消状态直到已有AXI收完，外部ID不携带tag。无tag未清的结果源和新实例同名共存；不增加epoch端口、超时或迟返错误标志。

短load提前查询与实际发射在同沿关联；查询未随发射则丢弃。实际普通请求若未紧接下一拍接受，不得使用旧early结果。early失败仅使这条load走普通路径；同组已发射的晚消费者留在本地MEM操作数等待位，等生产tag真实完成后继续，不重发/重复分配load、不冲刷无关整数。hit不组合反馈ID；早返回先本地捕获，再供下一拍消费者。吞吐预算每拍一个D$读口，提前与普通共享它，不复制D$。

### C06：RF/cache 技术宏

按推荐值冻结。替换 CPU5.2宏待定句，几何见决策节。FPGA异步RF包装使用现有 `edrv32_ram_cpu2_rf`（32×32，异步读1R1W），双发射两owner×四读副本，额外AGU路径只复制RF读副本；不复制D$。现有探针 `cache_data` 为2048×32、`cache_tag` 为512×19，仅是取指/查询起点，D$ dirty必须扩为20且不能照搬探针缺失的控制。

ASIC交付等延迟1R1W复制宏接口，32×32异步RF或原生4R2W等价宏；命名为 `edrv32_cpu2_asic_rf`、`edrv32_cpu2_asic_cache_data`、`edrv32_cpu2_asic_cache_tag` 的集成适配目标，不声称已有工艺库单元。工艺库具体cell名须在实际ASIC移植时绑定，不能现在编造。宏必须维持读延迟/字节写使能/年轻写优先和显式WB转发，不能偷偷改成同步RF。

异步RF双发射8192数据bit、小配置2048bit，公式分别2×4×32×32、2×32×32；资源/时序采用已测探针边界，未测ASIC不作频率结论。接口无实际取舍，FP乘法宏F06仍留后续。

### C07：DIV完整日程

需要决定模型hold与真实结果延迟的对应。方案A最后迭代合并符号修正，方案B独立修正拍（推荐）。A少1拍但把符号加减和商/余选择放入迭代末段；B复用固定修正级、增加一组32位结果控制寄存，验证日程统一，未测不报LUT或频率收益。

拟替换 CPU5.4 DIV完整延迟句：接受沿E0；E1幅值/位数差，E2对齐/初始化；E3起每拍迭代一轮，n=k或ceil(k/2)，k=max(0,bitlen(|a|)-bitlen(|b|)+1)；E(3+n)符号修正并捕获完成。正常本地结果延迟L=3+n，II=L（无完成反压时）；k=0也经过E3修正。除零/有符号溢出在E1分类，E2交付架构结果，L=2。完成反压只延后交付，不重复计算。

估算k=32时radix2为35拍、radix4为19拍；相对原模型含EX的2+n口径增加1拍，不可继续引用旧整程序周期为新实现保证。每条普通DIV若修正不能被独立指令遮蔽，周期增加上界为1，负载增量≤普通DIV条数；精确值待I03回放。板级仍选RADIX4_EARLY，不重新讨论已列配置值。

### C08：TAGE编码和更新

按推荐值冻结，替换 CPU5.4 最后一处编码/折叠待定；直接转录 `tools/cpu/eval/v2_round4_structures.py::RamTage` 的行为，不扩展预测算法。令w=log2(entries)，fold_w为所有w位分段XOR，h为该表截取历史；index=((pc>>2)^fold_w(h))&(E-1)，tag=((pc>>(w+2))^fold_10(h)^fold_9(h>>1))&1023，base=(pc>>2)&4095。

行编码 `{valid,tag[9:0],counter[2:0],usefulness[1:0]}`；初始invalid/counter0/u0，base/fast为01；软复位清历史/查询valid，方向RAM不并行复位，沿旧核上电初始化规则。最长匹配provider，次长alternate，无匹配用base；counter≥4预测taken，base≥2预测taken。provider从0表示base、1..K表示短到长表。

训练用D预读的当前行和同址老更新旁路；base饱和2bit更新，provider当前tag仍匹配才饱和3bit更新；仅预测与alternate不同才按预测正确与否增/减u。误预测按provider之后短到长查找，第一个invalid或u0项分配，counter=taken?4:3、u0；此前遇到的忙项u减1，最多分配一项。过滤历史只推进存活且有F1 token的条件分支，fast按全部解析条件分支。

MEM老、EX年轻同拍更新，单待写bundle吸收冲突，预测/训练读旁路待写及同沿写；不额外停顿。长折叠注册、F1命中注册，F2末级合并；额外副本资源已在第四轮估算，卡110验证满配4×512边界，其他几何须参数回归。

### C09：提交头中断和长操作取消

按推荐值冻结。替换 CPU6.2 末句：每拍在提交头、任何该拍架构副作用前采样；最老同步异常优先，随后按MEIP>MSIP>MTIP优先序及既有mie/MIE规则选择中断。接收中断当拍退休数0，mepc为最老未退休PC；空队列用下一应执行PC。无中断则老到年轻检查，老正常、年轻异常时仅老项退休。

提交头DIV从接受至本条退休作为不可中断事务；已授权设备、FENCE.I和D双beat从开始至结束也不可切开。普通FP长算术可在头未完成时被中断取消；更老不可中断事务存在时先完成它。年轻DIV/FP可由更老异常/分支冲刷取消，不以DIV不可中断为理由保留错路。WFI退休后停取指，任一mie允许的pending唤醒，MIE决定是否进陷阱。

分支恢复保留分支自身和更老项；陷阱取消故障/待执行头及年轻项。所有取消按C05广播，结果/flags/未授权store同时无效。不能等待D$ ready才发出注册重定向。无新中断窗口或预算取舍，验证须覆盖取消先于、同拍及晚于完成。

### F01：FP读口和完成深度

存在实际面积/吞吐取舍，推荐F默认3R/N8，FD默认2R/N16，满配FP可3R，保留全部2×2组合。拟替换 FPU2.4推荐列和CPU2.2/板级初值：F=3/8、FD=2/16，NONE=4；板级满配整数+F固定3/8。

2R先捕获两源次拍rs3，连续FMA入口II≥2；3R本体II可1，不增加整数写口。已有模型F matrix_s 39025→34929，收益估算(39025−34929)/39025=10.50%；vertex_s 16601→15449=6.94%，physics_s 121958→112742=7.56%。F3R相对2R增加3B=96 LUTRAM（源RF+两bank结果副本），逻辑bit加(32+N)B=1280，FF/APM不增；多一源选择路径需参数时序确认。

FD队列8→16，whetstone_d 154474→151235，减2.10%，matrix_d无变化88693；增112 LUT/176 FF（FPU7.2结构估算）。FD2R→3R加192 LUTRAM、N16时3072逻辑bit，matrix_d 88693→84597减4.62%。FD默认2R控制资源，N16给一般计算窗口；F默认3R是对旧设计记录2R默认建议的明确更新，以当前spec推荐为准。验证覆盖2R捕获/环回与3R多源，不能减少合法组合。

### F02：FS/Dirty/SD和FP CSR

按推荐值冻结。替换 FPU4表 FS待定行、4.2及CPU4.2 mstatus行：含F/FD复位FS=Off(00)，Initial=01/Clean=10/Dirty=11，SD=(FS==11)；SD只读。NONE的FS/SD读0写忽略、FP CSR非法。FS=Off时FP指令（含访存/搬移）和FP CSR访问均非法，mtval=指令。

仅在提交时：任何FP目的寄存器写（包括FLW/FLD/FMV）置Dirty；FP指令flags非0所致fflags写置Dirty；对fflags/frm/fcsr的实际CSR写访问置Dirty，即使写回相同值。只读CSR（CSRRS/RC零源）、FSW/FSD、无flags的整数目的比较/转换/分类不置Dirty。取消项无效；FP RF数据不复位，不以FS=Initial偷偷清空寄存器。

软件写mstatus.FS按2bit原值保存（含主动置Clean/Initial/Off），同拍陷阱优先沿CPU CSR规则；写fcsr三别名有序、flags OR与CSR显式写按指令年龄依次作用。所有CSR/系统单发并等待更老完成，动态rm在FP源接受前采样已生效frm；保留frm原样保存，使用非法编码时才陷阱。验证逐个触发Dirty并检查无写/取消保持。

### F04：自然对齐和两beat错误

按推荐值冻结。替换 FPU5.5两处待定及CPU5.6末句：S必须4B对齐，D必须8B对齐，不对齐在任何beat发出前报告cause4/6、mtval原地址；两beat低字后高字，共一个tag。FLD仅两字成功才完成64位结果；任一错误无FP寄存器/flags写回。第二beat访问错误cause5/7，mepc本条PC、mtval故障beat地址（原地址+4）。

可缓存FSD先完成两beat的地址/tag准备，再在不可撤销头依次写缓冲；设备/不可缓存从头授权后依次发单拍，低beat失败不发高beat。高beat失败不能撤销已完成低beat总线或存储副作用，不退休本条/年轻项，但明确允许部分存储；不得声称精确退休等于外部回滚。两个成功响应后才退休一次；两beat之间不退休年轻项/不响应中断。

自然对齐8B且行32B时 `(addr mod32)∈{0,8,16,24}`，高字偏移≤28，因此本版**不存在合法D指令跨cache行**，也不跨4KiB/PMA自然边界；行尾24/28必须覆盖。跨行双bank取指仍按C03；不为不可达FD跨行引入额外硬件。若未来改成4B对齐D，必须另提规格变更才讨论跨行store。

### F05：FPU最终端口及完成仲裁

按推荐值冻结，替换 FPU3.1“最终拼写”及5.4取消末句；CPU3.2引用同一表。外部FPU端口保留T位tag、原始instr、B位三源、int_src/rm以及每条flags，不另加异常通道。非法指令/精度/FS/rm由整数译码/CSR在进入FPU前形成CPU异常完成项，算术只返回结果/flags。

两个完成bank以tag[0]选，bank单写；每拍最多单FP目的结果捕获。所有源包括无rd branch/store都参与PC写仲裁；同bank先老后年轻，年轻在各单元本地valid保持到ready。不同bank若都为FP结果也只能接受老FP项；整数目的FP结果占槽0整数写路径，整数槽1写口保留。任意项转发本地捕获，结果副本按本节后述位段公式、PC每bank一份，不串深异步读到EX。

取消沿清pipeline/local valid；同拍结果接收与取消冲突，取消范围内不记完成。3R捕获三源后一次req握手，2R捕获rs3完成后才req握手，第二拍不再发送不完整请求；未读rs3时记分牌保留源版本/目的保留，后继独立整数可按序发射。源捕获额外拍只计一次，F03日程仍未定稿。

本次ask协调者明确修正R+1的域口径：源读端口不分域，整数双槽最多4源，FP槽0加整数槽1最多R+2源，故S=max(2I,R+2(I−1))，双发射为max(4,R+2)；低32位结果复制S+1份，高32位仅FD复制R+1份，各bank另有一份PC。2R补rs3拍最多1+2=3源；FSW/FSD为整数地址1+FP数据1+槽1整数2=4源，FCVT整数→FP为1+2=3源，FP→整数为1+2=3源，均不超过S。晚等待在完成/WB捕获，不增加异步读口。

拟同步替换CPU5.6/FPU5.4的“R+1份读取副本”句，FPU7.2资源表标旧口径待F06替换。估算物理LUTRAM（每bank每副本每数据bit一单元、单元容量64bit）为RF=R×B，队列=2×[32(S+1)+32×1_FD(R+1)+32]；逻辑bit为RF的32RB加队列N×同一括号。F/3R/N8：S5，RF96+队列448=544 LUTRAM，逻辑3072+1792=4864bit；FD/2R/N16：S4，RF128+队列576=704 LUTRAM，逻辑4096+4608=8704bit。均比原FPU7.2对应行多128 LUTRAM，逻辑分别多512/1024bit；不声称实测资源或重新批准F06。

### T02：合法参数矩阵和随机预算

需要选全部合法组合还是抽样组合。推荐全合法组合编译+规定短例，三主档完整架构回归；非主档每组合10固定种子，代价是full运行长，但不把合法参数变成未验证声明。替代方案仅两两覆盖能缩短运行，无法保证多选项交叉（如双bank/晚执行/TAGE）已验证，不推荐。

拟替换 CPU testplan6参数段、7的T02：按C01枚举，失效参数不重复构建；三主档NONE及三主档×F/FD×2R/3R×N8/16共27个主档点跑完整架构/集成回归。BP=GSHARE时忽略TAGE几何，NONE忽略FP参数。其余每点跑lint/CV02–CV09及CSR/异常短例，seed=0..9，每seed至少10000条退休（被陷阱终止后用下一定向段继续完成预算），长随机另纳full；覆盖目标仍须全部达到。

估算按当前正交值：方向几何为GSHARE2种+TAGE的fast容量2×表数3×表项4=26，其他BTB3×RAS2×IB3×DIV2×HPM3×Zba2=648，故单发射16848个整数结构；双发射再乘四个二值选项16得269568，总286416。每个整数结构有NONE1+F/FD×R2×N2=9，合2577744构建点；非主档随机至少(2577744−27)×10×10000=257771700000条退休。此为明确成本公式，不是已运行结果，协调者应据此向用户确认全矩阵预算或另提裁剪合法参数，不能静默用pairwise替代。

### T03：CPU独立验证观察字段

按推荐值冻结，替换 CPU testplan2退休接口末句和7的T03：观察本记录trace表、宏表、取消/提交/LSU/维护接口；定向时序以握手沿计，取消边沿优先、错路无副作用。CV04验提前失败本地等待而非重复load，CV06验C07完整L，CV07按C08独立状态模型，CV08逐字错误/信用，CV09满队列环回与bank碰撞，CV10/14按C09中断不可分割边界。

CV11/12检查扫描512沿、done/BUSY、写回错误沿既有APB路径，CV13采用F02/F04。层次化trace仅验证内部线，不升级外部IP端口；不以读取RTL内存或算式生成期望值。C10/perf阈值仍待后续，不在此预造数值。

### FT01：数值参考版本和随机预算

按推荐值冻结。拟替换 FPU testplan4参考版本/7的FT01：SoftFloat Release3e、TestFloat Release3e（TestFloat3系列对应版），以实际导入的上游commit记录版本，不现在编造仓库尚未存在的commit。full用testfloat_gen level2，针对每个已实现opcode/精度/适用五舍入逐条比对结果和每条flags；RMM、NaN、tininess-after-rounding按RISC-V包装处理，搬移/boxing/非法编码用定向位模型及Spike。

每类操作固定边界向量全部运行，序列随机seed=0..9，每seed至少10000条操作，全部8个F/FD×R×N组合均跑，非适用D指令在F配置检查非法。种子/输入/版本写测试日志；这只是有限预算不声称穷举浮点空间。厂商IP版本由实际Windows任务卡给定，算术正确性不依赖其近似模型。

### FT03：FS、双beat、端口与PDS期望

按推荐值冻结当前可决定部分。替换 FPU testplan7 FT03：FV10–15使用F02 FS逐事件转换、F04每beat错误/副作用、F05取消/仲裁和决策端口表；FV14覆盖低错、高错、每beat反压、中断等待、FD行尾24/28，未对齐在发总线前报错。无需制造合法8B对齐D跨行激励。

PDS必须列全部setup/hold WNS/TNS/WHS/THS、资源和宏等价，不能把探针达标写成整核通过；F03/F06及C10尚未批准的延迟/II/资源/频率接受数值仍明确待定，后续相应任务前补入testplan。这里冻结的是观察/报告字段，不替这些未测事项定稿。

## 决策

下列均为推荐接口清单；经协调者审核及用户确认后才转录成规格。`I=ISSUE_WIDTH`，`N=COMPLETION_DEPTH`，`T=log2(N)`（N4/8/16时2/3/4），`B=FLEN`，`R=FMA_READ_PORTS`，含FP时`S=max(2I,R+2(I−1))`（NONE为2I），`K=TAGE_TABLES`，`W=log2(TAGE_ENTRIES)`，`Q=ceil(log2(IB_DEPTH+5))`。多槽字段用独立标量端口 `...0_...`、`...1_...`，避免搬运大于256位的整体记录；表中的 `{j}`/`{p}` 是逐端口展开规则，非运行时索引。

### 模块划分

下表文件均以 `.v` 结尾；CPU根为 `rtl/cpu2/`，FP根为 `rtl/cpu2/fpu/`。全部clk_sys，不引入其他域；包装位于rtl/tech，表中既有名字表示保留、其他表示拟新增，不承诺本任务已有RTL。

| 文件/模块（省略.v） | 职责和规格条款 |
|---|---|
| edrv32_cpu2_top | 外部AXI/APB/IRQ、模块连线；CPU1/3/4.3 |
| edrv32_cpu2_frontend | F1/F2 PC、重定向、双bank/RAS恢复；CPU5.1/5.5 |
| edrv32_cpu2_predictor | fast gshare/BTB/RAS；CPU5.4/5.5 |
| edrv32_cpu2_tage / edrv32_cpu2_tage_update | TAGE查询/训练/待写；CPU5.4/C08；既有探针需参数化为规格合法几何 |
| edrv32_cpu2_fetch | I$物理bank拼合/owner候选；CPU5.2/5.5；既有探针拆出IB职责 |
| edrv32_cpu2_ib | 固定双头、在途信用和候选维护；CPU5.2/5.5 |
| edrv32_cpu2_decode / edrv32_cpu2_issue | 译码、配对/整数及FP记分牌、源捕获；CPU2/5.1–5.3/5.6 |
| edrv32_cpu2_rf / edrv32_cpu2_id_agu | 异步RF/LVT、ID提前地址；CPU5.2；既有 |
| edrv32_cpu2_alu / edrv32_cpu2_branch | 两槽EX/MEM简单执行、分支/JALR；CPU5.2/5.3/6.1 |
| edrv32_cpu2_mul / edrv32_cpu2_div | 单MUL/单DIV及本地完成保持；CPU5.4/C07 |
| edrv32_cpu2_completion / edrv32_cpu2_commit | 全核完成记录、转发、年龄取消/按序退休；CPU5.1/5.6/6 |
| edrv32_cpu2_csr | 整数/FP CSR、HPM、中断/WFI；CPU4/6，FPU4/F02 |
| edrv32_cpu2_lsu | 单LSU、提前关联、存储提交/FD双beat；CPU5.2/5.5/5.6，FPU5.5 |
| edrv32_cpu2_icache / edrv32_cpu2_dcache | RAM数据/元数据、PMA/miss/写缓冲；CPU5.5/6.4 |
| edrv32_cpu2_cache_ctrl | APB维护/错误中断；CPU4.3、cache4/5.4/6 |
| edrv32_cpu2_fpu_top / edrv32_cpu2_fpu_rf | FP路由/源读取、单FP架构写；FPU3/5.1/5.4 |
| edrv32_cpu2_fpu_fma32 / edrv32_cpu2_fpu_fma64 | 各精度ADD/MUL/FMA和共享尾端；FPU2.4/5.2；32已有探针 |
| edrv32_cpu2_fpu_divsqrt | 独立基4S/D迭代入口；FPU5.2/5.3 |
| edrv32_cpu2_fpu_convert / edrv32_cpu2_fpu_short | 转换、比较/最值/分类/符号/搬移；FPU2.1–2.3 |
| edrv32_cpu2_fpu_lz24 / edrv32_cpu2_fpu_lza32 | 既有32位FMA辅助；FPU5.2；D辅助按实际数据通路另定，不预留空模块 |

### 通用握手与年龄

下表中 `execute{j}`、`alu{j}_complete`、MEM 等待位的 j 指**执行管线**（C01）；`allocate{j}`、`head{j}`、`wb{j}`、`fetch_push{j}`、`ib_head{j}` 的 j 指**程序槽**。issue 在发射沿按 C01 规则把程序槽映射到管线，并把各自的完成 tag 随指令带到管线，退休和取消只按 tag 年龄判定。

表中方向A→B表示A端 `_o`/B端同词干 `_i`；反向亦然。凡valid/ready接口，posedge `valid&&ready`接受一次，等待保持valid/全部负载，只有取消可撤销尚未接受项；ready来自已寄存容量，ID只用寄存credit。固定延迟查询无ready时，由调用者预留接收槽。独立完成源各自一套接口，不能用共享valid隐含多源丢弃。

完成tag按程序顺序分配，双发射tag1=(tag0+1)modN；不为x0、branch、store省略记录。`age_head`是本拍开始最老存活tag，距离d=(tag−head)modN，只比较valid项，满N时用占用数区分满/空，不能用裸tag大小或半环比较。退休只释放连续队头。取消 `cancel_tag` 是首个取消项，清d≥d(cancel_tag)的存活项；分支取消从分支后第一存活tag开始，空年轻区不发cancel；陷阱/中断从故障/未退休头开始。head/cancel广播同沿生效，不额外打一拍再修正。

取消沿内所有生产者清被取消valid、包括已完成未交付结果与FP flags，禁止再次输出该实例；队列恢复tail后下一拍可重用tag。已发AXI必须收完，cache自行抑制取消结果，不让旧响应贴到新tag；不要求AXI可撤销。取消同拍响应可保持valid，接收方按年龄丢弃（不组合屏蔽响应形成环）。没有取消ack、epoch、检查错误位。前端未分配完成tag，以有序请求上下文关联I$；重定向清所有未发射项并使在途上下文无效，credit按撤销预留归还。

### 前端、IB、发射与预测器

每条IB记录保存PC/指令/取指异常/owner候选和预测token；K表字段按表分别传递，不能把长历史原样塞入IB。RAS快照采用完整RAS内容 `32×RAS_DEPTH` bit与指针 `log2(RAS_DEPTH)` bit、计数 `log2(RAS_DEPTH+1)` bit，分字段保存；两个字从同一原快照按程序顺序应用call/return，F2纠正重新应用保留前缀动作。

| 信号词干（加方向后缀） | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| fetch_push_valid / fetch_push_ready | fetch→IB / IB→fetch | 各1 | 整组入队；信用预留后返回必能存入 |
| fetch_push_count | fetch→IB | 2 | 1/2条；老taken只保留前缀 |
| fetch_push{j}_pc / instr | fetch→IB | 各32 | j=0,1，程序顺序 |
| fetch_push{j}_error | fetch→IB | 1 | 该字访问错误，后继不覆盖老字异常 |
| fetch_push{j}_candidates | fetch→IB | 5 | 两物理路的rs1/rs2 owner各2bit+bank选择1bit |
| fetch_push{j}_predict_taken / predict_target / predict_token | fetch→IB | 1/32/1 | 方向/目标/有F1查询token |
| fetch_push{j}_predict_provider / predict_alternate | fetch→IB | 3/1 | 0为base，1..K最长表 |
| fetch_push{j}_predict_index{p} / predict_tag{p} | fetch→IB | W/10 | p=0..K−1，查询时快照 |
| fetch_push{j}_predict_base_index / predict_fast_index | fetch→IB | 12/log2(GSHARE_ENTRIES) | 后续训练关联 |
| fetch_push{j}_ras_data / ras_ptr / ras_count | fetch→IB | 32×RAS_DEPTH / log2深度 / log2(深度+1) | 发射后只由控制指令携带快照 |
| ib_head{j}_valid | IB→decode/issue | 1 | 固定双头，无ready组合回IF |
| ib_head{j}_各字段 | IB→decode/issue | 同上逐字段 | 词干由fetch_push替换ib_head，读头不弹出 |
| ib_remove_count | issue→IB | 2 | 当沿实际分配/执行接受的连续老前缀0..I |
| ib_credit | IB→frontend | Q | IB_DEPTH+4物理条目减驻留/在途预留，寄存值 |
| frontend_flush | commit/branch→frontend/IB | 1 | 清未发射及在途上下文；重定向优先于入队 |
| redirect_valid / redirect_pc | commit/branch→frontend | 1/32 | 注册恢复PC，按最老有效重定向选择 |
| redirect_tag / age_head | completion→branch/commit | T/T | 比较已发射重定向年龄 |
| predict_req_valid / predict_req_pc | frontend→predictor/TAGE | 1/32 | F1双字查询，预留F2容量，无ready |
| predict_resp_valid / predict_resp{j}_各predict字段 | predictor/TAGE→fetch | 1/同上 | 固定F2，按原请求对应，不受本拍ID推进影响 |
| predict_train_valid / tag / pc / taken / target / type | branch→predictor | 1/T/32/1/32/3 | 类型0条件、1JAL、2JALR、3call、4return、5先pop再push；由指令链接寄存器关系译码 |
| predict_train_token / provider / alternate / index{p} / tag{p} / base_index / fast_index | branch→TAGE | 同上述token字段 | 另有predict_train_prediction 1位；EX/MEM各一组，MEM老；取消项不训练 |

预测快照在发射至branch时按上述字段原样传递；BTB valid、位置、目标由predictor持有。IB候选更新直接侦听下表的提交WB，WB1覆盖WB0；新入项和移动前存活项同沿修正。单发射无LVT，候选接口不实例化。

### RF、分配、源转发与执行

| 信号词干 | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| id_rs{p} / id_owner{p} / id_data{p} | issue→RF / issue→RF / RF→issue | 5/1/32 | p=0..2I−1，异步读，本地捕获；单发射无owner |
| lvt | RF→fetch/IB | 31 | x1..31 owner，沿现有探针；区域复制不延迟 |
| wb{j}_valid / rd / data | commit→RF/fetch/IB | 1/5/32 | 当沿架构写，j0老j1年轻，x0不写 |
| fp_read{p}_addr / fp_read{p}_data | issue→FP RF / FP RF→issue | 5/B | p=0..R−1，异步读、本地捕获，f0可写 |
| fp_wb_valid / rd / data | commit→FP RF | 1/5/B | 单写，当沿按序提交 |
| allocate_credit | completion→issue | log2(N+1) | 寄存空项信用，本拍提交不组合馈入 |
| allocate_valid / allocate_count / allocate_ready | issue→completion / issue→completion / completion→issue | 1/2/1 | 0..I项连续分配，原子对应执行接受；不足只发老项 |
| allocate{j}_tag / pc / instr / rd / dest | issue→completion | T/32/32/5/2 | dest0无、1整数、2FP；存储/branch无rd但保留PC |
| allocate{j}_csr_src | issue→completion | 32 | CSR源在发射沿捕获并随头项交给commit，其他类型忽略 |
| allocate{j}_store / divide / double_beat | issue→completion | 各1 | 提交不可分割边界类别 |
| source{p}_tag / source{p}_valid | issue→completion | T/1 | 源记分牌指定最新未提交生产项 |
| source{p}_ready / source{p}_data | completion→issue | 1/B（整数用低32） | 已完成任意项；本地捕获，不异步串EX |
| execute{j}_valid / execute{j}_ready | issue→ALU/branch / 单元→issue | 各1 | 每槽独立，本地入口可用信用 |
| execute{j}_tag / pc / instr | issue→单元 | T/32/32 | 原始编码作操作控制，不另造opcode宽度 |
| execute{j}_src1 / src2 / imm | issue→单元 | 各32 | 已捕获值/译码立即数 |
| execute{j}_late / source1_tag / source2_tag / source1_wait / source2_wait | issue→单元 | 1/T/T/1/1 | MEM晚执行与真实完成等待，非等待源tag忽略 |
| execute{j}_各predict快照字段 | issue→branch | 同前表 | 方向/目标/RAS与训练token |
| mul_req_valid / ready / tag / instr / src1 / src2 | issue↔MUL | 1/1/T/32/32/32 | valid/tag等输出，ready输入；任一程序槽择老，共享单入口 |
| div_req_valid / ready / tag / instr / src1 / src2 | issue↔DIV | 同上 | 单入口局部忙不冻结其他模块 |
| lsu_req_valid / ready / tag / instr / addr / store_data / early | issue↔LSU | 1/1/T/32/32/B/1 | FP数据按B捕获；普通整数仅低32，单指令入口 |
| early_req_valid / early_req_addr / early_req_tag | ID AGU→LSU | 1/32/T | 只在本沿load实际发射时有效，共用分配tag |
| early_resp_valid / early_resp_tag / early_resp_hit / early_resp_data | LSU→MEM操作数捕获 | 1/T/1/32 | 下一拍本地捕获；hit0不得置生产项完成 |
| age_head / cancel_valid / cancel_tag | completion→全部在途模块 | T/1/T | 通用包含边界取消；RF仅提交写无须取消端口 |

MEM等待位保留 `operand{j}_{p}_tag/valid`（T/1），p=1,2，监听已接受完成源的 `*_complete_tag/data`（T/32），命中就捕获并清wait；进入等待位时已完成源随execute输入捕获，不额外增加队列异步读口。已完成项将退休时，同沿WB数据必须供尚未捕获的等待源使用，不能释放后再按旧tag读。取消沿清等待valid。

源接口物理统一为p=0..S−1，其中S按F05公式；表中source还附 `source{p}_domain` 1位（0整数、1FP），issue按本拍实际源映射到这些端口，不同时暴露额外独立的FP队列读口；记分牌在issue内维护架构域→最新tag，取消后从保留项恢复，不能把旧tag源当成RF版本。2R未读rs3记住生产tag，即使生产者此时退休也必须捕获正确值；不允许年轻同目的FP提前覆盖。

### 完成、提交与 CSR

CSR指令的源和操作编码随allocate登记，commit使用该份已捕获记录。每个ALU、branch、MUL、DIV、LSU、CSR、FP响应有独立完成源，前缀 `alu0_complete`、`alu1_complete`、`branch_complete`、`mul_complete`、`div_complete`、`lsu_complete`、`csr_complete`、`fp_resp`。branch的链接值和PC作为一个完成源，不重复送ALU完成。

| 信号词干 | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| *_complete_valid / *_complete_ready | 单元→completion / 反向 | 各1 | 争用保留本地结果，年龄优先 |
| *_complete_tag / data / flags | 单元→completion | T/B/5 | 整数高位0，非FP flags0 |
| *_complete_exception / cause / tval | 单元→completion | 1/4/32 | 仅CPU6.1已定义同步异常，非法由decode生成同格式独立源 |
| head{j}_valid / done / tag / pc / instr / rd / dest / data / flags | completion→commit | 1/1/T/32/32/5/2/B/5 | 固定两头，data先捕获；j只到I−1 |
| head{j}_exception / cause / tval / store / divide / double_beat / csr_src | completion→commit | 1/4/32/1/1/1/32 | 提交按年龄，不越过未done头 |
| retire_count | commit→completion | 2 | 释放连续头0..I，不能越过单FP写限制 |
| commit_lsu_valid / ready / tag | commit↔LSU | 1/1/T | 头项授权副作用，ready代表LSU已接收授权，不代表已退休 |
| commit_lsu_done_valid / ready / tag / error / fault_addr | LSU↔commit | 1/1/T/1/32 | store/设备/双beat不可撤销事务结束；错误转cause5/7 |
| csr_req_valid / ready / tag / instr / src | issue↔CSR | 1/1/T/32/32 | 单发且先等更老达到有序边界；CSR读结果经完成源 |
| csr_commit_valid / instr / src | commit→CSR | 1/32/32 | 本拍架构CSR写，不再重新读可能变化的源 |
| fp_commit_flags_valid / fp_commit_flags / fp_commit_write | commit→CSR | 1/5/1 | 本拍累计flags；write表示FP目的写；F02置Dirty |
| csr_frm / csr_fs | CSR→issue | 3/2 | 已提交架构值，非法舍入在issue/译码形成异常 |
| irq_meip / irq_msip / irq_mtip / mtime | top→CSR | 1/1/1/64 | 已同步、沿旧外部词干 |
| irq_pending / irq_cause / trap_target | CSR→commit | 1/32/32 | 含MIE/mie判定，优先外部/软件/定时 |
| trap_valid / trap_pc / trap_cause / trap_tval | commit→CSR | 1/32/32/32 | 已决定陷阱，cause含interrupt最高位 |
| counter_retire_count / hpm_event | commit/各模块→CSR | 2/16 | 事件1..16脉冲/计数布尔，控制退休分支数另送hpm_branch_count[1:0] |

普通load完成即done；store准备完成只表示地址/tag已备妥，commit须授权并等done再退休，不能把完成bank写成功当成副作用完成。FP→整数通过dest控制，单FP完成写口按结果目的域判定，整数结果仍使用槽0整数提交写口。

### 核与FPU及其各单元

方向以整数issue/completion为A、FPU为B；逐信号拼写沿现有spec：

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

### LSU、D$和提前查询

| 信号词干 | 方向（LSU为A） | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| dc_req_valid / dc_req_ready | A→D$ / 反向 | 各1 | 请求接受一次，已接受请求不能静默丢弃 |
| dc_req_tag / dc_req_beat | A→D$ | T/1 | 同条FD两beat共tag，beat0/1区分，单beat为0 |
| dc_req_addr / dc_req_store / dc_req_size | A→D$ | 32/1/2 | 字节地址、写、0字节1半字2字；FD拆为size2 |
| dc_req_data / dc_req_mask / dc_req_early | A→D$ | 32/4/1 | 未移位字数据/字节掩码、关联紧前拍early |
| dc_resp_valid / dc_resp_ready | D$→A / 反向 | 各1 | 保留响应直到捕获，下一拍命中 |
| dc_resp_tag / dc_resp_beat | D$→A | T/1 | 请求关联，不用“当前MEM指令”暗指 |
| dc_resp_way_hit / dc_resp_way0_data / dc_resp_way1_data | D$→A | 2/32/32 | 独热路、本地按字节合并写缓冲，特殊返回走way0 |
| dc_resp_error / dc_resp_device | D$→A | 各1 | error仅valid时有效；device为准备响应、尚未发设备事务 |
| dc_commit_valid / dc_commit_ready / dc_commit_tag / dc_commit_beat | A↔D$ | 1/1/T/1 | 头授权后提交指定beat；ready是接收提交，设备还要等最终响应 |
| dc_commit_data / dc_commit_mask | A→D$ | 32/4 | 可缓存store进入写缓冲的数据/掩码 |
| dc_done_valid / dc_done_ready / dc_done_tag / dc_done_beat / dc_done_error / dc_done_data | D$↔A | 1/1/T/1/1/32 | 授权后store/设备真正完成；设备load结果此处交付 |
| dc_cancel_valid / dc_cancel_tag / dc_age_head | A→D$ | 1/T/T | 清未授权项，已有AXI继续收完而不回送旧实例 |
| dc_early_valid / dc_early_addr / dc_early_tag | A→D$ | 1/32/T | 发射沿查询，使用同一物理读口 |
| dc_early_resp_valid / dc_early_resp_tag / dc_early_hit / dc_early_way0_data / dc_early_way1_data | D$→A | 1/T/2/32/32 | 下一拍固定返回，失败hit00，LSU捕获后才供消费者 |
| dc_fence_valid / dc_fence_ready / dc_fence_clean_all | commit→D$ / 反向 / commit→D$ | 各1 | clean_all0排空写缓冲，1全clean |
| dc_fence_done | D$→commit | 1 | 已接受fence完成脉冲，无错误旁路 |
| dc_wb_event / dc_miss_event | D$→CSR | 各1 | 写回AW/新miss事件，非请求等待拍数 |

D$寄存准入需预留同步RAM返回及发现miss后一拍的已接受请求槽；不沿旧核静默丢第二请求。early占用读口时不再接受另一普通读，选择来自已登记的端口预约；其后实际请求 `dc_req_early=1` 时重用捕获结果，失败则普通访问本地顺延。缓存响应device只是准备阶段，LSU不把它当完成数据；提交头授权后才发设备AXI，最终dc_done后才退休。可缓存store直到提交不改架构内存，次拍排空写缓冲；FD若低beat已经排空不回滚。

### 前端与 I$、维护控制

I$请求是一组最多两条指令，内部最多保留两组上下文（同步返回槽+miss后续已接收槽）；IB按每组两条预留信用。双bank跨行两行分别查询，miss串行完成后组装，两字分别保存错误；两组按序响应，没有tag复用歧义；取消只需清全部未发射上下文。

| 信号词干 | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| ic_req_valid / ic_req_ready / ic_req_addr | frontend↔I$ | 1/1/32 | 请求PC，dual0为8B对齐，dual1为4B对齐 |
| ic_resp_valid / ic_resp_ready | I$↔frontend | 各1 | 响应组，本地捕获；不静默丢弃已接受组 |
| ic_resp_word{j}_way{k}_instr / ic_resp_word{j}_way_hit / ic_resp_word{j}_error | I$→fetch | 每路32/2/1 | j=0,1对应PC/PC+4，k=0,1两路未选数据；owner查询在选路前并行，不能先mux指令再查LVT；非缓存返回way0 |
| ic_cancel | frontend→I$ | 1 | 冲刷全部未返回组；AXI收完不回送，取消同拍响应由前端丢弃 |
| ic_inv_valid / ic_inv_ready / ic_inv_done | commit↔I$ | 各1 | FENCE.I在D全clean后发，512组扫描完成给done |
| ic_miss_event | I$→CSR | 1 | 每行miss一次，跨行双miss计两次 |
| maint_req_valid / maint_req_ready / maint_cmd / maint_addr / maint_size | cache_ctrl↔D$ | 1/1/3/32/32 | 沿cache3.2方向，valid保持到ready |
| maint_busy / wb_err / wb_err_addr | D$→cache_ctrl | 1/1/32 | BUSY、电平扫描状态；写回错误单拍/行地址 |
| cache_irq | cache_ctrl→top | 1 | IRQ_STAT&IRQ_EN，外部cache_irq_o |

FENCE.I顺序为D全clean done→I inv done→注册下一PC重取。维护请求与FENCE由D$单个维护入口串行；设备轮询可继续，可缓存已接受请求本地等待；队列容量和ready只用登记状态，不能让地址译码组合回ID。

### L1外部逐信号表

I$模块AR/R前缀 `axi_`，在top改为 `ic_axi_`；D$五通道在top为 `dc_axi_`。下表 `x=ic/dc` 的AR/R各展开一次，AW/W/B仅dc；ID固定0。没有内部tag、epoch或beat字段出IP。

| 顶层信号（完整后缀） | 方向 | 位宽 | 语义/握手 |
|---|---|---:|---|
| x_axi_arid_o | out | 4 | 固定0 |
| x_axi_araddr_o | out | 32 | 行对齐或原设备地址；ROM取指8B对齐 |
| x_axi_arlen_o | out | 8 | 行3、单拍0 |
| x_axi_arsize_o | out | 3 | 行/ROM3，其他0..2 |
| x_axi_arburst_o | out | 2 | INCR=01 |
| x_axi_arvalid_o / x_axi_arready_i | out/in | 各1 | AXI保持到握手 |
| x_axi_rid_i | in | 4 | 返回ID0，既有协议，不加检查端口 |
| x_axi_rdata_i | in | 64 | 读数据 |
| x_axi_rresp_i | in | 2 | OKAY/SLVERR/DECERR沿既有错误路径 |
| x_axi_rlast_i | in | 1 | 最后beat |
| x_axi_rvalid_i / x_axi_rready_o | in/out | 各1 | 接收缓冲容量反压；错误仍收完突发 |
| dc_axi_awid_o | out | 4 | 固定0 |
| dc_axi_awaddr_o | out | 32 | 写回行/设备原地址 |
| dc_axi_awlen_o | out | 8 | 行3、单拍0 |
| dc_axi_awsize_o | out | 3 | 行3、设备0..2 |
| dc_axi_awburst_o | out | 2 | INCR=01 |
| dc_axi_awvalid_o / dc_axi_awready_i | out/in | 各1 | 保持到握手 |
| dc_axi_wdata_o | out | 64 | 对应64位数据lane |
| dc_axi_wstrb_o | out | 8 | 按原addr[2:0]移位掩码 |
| dc_axi_wlast_o | out | 1 | 最后beat |
| dc_axi_wvalid_o / dc_axi_wready_i | out/in | 各1 | 与AW独立握手，保持负载 |
| dc_axi_bid_i | in | 4 | 返回ID0 |
| dc_axi_bresp_i | in | 2 | 写回错误走APB，设备错误走指令访问异常 |
| dc_axi_bvalid_i / dc_axi_bready_o | in/out | 各1 | B完成写事务 |
| apb_paddr_i | in | 12 | 系统槽5内偏移，沿SoC4.3 |
| apb_psel_i / apb_penable_i / apb_pwrite_i | in | 各1 | APB setup/access/方向 |
| apb_pwdata_i / apb_pstrb_i | in | 32/4 | 既有寄存器写数据/字节选通语义 |
| apb_pready_o / apb_prdata_o / apb_pslverr_o | out | 1/32/1 | APB完成/读值/错误；未列偏移读0写无效，不新造错误 |

外部另有 `clk_i/rst_n_i`、`irq_meip_i/irq_msip_i/irq_mtip_i`、`mtime_i`、`cache_irq_o`、`debug_o[63:0]`，方向/宽度见CPU3.1和上述CSR/debug定义。APB超时只由现有桥实现，cache不新增计时器。所有AXI事务发出后不能取消，年龄取消只影响内部回送和未授权副作用。

### 技术包装逐信号与几何

RF包装端口为 `clk_i`1、`wr_en_i`1、`wr_addr_i`5、`wr_data_i`32、`rd_addr_i`5、`rd_data_o`32，异步读。cache包装端口为 `clk_i`1、`wr_en_i`1、`wr_addr_i`A、`wr_data_i`D、数据宏另有`wr_mask_i`D/8、`rd_addr_i`A、`rd_data_o`D，同步一拍读，无valid/ready；调用者用流水valid关联，取消只清控制。技术包装本身不理解年龄，不增加取消口。

| 包装名称（rtl/tech，省略.v） | 几何/副本 |
|---|---|
| edrv32_ram_cpu2_rf（已有） | 32×32，双发射2owner×4读，小配置2读；AGU额外RF读按实际路径复制 |
| edrv32_ram_cpu2_cache_data（已有） | I$双bank每路2048×32，共4宏；单bank每路2048×64用下列data64宏 |
| edrv32_ram_cpu2_cache_data64（拟新增） | I$单bank/D$每路2048×64，D$8字节写使能，无D$查询副本 |
| edrv32_ram_cpu2_cache_tag（已有） | I$每路512×19 valid+tag；双bank查询按端口需求复制/分bank，容量不翻倍 |
| edrv32_ram_cpu2_cache_dtag（拟新增） | D$每路512×20 valid+dirty+tag |
| edrv32_ram_cpu2_cache_lru（拟新增） | 每侧512×1，同步元数据；两路比较后下一拍更新 |

TAGE/base预测与训练宏沿probes几何规则扩展合法参数：每表E×16，预测按双字奇偶bank各E/2×16、训练E×16；base预测2×2048×2、训练4096×2。读/写地址宽度由深度导出；数据宽16/2，同步1R1W，写端无mask。fast异步1024×2按容量分bank、BTB按总容量奇偶bank，RAS为寄存状态。FPU RF B宽异步单写R副本；共享完成每bank低32位为N/2×32异步单写S+1副本，FD高32位N/2×32为R+1副本，另有N/2×32 PC宏，控制valid/flags为FF；S及资源公式见F05，F06实际宏打包另定。

### 退休trace（顶层内部线，不是IP端口）

j=0,1按年龄，只有一条时在0。所有字段在该退休或陷阱事件拍有效，非退休项字段不要求有意义。名称均以 `_w` 结尾。

| 信号 | 位宽 | 语义 |
|---|---:|---|
| trace_valid_w / trace_pc_w / trace_instr_w | 2/64/64 | 两条退休valid/PC/编码，低字段老 |
| trace_rd_w / trace_rd_domain_w / trace_rd_data_w | 10/4/128 | 两个5bit rd、两个2bit目的域、两个64bit值；FP f0不能当无写 |
| trace_flags_w / trace_fflags_w / trace_frm_w / trace_fs_w | 10/5/3/2 | 每条flags及当拍全部提交后的架构状态 |
| trace_csr_valid_w / trace_csr_addr_w / trace_csr_data_w | 2/24/64 | 每条实际CSR写、12位地址/32位最终写值 |
| trace_mem_valid_w / trace_mem_store_w / trace_mem_addr_w / trace_mem_data_w / trace_mem_mask_w | 2/2/64/128/16 | 每条访存架构记录；地址原地址、64bit数据、8bit掩码，D只退休一次 |
| trace_trap_w / trace_cause_w / trace_trap_pc_w / trace_tval_w | 1/32/32/32 | 陷阱可能与更老退休同拍，故障项不置退休valid |
| trace_mem_effect_valid_w / trace_mem_effect_tag_w / trace_mem_effect_addr_w / trace_mem_effect_data_w / trace_mem_effect_mask_w | 1/T/32/32/4 | 每个已授权store beat实际副作用，用于高beat失败的部分写记分板 |
| trace_redirect_valid_w / trace_redirect_tag_w / trace_redirect_pc_w / trace_redirect_target_w / trace_redirect_stage_w / trace_redirect_cause_w | 1/T/32/32/2/2 | stage1F2、2EX、3MEM；cause1方向、2目标、3非控制误预测 |
| trace_source{p}_valid_w / trace_source{p}_tag_w / trace_source{p}_domain_w | 1/T/1 | 每个实际等待/旁路源tag及整数/FP域，RF源valid0；端口号同源表 |

内存记分板同时用AXI/BFM观察真正外部副作用、trace观察提交意图；可缓存写对架构生效指写缓冲接受，不要求等待后续写回。若发生故障FSD，trace_trap仍给本条PC/高字地址，不能伪造一条退休来解释部分写。

### 实现补充（2026-11-28，RTL第一波提问）

**配置与物理端口。** 同名模块只有 `ISSUE_WIDTH`/`FPU_FORMAT` 两个参数且不得 ifdef，参数无法删端口；规格中"单发射无 j1/owner/source_wait 端口、NONE 无 FP 端口"按下述口径实现：内部模块物理端口取最大命名集合，逐信号展开、位宽按参数；不适用的配置在模块内 generate 不实例化相关逻辑，输出驱动常量0，输入不读，上层不连接（输入接0）。未读输入用一行 `verilator lint_off UNUSEDSIGNAL` 包住的归并 `unused_w`，六配置 lint 均须0告警。顶层外部端口六配置相同。

**TAGE 的 D 预读（I01）。** issue 在本沿实际发射、带 F1 token 的条件分支，按程序槽 j=0..I−1 送 issue→TAGE：`predict_read{j}_valid`1、`predict_read{j}_tag`T、`predict_read{j}_index{p}`W、`predict_read{j}_tag{p}`10、`predict_read{j}_base_index`12。TAGE 用训练副本同步读，下一沿把各表当前行捕获进以完成 tag 关联的预读记录；记录等待期间侦听每次表写与待写项，同 index 就替换所存行（C08 同址老更新旁路）。EX/MEM 的 `predict_train_*` 按 `predict_train_tag` 找记录训练，provider/alternate/prediction 仍随 train 送来，不在预读时重复发送。TAGE 接 `age_head/cancel_valid/cancel_tag` 清被取消记录，训练完成释放记录。不靠固定拍推进。记录数取发射到 MEM 训练之间最多在途的条件分支数（由流水深度导出，写进 RTL 设计说明，不作参数）。

**提交侧补充端口（I04）。**

| 信号词干 | 方向 | 位宽 | 语义 |
|---|---|---:|---|
| decode_complete_valid / ready / tag / exception / cause / tval | issue→completion / 反向 / issue→completion | 1/1/T/1/4/32 | decode 生成的独立完成源：非法指令、ECALL/EBREAK、取指错误；格式同 `*_complete` |
| lsu_complete_device | LSU→completion | 1 | 设备访问准备完成，登记为 `head{j}_device` |
| head{j}_device | completion→commit | 1 | 头为 store、device 或 double_beat 时，commit 用 `commit_lsu_*` 授权，等 `commit_lsu_done` 后退休 |
| lsu_complete_mem_addr / mem_data / mem_mask | LSU→completion | 32/64/8 | trace 访存元数据；completion 用普通寄存器保存（不用技术包装），经 `head{j}_mem_*` 只送 trace，FPGA 中无负载被综合删除 |
| branch_redirect_valid / tag / pc | branch→completion、frontend | 1/T/32 | branch 内部选本沿最老误预测（含两管线 EX/MEM），注册输出 |
| commit_redirect_valid / pc | commit→frontend | 1/32 | 陷阱、MRET、FENCE.I 及串行化重取；同沿优先于 branch 重定向 |
| commit_cancel_valid / tag | commit→completion | 1/T | 陷阱/中断从头 tag 起取消；同沿优先于 branch |
| mret_valid / csr_mepc | commit→CSR / CSR→commit | 1/32 | MRET 退休沿 CSR 恢复 MIE/MPIE；mepc 为已提交寄存值 |
| irq_wake | CSR→commit | 1 | 任一 mie 允许的 pending，不看 MIE（CPU6.3 WFI 唤醒） |
| fetch_stop | commit→frontend | 1 | WFI 退休后为1停取指，irq_wake 后清0 |

completion 收到 `branch_redirect_valid` 时，若该 tag 之后有存活项，`cancel_tag`=该 tag+1（mod N），否则不发 cancel；`commit_cancel_valid` 同沿时取 commit 的值。空队列时的"下一应执行 PC"是 commit 内部寄存 `next_pc_r`（随退休、重定向、陷阱、MRET 更新），不设端口。

**设备 load 与 FD 设备访问（I05）。** 设备 load（含 FLD 两 beat）先以 `lsu_complete_device=1` 完成，只表示"可授权"：该项 done=1 供提交头授权，但 `source{p}_ready` 必须为0，准备数据不得转发。commit 授权后 LSU 发出设备事务（FD 两 beat 在 LSU 内拼成 B 位），`commit_lsu_done` 增加 `commit_lsu_done_data`（B 位）；commit 用它做本条退休写，同沿 WB 广播供等待源捕获（沿"已完成项将退休时同沿 WB 供等待源"规则）。completion 不做二次完成更新。可缓存 FLD 两 beat 都命中后一次完成 64 位，按普通 load。

**I$ 跨行 LRU（I05）。** 双 bank 跨行组命中的两行组号相邻、奇偶不同。I$ 双 bank 的 LRU 按组号奇偶分两块，每块用 `edrv32_ram_cpu2_cache_lru`，地址 `{1'b0, set[8:1]}`，跨行命中同沿各写一块，不串行。总容量不变；单 bank I$ 与 D$ 各一块整 512 组。

**RAS 恢复（I01）。** branch→frontend 随 `branch_redirect_*` 增 `branch_redirect_ras_data`（32×RAS_DEPTH）、`branch_redirect_ras_ptr`（log2深度）、`branch_redirect_ras_count`（log2(深度+1)），即该分支执行前的快照；另增 `branch_redirect_ras_pop`1、`branch_redirect_ras_push`1、`branch_redirect_link`32（分支 PC+4）。frontend 恢复快照后按本条类型先 pop 再 push。commit 重定向（陷阱、MRET、FENCE.I、串行化重取）不恢复 RAS，沿用当前内容：RAS 只是预测状态，不影响架构正确性，commit 不携带 RAS 快照。

**FP 源端口映射（I04）。** FP 域源固定使用 `source0..R−1`（F：0..2；FD：0..1，第三源补读复用 source0/1），`sourceR..S−1` 只承载整数源。FD 高32位每 bank 的 R+1 份副本对应 source0..R−1 加提交头读。

## 影响

审核通过后需修改CPU spec2.2/2.3、3、4、5、6及9的C01–C09；FPU spec2.4、3、4、5.1/5.4/5.5及9的F01/F02/F04/F05；CPU testplan2/4/6/7的T02/T03及对应CV02–CV14；FPU testplan4/6/7的FT01/FT03及FV10–FV15。C10、F03/F06与FT03中的未测数值继续待定；旧cpu/cache规格不改，外部总线无差异。

后续RTL任务按模块表拆分，技术包装/文件列表等由协调者负责。探针需改成完整容量/取消控制，不能把探针已测频率当正式模块验收。DIV独立修正拍必须重放模型；T02预算很大，须向用户明确合法参数全集的成本。本文验收为文档覆盖/信号宽度与命名自检及 `git diff --check`，无RTL改动，RTL lint/仿真不适用。

## 状态

**已决定**（用户 2026-11-28 确认）：
- C02–C04、C06、C08、C09、F02、F04、F05、T03、FT01、FT03 及协调者更正后的 C01 按推荐值冻结；
- C05 采用方案 A（T 位队列槽号 + 队头相对年龄）；C07 采用方案 B（独立符号修正拍，正常 L=3+n）；
- **配置大幅收敛（取代 C01 参数部分、F01、T02）**：CPU 只保留"单发射满配"和"双发射满配"两种，不再提供其余细分参数；两种都固定包含 Zba。FPU 保留 NONE/F/FD 三选一，内部固定 F=3 读口/完成队列 8 项、FD=2 读口/16 项，NONE 为 4 项 FF 完成记录。合法配置共 2×3=6 种，全部跑完整回归。本 SoC 板级用双发射 + F。

下面的汇总表是审核前的推荐，保留作记录。

| 编号 | 推荐结论（一句话） | 用户是否需在多个方案间选择 |
|---|---|---|
| C01 | 保留2.2参数，按所列表及依赖规则冻结配对 | 否 |
| C02 | 两路并扫512组，16组段，完成以done/BUSY为准 | 否 |
| C03 | AXI64/APB逐信号完全沿旧外部契约，内部串行miss | 否 |
| C04 | HPM原编码/局部等待，debug同义重映射，trace双域64位 | 否 |
| C05 | T位槽tag、head相对年龄和原子取消，本地等待短load失败 | 是 |
| C06 | FPGA异步RF/同步cache及等延迟ASIC适配契约 | 否 |
| C07 | DIV独立修正拍，正常L=3+n，特殊L=2，重放模型 | 是 |
| C08 | RamTage折叠/饱和/短到长分配/单待写旁路 | 否 |
| C09 | 提交头采样中断，保留DIV/设备/FENCE.I/双beat边界 | 否 |
| F01 | F默认3R/N8、FD默认2R/N16，保留其他合法组合 | 是 |
| F02 | FS复位Off，按实际架构FP写/flags/CSR写置Dirty | 否 |
| F04 | S4B/D8B自然对齐，高beat错误允许已完成低beat副作用 | 否 |
| F05 | 固定FPU端口、位段统一源副本、取消和按年龄完成仲裁 | 否 |
| T02 | 全合法组合短回归，每组合10种子，27主档点完整回归 | 是 |
| T03 | 冻结双域退休/异常/部分写观察与逐拍测试期望 | 否 |
| FT01 | SoftFloat/TestFloat3e，level2及每类10序列种子 | 否 |
| FT03 | 先冻结FS/双beat/端口观察，实测接受数值留后续 | 否 |
