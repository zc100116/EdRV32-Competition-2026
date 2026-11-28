# GPU v2 实施方案

| 项 | 内容 |
|---|---|
| 版本 / 日期 | v0.1 / 2026-11-27 |
| 状态 | 草案；所有实施Task尚未开始 |
| 对应文档 | docs/spec/gpu-v2-spec.md、docs/testplan/gpu-v2-testplan.md v0.1 |
| 决策依据 | 用户批准进入规格阶段；GPU v2架构M-9最终推荐及M-8/M-6单元结论 |

## 1. 目标和完成标准

交付可复现、可验证的GPU v2 IP、Python逐位参考、PC模拟器、ES 1.1 Common驱动与驱动内桌面GL 1.x兼容层。默认必须采用tile64×64/W256/64B十一属性顶点/无DDR平面表、vec4 FP32/C12、四池九在途setup、双lane、分时双纹理与64KiB cache、双帧槽、RGB565/D16/S8；quad/后处理AA默认关闭，对象功能迁至驱动。

完成必须满足：规格行为定稿、配套验证方案smoke/full/perf通过；D1无背压150MHz顶点≥5M/s和11属性setup≥5M次/s；1k/5k/10k实际帧时间、DDR/cache统计、资源和PDS/上板结果可复现。不得把5M顶点或setup次/s改称任意独立三角形5M/s。对未达到的目标必须如实记录，由协调者推动修订与用户确认。

本方案中的任务状态全部为[ ]；它描述后续工作，不表示已经获准实现/合入。每行对应一个Orca Task或Windows任务卡；具体Task五项内容由协调者按该行展开，编码/共享接口必须先冻结再派并行实现。

## 2. 前置条件

- 协调者必须审核三份草稿，并提交用户确认规格；正在上板的gpu-spec v0.6保持独立，不在本阶段追改。
- Linux环境必须具有仓库规定的Verilator5、Python标准库、C11/交叉工具链；参考模型入口为tools/gpu/model/，PC模拟器现有入口为tools/gpu/emu/。不得直接把研究脚本当完整v2模拟器。
- Windows探针必须使用用户创建的PDS工程和真实PG2L200H-6器件、APM/DRM包装；任务卡必须锁commit和PDS版本。Linux不得模拟PDS结果。IP创建说明、寄存器描述、filelists、约束/脚本和docs/spec由协调者维护。
- Mesa与piglit必须具备真实ES1构建/上下文；piglit源码枚举已在验证方案列出，但尚未编译/运行。
- mem_xbar P3必须提供256位边界并支持SoC约定背压；BSP cache一致性、DISP和PLIC契约必须可用于SoC联调。
- 所有资源/吞吐/帧预算初值必须沿M-9计费；完整q/双面字段、索引/段头字节、银行端口和调度待定项必须在对应单元Task前收敛，不得由worker静默补接口。

## 3. 待办清单

执行者模型按CLAUDE.md §11.9：实现、工具、测试使用Codex GPT-6.1 Sol，思考强度medium（用户2026-10-31决定，取代§11.9的high）；协调者负责规格/共享文件/评审，Windows用户负责GUI，Windows Codex负责任务卡允许的命令行与结果收集。独立模块/SoC验证worker不得阅读被测RTL。任务名为拟派发标识，不是已经存在的Task ID或分支。

### 3.1 先做PDS小探针

四探针必须先于大规模模型/RTL实施，探针需要的最小Python向量生成可随探针编写。探针之间可独立派发；每项内部必须包含Linux逐位验证和Windows真实PDS结果，不以结构估算结案。

