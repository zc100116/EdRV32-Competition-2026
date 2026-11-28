# CPU v2 IP 规格

| 项 | 内容 |
|---|---|
| 版本 | v0.2 |
| 日期 | 2026-11-28 |
| 状态 | 已确认（用户 2026-11-28 决定接口冻结与配置收敛）；C10、F03、F06 仍待实测 |
| 范围 | 独立可移植 CPU v2 IP：整数核、L1 I$/D$ 及控制器、可选 FPU 集成 |
| 关联文档 | docs/spec/fpu-spec.md、docs/testplan/cpu-v2-testplan.md、docs/testplan/fpu-testplan.md、docs/plan/cpu-v2-plan.md；docs/design/2026-11-27-cpu-v2-architecture.md 第四轮；docs/design/2026-11-27-cpu-v2-fpu.md 第二版；docs/spec/edrv32-soc-spec.md |

## 1. 概述

1.1 CPU v2 必须是可移植的独立 IP；在 EdRV32 SoC 中必须工作于 clk_sys，作为控制和通用计算核心，通过两个 AXI64 主口访问系统总线。

1.2 本规格定义新 IP。`docs/spec/cpu-spec.md` v0.23 和 `docs/spec/cache-spec.md` v0.14 继续描述正在使用的旧核，不因本草稿改变。本文明确引用的旧规格仅作为兼容契约，不继承其旧流水实现和时序数字。

1.3 FPU 内部算术和流水必须符合 `fpu-spec.md`；CPU 集成必须符合本文第3节、4.2、5.6。

## 2. 功能描述

### 2.1 ISA 与配置

必须实现 RV32IM、Zicsr、Zicntr、Zifencei 和 M 态；不实现 C、A、Zbb、PMP、S/U、调试模式、触发器和 NMI。指令必须 4 字节对齐，整数 load/store 必须自然对齐。必须实现 Zba，仅包含 RV32 的 SH1ADD/SH2ADD/SH3ADD。

FPU_FORMAT 必须为 NONE、F 或 FD；F/FD 的完整软件可见行为见 fpu-spec 2、4、6。NONE 必须不实现 FP 状态和 FP CSR，F 必须不接受 D 指令。

### 2.2 构建参数与固定结构

CPU 必须只提供以下两个构建参数；其他结构必须按固定表实现，不保留独立开关。

| 参数 | 合法值 | 板级取值 |
|---|---|---|
| ISSUE_WIDTH | 1（单发射精简）、2（双发射满配） | 2 |
| FPU_FORMAT | NONE、F、FD | F |

| 固定结构 | 单发射精简 | 双发射满配 |
|---|---|---|
| 快速预测 / TAGE | gshare4096，无TAGE | gshare4096；4×512，历史4/12/32/96 |
| BTB / RAS | 64项 / 4深 | 128项 / 8深 |
| IB | 4项，另有4项物理在途预留 | 8项，另有4项物理在途预留 |
| 取指 | 64位、8B对齐 | 双32位bank，任意4B对齐PC/PC+4 |
| 整数RF | 异步2R1W，2048数据bit，无LVT | 异步4R2W，两owner×四读副本，8192数据bit，F2 LVT候选 |
| 晚执行 | 无 | 每管线早ALU+晚简单ALU、晚条件分支 |
| MUL / JALR | 单管线共享入口 | 两管线择老共享入口，单元各一套 |
| DIV | radix-2位长提前结束，独立符号修正拍 | radix-4位长提前结束，独立符号修正拍 |
| HPM | 2个（3–4） | 8个（3–10） |
| Zba | SH1ADD/SH2ADD/SH3ADD，固定实现 | SH1ADD/SH2ADD/SH3ADD，固定实现 |
| LSU / 缓存 | 单LSU，I$/D$各32KiB/2路/32B行，不合并双load | 同左 |

| FPU格式固定结构 | NONE | F | FD |
|---|---|---|---|
| FP RF / 源读口数 | 无 | 32×32 / 3 | 32×64 / 2 |
| 全核完成记录数 N | 4，独立FF | 8，LUTRAM数据/PC+FF控制 | 16，LUTRAM数据/PC+FF控制 |
| tag位宽 T / 数据位宽 B | 2 / 32 | 3 / 32 | 4 / 64 |
| 单/双发射统一源端口数 S | 2 / 4 | 3 / 5 | 2 / 4 |
| 分配信用位宽 | 3 | 4 | 5 |

合法配置必须为2×3共6种，全部完整回归；本SoC板级必须为双发射满配+F。N/T/B/S是固定结构的局部常量，不是构建参数。

### 2.3 发射与执行能力

必须顺序发射和按序提交。程序槽0较老、槽1年轻；执行管线与程序槽分离，退休、异常、中断、冲刷和WAW必须按槽年龄判定。

| 执行管线 | 单发射精简 | 双发射满配 |
|---|---|---|
| 管线0 | 全部类型 | 全部类型 |
| 管线1 | 无 | A早整数ALU（含移位/Zba）、B条件分支/JAL、M乘法、J JALR |

L为整数LSU，D为DIV，P为FP算术/转换/FP访存，S为CSR/系统/FENCE；这些类型必须进入管线0。单发射必须每拍至多发射一条。双发射两条同组必须满足：

1. 必须存在一条进入管线1、另一条进入管线0的分配。槽1可由管线1执行时，槽0→管线0、槽1→管线1；否则槽0可由管线1执行时必须互换。因此年轻LSU/DIV可与老A配对。
2. 每组必须至多一条控制转移（B/J）、一条LSU、一条MUL、一条DIV、一条P；共享单元不复制。
3. S必须两个方向均不配对，并等待更老指令达到有序边界。P必须仅与独立A同组，P进入管线0。
4. 槽1源等于槽0目的时必须禁止RAW配对（整数x0除外）；5.3的早ALU/实际短load→晚简单ALU/条件分支为例外。FP组内相关必须不配对。WAW可配，年轻写生效；WAR必须不阻塞。
5. 槽1异常时槽0必须可正常提交，与管线分配无关。

