# CPU v2 IP 实施方案

| 项 | 内容 |
|---|---|
| 版本/日期/状态 | v0.1-draft / 2026-11-27 / 草案；全部任务未开始 |
| 配套规格 | cpu-v2-spec.md v0.1-draft、fpu-spec.md v0.1-draft |
| 配套验证方案 | cpu-v2-testplan.md v0.1-draft、fpu-testplan.md v0.1-draft |
| 依据 | C2-I第四轮、C2-F2第二版；协调者2026-11-27确认仅需五份草稿，FPU任务统一纳入本计划 |

## 1. 目标和完成标准

目标是形成独立可移植CPU v2 IP，并将NONE/F/FD作为同一IP构建配置。完成必须包括已确认规格/接口、实现、独立验证、perf模型对照、技术包装和PDS测量证据；当前阶段仅产出草稿，协调者负责审核和正式文档，不授权本worker实施RTL或改旧规格。

验收必须通过两份验证方案规定的smoke/full/perf适用档位，逐条规格映射完整，风格/lint零告警，架构/逐位/副作用零不一致。150MHz规划和135MHz整片压力目标须由PDS定稿，未测量不得宣称已达标；所有资源和周期估算必须被实测结果替换或明确保留为模型参考。

## 2. 前置条件

必须先由协调者核对设计记录第四轮主档、F默认3R建议和两规格待定项，再形成首批关键路径探针的自包含Task与Windows任务卡。Linux使用既有Verilator/Spike/GCC15.2环境，Windows使用PDS/ModelSim和PG2L200H-6，厂商IP由用户按创建说明生成。

**首批必须先做五项关键路径独立PDS探针**：ID提前地址、TAGE F2、双bank取指拼合、LVT RF、FP32 FMA。探针Task只验证设计假设，不提前开发整核。探针之间可独立执行；完成后协调者根据报告冻结相关接口/延迟并重跑模型，再派发模块RTL和独立验证。

并行模块开发前必须冻结跨模块端口、valid/credit、年龄/取消、提交、FP CSR和LSU双beat契约。rtl/tech、共享文件列表、寄存器描述、fpga脚本/约束/IP说明及正式spec/testplan/plan由协调者负责；各Task归属必须在派发时列明，worker不得跨归属修改。

## 3. 待办清单

执行者缩写：C=协调者Claude（当前会话模型），D=RTL/工具Codex GPT-6.1 Sol、思考强度中，V=独立验证Codex GPT-6.1 Sol、思考强度中，W=用户GUI+Windows Codex。D负责本模块单元测试，V负责模块/SoC测试且不得阅读D的RTL。每行必须展开为一个Orca Task或一张Windows任务卡，实际Task ID/分支由协调者派发时填写；当前引用的是拟任务名，不声称已存在。