| 编号 | 内容 | 执行者（角色/模型） | 依赖 | 验收标准 | 分支或任务卡初值 | 状态 |
|---|---|---|---|---|---|---|
| G-P00 | 协调者确认探针接口/指标，准备最小IP说明、约束、导入与四张卡 | 协调者Claude；Windows用户+Codex Sol/medium | 规格草稿评审 | 输入commit/器件/版本/完整操作/产物/通过判据齐全；仅探针所需源文件 | tasks/win/<日期>-<号>-gpu-v2-probes | [~] 探针约束 220 MHz（4.545 ns），两组 worker 已派；四张子卡在 RTL 完成后由协调者合并为一张 |
| G-P01 | vec4 FP32 MUL/FMA与staged DP3/DP4探针，原生4lane、两APM/尾数乘积、独立加法树 | RTL Codex Sol/medium；Windows用户+Codex Sol/medium | G-P00 | 对Python位参考含抵消样本一致；报告12/13拍预算、II、200/150MHz时序、LUT/FF/APM；不得以融合DP替代 | task-gpu-v2-probe-fp32；Windows子卡fp32 | [~] 卡 112：116 MHz（WNS −4.078 @220）；重新切拍 GP-C ctx_6a1e88bfb6eb |
| G-P02 | 小表SFU、II4混合预约、setup独立RCP表读口探针 | RTL Codex Sol/medium；Windows用户+Codex Sol/medium | G-P00 | M5/M6原语料逐位、512混合无预约冲突；实测延迟/时序、1DRM映射与scratch端口/资源 | task-gpu-v2-probe-sfu；Windows子卡sfu | [~] 卡 112：137.8 MHz；重新切拍 GP-C |
| G-P03 | source48 setup规格化/49×33完整积/60位整数重定位探针 | RTL Codex Sol/medium；Windows用户+Codex Sol/medium | G-P00 | area1/近共线/抵消/64边界与Python一致；完整积低位保留；200/150MHz资源与时序 | task-gpu-v2-probe-setup-arith；Windows子卡setup | [~] 卡 112：114.5 MHz（N48 首拍 27 级）；重新切拍 GP-C |
| G-P04 | RF/常量/program与setup72×92 bank的DRM映射/读写捕获探针 | RTL Codex Sol/medium；Windows用户+Codex Sol/medium | G-P00 | 单写入点、真实IP延迟/同址语义、最坏并发读写和bank冲突trace；实测DRM/CLMS/FF；核实C12行宽初值 | task-gpu-v2-probe-banks；Windows子卡banks | [x] 卡 112：DRM 版 243.8 MHz/159 DRM，LUTRAM 版 259.9 MHz/15 DRM+3312 LR；同址旧值 ModelSim PASS；映射待 G2-08 |
| G-P05 | 审核四探针、修订延迟/资源/频率及算法/端口定稿项 | 协调者Claude | G-P01..04 | 原始报告与commit齐全；G2-01/06/07/08写入已确认结论或明确剩余待定，不删除失败样本 | task-gpu-v2-probe-review | [ ] |

### 3.2 Python模型与PC模拟器升级

| 编号 | 内容 | 执行者（角色/模型） | 依赖 | 验收标准 | 分支或任务卡初值 | 状态 |
|---|---|---|---|---|---|---|
| G-M01 | 冻结原生命令、状态包、全属性顶点/bin/目标格式与单元接口 | 协调者Claude，模型/驱动接口评审Codex Sol/medium | G-P05 | 逐字段编码可生成，64B一般q/双面完整性明确；索引表/段头流量更新；G2-02..06关闭到可实现版本 | task-gpu-v2-contracts | [ ] |
| G-M02 | Python v2逐位模型：顶点/SFU/clip/source48与完整图元覆盖 | 模型Codex Sol/medium | G-M01 | VT04–11的逐位向量、M5/M6全部原语料与780恒等式；特殊值/负分母按定稿契约 | task-gpu-v2-model-geometry | [ ] |
| G-M03 | Python v2逐位模型：cache语义、双纹理/env/fog/像素/目标/双槽 | 模型Codex Sol/medium | G-M02 | VT12–18定向期望、所有枚举/顺序、ReadPixels布局；模型自检通过 | task-gpu-v2-model-pixel | [ ] |
| G-M04 | PC C模拟器升级v2，接统一格式/命令与API fixture回放 | 模拟器Codex Sol/medium | G-M03 | 同命令/DDR输入与Python最终目标/读回逐位一致；C11 -Wall -Wextra -Werror；旧入口不被误当v2 | task-gpu-v2-emu | [ ] |
| G-M05 | Mesa ES1环境、piglit PG01–04与API/帧fixture、容差校准 | 验证Codex Sol/medium | G-M04 | 真ES1+软件renderer证据、源码目标实跑、M分类误差与边界报告；V2-01/02由协调者冻结 | task-gpu-v2-api-reference | [ ] |
| G-M06 | v2事件/周期与DDR/cache trace模型，重算三档和1k/5k/10k预算 | 模型Codex Sol/medium | G-M04 | M9原点复现；v/f/λ实数、扩展记录/索引/段头/物化字节完整，lower/planning/serial分列；不得宣称已板测 | task-gpu-v2-cycle-model | [ ] |