## 3. 接口

### 3.1 模块与位宽约定

所有端口必须同属clk_sys；每个模块必须有1位clk_i、rst_n_i，控制异步复位并在本域同步释放，数据阵列不复位。下表所有内部信号均采用所在模块的_i/_o方向后缀，表内“a/b”必须分别实现为独立标量端口。I为1或2，T/B/S及N必须采用2.2的固定值；R在F为3、FD为2，NONE无FP端口。双发射TAGE表数固定4，索引9位；单发射无TAGE及其查询/训练/快照端口。IB信用单/双发射为4/4位；RAS内容/指针/计数单发射为128/2/3位，双发射为256/3/4位。表中j/p为编译时逐端口展开；单发射的执行/分配/退休/WB只有j=0，取指组仍可返回两个字。

外部AXI64/APB必须沿SoC4.1/4.3和旧cache2.3/4/5.3/5.4/6，PMA与寄存器不变；APB地址为12位。位宽T代表NONE/F/FD分别2/3/4，B代表32/32/64，S代表2.2固定表，不得另引入可配参数。逐信号接口见3.9。


下表文件均以 `.v` 结尾；CPU根为 `rtl/cpu2/`，FP根为 `rtl/cpu2/fpu/`。全部clk_sys，不引入其他域；包装位于rtl/tech，表中模块必须按职责实现，已有探针必须补齐完整控制。

| 文件/模块（省略.v） | 职责和规格条款 |
|---|---|
| edrv32_cpu2_top | 外部AXI/APB/IRQ、模块连线；CPU1/3/4.3 |
| edrv32_cpu2_frontend | F1/F2 PC、重定向、双bank/RAS恢复；CPU5.1/5.5 |
| edrv32_cpu2_predictor | fast gshare/BTB/RAS；CPU5.4/5.5 |
| edrv32_cpu2_tage / edrv32_cpu2_tage_update | 仅双发射TAGE查询/训练/待写；CPU5.4/C08；既有探针必须扩展到固定4×512几何 |
| edrv32_cpu2_fetch | I$物理bank拼合/owner候选；CPU5.2/5.5；既有探针拆出IB职责 |
| edrv32_cpu2_ib | 按发射宽度固定头、在途信用和候选维护；CPU5.2/5.5 |
| edrv32_cpu2_decode / edrv32_cpu2_issue | 译码、配对/整数及FP记分牌、源捕获；CPU2/5.1–5.3/5.6 |
| edrv32_cpu2_rf / edrv32_cpu2_id_agu | 异步RF/LVT、ID提前地址；CPU5.2；既有 |
| edrv32_cpu2_alu / edrv32_cpu2_branch | 按2.2实现单管线EX或双管线EX/MEM简单执行、分支/JALR；CPU5.2/5.3/6.1 |
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

### 3.2 通用握手与年龄

下表中 `execute{j}`、`alu{j}_complete`、MEM 等待位的 j 指**执行管线**（2.3）；`allocate{j}`、`head{j}`、`wb{j}`、`fetch_push{j}`、`ib_head{j}` 的 j 指**程序槽**。issue 在发射沿按 C01 规则把程序槽映射到管线，并把各自的完成 tag 随指令带到管线，退休和取消只按 tag 年龄判定。

表中方向A→B表示A端 `_o`/B端同词干 `_i`；反向亦然。凡valid/ready接口，posedge `valid&&ready`接受一次，等待保持valid/全部负载，只有取消可撤销尚未接受项；ready来自已寄存容量，ID只用寄存credit。固定延迟查询无ready时，由调用者预留接收槽。独立完成源各自一套接口，不能用共享valid隐含多源丢弃。

完成tag按程序顺序分配，双发射tag1=(tag0+1)modN；不为x0、branch、store省略记录。`age_head`是本拍开始最老存活tag，距离d=(tag−head)modN，只比较valid项，满N时用占用数区分满/空，不能用裸tag大小或半环比较。退休只释放连续队头。取消 `cancel_tag` 是首个取消项，清d≥d(cancel_tag)的存活项；分支取消从分支后第一存活tag开始，空年轻区不发cancel；陷阱/中断从故障/未退休头开始。head/cancel广播同沿生效，不额外打一拍再修正。

取消沿内所有生产者清被取消valid、包括已完成未交付结果与FP flags，禁止再次输出该实例；队列恢复tail后下一拍可重用tag。已发AXI必须收完，cache自行抑制取消结果，不让旧响应贴到新tag；不要求AXI可撤销。取消同拍响应可保持valid，接收方按年龄丢弃（不组合屏蔽响应形成环）。没有取消ack、epoch、检查错误位。前端未分配完成tag，以有序请求上下文关联I$；重定向清所有未发射项并使在途上下文无效，credit按撤销预留归还。

### 3.3 前端、IB、发射与预测器

每条IB记录保存PC/指令/取指异常和快速预测快照；owner候选及TAGE token/4表字段只在双发射保存，4表字段按表分别传递，不能把长历史原样塞入IB。RAS快照必须分字段保存，内容/指针/计数的单/双发射位宽见3.1；两个字从同一原快照按程序顺序应用call/return，F2纠正重新应用保留前缀动作。

