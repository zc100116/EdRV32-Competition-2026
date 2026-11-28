# CPU v2 FPU 验证方案

| 项 | 内容 |
|---|---|
| 版本/日期/状态 | v0.2 / 2026-11-28 / 已确认 |
| 对应规格 | fpu-spec.md v0.2；集成同时对应cpu-v2-spec.md |
| 关联文档 | cpu-v2-testplan.md、cpu-v2-plan.md；C2-F2第二版 |

## 1. 验证对象和范围

必须验证F/FD全指令、五舍入、特殊值/flags/boxing、算术逐拍流水、FP RF和共享完成集成。单元层负责数值和局部接口；核层负责按序架构状态、CSR、FS、取消和双beat；SoC层负责真实总线/中断、上下文和软件负载。NONE必须验证无FP状态可见。整数ISA和L1完整维护测试由cpu-v2-testplan负责，FPU相关交叉仍必须在本方案检查。

## 2. 验证环境

单元必须在verif/unit/下使用Verilator5 --timing，输入由Berkeley TestFloat Release3e生成，SoftFloat Release3e提供逐位参考，辅以RISC-V语义包装。核级verif/block/必须有Spike退休比对、AXI可变等待/错误模型和年龄记分板；SoC级verif/soc/必须使用完整SoC、既有存储器模型及CLINT/PLIC。厂商APM/RAM逐拍等价必须通过Windows ModelSim，时序/资源必须通过PDS任务卡。

独立验证worker必须依据规格和本方案实现，不阅读被测RTL。test.yaml必须记录配置、程序/向量、seed、模型版本、顶层/files.f、档位和超时；软件使用GCC15.2.0，核级tohost、SoC SIM_EXIT=0及UART日志。参考模型和DUT必须使用同一ELF/输入。

## 3. 测试项清单

U/B/S为单元/核/SoC；每族必须包含表内全部子场景，每条适用S/D均执行；F只检查S、FD检查S/D，NONE检查无FP状态与非法访问。

