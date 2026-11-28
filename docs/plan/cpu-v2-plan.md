# CPU v2 IP 实施方案

| 项 | 内容 |
|---|---|
| 版本/日期/状态 | v0.2 / 2026-11-28 / 草案；S01完成，模块实施待开始 |
| 配套规格 | cpu-v2-spec.md v0.2、fpu-spec.md v0.2 |
| 配套验证方案 | cpu-v2-testplan.md v0.2、fpu-testplan.md v0.2 |
| 依据 | C2-I第四轮、C2-F2第二版；协调者2026-11-27确认仅需五份草稿，FPU任务统一纳入本计划 |

## 1. 目标和完成标准

目标是形成独立可移植CPU v2 IP，并将NONE/F/FD作为同一IP构建配置。完成必须包括已确认规格/接口、实现、独立验证、perf模型对照、技术包装和PDS测量证据；本稿为v0.2审核交付，协调者负责审核和正式文档，不授权本worker实施RTL或改旧规格。

验收必须通过两份验证方案规定的smoke/full/perf适用档位，逐条规格映射完整，风格/lint零告警，架构/逐位/副作用零不一致。150MHz规划和135MHz整片压力目标须由PDS定稿，未测量不得宣称已达标；所有资源和周期估算必须被实测结果替换或明确保留为模型参考。

## 2. 前置条件

接口与配置已按2026-11-28用户决定冻结：CPU仅单发射精简/双发射满配且固定Zba，FPU仅NONE/F/FD固定内部结构；6种配置全部完整回归。五探针已完成，F03/F06/C10的真实整核接受数值仍待后续任务。Linux使用既有Verilator/Spike/GCC15.2环境，Windows使用PDS/ModelSim和PG2L200H-6，厂商IP由用户按创建说明生成。

**首批五项关键路径独立PDS探针已完成**：ID提前地址、TAGE F2、双bank取指拼合、LVT RF、FP32 FMA。探针Task只验证设计假设，不提前开发整核。探针之间可独立执行；完成后协调者根据报告冻结相关接口/延迟并重跑模型，再派发模块RTL和独立验证。

并行模块开发前必须冻结跨模块端口、valid/credit、年龄/取消、提交、FP CSR和LSU双beat契约。rtl/tech、共享文件列表、寄存器描述、fpga脚本/约束/IP说明及正式spec/testplan/plan由协调者负责；各Task归属必须在派发时列明，worker不得跨归属修改。

## 3. 待办清单

执行者缩写：C=协调者Claude（当前会话模型），D=RTL/工具Codex GPT-6.1 Sol、思考强度高，V=独立验证Codex GPT-6.1 Sol、思考强度高，W=用户GUI+Windows Codex。D负责本模块单元测试，V负责模块/SoC测试且不得阅读D的RTL。每行必须展开为一个Orca Task或一张Windows任务卡，实际Task ID/分支由协调者派发时填写；当前引用的是拟任务名，不声称已存在。

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
| P07 | LVT RF探针RTL：4R2W F2候选owner与单发射2R1W，技术包装行为模型 | D | P00 | 同址双写/IB等待owner修正/WB逐口检查，lint0 | task-cpu-v2-probe-rf / 派发时分支 | [x] P-INT 完成（04753dba1），四项 smoke 通过 |
| P08 | LVT RF探针PDS/厂商RAM等价 | W | P07 | 异步读/候选owner/WB更新时序、LUTRAM打包及ASIC等价宏接口记录 | tasks/win/20261127-110-cpu2-probes（工程A） | [x] 卡 110 第 2 轮：153.5 MHz，见 docs/reports/2026-11-28-timing-cpu2-probes.md |
| P09 | FP32 FMA探针RTL及APM包装行为测试 | D | P00 | 完整积和X/Y捕获、4拍链/8拍FMA初值、77位carry/LZA逐拍证据 | task-cpu-v2-probe-fma / 派发时分支 | [x] P-FMA 完成（e1fd27d5c），112 万向量逐位通过；Yosys 参考 E7/E8 超预算，待 PDS |
| P10 | FP32 FMA探针PDS/厂商APM逐拍等价 | W | P09 | X/Y、MULT/P/CPO级联和carry77段实测，setup/hold/资源报告 | tasks/win/20261127-110-cpu2-probes（工程B） | [x] 卡 110：158.5 MHz，2 APM |
| P11 | 五探针评审、修订延迟/资源/频率初值并重放性能模型 | C | P02/P04/P06/P08/P10 | 接口与可实现边界明确；不通过假设有显式修订，更新正式规格需用户确认 | task-cpu-v2-probe-review / 协调者分支 | [x] 卡 110 第 3 轮 165 MHz 约束下整数 168.4 / FMA 179.2 MHz；初值保留，FMA LUT 回收放到 F02 |