| 信号词干（加方向后缀） | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| fetch_push_valid / fetch_push_ready | fetch→IB / IB→fetch | 各1 | 整组入队；信用预留后返回必能存入 |
| fetch_push_count | fetch→IB | 2 | 1/2条；老taken只保留前缀 |
| fetch_push{j}_pc / instr | fetch→IB | 各32 | j=0,1，程序顺序 |
| fetch_push{j}_error | fetch→IB | 1 | 该字访问错误，后继不覆盖老字异常 |
| fetch_push{j}_candidates（仅双发射） | fetch→IB | 5 | 两物理路的rs1/rs2 owner各2bit+bank选择1bit |
| fetch_push{j}_predict_taken / predict_target / predict_token | fetch→IB | 1/32/1 | 方向/目标；token仅双发射，表示有F1查询 |
| fetch_push{j}_predict_provider / predict_alternate（仅双发射） | fetch→IB | 3/1 | 0为base，1..4最长表 |
| fetch_push{j}_predict_index{p} / predict_tag{p}（仅双发射） | fetch→IB | 9/10 | p=0..3，查询时快照 |
| fetch_push{j}_predict_base_index / predict_fast_index | fetch→IB | 12/12 | base_index仅双发射；fast_index用于两种配置的gshare训练 |
| fetch_push{j}_ras_data / ras_ptr / ras_count | fetch→IB | 单128/2/3；双256/3/4 | 发射后只由控制指令携带快照 |
| ib_head{j}_valid | IB→decode/issue | 1 | 单发射一头/双发射双头，无ready组合回IF |
| ib_head{j}_各字段 | IB→decode/issue | 同上逐字段 | 词干由fetch_push替换ib_head，读头不弹出 |
| ib_remove_count | issue→IB | 2 | 当沿实际分配/执行接受的连续老前缀0..1（单发射）或0..2（双发射） |
| ib_credit | IB→frontend | 4 | 单8/双12物理条目减驻留/在途预留，寄存值 |
| frontend_flush | commit/branch→frontend/IB | 1 | 清未发射及在途上下文；重定向优先于入队 |
| redirect_valid / redirect_pc | commit/branch→frontend | 1/32 | 注册恢复PC，按最老有效重定向选择 |
| redirect_tag / age_head | completion→branch/commit | T/T | 比较已发射重定向年龄 |
| predict_req_valid / predict_req_pc | frontend→predictor/TAGE | 1/32 | F1双字查询，预留F2容量，无ready |
| predict_resp_valid / predict_resp{j}_各predict字段 | predictor/TAGE→fetch | 1/同上 | 固定F2，按原请求对应，不受本拍ID推进影响 |
| predict_train_valid / tag / pc / taken / target / type | branch→predictor | 1/T/32/1/32/3 | 类型0条件、1JAL、2JALR、3call、4return、5先pop再push；由指令链接寄存器关系译码 |
| predict_train_fast_index | branch→predictor | 12 | 查询时gshare索引；单发射EX一组，双发射EX/MEM各一组，取消项不训练 |
| predict_train_token / provider / alternate / index{p} / tag{p} / base_index（仅双发射） | branch→TAGE | 同上述token字段 | 另有predict_train_prediction 1位；EX/MEM各一组，MEM老；取消项不训练 |

预测快照在发射至branch时按上述字段原样传递；BTB valid、位置、目标由predictor持有。IB候选更新直接侦听下表的提交WB，WB1覆盖WB0；新入项和移动前存活项同沿修正。单发射无LVT，候选/owner接口不实例化；单发射不实例化MEM晚执行及source_wait端口，源依赖必须在发射前等待。

### 3.4 RF、分配、源转发与执行

| 信号词干 | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| id_rs{p} / id_owner{p} / id_data{p} | issue→RF / issue→RF / RF→issue | 5/1/32 | p=0..1（单发射）或0..3（双发射），异步读，本地捕获；单发射无owner |
| lvt（仅双发射） | RF→fetch/IB | 31 | x1..31 owner，沿现有探针；区域复制不延迟 |
| wb{j}_valid / rd / data | commit→RF/fetch/IB | 1/5/32 | 当沿架构写，j0老j1年轻，x0不写 |
| fp_read{p}_addr / fp_read{p}_data | issue→FP RF / FP RF→issue | 5/B | p=0..R−1，异步读、本地捕获，f0可写 |
| fp_wb_valid / rd / data | commit→FP RF | 1/5/B | 单写，当沿按序提交 |
| allocate_credit | completion→issue | 3/4/5（NONE/F/FD） | 寄存空项信用，本拍提交不组合馈入 |
| allocate_valid / allocate_count / allocate_ready | issue→completion / issue→completion / completion→issue | 1/2/1 | 0..1（单发射）或0..2（双发射）项连续分配，原子对应执行接受；不足只发老项 |
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

源接口物理统一为p=0..S−1，其中S按2.2固定表；表中source还附 `source{p}_domain` 1位（0整数、1FP），issue按本拍实际源映射到这些端口，不同时暴露额外独立的FP队列读口；记分牌在issue内维护架构域→最新tag，取消后从保留项恢复，不能把旧tag源当成RF版本。2R未读rs3记住生产tag，即使生产者此时退休也必须捕获正确值；不允许年轻同目的FP提前覆盖。

### 3.5 完成、提交与 CSR

CSR指令的源和操作编码随allocate登记，commit使用该份已捕获记录。每个ALU、branch、MUL、DIV、LSU、CSR、FP响应有独立完成源，前缀 `alu0_complete`、`alu1_complete`、`branch_complete`、`mul_complete`、`div_complete`、`lsu_complete`、`csr_complete`、`fp_resp`。branch的链接值和PC作为一个完成源，不重复送ALU完成。

| 信号词干 | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| *_complete_valid / *_complete_ready | 单元→completion / 反向 | 各1 | 争用保留本地结果，年龄优先 |
| *_complete_tag / data / flags | 单元→completion | T/B/5 | 整数高位0，非FP flags0 |
| *_complete_exception / cause / tval | 单元→completion | 1/4/32 | 仅CPU6.1已定义同步异常，非法由decode生成同格式独立源 |
| head{j}_valid / done / tag / pc / instr / rd / dest / data / flags | completion→commit | 1/1/T/32/32/5/2/B/5 | 按发射宽度设置头端口，data先捕获；单发射j=0，双发射j=0,1 |
| head{j}_exception / cause / tval / store / divide / double_beat / csr_src | completion→commit | 1/4/32/1/1/1/32 | 提交按年龄，不越过未done头 |
| retire_count | commit→completion | 2 | 释放连续头0..1（单发射）或0..2（双发射），不能越过单FP写限制 |
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