| 编号/层级 | 对应规格 | 内容 | 激励方法 | 检查方法 | 档位 |
|---|---|---|---|---|---|
| FV01 U/B | 1、2.1、2.4、6.2 | 全opcode、f0可写、源=目的、F/FD/NONE可见性、RV32不支持指令、FS Off | 指令定向、riscv-arch-test F/D、随机寄存器 | Spike、架构签名 | smoke/full |
| FV02 U/B | 2.2、4.1 | 五种静态/动态舍入、正负tie/邻ULP、动态frm有序采样、精确不置NX | TestFloat、定向边界、CSR交叉 | SoftFloat结果+flags、Spike | smoke/full |
| FV03 B | 2.2、4、6.2 | 静态rm101/110非法；动态frm101/110/111非法；写frm/fcsr保留编码本身不陷阱；不使用rm操作不误报 | 逐编码短程序、CSR与长FMA排序 | Spike逐条比对、cause2/mtval、无结果/flags提交 | smoke/full |
| FV04 U/B | 2.2、6.1 | 最小/最大subnormal、最小normal、单/双/三源非规格化、精确/非精确渐进下溢、舍入后tininess | TestFloat、边界构造 | 逐位UF/NX、零软件陷入/FTZ | smoke/full |
| FV05 U/B | 2.1、2.2 | qNaN/sNaN每源/payload、±0/∞、min/max单/双NaN与零符号、FEQ和FLT/FLE差异、FCLASS十类 | 定向特殊值交叉、随机编码 | RISC-V包装参考、flags逐位 | smoke/full |
| FV06 U/B | 2.1、2.2、5.2 | 四FMA单次舍入、精确消去、低积改变tie、积溢出加数抵消、0×∞+qNaN | TestFloat、fused与非fused不同反例 | 完整FMA参考；含S(1+2^-23)(1-2^-23)-1=-2^-46 | smoke/full |
| FV07 U/B | 2.1、2.2 | ADD/MUL原opcode特殊值、转换每方向、整数范围端点/越界/NaN、OF/UF/NX/NV优先 | TestFloat及定向饱和值 | 结果与flags、Spike | smoke/full |
| FV08 U/B | 2.2、5.2、5.3 | DIV/SQRT 0/0、∞/∞、有限/0、负sqrt、sqrt(-0)、digit各值、精确/非精确余数、困难舍入 | TestFloat、定向残数边界、随机 | SoftFloat逐位，逐拍recurrence完成时序 | smoke/full |
| FV09 U/B | 2.3、2.1、5.5 | 正确/错误boxing，FLW/窄结果上部全1，FSW/FMV.X.W保低位，FSGNJ保payload、S/D转换、FLD/FSD原样 | 原始64位图案和上下文往返 | 位精确参考与Spike | smoke/full |
| FV10 U/B | 3、5.1、5.4 | FD固定2R先读两源再rs3、未读期间RAW/WAW、F固定3R吞吐、双发射整数配对、单发射单管线发射、转换整数域冲突 | 定向依赖图、随机指令调度 | 双域版本记分板，源捕获/完成逐拍 | smoke/full |
| FV11 U/B | 3.3、5.2–5.4、6.3 | ADD/MUL/FMA共享尾端预约、S/D相撞、DIV并发；load/FMA同完成、两bank同/异、branch PC/load结果撞bank | 控制发射间隔、随机背压 | 按年龄仲裁、源结果保留，无丢/重 | smoke/full |
| FV12 U/B | 4、5.4、6.3 | N8/16满空环回、统一S源低位S+1/FD高位3份结果副本任意项转发、最新tag对旧RF、消费者错过末级仍可读非头结果 | 长头阻塞+短年轻完成、tag多次环回 | 独立tag模型、结果/flags/提交次序 | smoke/full |
| FV13 B/S | 4.1、4.2、6 | fflags粘滞OR/清写别名、frm/fcsr排序、FS Dirty/SD、MRET/上下文保存、FS Off错误 | 程序、CSR与长算术交错 | Spike CSR/FS逐条比对 | smoke/full |
| FV14 U/B/S | 3.2、5.5、6.2 | S一beat、D低/高两beat、行尾24/28、非缓存/设备、第一/第二拍错误、对齐异常、中间IRQ | AXI延迟/错误注入、定向程序 | 完整FLD后才转发、单指令退休、副作用契约 | smoke/full |
| FV15 B/S | 1.2、5.1、5.4、6.3 | FDIV/FSQRT期间整数推进、头堵/满、双发射晚分支/单发射EX分支冲刷、老load fault、IRQ取消年轻结果/flags/store | 约束随机FP/整数和异常交叉 | Spike、年龄/内存模型 | full |
| FV16 U | 5.2、5.3、7.1 | 2/12APM链、D Δe=0/8/16、完整积/对齐寄存、X/Y直接采样、MULT/P/CPO拍数 | 极值+随机无符号积、厂商逐拍等价 | 完整48/106位积，逐级延迟 | full |
| FV17 B/S | 7.2、7.3 | 固定F(3R/N8)、FD(2R/N16)的matrix/Whetstone/vertex/physics，NONE软浮点对照 | 同源码GCC15.2编译、固定输入 | 程序数值输出、周期分项/模型及资源 | perf |
| FV18 U/B | 2.4、7、8、9 | NONE/F/FD三种格式、两种CPU集成6种配置完整回归、lint、控制复位、FP32 FMA及D关键段PDS | 固定配置编译/定向、Windows探针 | 零告警、功能矩阵、setup/hold与资源 | full/perf |

## 4. 参考模型

SoftFloat必须设置tininess-after-rounding，精度和舍入必须与指令一致；必须包装canonical NaN、minimumNumber/maximumNumber、比较NV、FCLASS、符号/搬移、NaN-boxing及RV32转换饱和值。不得直接把通用IEEE库当全部RISC-V参考，也不得用宿主float计算期望。

FT01：参考必须使用SoftFloat Release3e、TestFloat Release3e（TestFloat3系列对应版），以实际导入上游commit记录，不预造尚未导入的commit。必须记录生成选项、seed、精度/舍入；full必须使用testfloat_gen level2，逐已实现opcode×精度×适用五舍入比对结果与每条flags。RMM、NaN、tininess-after-rounding必须按RISC-V包装；搬移/boxing/非法编码必须用定向位模型及Spike。每类固定边界必须全部运行，序列随机seed=0..9，每seed至少10000条操作，F/FD各自固定结构必须全部运行，NONE必须验证非法FP访问；F的D指令必须非法。厂商IP版本必须由Windows任务卡给出，算术正确性不得依赖其近似模型。

Spike必须比较退休PC/编码、rd/domain、原始32/64位结果、每次退休后的累计fflags/fcsr、FS、陷阱和访存地址/store数据；每条flags由单元级SoftFloat/TestFloat向量逐条验证（Spike日志在粘滞位已置时无法恢复每条flags）；load原始数据按rd值的低size字节一致性检查；逐beat外部副作用（含FSD部分写）用trace_mem_effect与AXI/BFM比较；源tag、F2纠正等实现相关字段不与Spike比较，由核级一致性检查（重定向目标等于下一条退休PC）覆盖。F/D架构测试必须使用仓库riscv-arch-test实际commit和适配说明。I/M/Zicsr/Zba与F/D混合必须同时经过CPU验证，不只验证纯FP程序。