### 3.2 接口冻结与验证基础设施

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| S01 | CPU/FPU v0.2规格、验证/实施方案及逐信号接口冻结；两种CPU×三格式固定结构 | C | P11 | C01–C09及F01/F02/F04/F05、T02/T03/FT01/FT03按用户2026-11-28决定转录；C10/F03/F06仍待测 | task-cpu-v2-spec-freeze / 协调者分支 | [x] 用户2026-11-28确认；v0.2审核草稿已形成 |
| V01 | 按规格trace建立双域64位退休、CSR/FS、异常及逐beat副作用Spike比较器 | V | S01 | 已知正确/故意错误trace验证比较器，覆盖双退休、老退休+年轻异常及FSD部分写 | task-cpu-v2-verif-env / 派发时分支 | [ ] |
| V02 | 架构测试适配和受约束随机指令环境 | V | S01/V01 | I/M/Zicsr/Zba/F/D集、seed复现，配对/晚执行/提前地址/冲刷交叉生成 | task-cpu-v2-verif-isa / 派发时分支 | [ ] |
| V03 | 建立单/双发射×NONE/F/FD六种固定配置的构建/lint/完整回归档位与性能输入 | V | S01/V01 | 两testplan所有测试项有test.yaml，6种全部full及seed0..9预算、Zba对应trace与perf区间固定 | task-cpu-v2-verif-matrix / 派发时分支 | [ ] |

### 3.3 前端、后端与 LSU/L1

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| I01 | frontend/predictor/tage/tage_update/fetch/ib：单发射gshare4096无TAGE/BTB64/RAS4/IB4+4预留/64位8B对齐；双发射TAGE4×512+gshare4096/BTB128/RAS8/IB8+4预留/双bank及owner候选 | D | S01/P04/P06/P08 | CV07/CV08单元通过；单发射精简前端全部边界，双发射XOR折叠/训练待写/跨行逐字错误/寄存信用与恢复符合逐信号表 | task-cpu-v2-frontend / 派发时分支 | [ ] |
| I02 | decode/issue/rf/id_agu/alu/branch：单发射2R1W与双发射4R2W LVT；程序槽/管线映射、配对、双域记分牌与本地晚操作数等待 | D | S01/P02/P08 | CV02–CV05通过；老A+年轻LSU互换、WAW按槽、early失败不重发、单发射无晚执行 | task-cpu-v2-backend / 派发时分支 | [ ] |
| I03 | mul/div：单MUL全流水，单发射radix-2/双发射radix-4位长提前结束DIV；双发射共享输入按年龄选、单发射单入口 | D | S01 | CV06通过；MUL延迟4/II1，DIV正常单发射L=3+k、双发射L=3+ceil(k/2)/特殊L2、背压保持；回放独立修正拍并更新性能模型 | task-cpu-v2-muldiv / 派发时分支 | [ ] |
| I04 | completion/commit/csr：NONE4项FF、F8/FD16共享bank；单发射2HPM（3–4）/双发射8HPM（3–10）、CSR/FS、年龄取消、精确中断与重定向 | D | S01 | CV09/CV10/CV14通过；head相对年龄/原子取消/完整提交边界、已捕获CSR源和FS逐事件正确；六配置端口容量一致 | task-cpu-v2-commit / 派发时分支 | [ ] |
| I05 | lsu/icache/dcache/cache_ctrl：单LSU提前关联、RAM元数据、512组扫描、写缓冲、APB维护、FD两beat准备/授权/done | D | S01/P02/P06 | CV04/CV11/CV12通过；逐tag/beat关联、16组段、done/BUSY、设备头授权及AXI/APB逐信号不变；测维护附加拍数 | task-cpu-v2-lsu-l1 / 派发时分支 | [ ] |
| I06 | top：单发射精简/双发射满配的NONE核连线集成与独立核级验证 | V | I01/I02/I03/I04/I05/V02/V03 | 单发射+NONE、双发射+NONE均完整CPU smoke/full，固定Zba必测，Spike零不一致 | task-cpu-v2-none-integration / 派发时分支 | [ ] |