### 3.3 按单元拆RTL Task

本阶段必须在G-M01接口冻结、G-M02..06模型/模拟器基础完成后启动。下表各实现Task必须包含所属单元TB、相应smoke/full与lint/风格0告警；共享文件改动由协调者独立处理。独立验证Task可与实现Task同时开始，依据冻结规格写TB。

| 编号 | 内容 | 执行者（角色/模型） | 依赖 | 验收标准 | 分支或任务卡初值 | 状态 |
|---|---|---|---|---|---|---|
| G-R01 | 顶点vec4引擎、C12 RF、常量/程序加载、静态排程与ISA | RTL Codex Sol/medium | G-M05/06 | VT04/05与Python逐指令；D1≥5M顶点/s@150预算；所有已公布状态程序容量可装入 | task-gpu-v2-vertex | [ ] |
| G-R02 | SFU小表、混合请求/标签/scratch、共享setup倒数读口 | RTL Codex Sol/medium | G-M05/06 | VT06，II4与真实延迟、源端口/返回写口冲突覆盖，表1DRM | task-gpu-v2-sfu | [ ] |
| G-R03 | 六视锥+一用户面clip、投影、flat/双面、点中心裁剪 | RTL Codex Sol/medium | G-M05/06 | VT07/10，共享边反向逐位、全属性传递与标准六面 | task-gpu-v2-clip | [ ] |
| G-R04 | 四池/九在途setup、field banks、source48与整数重定位 | RTL Codex Sol/medium | G-M05/06 | VT09/10/22；11属性≥5M次/s@150、首包与16属性单列；逐位跨tile无跳变 | task-gpu-v2-setup | [ ] |
| G-R05 | bin、输入/tile顶点cache、64B及定稿扩展打包、W256 DMA | RTL Codex Sol/medium | G-M05/06 | VT08/13，真实字节/聚合、draw身份、顺序与无DDR平面表 | task-gpu-v2-bin | [ ] |
| G-R06 | 双lane三角形覆盖、width1线/点smooth/sprite覆盖 | RTL Codex Sol/medium | G-M05/06 | VT11/22，共享边/端点与Python一致、lane尾部/helper正确 | task-gpu-v2-raster | [ ] |
| G-R07 | 两投影纹理透视/2×2 LOD和helper流水 | RTL Codex Sol/medium | G-M05/06 | VT10/12，一般q、负/零分母按定稿语义、各舍入节点逐位 | task-gpu-v2-perspective | [ ] |
| G-R08 | texture格式/地址/过滤/两遍反馈、64/128/192KiB四bank cache | RTL Codex Sol/medium | G-M05/06 | VT12/13/22，冷/热输出相同，miss/evict/更新身份正确、服务率实测 | task-gpu-v2-texture | [ ] |
| G-R09 | env/COMBINE、雾、coverage alpha、全部像素运算 | RTL Codex Sol/medium | G-M05/06 | VT14/15/22全枚举、alpha0、Da=1、logic旁路、连续RMW正确 | task-gpu-v2-pixel | [ ] |
| G-R10 | tile load/store、RGB565/D16S8与可选目标、物化/ReadPixels支持 | RTL Codex Sol/medium | G-M05/06 | VT16，保留D/S/clear mask、多区间、目标最后B完成 | task-gpu-v2-target | [ ] |
| G-R11 | 原生命令/APB寄存器、双槽控制、状态版本、完成/中断/ABORT | RTL Codex Sol/medium；共享定义协调者 | G-M05/06 | VT01/02/17/18，两个边界错误，无内部额外检查；退休与所有权严格正确 | task-gpu-v2-command | [ ] |
| G-V01 | 独立GPU模块/SoC TB与API fixture适配 | 独立验证Codex Sol/medium，不读被测RTL | G-M05/06、冻结接口 | 按VT01–25实现计划内测试和字段映射；模块比较Python，SoC含P3/PLIC/BSP | task-gpu-v2-block-verif | [ ] |
| G-I01 | RTL集成与独立TB联调、默认档回归、参数构建 | 集成Codex Sol/medium；协调者审查 | G-R01..11、G-V01 | smoke/full/perf、所有逐位比较；失败分RTL/测试/规格归因，规格歧义先问 | task-gpu-v2-integrate | [ ] |