### 3.1 首批关键路径探针

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/任务卡、分支 | 状态 |
|---|---|---|---|---|---|---|
| P00 | 冻结五探针边界、输入/输出寄存和测量条件，编制任务卡/IP说明 | C | 用户规格阶段授权 | 每探针有完整端口、时序约束/器件、产物模板；不改整核功能 | task-cpu-v2-probe-contract / 派发时分支 | [x] 卡 110 已下发； 用户 2026-11-27 同意按 v0.1 做探针；整数四探针合一个 PDS 工程（P-INT），FMA 单独工程（P-FMA） |
| P01 | ID RF/WB→AGU独立探针RTL和单元激励 | D | P00 | 资格规则、RF读/选择/加法边界可仿真，风格/lint0 | task-cpu-v2-probe-id / 派发时分支 | [x] P-INT 完成（04753dba1），四项 smoke 通过 |
| P02 | ID提前地址探针PDS | W | P01 | 最差setup/hold、资源/扇出/路径；与5.736/5.796ns估算对照，原始报告路径齐全 | tasks/win/20261127-110-cpu2-probes（工程A） | [x] 卡 110 第 2 轮：153.5 MHz，见 docs/reports/2026-11-28-timing-cpu2-probes.md |
| P03 | TAGE F2探针RTL，含训练副本和待写前置命中旁路 | D | P00 | 当前行更新/碰撞和四表512端口模型自检，lint0 | task-cpu-v2-probe-tage / 派发时分支 | [x] P-INT 完成（04753dba1），四项 smoke 通过 |
| P04 | TAGE F2探针PDS | W | P03 | 比较/优先、训练副本、单待写旁路和双查询路径实测，RAM碎片计数 | tasks/win/20261127-110-cpu2-probes（工程A） | [x] 卡 110 第 2 轮：153.5 MHz，见 docs/reports/2026-11-28-timing-cpu2-probes.md |
| P05 | 双bank取指拼合探针RTL，含行尾两行、最老taken和owner前置入口 | D | P00 | 任意4B起点、拼合/恢复功能自检，固定头边界明确 | task-cpu-v2-probe-fetch / 派发时分支 | [x] P-INT 完成（04753dba1），四项 smoke 通过 |
| P06 | 双bank取指拼合探针PDS | W | P05 | bank→拼合/owner路径setup/hold和真实宏端口几何 | tasks/win/20261127-110-cpu2-probes（工程A） | [x] 卡 110 第 2 轮：153.5 MHz，见 docs/reports/2026-11-28-timing-cpu2-probes.md |
| P07 | LVT RF探针RTL：4R2W F2候选owner与小2R1W，技术包装行为模型 | D | P00 | 同址双写/IB等待owner修正/WB逐口检查，lint0 | task-cpu-v2-probe-rf / 派发时分支 | [x] P-INT 完成（04753dba1），四项 smoke 通过 |
| P08 | LVT RF探针PDS/厂商RAM等价 | W | P07 | 异步读/候选owner/WB更新时序、LUTRAM打包及ASIC等价宏接口记录 | tasks/win/20261127-110-cpu2-probes（工程A） | [x] 卡 110 第 2 轮：153.5 MHz，见 docs/reports/2026-11-28-timing-cpu2-probes.md |
| P09 | FP32 FMA探针RTL及APM包装行为测试 | D | P00 | 完整积和X/Y捕获、4拍链/8拍FMA初值、77位carry/LZA逐拍证据 | task-cpu-v2-probe-fma / 派发时分支 | [x] P-FMA 完成（e1fd27d5c），112 万向量逐位通过；Yosys 参考 E7/E8 超预算，待 PDS |
| P10 | FP32 FMA探针PDS/厂商APM逐拍等价 | W | P09 | X/Y、MULT/P/CPO级联和carry77段实测，setup/hold/资源报告 | tasks/win/20261127-110-cpu2-probes（工程B） | [x] 卡 110：158.5 MHz，2 APM |
| P11 | 五探针评审、修订延迟/资源/频率初值并重放性能模型 | C | P02/P04/P06/P08/P10 | 接口与可实现边界明确；不通过假设有显式修订，更新正式规格需用户确认 | task-cpu-v2-probe-review / 协调者分支 | [~] 实测报告已出（独立 153.5/158.5 MHz）；用户 2026-11-28 要求多留余量，独立探针目标提到 165 MHz（对 150 留 10%），P-INT-T（fd048ddf3）、P-FMA-T（8344727fc）完成；卡 110 第 3 轮 165 MHz 约束下整数 168.4 / FMA 179.2 MHz 均通过 |

### 3.2 接口冻结与验证基础设施

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| S01 | CPU/FPU规格、测试方案和参数矩阵审核冻结；明确所有跨模块接口 | C | P11 | C01–C09、F01/F02/F04/F05及验证待定项有确认条款；用户确认正式规格 | task-cpu-v2-spec-freeze / 协调者分支 | [ ] |
| V01 | 核级退休/双域CSR/内存与Spike比对基础设施 | V | S01 | 已知正确与故意错误trace检验比较器；双退休/FP64/异常可表达 | task-cpu-v2-verif-env / 派发时分支 | [ ] |
| V02 | 架构测试适配和受约束随机指令环境 | V | S01/V01 | I/M/Zicsr/Zba/F/D集、seed复现，配对/晚执行/提前地址/冲刷交叉生成 | task-cpu-v2-verif-isa / 派发时分支 | [ ] |
| V03 | 单元/核/SoC参数回归档位与性能输入整理 | V | S01/V01 | 两testplan全部测试项有test.yaml归属，参数矩阵和perf测量区间固定 | task-cpu-v2-verif-matrix / 派发时分支 | [ ] |