### 3.6 核与FPU及其各单元

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

### 3.7 LSU、D$和提前查询

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

### 3.8 前端与 I$、维护控制

I$请求是一组最多两条指令，内部最多保留两组上下文（同步返回槽+miss后续已接收槽）；IB按每组两条预留信用。双bank跨行两行分别查询，miss串行完成后组装，两字分别保存错误；两组按序响应，没有tag复用歧义；取消只需清全部未发射上下文。

| 信号词干 | 方向 | 位宽 | 语义/握手/取消 |
|---|---|---:|---|
| ic_req_valid / ic_req_ready / ic_req_addr | frontend↔I$ | 1/1/32 | 请求PC，单发射为8B对齐，双发射为4B对齐 |
| ic_resp_valid / ic_resp_ready | I$↔frontend | 各1 | 响应组，本地捕获；不静默丢弃已接受组 |
| ic_resp_word{j}_way{k}_instr / ic_resp_word{j}_way_hit / ic_resp_word{j}_error | I$→fetch | 每路32/2/1 | j=0,1对应PC/PC+4，k=0,1两路未选数据；owner查询在选路前并行，不能先mux指令再查LVT；非缓存返回way0 |
| ic_cancel | frontend→I$ | 1 | 冲刷全部未返回组；AXI收完不回送，取消同拍响应由前端丢弃 |
| ic_inv_valid / ic_inv_ready / ic_inv_done | commit↔I$ | 各1 | FENCE.I在D全clean后发，512组扫描完成给done |
| ic_miss_event | I$→CSR | 1 | 每行miss一次，跨行双miss计两次 |
| maint_req_valid / maint_req_ready / maint_cmd / maint_addr / maint_size | cache_ctrl↔D$ | 1/1/3/32/32 | 沿cache3.2方向，valid保持到ready |
| maint_busy / wb_err / wb_err_addr | D$→cache_ctrl | 1/1/32 | BUSY、电平扫描状态；写回错误单拍/行地址 |
| cache_irq | cache_ctrl→top | 1 | IRQ_STAT&IRQ_EN，外部cache_irq_o |

FENCE.I顺序为D全clean done→I inv done→注册下一PC重取。维护请求与FENCE由D$单个维护入口串行；设备轮询可继续，可缓存已接受请求本地等待；队列容量和ready只用登记状态，不能让地址译码组合回ID。

### 3.9 L1外部逐信号表

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

### 3.10 技术包装逐信号与几何

RF包装端口为 `clk_i`1、`wr_en_i`1、`wr_addr_i`5、`wr_data_i`32、`rd_addr_i`5、`rd_data_o`32，异步读。cache包装端口为 `clk_i`1、`wr_en_i`1、`wr_addr_i`A、`wr_data_i`D、数据宏另有`wr_mask_i`D/8、`rd_addr_i`A、`rd_data_o`D，同步一拍读，无valid/ready；调用者用流水valid关联，取消只清控制。技术包装本身不理解年龄，不增加取消口。

| 包装名称（rtl/tech，省略.v） | 几何/副本 |
|---|---|
| edrv32_ram_cpu2_rf | 32×32，双发射2owner×4读，单发射2读；AGU额外RF读按实际路径复制 |
| edrv32_ram_cpu2_cache_data | I$双bank每路2048×32，共4宏；单bank每路2048×64用下列data64宏 |
| edrv32_ram_cpu2_cache_data64 | I$单bank/D$每路2048×64，D$8字节写使能，无D$查询副本 |
| edrv32_ram_cpu2_cache_tag | I$每路512×19 valid+tag；双bank查询按端口需求复制/分bank，容量不翻倍 |
| edrv32_ram_cpu2_cache_dtag | D$每路512×20 valid+dirty+tag |
| edrv32_ram_cpu2_cache_lru | 每侧512×1，同步元数据；两路比较后下一拍更新 |

技术包装地址/数据位宽必须固定如下：RF为5/32；cache_data为11/32，cache_data64为11/64且mask8；cache_tag为9/19，cache_dtag为9/20，cache_lru为9/1。仅双发射的TAGE训练为9/16，预测奇偶bank为8/16；base训练为12/2，预测bank为11/2。通用端口中的A/D必须分别采用对应固定地址/数据位宽。

仅双发射实例化TAGE：每表512×16，训练512×16；预测按双字奇偶bank各256×16、base预测2×2048×2；base训练4096×2。读/写地址宽度由深度导出；数据宽16/2，同步1R1W，写端无mask。两种配置fast异步4096×2按容量分bank；单发射BTB64，双发射BTB128按总容量奇偶bank，RAS为寄存状态。FPU RF必须为F32×32三读副本、FD32×64两读副本，异步单写；F共享完成每bank低32位为4×32、单/双发射4/6副本；FD低32位为8×32、单/双发射3/5副本，FD高32位8×32为3副本，另有F4×32/FD8×32 PC宏；NONE必须用4项FF，不实例化上述完成RAM，控制valid/flags为FF；S见2.2固定表；资源见fpu-spec 7.2，F06实际宏打包另定。

### 3.11 退休trace（顶层内部线）

单发射j=0，双发射j=0,1按年龄，只有一条时在0。所有字段在该退休或陷阱事件拍有效，非退休项字段不要求有意义。名称均以 `_w` 结尾。