### 3.4 FPU 单元、验证与整数核集成

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| F01 | fpu_rf与issue源捕获接口：F固定3R、FD固定2R；统一S源副本和未读rs3生产版本 | D | S01/P08 | FV10/FV12通过；F N8/FD N16、单/双发射源数正确；rs3生产者退休同沿不丢值 | task-cpu-v2-fp-rf / 派发时分支 | [ ] |
| F02 | fpu_fma32/fpu_convert/fpu_short及lz24/lza32：S ADD/MUL/FMA共享尾端、转换与短操作 | D | S01/P10 | FV02/FV04–FV07/FV09/FV11/FV16通过；逐位/flags及F03开发初值拍数报告；回收探针LUT | task-cpu-v2-fp32 / 派发时分支 | [ ] |
| F03 | fpu_divsqrt：独立基4 S/D recurrence及本地完成/年龄取消 | D | S01/P10 | FV08逐位/flags通过；S19/D35初值按真实准备/迭代/尾端记录，完成背压与取消不丢结果 | task-cpu-v2-fp-divsqrt / 派发时分支 | [ ] |
| F04 | fpu_fma64：D独立12APM完整106位积和D ADD/MUL/FMA共享尾端；只在FD实例化 | D | S01/F02 | FV06/FV07/FV09/FV16 D通过；Δe0/8/16及单次舍入正确，F03 D延迟/II实测输入齐全 | task-cpu-v2-fp64 / 派发时分支 | [ ] |
| F05 | SoftFloat/TestFloat Release3e RISC-V包装及独立F/D参考/验证程序 | V | S01/V01 | FV01–FV09可运行；FT01 level2与每类seed0..9各10000操作；F仅S、FD S/D、NONE无状态的期望完整 | task-cpu-v2-fp-verif / 派发时分支 | [ ] |
| F06 | D关键段PDS、APM/RAM逐拍等价和统一源副本资源测量 | W | F03/F04/F01 | carry84/carry57、D级联/尾端全部setup/hold与真实宏碎片；F03/F06未测数值据报告定稿 | Windows任务卡编号待派发 / win分支待派发 | [ ] |
| F07 | fpu_top接入top/issue/completion/commit/csr/lsu：FP管线0及程序槽互换、单FP写口、FS、两beat | D | I01/I02/I03/I04/I05/F01/F02/F03/F04/F05 | CV13/FV10–FV15联调通过；F/FD各在单/双发射正确，FSD高错允许低beat副作用，整数RF/D$不增副本 | task-cpu-v2-fp-integration / 派发时分支 | [ ] |
| F08 | 独立F/FD核级/SoC验证并汇总全部六种配置完整回归 | V | F07/F06/I06/V02/V03 | CPU/FPU全部适用full及架构测试、随机预算通过；NONE/F/FD均与两种CPU交叉，flags/FS/部分写符合Spike和内存记分板 | task-cpu-v2-fp-validation / 派发时分支 | [ ] |

FPU任务F01–F05在S01后可按依赖并行于整数模块；F07必须等待整数提交/LSU/前端接口实现，F08必须独立于RTL作者。FP32探针先于FPU RTL，D探针以F04真实结构定稿D延迟；不得把FPU资源增量漏计进最终IP。

### 3.5 性能、整片与交付