### 3.3 前端、后端与 LSU/L1

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| I01 | 前端gshare/TAGE、BTB/RAS、64位/双bank、IB/信用/owner传递 | D | S01/P04/P06/P08 | CV07/CV08单元全部通过；单训练口/跨行/恢复可测 | task-cpu-v2-frontend / 派发时分支 | [ ] |
| I02 | RF/LVT、早晚ALU和配对/记分牌后端 | D | S01/P02/P08 | CV02–CV05单元通过，真实年龄/结果边界与模型一致 | task-cpu-v2-backend / 派发时分支 | [ ] |
| I03 | MUL/DIV单元和双槽共享输入 | D | S01 | CV06单元通过，完整DIV拍数定稿并回放，APM本地捕获 | task-cpu-v2-muldiv / 派发时分支 | [ ] |
| I04 | 完成队列、按序提交/CSR/HPM、精确异常/中断/重定向 | D | S01 | CV09/CV10/CV14单元通过，无全局stall、取消无副作用 | task-cpu-v2-commit / 派发时分支 | [ ] |
| I05 | LSU/L1：单份D$提前请求、RAM元数据、写缓冲、维护/APB、双beat入口 | D | S01/P02/P06 | CV04/CV11/CV12单元通过，外部AXI/APB契约一致 | task-cpu-v2-lsu-l1 / 派发时分支 | [ ] |
| I06 | NONE核集成与独立核级验证 | V | I01/I02/I03/I04/I05/V02/V03 | 三主档NONE的CPU smoke/full通过，Spike零不一致 | task-cpu-v2-none-integration / 派发时分支 | [ ] |

### 3.4 FPU 单元、验证与整数核集成

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| F01 | FP RF 2R/3R、源捕获、记分牌和任意项转发接口 | D | S01/P08 | FV10/FV12单元通过，F默认3R及N8/16端口容量正确 | task-cpu-v2-fp-rf / 派发时分支 | [ ] |
| F02 | FP32 FMA及ADD/MUL旁路/共享尾端、转换/短操作 | D | S01/P10 | FV02/FV04–FV07/FV09/FV11/FV16单元通过，逐位及拍数正确 | task-cpu-v2-fp32 / 派发时分支 | [ ] |
| F03 | 独立基4 DIV/SQRT，S/D recurrence | D | S01/P10 | FV08单元逐位与flags通过；S19/D35初值经真实分段核对 | task-cpu-v2-fp-divsqrt / 派发时分支 | [ ] |
| F04 | D独立扩展、12APM完整积、D ADD/MUL/FMA尾端 | D | S01/F02 | FV06/FV07/FV09/FV16的D精度通过，Δe=0与106位积正确 | task-cpu-v2-fp64 / 派发时分支 | [ ] |
| F05 | TestFloat/SoftFloat RISC-V包装及独立F/D验证程序 | V | S01/V01 | FV01–FV09参考向量和FV03非法rm/frm Spike比对可运行 | task-cpu-v2-fp-verif / 派发时分支 | [ ] |
| F06 | D关键段PDS、厂商APM/RAM等价与资源测量 | W | F03/F04 | carry84/carry57、D级联和尾端setup/hold，逐拍等价/宏碎片资源 | Windows任务卡编号待派发 / win分支待派发 | [ ] |
| F07 | F/FD接入整数核：槽0、共享完成bank、CSR/FS、LSU两beat | D | I01–I05/F01/F02/F03/F04/F05 | CV13/FV10–FV15单元联调通过；不增加整数RF端口或D$副本 | task-cpu-v2-fp-integration / 派发时分支 | [ ] |
| F08 | 独立F/FD核级/SoC联合验证与全参数回归 | V | F07/F06/V02/V03 | FPU full及CPU集成矩阵通过，FP flags/FS/访存副作用与Spike一致 | task-cpu-v2-fp-validation / 派发时分支 | [ ] |

FPU任务F01–F05在S01后可按依赖并行于整数模块；F07必须等待整数提交/LSU/前端接口实现，F08必须独立于RTL作者。FP32探针先于FPU RTL，D探针以F04真实结构定稿D延迟；不得把FPU资源增量漏计进最终IP。