| 信号 | 位宽（单发射；双发射） | 语义 |
|---|---:|---|
| trace_valid_w / trace_pc_w / trace_instr_w | 1/32/32；2/64/64 | 每槽退休valid/PC/编码，低字段老 |
| trace_rd_w / trace_rd_domain_w / trace_rd_data_w | 5/2/64；10/4/128 | 每槽5bit rd、2bit目的域、64bit值；FP f0不能当无写 |
| trace_flags_w / trace_fflags_w / trace_frm_w / trace_fs_w | 5/5/3/2；10/5/3/2 | 每条flags及当拍全部提交后的架构状态 |
| trace_csr_valid_w / trace_csr_addr_w / trace_csr_data_w | 1/12/32；2/24/64 | 每条实际CSR写、12位地址/32位最终写值 |
| trace_mem_valid_w / trace_mem_store_w / trace_mem_addr_w / trace_mem_data_w / trace_mem_mask_w | 1/1/32/64/8；2/2/64/128/16 | 每条访存架构记录；地址原地址、64bit数据、8bit掩码，D只退休一次 |
| trace_trap_w / trace_cause_w / trace_trap_pc_w / trace_tval_w | 1/32/32/32 | 陷阱可能与更老退休同拍，故障项不置退休valid |
| trace_mem_effect_valid_w / trace_mem_effect_tag_w / trace_mem_effect_addr_w / trace_mem_effect_data_w / trace_mem_effect_mask_w | 1/T/32/32/4 | 每个已授权store beat实际副作用，用于高beat失败的部分写记分板 |
| trace_redirect_valid_w / trace_redirect_tag_w / trace_redirect_pc_w / trace_redirect_target_w / trace_redirect_stage_w / trace_redirect_cause_w | 1/T/32/32/2/2 | stage1F2、2EX、3MEM；cause1方向、2目标、3非控制误预测 |
| trace_source{p}_valid_w / trace_source{p}_tag_w / trace_source{p}_domain_w | 1/T/1 | 每个实际等待/旁路源tag及整数/FP域，RF源valid0；端口号同源表 |

内存记分板同时用AXI/BFM观察真正外部副作用、trace观察提交意图；可缓存写对架构生效指写缓冲接受，不要求等待后续写回。若发生故障FSD，trace_trap仍给本条PC/高字地址，不能伪造一条退休来解释部分写。

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
| 323–32A | mhpmevent3–10 | 单发射仅323–324（3–4），双发射323–32A（3–10）；RW，0，低5位事件编码 |
| 340 / 341 / 342 / 343 | mscratch/mepc/mcause/mtval | RW，0；mepc低2位0，mtval规则见6.1 |
| B00/B80、B02/B82 | mcycle/h、minstret/h | RW，0，64位低/高32；minstret每拍加0..ISSUE_WIDTH |
| B03–B0A/B83–B8A | mhpmcounter3–10/h | RW，0，单发射仅B03–B04/B83–B84，2个64位；双发射8个64位计数器 |
| C00/C80、C01/C81、C02/C82 | cycle/h、time/h、instret/h | RO别名；time来自mtime_i |
| C03–C0A/C83–C8A | hpmcounter3–10/h | 已实现HPM的RO别名；单发射仅C03–C04/C83–C84 |
| F11–F14 | mvendorid/marchid/mimpid/mhartid | RO，0 |

单发射必须仅实现HPM3–4，双发射必须实现HPM3–10。不存在CSR或写RO CSR必须非法指令，misa写忽略例外。计数器软件写与自动增加同拍必须软件写优先。HPM事件1–16必须沿旧 cpu-spec 7.1编码，事件延迟一拍，配对失败优先级5>6>7>8；局部等待事件定义见下文。

事件0–16编码/一拍延迟及5>6>7>8优先级沿旧核7.1；事件1/2/3是双/单/零退休周期，4是退休控制条数；5–8只在老槽发射、年轻未发射时计；9最老ID因load源未就绪，10最老ID因DIV源/入口或提交头DIV事务未完成而等待（每拍布尔OR一次），11不可撤销设备事务等待，12可发射但IB空，13/14每次I/D miss分配，15写回AW握手，16寄存分支/跳转误预测恢复。不把“DIV在后台运行但未阻塞”计入10。

`debug_o` 必须沿旧核7.2位图；[4:2]改为 `min(IB驻留数,7)`，[12:11]改为两条退休valid，[13]ID局部等待，[14]提交头访存等待，[16]EX/MEM解析的寄存重定向，[17]F2纠正，其余同义字段保持，保留[31:30]=0。该截断只用于观察，不影响信用。


### 4.2 相对旧核的软件可见差异

| 差异 | v2 规定 |
|---|---|
| Zba | 固定支持三个RV32 shift-add |
| F/D | 按配置增加misa位、FP寄存器和001/002/003 CSR，见fpu-spec |
| mstatus | 含FP时增加FS[14:13]及SD[31]；复位FS=Off，Dirty/SD必须沿fpu-spec 4 |
| HPM | 单发射固定2个HPM（3–4）、双发射固定8个（3–10），均带cycle/instret/time |
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
| IF | PC、BTB/快速方向、同步I$、IB写入；双发射另有TAGE F2 |
| ID | 单发射单头/双发射双头译码、RF/记分牌、配对、合格load提前地址 |
| EX | 早ALU、AGU、早分支/JALR、MUL入口、长单元发射 |
| MEM | 普通load返回捕获、双发射的晚简单ALU/晚条件分支、本地异常收集 |
| WB | 完成记录和转发捕获、按序写RF/flags及store提交 |

各级必须使用局部 valid/credit，无全局停顿。ID必须只使用已登记容量发射；D$ hit/miss必须本地产生，不能组合穿透到ID/RF/IF。最老指令不就绪时必须阻止年轻越序发射；完成队列满必须反压新发射；已完成结果和前端可依各自容量推进。长操作必须用目的记分牌，不得冻结整核。