### 3.4 最后实现驱动与兼容层、整片验证

| 编号 | 内容 | 执行者（角色/模型） | 依赖 | 验收标准 | 分支或任务卡初值 | 状态 |
|---|---|---|---|---|---|---|
| G-D01 | 原生命令提交、内存/状态快照、双槽、BSP一致性、物化/退休 | 驱动Codex Sol/medium | G-I01 | VT02/08/16/17/18的PC与SoC相同输入结果；无过早复用/错误吞掉 | task-gpu-v2-native-driver | [ ] |
| G-D02 | ES1.1 Common状态/API/矩阵栈/数组/VBO/灯/纹理/mip/palette/错误 | 驱动Codex Sol/medium | G-D01 | F01–F19入口和最小限制覆盖、VT03/19/25、Mesa帧与Python比较；微码全部状态可装入 | task-gpu-v2-gles11 | [ ] |
| G-D03 | 桌面GL1.x兼容集合、对象运动/碰撞迁驱动 | 驱动Codex Sol/medium | G-D02 | VT20/21；公布函数逐个与等价ES流相同；CPU对象成本/状态副作用单列 | task-gpu-v2-desktop-compat | [ ] |
| G-D04 | 可选quad/后处理AA实现与集成（仅范围确认后派发） | RTL/驱动Codex Sol/medium | G-D03、G2-12可选范围定稿 | VT20开启/关闭，AA halo与原图邻域正确；默认构建仍为关闭 | task-gpu-v2-options | [ ] |
| G-W01 | 全GPU及整片PDS/上板卡，150/200MHz、P3竞争和真实cache trace | 协调者卡；Windows用户+Codex Sol/medium | G-D03；启用可选项时加G-D04 | 资源/时序按CLAUDE10.5，1k/5k/10k/读回场景原始数据，实际freq/B/λ/v/f，VT23/24 | tasks/win/<日期>-<号>-gpu-v2-board | [ ] |
| G-F01 | 依据回归/PDS/板测关闭待定项、审核定稿与用户验收 | 协调者Claude | G-W01 | G2-01..12/V2-01..03逐项决议；规格/验证/方案同步，未达标明确报告，用户确认后合入/tag | task-gpu-v2-finalize | [ ] |

G-D04为可选功能待办，若用户决定本版关闭且不实施，协调者必须在正式方案中移除该Task并保留关闭构建验收，不把未实现标成完成。任何条目实施前都必须限定文件归属；并发worker必须用独立worktree，共享文件只由协调者修改。

## 4. 规格定稿项