| 编号 | 内容 | 执行者 | 依赖 | 验收标准 | 拟Task/分支 | 状态 |
|---|---|---|---|---|---|---|
| A01 | 单发射精简/双发射满配×三格式perf回归、固定Zba输入和DIV新日程模型分项对照 | V | I06/F08 | CV15/FV17通过，程序输出正确，模型/RTL分项差异和F03/FT02阈值有依据 | task-cpu-v2-performance / 派发时分支 | [ ] |
| A02 | CPU+L1+FPU独立PDS及完整SoC接入PDS/上板 | W | A01 | 全部相关域setup/hold报告、实测资源、CoreMark/视觉/LVGL及FP负载结果 | Windows任务卡编号待派发 / win分支待派发 | [ ] |
| A03 | 规格定稿、可移植技术包装交付、审核与里程碑汇报 | C | A02 | 所有待定项有数据/明确取值；用户确认正式规格与合入，保留旧核文档边界 | task-cpu-v2-final-review / 协调者分支 | [ ] |

## 4. 规格定稿项

| 关联ID | 已冻结或开发初值 | 定稿时机和数据 |
|---|---|---|
| C01–C09、F01/F02/F04/F05、T02/T03/FT01/FT03 | 接口冻结记录已决定；单发射精简/双发射满配固定Zba，F3R/N8、FD2R/N16、NONE4项FF，共6种全部full | S01完成；模块按v0.2逐信号及行为实施，不重新开放参数 |
| C07模型差异 | DIV独立修正拍正常L=3+n（单发射n=k，双发射n=ceil(k/2)），特殊L2，接口/日程已冻结 | I03按真实日程回放模型，A01不得把第四轮旧周期当新实现保证 |
| F03 | S5/7/8、D6/18/20、DIV/SQRT19/35、D II4，本体与源捕获分开计 | F02/F03/F04逐拍、F06 PDS后更新模型与验证期望 |
| F06 | 固定源副本资源公式，FPGA/ASIC乘法宏实际打包及等价仍待测 | F06及A02真实宏等价/综合资源替代估算 |
| C10、T01、FT02 | 150规划/135压力、资源±30%/FPU±40%仅预算，perf阈值未批准；维护附加拍数、控制扇出预算待测 | I05测维护周期，A01测perf分项，A02整片setup/hold/上板后由协调者与用户定稿 |

## 5. 风险和阻塞

| 风险/当前未决项 | 影响 | 处理与责任 |
|---|---|---|
| F2 owner探针已测，整核异步RAM/LVT布线仍待验证 | 双发射整核频率可能变化 | A02测整核路径，C依实际setup/hold明确修订 |
| 双发射TAGE训练副本/单待写项端口和真实RAM碎片 | 表资源和F2时序变化 | I01验证完整容量端口/旁路，A02测实际宏碎片 |
| RAM元数据使I$失效不再旧核一拍完成 | FENCE.I/复位/维护周期变化 | I05按冻结C02实现扫描/填充重叠语义并测维护周期 |
| 长操作、任意项转发和bank冲突本地捕获新增拍 | 依赖/窗口模型偏差 | V01/F05独立检查；实际多拍则更新规格和模型 |
| FD高beat失败允许低beat部分写，合法8B对齐D不跨行 | 内存比较器必须区分退休与实际副作用 | I05/F07/V01按冻结F04逐beat记录，不实现回滚 |
| APM链和77/84/57位carry为结构估算 | FP延迟/II/频率变化 | F02/F03/F04逐拍与F06实测，F03规格更新后再跑A01 |
| 整片拥塞与独立探针差异、模型未完整覆盖错路/miss | 估算性能无法当板上成绩 | A02完整SoC测量，报告全部域setup/hold和软件条件 |

本表列的是待定设计输入，不代表当前实现已经失败。若探针否定初值，协调者必须明确修改规格/模型和Task，不增加备用路径、门禁或未经请求的保护。

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-27 | v0.1-draft | CPU v2规格阶段实施草稿；先五项PDS探针，再模块/独立验证/集成；FPU统一纳入CPU计划，全部任务未开始 |
| 2026-11-28 | v0.2 | 依据 docs/design/2026-11-28-cpu-v2-interface-freeze.md 已决定状态及更正 C01，冻结接口、行为和两种CPU×三种FPU格式，Zba固定启用，更新模型估算、验证和实施依赖 |
| 2026-11-28 | v0.2 | 按用户决定将单发射固定为精简结构+Zba；双发射满配及NONE/F/FD固定结构不变，同步接口、验证、实施和模型结论 |