NONE必须使用4项独立FF完成记录。含FP必须使用F为8项、FD为16项全核共享顺序完成队列，替换原4项；数据用LUTRAM、控制用FF。每拍最多提交ISSUE_WIDTH条、最多一个FP目的；store/设备副作用只能在最老且不可撤销时发生。冲刷必须按年龄取消年轻结果、flags和store。

控制根应按区域注册复制，根扇出目标≤8、局部叶≤16，数据保持使能按不超过16位分区；数值为实现预算 **[待定]**，最终按PDS定稿。

### 5.2 RF、提前地址与延迟

双发射RF必须为两个写owner bank×四个32×32读副本，共8192数据bit；31位FF LVT记录x1..x31 owner，x0硬零。同址双写必须年轻写生效，WB必须显式转发，不依赖RAM同址读写模式。

双发射F2必须在物理取指bank后并行查询LVT，IB每指令必须保存两份候选owner/源和bank选择（共5bit）；存活IB项遇WB同寄存器必须同边沿更新两份候选，同址双写按年龄选择。ID必须选择注册owner，与RAM数据读并行。WB tag应分区域复制，不能晚一拍修正owner。单发射2R1W必须不增加LVT。

RAM/APM必须通过rtl/tech包装；ASIC必须以等价复制1R1W宏或原生4R2W寄存器堆宏替代，保持读延迟、年轻写优先及WB转发语义。宏名称/几何必须符合3.10。ASIC适配目标必须为edrv32_cpu2_asic_rf、edrv32_cpu2_asic_cache_data、edrv32_cpu2_asic_cache_tag；实际工艺cell在移植时绑定。

ID提前地址必须仅使用RF或已完成WB值。若同组较老项、EX、MEM任一未提交生产者写rs1，或WB乘法结果尚未完成，必须不合格；x0不构成依赖。合格load在ID末给地址，EX返回先本地捕获再供消费者；不增加第二D$副本。store必须不提前。miss/设备/维护冲突必须按普通事务完成，未完成结果不得被消费者使用，early查询必须与实际发射同沿关联，未随发射必须丢弃；普通请求未紧接下一拍接受必须不复用旧early结果。失败load必须走普通访问；已发射晚消费者必须在MEM按生产tag本地等待真实完成，不重发或重复分配load，不冲刷无关整数；hit不得组合反馈ID。

| 结果 | 消费者最早进入EX的间隔（生产者进入EX为0） |
|---|---|
| 早ALU、链接地址 | 1 |
| 合格且实际命中的短load | 1 |
| 普通load | 2 |
| 晚简单ALU | 2 |
| MUL | 4，全流水II=1 |
| CSR读 | 2；有序边界仍必须满足 |
| DIV | 可变，依实际完成记分牌；日程见5.4 |

### 5.3 晚执行与同组相关

双发射满配必须每管线各有EX早ALU和MEM晚简单ALU；必须只在等待一拍且操作受支持时选择晚执行。支持ADD/ADDI/SUB、AND/OR/XOR及立即数、SLT/SLTU及立即数；必须包含三个固定移位加法。移位、MUL/DIV、CSR、访存地址和JALR不得晚执行。

| 生产者→年轻消费者 | 同组行为 |
|---|---|
| EX早ALU或合格短load→晚简单ALU/条件分支 | 可配，老结果先捕获，下一拍MEM使用 |
| 普通load→同组消费者 | 不可配 |
| 前组普通load→晚简单ALU | 可在消费者自身MEM使用前拍捕获结果 |
| 晚ALU→后继 | 必须按延迟2判定；不得同MEM段级联 |
| ALU/load→地址、MUL、JALR | 必须按实际可用时间等待 |

晚条件分支必须在MEM解析并按该级恢复，不能套用EX罚拍。单发射精简必须不实现晚执行。同组WAW必须按年龄保持最后写入；其他类型矩阵必须符合2.3。

### 5.4 乘除法与预测器

MUL/MULH/MULHSU/MULHU必须用33×33有符号乘法覆盖，APM输出必须直接进入本地结果寄存器，延迟4。DIV/DIVU/REM/REMU必须实现符号修正和ISA的除零/最小负数除-1语义。单发射必须使用radix-2位长提前结束，双发射必须使用radix-4位长提前结束；k=max(0,bitlen(|a|)-bitlen(|b|)+1)，单发射n=k，双发射n=ceil(k/2)。接受沿E0；E1幅值/位数差，E2对齐/初始化；E3起每拍一轮，E(3+n)必须独立符号修正并捕获完成。正常L=3+n、无完成反压时II=L；k=0仍经过E3。除零/有符号溢出必须E1分类、E2交付，L=2。完成反压必须只延后交付、不重复计算。k=32时单发射L=35，双发射L=19。第7节旧第四轮周期仅是原模型基线，I03必须回放独立修正拍。

快速预测必须使用固定4096项gshare两位计数表，GHR宽度12位，索引必须为(PC>>2)低GHR宽度位与GHR异或，计数器初值弱不跳；BTB必须保存目标、类型、有效和位置，RAS必须支持call/return、满覆盖最老、快照恢复。单发射BTB64/RAS4，双发射BTB128/RAS8；基本更新/复位沿旧核。以下TAGE条款只适用于双发射，单发射必须不实例化TAGE。

TAGE必须在F1快速gshare外增加同步RAM基表4096×2和4张512×16标签表；F2选择最长匹配provider、次长alternate，无匹配用基表，方向不同必须纠正一拍。四表历史长度固定为(4,12,32,96)；每项tag10、计数3、usefulness2、valid1，共16bit。索引/标签必须采用分段XOR折叠，长历史必须注册折叠。

