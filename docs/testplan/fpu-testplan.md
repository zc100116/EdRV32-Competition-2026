# CPU v2 FPU 验证方案

| 项 | 内容 |
|---|---|
| 版本/日期/状态 | v0.1-draft / 2026-11-27 / 草案 |
| 对应规格 | fpu-spec.md v0.1-draft；集成同时对应cpu-v2-spec.md |
| 关联文档 | cpu-v2-testplan.md、cpu-v2-plan.md；C2-F2第二版 |

## 1. 验证对象和范围

必须验证F/FD全指令、五舍入、特殊值/flags/boxing、算术逐拍流水、FP RF和共享完成集成。单元层负责数值和局部接口；核层负责按序架构状态、CSR、FS、取消和双beat；SoC层负责真实总线/中断、上下文和软件负载。NONE必须验证无FP状态可见。整数ISA和L1完整维护测试由cpu-v2-testplan负责，FPU相关交叉仍必须在本方案检查。

## 2. 验证环境

单元必须在verif/unit/下使用Verilator5 --timing，输入由Berkeley TestFloat生成，SoftFloat 3e提供逐位参考，辅以RISC-V语义包装。核级verif/block/必须有Spike退休比对、AXI可变等待/错误模型和年龄记分板；SoC级verif/soc/必须使用完整SoC、既有存储器模型及CLINT/PLIC。厂商APM/RAM逐拍等价必须通过Windows ModelSim，时序/资源必须通过PDS任务卡。

独立验证worker必须依据规格和本方案实现，不阅读被测RTL。test.yaml必须记录配置、程序/向量、seed、模型版本、顶层/files.f、档位和超时；软件使用GCC15.2.0，核级tohost、SoC SIM_EXIT=0及UART日志。参考模型和DUT必须使用同一ELF/输入。

## 3. 测试项清单

U/B/S为单元/核/SoC；每族必须包含表内全部子场景，每条适用S/D均执行。

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
| FV10 U/B | 3、5.1、5.4 | 2R先读两源再rs3、未读期间RAW/WAW、3R吞吐、整数配对、转换整数域冲突 | 定向依赖图、随机指令调度 | 双域版本记分板，源捕获/完成逐拍 | smoke/full |
| FV11 U/B | 3.3、5.2–5.4、6.3 | ADD/MUL/FMA共享尾端预约、S/D相撞、DIV并发；load/FMA同完成、两bank同/异、branch PC/load结果撞bank | 控制发射间隔、随机背压 | 按年龄仲裁、源结果保留，无丢/重 | smoke/full |
| FV12 U/B | 4、5.4、6.3 | N8/16满空环回、R+1结果副本任意项转发、最新tag对旧RF、消费者错过末级仍可读非头结果 | 长头阻塞+短年轻完成、tag多次环回 | 独立tag模型、结果/flags/提交次序 | smoke/full |
| FV13 B/S | 4.1、4.2、6 | fflags粘滞OR/清写别名、frm/fcsr排序、FS Dirty/SD、MRET/上下文保存、FS Off错误 | 程序、CSR与长算术交错 | Spike CSR/FS逐条比对 | smoke/full |
| FV14 U/B/S | 3.2、5.5、6.2 | S一beat、D低/高两beat、行边界/非缓存/设备、第一/第二拍错误、对齐异常、中间IRQ | AXI延迟/错误注入、定向程序 | 完整FLD后才转发、单指令退休、副作用契约 | smoke/full |
| FV15 B/S | 1.2、5.1、5.4、6.3 | FDIV/FSQRT期间整数推进、头堵/满、晚分支冲刷、老load fault、IRQ取消年轻结果/flags/store | 约束随机FP/整数和异常交叉 | Spike、年龄/内存模型 | full |
| FV16 U | 5.2、5.3、7.1 | 2/12APM链、D Δe=0/8/16、完整积/对齐寄存、X/Y直接采样、MULT/P/CPO拍数 | 极值+随机无符号积、厂商逐拍等价 | 完整48/106位积，逐级延迟 | full |
| FV17 B/S | 7.2、7.3 | F/FD和2R/3R、N8/16的matrix/Whetstone/vertex/physics，NONE软浮点对照 | 同源码GCC15.2编译、固定输入 | 程序数值输出、周期分项/模型及资源 | perf |
| FV18 U/B | 2.4、7、8、9 | 全参数矩阵、lint、控制复位、FP32 FMA及D关键段PDS | 参数编译/定向、Windows探针 | 零告警、功能矩阵、setup/hold与资源 | full/perf |