| 规格/验证编号 | 定稿内容 | 时机/任务 | 依据/负责者 |
|---|---|---|---|
| G2-01 | FP32/SFU/setup切拍、实际频率、W256η及GPU带宽份额 | G-P05初定，G-W01最终 | 探针与整片PDS、共享DDR板测；协调者/用户 |
| G2-02 | 最小限制、point/sprite范围、viewport、桌面兼容函数集合 | G-M01 | API状态清单/ES1要求/驱动支持范围；协调者/用户 |
| G2-03 | 原生头/负载/状态、APB/错误/AXI身份 | G-M01；G-R11前冻结 | 模型与驱动接口逐字段评审；协调者 |
| G2-04 | 完整64B布局与一般q/双面表示，禁止FP16 | G-M01并由G-M02实证；G-R05前冻结 | 全状态输出标量计数、逐位精度、DDR重新计费；协调者/用户 |
| G2-05 | bin段头/源索引表/clear记录、打包burst | G-M01、G-M06 | 真实DDR字节和顺序trace；协调者 |
| G2-06 | 1024行指令/静态控制宽度、C12派生、灯循环 | G-P04/05、G-M01/02；G-R01前冻结 | 最坏状态可装入与发射/返回冲突、DRM端口；协调者 |
| G2-07 | FP32特殊值、clip/透视舍入、SFU返回延迟 | G-P05、G-M02；G-R01/02/03/07前冻结 | 每节点位结果、M5/M6压力和PDS延迟；协调者/用户 |
| G2-08 | setup bank字段/端口与tile侧setup/双槽调度 | G-P04/05、G-M06；G-R04/05/11前冻结 | 逐拍bank预约/真实DRM返回，不能只用理想DAG；协调者 |
| G2-09 | 精确点线smooth/diamond覆盖、量化 | G-M02/05；G-R06前冻结 | 独立覆盖模型和Mesa对照；协调者/用户 |
| G2-10 | texture存储/cache配置、MIN/MAG门限 | G-M03/05/06；G-R08前冻结 | tap/过滤逐位、真实trace、带宽/资源；协调者 |
| G2-11 | env/COMBINE整数表、PolygonOffset量化 | G-M03/05；G-R09前冻结 | ES公式与解析向量/Mesa；协调者 |
| G2-12 | 三档/可选功能、AA halo和资源/帧估算 | G-M06初定；G-D04派发前决定功能，G-W01最终测量 | 明确目标格式/属性负载、整片CLMA/CLMS与板测；协调者/用户 |
| V2-01/02 | 锁Mesa/piglit环境、分类容差 | G-M05；G-V01前冻结 | 真ES1软件renderer、定向帧/边界差异；协调者 |
| V2-03 | 验证期望与全部规格待定同步 | 各对应Task前；G-F01闭合 | 条款→VT映射逐项完整，不能以SKIP代替必需项；协调者 |

对规格范围的选择由用户最终决定；协调者应一次提问一项，给推荐和可审查数据。不能把未决格式作为实现worker自行选择的自由度，也不能增加额外防御检查或自动降级来绕过未决项。

## 5. 风险和阻塞

| 风险/当前未决事实 | 应对工作与归属 |
|---|---|
| 64B仅证明十一属性的容量提案，一般q/双面可能需要更多字段；M9未做完整格式数值验证 | G-M01/02计数并冻结，G-M06重新计费；不得先用FP16填入 |
| Task旧1024×96与M8 C12行宽不同 | 已获协调者确认用64位指令+待定控制，160有效位初值/5DRM；G-P04/G-M02验证压缩可能性 |
| setup 29.714平均模型依赖72 bank真实地址/端口，M9改为每tile重建 | G-P03/04验证、G-M06按tile消费侧调度；G-R04报告均值/首包/尾部与实际气泡 |
| 顶点5M/s不等于源三角形5M/s，cold mesh普通setup上限约3.089Mtri/s | G-M06/G-W01分开报告v/f/λ与pixel；不选未批准的专用setup替代四池方案 |
| 完整ES一般q、双面、smooth点线、特殊值尚未端到端数值证明 | G-M02/03/05及独立VT，先冻结算术再实现；所有原压力样本保留 |
| W256提高接口能力不提高物理DDR；高miss/保留D/S/读回会破坏理想交叠 | G-M06/G-V01/G-W01真实合计流量与序列；模型三种口径分列 |
| PDS资源±40%估算、CLMS列拥塞；满配纹理/目标额不含所有附加逻辑 | 探针优先，整片结果由G-W01收敛；不得用容量余额宣称可布线 |
| piglit现有GLES1覆盖窄；Mesa真实ES1环境尚未建成 | G-M05建环境并自有fixture补足；未公布扩展只记录不适用 |
| Windows PDS/IP/用户GUI排期是外部依赖 | G-P00明确卡和产物，协调者安排执行；没有报告时明确未取得，不编造测量 |

以上是规格/实施数据未决项，不引入运行时门禁、检查/校验和、watchdog、重试或兜底。当前仅起草文档，没有实施失败或实测资源结论。

## 6. 变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-11-27 | v0.1 | 初稿；顺序为PDS四小探针→Python/PC模型→单元RTL与独立验证→驱动/兼容层→整片/上板；所有Task为[ ]；登记G2/V2定稿时机 |