只有有F1查询token的存活条件分支必须训练TAGE和推进其过滤历史，BTB冷miss不得训练该状态；fast gshare必须按全部解析条件分支更新。每表及基表必须有独立1R1W训练副本，D预读当前行；EX/MEM按年龄更新并镜像写预测副本。每拍单写，一个待写项必须吸收老MEM/年轻EX碰撞；待写项已占用且同拍MEM与EX都训练时，按待写项>MEM>EX优先，EX的表写入必须丢弃（过滤历史仍照常推进），不得停顿或增加待写项；查询必须旁路待写项，index/tag命中在F1计算并注册，F2末级合并。误预测最多向更长表分配一项，分配压力下降低候选usefulness；具体编码/折叠和分配顺序必须如下。

令w=9、E=512，fold_w为所有w位分段XOR，h为该表截取历史；index=((pc>>2)^fold_w(h))&(E-1)，tag=((pc>>(w+2))^fold_10(h)^fold_9(h>>1))&1023，base=(pc>>2)&4095。

行编码 `{valid,tag[9:0],counter[2:0],usefulness[1:0]}`；初始invalid/counter0/u0，base/fast为01；软复位清历史/查询valid，方向RAM不并行复位，沿旧核上电初始化规则。最长匹配provider，次长alternate，无匹配用base；counter≥4预测taken，base≥2预测taken。provider从0表示base、1..4表示短到长表。

训练用D预读的当前行和同址老更新旁路；base饱和2bit更新，provider当前tag仍匹配才饱和3bit更新；仅预测与alternate不同才按预测正确与否增/减u。误预测按provider之后短到长查找，第一个invalid或u0项分配，counter=taken?4:3、u0；此前遇到的忙项u减1，最多分配一项。过滤历史只推进存活且有F1 token的条件分支，fast按全部解析条件分支。

### 5.5 取指与 L1

单发射精简必须使用64位、8B对齐取指组。双发射满配必须以奇偶32位两个bank读取任意4字节对齐的PC及PC+4，再拼合固定逻辑双槽；跨行必须分别查询两行并保留各自错误信息。BTB必须改为字索引、奇偶分bank，总容量不得翻倍；两字分别查询方向/目标，选择最老taken。F2纠正必须按原快照修正第二条call/return的RAS动作。

IB必须用固定头寄存器；发请求只依据寄存信用，单发射逻辑深度4、物理8项，双发射逻辑深度8、物理12项，均按旧核IB_DEPTH+4规则计入在途预留，不组合依赖本拍发射。

I$/D$必须各32KiB、2路、32B行、512组；tag=addr[31:14]。必须采用RAM元数据（valid/dirty/LRU/tag），本地hit/miss，写回/写分配D$，每侧至多一个miss；两种配置必须不实现双load合并。复位释放后第1至512个上升沿必须两路并行清各组valid/dirty/LRU，I/D并扫，随后才接受阵列请求；数据不复位。I$整失效必须同样扫描512组，末组清除后给done；重叠填充必须收完但不置有效。

D$必须有1项地址/32位数据/4位掩码写缓冲；提交后下一拍写阵列，可同拍排空并接新项。load必须按字节合并同字较老store。PMA、AXI错误、非缓存和设备访问必须沿旧cache-spec 2.3、5.3、6，设备只在提交后发事务并等响应。

维护必须沿旧cache-spec 5.4：范围clean/invalidate/clean+invalidate、全clean；开始前排空写缓冲；invalidate必须允许丢弃脏数据；OP_SIZE=0仅命令1–3立即完成；范围每组至多访问一次；设备访问/状态轮询继续，可缓存请求延迟至维护结束。FENCE必须等写缓冲空；FENCE.I必须D$全clean→I$失效→从下一条重取。与在途填充重叠时失效优先，取消请求的填充可完成但不得回送已取消结果。组段必须固定16组，共32个脏标志；范围扫描次数必须为min(ceil((addr+size)/32)-floor(addr/32),512)，两路并查。外部软件必须以done/BUSY判完成；实际写回附加拍数仍待仿真测量。

### 5.6 FPU 集成与精确边界

FP算术、转换和访存必须进入执行管线0；双发射另一条只能为独立A，槽/管线映射必须符合2.3。FD固定2R FMA必须先捕获rs1/rs2、次拍读rs3，该拍可执行独立整数但不得再读新FP；F固定3R必须同拍捕获三源。整数域/FP域必须独立跟踪RAW/WAW，FP组内相关不得配对。

共享队列必须按tag奇偶分两个单写bank，branch/store等无rd项也占一个完成写槽（写done/异常记录）；PC必须在分配沿由allocate{j}_pc写入PC宏（相邻tag落在不同bank，不与完成写冲突），完成源不携带PC；同bank和单FP写口冲突必须按年龄选择并保留年轻源本地结果。必须支持任意未提交完成项按tag转发，结果RAM低32位必须具备S+1份读取副本（单/双发射F为4/6、FD为3/5），FD高32位必须具备3份，PC每bank1份；输出必须本地捕获，不能深队列异步读直串EX。

FLW/FSW必须占一个32位LSU beat；FLD/FSD必须低地址字再高地址字两个beat，共享一条指令和一个提交tag，FLD两字齐全才可使用，中间不得退休/响应中断。不承诺64位原子访存。必须按fpu-spec 5.5实现S4B/D8B自然对齐、逐beat错误与允许低beat部分存储。合法D必须不跨32B行。

## 6. 错误处理

6.1 必须按最老指令精确陷阱：故障项及年轻项不提交，已更老项可提交；mepc必须指故障PC，mtval必须按旧核规则。取指/跳转目标不对齐cause0、取指访问1、非法2、EBREAK3、load不对齐4/访问5、store不对齐6/访问7、M态ECALL11。非法mtval=编码、EBREAK=PC、地址异常=地址、其他0。

6.2 中断必须沿旧核MEIP/MSIP/MTIP、mie/mstatus使能、direct/vectored和MRET恢复语义，在提交头可中断边界进入；不得切开设备访问、除法退休事务、FENCE.I或D双beat指令。每拍在提交头、任何该拍架构副作用前采样；最老同步异常优先，随后按MEIP>MSIP>MTIP优先序及既有mie/MIE规则选择中断。接收中断当拍退休数0，mepc为最老未退休PC；空队列用下一应执行PC。无中断则老到年轻检查，老正常、年轻异常时仅老项退休。