## 4. 参考模型

SoftFloat必须设置tininess-after-rounding，精度和舍入必须与指令一致；必须包装canonical NaN、minimumNumber/maximumNumber、比较NV、FCLASS、符号/搬移、NaN-boxing及RV32转换饱和值。不得直接把通用IEEE库当全部RISC-V参考，也不得用宿主float计算期望。

TestFloat必须记录版本、生成选项、seed和精度/舍入；full应使用level2，独立算术资格回归应至少完成每精度/算术类/舍入的level1完整生成流（超过60秒的放full，不强塞smoke）。定向集必须补齐生成器不覆盖的RISC-V CSR/boxing和FMA异常规则。

Spike必须比较退休PC/编码、rd/domain、原始32/64位结果、每条flags、累计fcsr、FS、陷阱和访存副作用；F/D架构测试必须使用仓库riscv-arch-test实际commit和适配说明。I/M/Zicsr/Zba与F/D混合必须同时经过CPU验证，不只验证纯FP程序。

周期模型必须使用C2-F2脚本和相同trace，记C_total=integer+structure+dependency+writeback+fd_beat，按实际调度互斥计数，不能独立最坏值相加。完整CPU前端/miss影响必须另列；F默认3R必须采用3R模型，不能引用2R周期冒充默认结果。

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

每条规格条款必须至少对应一个测试项，细化不得遗漏强制语句。必须覆盖每指令×S/D×适用五舍入、输入十分类、所有flags单bit及可达组合、正确/错误boxing、每FMA变体单次舍入反例、每转换边界、DIV/SQRT digit/余数修正。流水必须覆盖R/N各值、尾端每相位、同/跨bank、单FP写口冲突、任意项转发环回、每类冲刷源×未读rs3/执行中/已完成未提交、两beat每阶段错误/中断。有限随机不得宣称穷举全浮点空间。

## 6. 通过判据和回归档位划分

smoke必须覆盖F默认3R/8和FD推荐2R/16的全部指令短例、五舍入、非法rm/frm、subnormal、boxing、CSR、单次舍入和完成冲突；每个单项约60秒以内。full必须运行TestFloat完整流、架构测试、全部定向与长随机及厂商等价；perf必须固定六个C2-F2软件负载和NONE/F/FD，对比2R/3R/N8/16并单列模型局限。

F/FD×2R/3R×N8/16的8个组合必须各跑单元算术、核级CSR/取消/双beat和架构回归；NONE必须验证无状态可见。再与CPU三主档交叉跑集成短例及代表完整程序，完整参数回归范围按CPU T02冻结。

通过必须为零逐位结果/每条flags/架构状态不一致、架构签名通过、合法subnormal零软件陷入、取消项零副作用、零丢失/重复完成；所有规定覆盖点必须达成。失败必须打印输入原始位、操作/舍入、期望/实际结果及flags、PC/tag/周期/seed并结束。Lint/风格零告警；PDSsetup/hold和资源必须以真实报告判定，估算性能容差见FT02。

## 7. 待定事项与变更记录

| ID | 事项/推荐初值 | 定稿时机 |
|---|---|---|
| FT01 | 参考版本和随机预算：推荐SoftFloat3e/TestFloat3对应版本，full level2，每类至少固定边界与10个序列种子；厂商IP版本按任务卡 | 验证Task派发前 |
| FT02 | 性能周期容差：推荐单元定向日程精确一致，完整负载先报告互斥分项偏差，不预设未知硬件容差 | F03确定后、perf执行前 |
| FT03 | FS/双beat错误/最终端口和PDS接受数值：推荐依F02–F06和CPU C05/C10冻结后补齐期望 | 并行RTL/独立验证Task前 |

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-27 | v0.1-draft | 配套FPU第二版结构；加入协调者确认的保留rm/frm非法测试FV03 |