### 3.5 性能、整片与交付

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| A01 | 三主档及F/FD perf回归、模型分项对照 | V | I06/F08 | CV15/FV17通过、程序输出正确，周期/模型偏差有解释 | task-cpu-v2-performance / 派发时分支 | [ ] |
| A02 | CPU+L1+FPU独立PDS及完整SoC接入PDS/上板 | W | A01 | 全部相关域setup/hold报告、实测资源、CoreMark/视觉/LVGL及FP负载结果 | Windows任务卡编号待派发 / win分支待派发 | [ ] |
| A03 | 规格定稿、可移植技术包装交付、审核与里程碑汇报 | C | A02 | 所有待定项有数据/明确取值；用户确认正式规格与合入，保留旧核文档边界 | task-cpu-v2-final-review / 协调者分支 | [ ] |

## 4. 规格定稿项

| 关联ID | 初值/推荐 | 定稿时机和数据 |
|---|---|---|
| C06、C10局部，F03的S/F06 | RF异步RAM+F2 LVT、150/135MHz估算、S5/7/8 | P11用五探针真实setup/hold、宏几何及资源暂定 |
| C01/C08 | 三主档、单控制/LSU/MUL、TAGE4×512/历史4/12/32/96 | S01前核对模型配对和训练行为，冻结参数/折叠/分配细则 |
| C02/C03 | RAM元数据扫描512组、组段16、外部AXI/APB不改 | S01前冻结复位/失效边界；I05测周期，A02测时序 |
| C04/C05/C09、F02/F04/F05 | trace/年龄tag、valid-credit、FS Off、S4B/D8B对齐、精确提交 | S01必须在并行模块实现前冻结逐信号及异常/取消契约 |
| F01 | F默认3R/N8、FD默认2R/N16，可选3R | S01由协调者按C2-F2收益/资源确认 |
| C07 | 基2/4位长早结束，完整预处理/修正拍数待定 | I03单元通过后更新模型，核集成前定稿 |
| F03的D、F06 | D6/18/20、DIV/SQRT19/35、D II4，估算资源 | F06用真实D流水与厂商等价/PDS，A01前更新模型 |
| T01–T03、FT01–FT03 | 固定模型/软件、随机预算与性能比较条件 | S01/V03前明确测试矩阵；F03后冻结周期期望 |
| C10最终、F06最终 | 三主档资源估算±30%、FPU增量±40%；150规划/135压力 | A02整片setup/hold和上板负载后，由协调者/用户定稿 |

## 5. 风险和阻塞

| 风险/当前未决项 | 影响 | 处理与责任 |
|---|---|---|
| F2 owner预算仅约.050ns模型余量，异步RAM/LVT实际布线未知 | 推荐主档频率可能变化 | P06/P08先测，C评审后明确修订，不自动降级 |
| TAGE训练副本/单待写项端口和真实RAM碎片 | 表资源和F2时序变化 | P03/P04验证端口与旁路；S01冻结 |
| RAM元数据使I$失效不再旧核一拍完成 | FENCE.I/复位/维护周期变化 | C02在I05之前明确扫描握手与填充重叠语义 |
| 长操作、任意项转发和bank冲突本地捕获新增拍 | 依赖/窗口模型偏差 | V01/F05独立检查；实际多拍则更新规格和模型 |
| FD第二beat错误/跨行store边界未冻结 | 独立实现/验证无法共享期望 | S01前由C确认F04/C05，禁止自行推导事务回滚 |
| APM链和77/84/57位carry为结构估算 | FP延迟/II/频率变化 | P10/F06实测，F03更新后再跑A01 |
| 整片拥塞与独立探针差异、模型未完整覆盖错路/miss | 估算性能无法当板上成绩 | A02完整SoC测量，报告全部域setup/hold和软件条件 |

本表列的是待定设计输入，不代表当前实现已经失败。若探针否定初值，协调者必须明确修改规格/模型和Task，不增加备用路径、门禁或未经请求的保护。

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-27 | v0.1-draft | CPU v2规格阶段实施草稿；先五项PDS探针，再模块/独立验证/集成；FPU统一纳入CPU计划，全部任务未开始 |