周期模型必须使用C2-F2脚本和相同trace，记C_total=integer+structure+dependency+writeback+fd_beat，按实际调度互斥计数，不能独立最坏值相加。完整CPU前端/miss影响必须另列；F必须采用固定3R/N8模型，FD必须采用固定2R/N16模型。

## 5. 覆盖目标

| 规格范围 | 对应测试项 |
|---|---|
| 1全部 | FV01、FV15 |
| 2.1 | FV01、FV05–FV09 |
| 2.2 | FV02–FV08 |
| 2.3/2.4 | FV09/FV01+FV10+FV18 |
| 3全部 | FV10、FV11、FV14 |
| 4全部 | FV02、FV03、FV13 |
| 5.1 | FV10、FV15 |
| 5.2 | FV06–FV08、FV11、FV16 |
| 5.3 | FV08、FV10、FV11、FV16 |
| 5.4 | FV10–FV12、FV15 |
| 5.5 | FV09、FV14 |
| 6全部 | FV01、FV03、FV04、FV13–FV15 |
| 7/8 | FV16–FV18/全部测试族 |
| 9/10 | FV18和对应族随定稿核对；变更记录为文档审核项 |

每条规格条款必须至少对应一个测试项，细化不得遗漏强制语句。必须覆盖每指令×S/D×适用五舍入、输入十分类、所有flags单bit及可达组合、正确/错误boxing、每FMA变体单次舍入反例、每转换边界、DIV/SQRT digit/余数修正。流水必须覆盖F固定3R/N8与FD固定2R/N16、尾端每相位、同/跨bank、单FP写口冲突、任意项转发环回、每类冲刷源×未读rs3/执行中/已完成未提交、两beat每阶段错误/中断。有限随机不得宣称穷举全浮点空间。

## 6. 通过判据和回归档位划分

smoke必须覆盖F固定3R/N8、FD固定2R/N16的全部指令短例、五舍入、非法rm/frm、subnormal、boxing、CSR、单次舍入和完成冲突；每单项约60秒内。full必须运行FT01规定的TestFloat level2完整流、架构测试、全部定向、10个序列种子和长随机及厂商等价。perf必须固定六个C2-F2软件负载和NONE/F/FD，采用各自固定R/N，单列模型局限。

格式回归必须只有NONE/F/FD三种；F和FD必须各跑全部单元算术、核级CSR/取消/适用双beat及架构回归，NONE必须验证无FP状态。三格式必须与单发射精简/双发射满配交叉共6种配置，全部完整回归，预算必须沿CPU T02；不得再构建可选R/N组合。

FT03：FV10–15必须使用F02已冻结的FS逐事件转换、F04逐beat错误/部分副作用、F05取消与年龄仲裁和规格逐信号表。FV14必须覆盖低错、高错、每beat反压、中断等待、FD行尾24/28；S非4B/D非8B对齐必须在发总线前报错。合法D不会跨32B行，不制造合法D跨行场景。

通过必须为零逐位结果/每条flags/架构状态不一致、架构签名通过、合法subnormal零软件陷入、取消项零副作用、零丢失/重复完成，所有功能覆盖必须达到。失败必须打印原始输入、操作/舍入、期望/实际结果与flags、PC/tag/周期/seed后结束。lint/风格必须零告警。PDS必须报告全部setup/hold WNS/TNS/WHS/THS、资源及宏等价，不把探针通过写成整核通过；F03/F06/C10未批准的延迟/II/资源/频率接受数值仍为待测，性能容差仍见FT02。

## 7. 待定事项与变更记录

| ID | 事项/推荐初值 | 定稿时机 |
|---|---|---|
| FT02 | 性能周期容差：推荐单元定向日程精确一致，完整负载先报告互斥分项偏差，不预设未知硬件容差 | F03确定后、perf执行前 |

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-27 | v0.1-draft | 配套FPU第二版结构；加入协调者确认的保留rm/frm非法测试FV03 |
| 2026-11-28 | v0.2 | 依据 docs/design/2026-11-28-cpu-v2-interface-freeze.md 已决定状态及更正 C01，冻结接口、行为和两种CPU×三种FPU格式，Zba固定启用，更新模型估算、验证和实施依赖 |
| 2026-11-28 | v0.2 | 按用户决定将单发射固定为精简结构+Zba；双发射满配及NONE/F/FD固定结构不变，同步接口、验证、实施和模型结论 |
| 2026-11-28 | v0.2 | Spike比较范围按其日志能力收窄：每条flags移至单元级SoftFloat，核级比累计fflags；副作用对BFM；实现相关字段做一致性检查（V01提问） |