提交头DIV从接受至本条退休作为不可中断事务；已授权设备、FENCE.I和D双beat从开始至结束也不可切开。普通FP长算术可在头未完成时被中断取消；更老不可中断事务存在时先完成它。年轻DIV/FP可由更老异常/分支冲刷取消，不以DIV不可中断为理由保留错路。WFI退休后停取指，任一mie允许的pending唤醒，MIE决定是否进陷阱。

6.3 WFI必须提交后停取指，任一使能中断等待（无论MIE）恢复。寄存重定向必须按年龄优先于年轻重定向，不能等待D$握手才冲刷。FP算术异常必须仅置fflags，不陷阱。

6.4 PMA违规必须不发总线；填充错误必须返回访问异常、不置行有效且收完剩余beat。脏写回B错误必须置APB错误状态、地址及中断，后续填充继续，遵循旧契约；不得新增超时、重试、校验或恢复路径。

## 7. 性能与资源指标

所有下列数字均为模型/结构估算，非RTL/PDS实测；两种配置均固定Zba、FPU_FORMAT=NONE，含L1，不含FPU集成。资源误差约±30%，总LUT已含LUTRAM，DRM按宏碎片计数。单发射为本次按第四轮脚本回放，双发射必须采用第四轮full/combo4-zba-head既有点。

| 固定配置 | CM/视觉/LVGL周期估算 | CM/MHz估算 | 视觉/LVGL IPC估算 | LUT/FF/CLM估算 | DRM36K/APM估算 |
|---|---|---:|---|---|---|
| 单发射精简+Zba | 2673925/2000889/606286 | 3.7398 | 0.9142/0.8666 | 6662/3877/2380 | 18/4 |
| 双发射满配+Zba | 1599073/1169941/421058 | 6.2536 | 1.5635/1.2478 | 11907/6550/4253 | 25.5/4 |

输入/预算提交为1a26a7924，第四轮模型模块提交为c6bd0dbd0b7dbc644edde2883f61e0e302c1747b；GCC15.2，输入为build/cpu-v2/isa/zba/{coremark,vision,render}的ELF反汇编、Spike trace/log，测量start_time至stop_time。单发射周期及资源由提交30ad54fc2的tools/cpu/eval/run_v2_single.py生成，原始输出为build/cpu-v2-single/{coremark,vision,render}.json；双发射采用第四轮full/combo4-zba-head既有点。

以上周期仅作为第四轮原DIV等待口径的模型基线，不作为5.4独立修正拍后RTL的周期保证；I03必须按正常L=3+n（单发射n=k、双发射n=ceil(k/2)）/特殊L2回放并报告差值。模型RF均按异步读；单发射采用第四轮small基点及Zba软件输入。资源估算不包含尚未测量的独立DIV修正寄存开销，实际资源仍归C10。

单发射复现（仓库根目录，三个负载串行）：`. ~/.local/opt/edrv32/env.sh; for w in coremark vision render; do python3 tools/cpu/eval/run_v2_single.py "$w" || exit; done`。

双发射复现（串行；head RF只改变资源/关键路径，不改变异步RF周期）：`. ~/.local/opt/edrv32/env.sh; for w in coremark vision render; do python3 tools/cpu/eval/run_v2_round4.py "$w" --bases full --names combo4-zba --output "build/sp-c3-dual-$w.jsonl" || exit; done; PYTHONPATH=tools/cpu/eval python3 -c "from v2_round4_estimates import estimate; print(estimate('full','combo4-zba-head'))"`。

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

必须按cpu-v2-testplan逐条检查本规格1–7的条款；CPU/Spike逐退休比对、架构测试、6种配置完整回归、配对/晚执行/提前地址/冲刷和精确异常交叉必须通过。L1必须验证PMA、字节转发、背压、维护、失效与在途填充。F/FD集成必须同时通过fpu-testplan。模型数字只能作为perf对照，不作为已完成RTL验证的证据。

## 9. 待定事项

| ID | 事项及开发初值 | 定稿时机/依据 |
|---|---|---|
| C10 | 150/135MHz、资源及perf阈值；根扇出≤8/叶≤16、使能按≤16位分区均为实现预算；维护无写回访问组数+8/全clean干净32+8为预算，写回附加拍数待测 | RTL回归、整片PDS和上板；I03回放DIV独立修正拍，不把旧模型当保证 |

FPU延迟/II和资源实测未决项必须见fpu-spec F03/F06；验证性能阈值必须见testplan T01/FT02。

## 10. 变更记录

| 日期 | 版本 | 变更/依据 |
|---|---|---|
| 2026-11-27 | v0.1-draft | 按用户批准的CPU v2规格阶段起草新IP；依据C2-I第四轮、C2-F2第二版，供协调者定稿 |
| 2026-11-28 | v0.2 | 依据 docs/design/2026-11-28-cpu-v2-interface-freeze.md 已决定状态及更正 C01，冻结接口、行为和两种CPU×三种FPU格式，Zba固定启用，更新模型估算、验证和实施依赖 |
| 2026-11-28 | v0.2 | 按用户决定将单发射固定为精简结构+Zba；双发射满配及NONE/F/FD固定结构不变，同步接口、验证、实施和模型结论 |
| 2026-11-28 | v0.2 | 用户确认：完成队列PC改为分配沿写入，完成源不带PC，完成写仲裁与模型口径不变（I04提问，见 docs/design/2026-11-28-cpu-v2-interface-freeze.md 实现补充） |
| 2026-11-28 | v0.2 | 用户确认：TAGE待写项占用时MEM/EX同拍训练，丢弃EX表写入（I01提问） |
