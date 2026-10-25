# EdRV32 数据冲突与 Cache 行为：按间隔、周期和状态展开

**本文是实现证据，不是架构需求来源。** 应先读 [CPU 自顶向下推导](<G:/claude code/EdRV32-Competition-2026/docs/architecture/2026-09-26-cpu-first-principles-analysis.zh.md>)，再用本矩阵检查当前实现是否满足所选模型。案例数量不能证明情况分类完整，也不能证明现有特殊支路都必要。

日期：2026-09-26。本文件补充并细化 [执行与控制概览](<G:/claude code/EdRV32-Competition-2026/docs/architecture/2026-09-26-cpu-execution-and-control-guide.zh.md>)。概览只能说明机制，不能用来推导固定停顿拍数；这里把动态生产者位置、消费者位置、Cache/队列状态及实际逐拍记录对应起来。

**本次新增 365 个定向仿真场景。全部通过各自的结果/事务检查，包含 7 个期望 Load access fault 的测试；这不等于全状态形式验证，也不消除前次确认的 Store/IRQ 缺陷。** 产品 RTL 没有改动。

## 1. 实验条件与如何读数据

使用 ModelSim SE-64 2020.4、SIM_MODE、cached_core native harness、I/D Cache 各 256 lines、内存模型 IMEM_LAT=1 / DMEM_LAT=2。模型数据空间为 64 KiB。乘法使用 harness 默认的 portable backend，而不是板级 Pango APM IP。通过程序先跑一次预热 ICache/预测器，再测第二次相同指令序列；显式的冷启动测试例外。

可缓存地址 0x80001000、0x80002000、0x80003000 在该 Cache 几何下映射到同一 set。干净 miss 在第二次执行切换数据地址；脏替换事先把同 set 的两路都写脏。uncached 测试用 0xC0001000，并在 testbench 外部存储模型将它映射到相应物理数据，**不是板上 DDR 实测**。

P 表示生产者，C 表示消费者，g 表示中间隔着的指令数：g=0 相邻，g=1 隔一条，以此类推。纯 RAW 矩阵中的中间指令是独立 NOP；填队列、多写同 rd 等测试另外注明。

表中 `D/X/R` 含义：

- D：C 已经有效到达 DECODE，但不能被接收的拍数。包含数据、结构和容量等待，不能全部叫 RAW。
- X：C 已经进入 EX，但不能离开的拍数。可能等数据，也可能等资源/下游。
- R：C 退休边沿减去 P 退休边沿。理想无阻塞整数流为 g+1；它不是 P 从执行到完成的延迟。
- P 的 DECODE 接收边沿定义为 T0，以下逐拍表都相对 T0。

还记录了 C 首次到 DECODE 的时刻。因此 g=6、D=0 不一定等于没有性能损失；它可能很晚才挤进 DECODE。

输出：[测试源码](<G:/claude code/EdRV32-Competition-2026/out/audit/2026-09-26-cpu-matrix/tb_cpu_matrix.sv>)、[结果 CSV](<G:/claude code/EdRV32-Competition-2026/out/audit/2026-09-26-cpu-matrix/results.csv>)、[逐拍 CSV](<G:/claude code/EdRV32-Competition-2026/out/audit/2026-09-26-cpu-matrix/trace.csv>)、[控制状态补充](<G:/claude code/EdRV32-Competition-2026/out/audit/2026-09-26-cpu-matrix/extra.csv>)、[仿真日志](<G:/claude code/EdRV32-Competition-2026/out/audit/2026-09-26-cpu-matrix/run.log>)。

测试采用确定性数据，检查消费结果、目标指令实际转移/退休、branch/JALR 错路标记、错误响应 trap、warm 无 miss、dirty writeback 和队列达到 full 等条件。不是随机数据差分测试；其主要新增证据是控制路径与周期关系。

## 2. 先统一阶段名字与实际寄存位置

源码的 `ex_valid_w` 是 EX 输出寄存包，已经在 MEM1 输入；`decode_valid_w` 是 DECODE 输出寄存包，正在 EX 执行。仅凭信号名字很容易把相邻情况错后一拍。

| P 的位置（无阻塞） | 相对周期 | DECODE 看到的记录 | 数据在何处 |
|---|---:|---|---|
| DECODE 接收 P | T0 | 当前待译码输入 | RF/已有旁路 |
| DECODE→EX resident，EX 执行 P | T1 | resident hazard | ALU 结果尚未进入 EX 输出寄存器 |
| EX→MEM1 寄存包 | T2 | `ex_*` bypass | ALU 已 ready；Load 尚待 PMA/分配 |
| MEM1 两项 FIFO 的 head | T3 | `mem1_packet_*` bypass | ALU ready；cacheable Load 有 late-load 身份 |
| MEM2 内部 owner | T4 | `mem2_hazard_*` bypass | ALU ready；Load token 与实际完成数据分开 |
| MEM2→COMMIT packet | T5 | COMMIT bypass | 普通成功指令可退休，queued Load 查询 LQ |
| P 已正常写 RF | T6 及以后 | RF、同拍写碰撞旁路 | 正常 GPR 状态；MDU 另看授权/实际写回 |

有反压后，P 会停在某位置，中间指令也可能排队。因此静态 g 只能在指定条件下对应某一级，不能用“隔三条一定在 MEM2”解释所有运行状态。

## 3. ALU 生产者：相邻到隔六条逐个分析

示例 `addi x5,x12,0; NOP×g; addi x6,x5,1`。预热、无外部阻塞时，g=0..6 的 D/X 均为 0/0，R 分别为 1..7。

| 间隔 g | C 首次在 DECODE 时 P 的位置 | 选择与动作 | 为什么不需要停顿 |
|---:|---|---|---|
| 0 | EX resident（T1） | DECODE 给 C 设置 resident-bypass 标记；C 到 EX 后取 P 的 EX 输出寄存值 | 不把同拍 P 的 ALU 结果组合回灌 DECODE，而是在下一拍 EX 使用 |
| 1 | EX 输出记录（T2） | `operand_resolve` 选 EX bypass | 数据已寄存且 ready |
| 2 | MEM1 FIFO head（T3） | 选 MEM1 bypass | 数据继续随 P 的指令包携带 |
| 3 | MEM2 owner（T4） | 选 MEM2 bypass | 普通 ALU 的 result_ready 保持为 1 |
| 4 | COMMIT（T5） | 选 COMMIT bypass | 不必等 RF 更新后再多等一拍 |
| 5 | 已写 RF（T6） | 读 RF | 新值已在架构寄存器中 |
| 6 | 已写 RF（T7） | 读 RF | 同上 |

本次同时测试了值用作 ALU rs2、branch operand、JALR target、Store data、Store address、后继 Load address，纯 ALU 生产者在本实验条件下均没有额外 D/X 等待。Store/Load 的消费者目标数据行已预热。

这并不保证反压时仍零等待。若 C 到 EX 后下游不接受，而 P 的旁路只出现一拍，EX 必须本地捕获并保持结果；否则 P 离开后 C 会丢数据。[EX operand capture](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/execute/edrv32_ex_stage.v:280>)。

## 4. Load hit：同样的间隔并不得到单调改善

示例 `lw x5,0(x10); NOP×g; addi x6,x5,1`。

| g | D 等待 | X 等待 | R | 实际释放路径 |
|---:|---:|---:|---:|---|
| 0 | 2 | 0 | 3 | resident 等一拍、EX 输出记录等一拍，MEM1 late-load 放行 |
| 1 | 1 | 0 | 3 | EX 输出记录 hard-block，随后 MEM1 late-load 放行 |
| 2 | 0 | 0 | 3 | DECODE 直接认出 MEM1 cacheable Load，C 去 EX 等/取 LQ 值 |
| 3 | 1 | 0 | 5 | MEM2 记录仍不 ready，尽管 LQ 已完成；等下一拍 COMMIT bypass |
| 4 | 0 | 0 | 5 | COMMIT bypass 直接提供已完成 LQ 值 |
| 5 | 0 | 0 | 6 | RF |
| 6 | 0 | 0 | 7 | RF |

**隔两条可以不停，隔三条反而要停一拍，是本次实际复现的性能不连续，不是教科书给定的 load-use 规则。**

### 4.1 相邻 Load→ALU（case 50）

| 周期 | P | C | 关键控制与动作 |
|---|---|---|---|
| T0 | DECODE 接收 | 尚未到 D | P 的输入已准备 |
| T1 | EX 算地址 | D 等待 | resident 是 Load，不是可 resident-forward 的 ALU/JUMP |
| T2 | MEM1 分类、分配 | D 等待 | `ex_bypass_is_load=0`，普通未就绪 producer hard-block |
| T3 | MEM1 FIFO head；D$ lookup 完成 | D 接收 | 已知可缓存，C 携带 late-load PC；该边沿 LQ 捕获 hit data |
| T4 | MEM2 owner；LQ done=1 | EX 使用 LQ 值并执行 | C 不再需要额外 EX wait |
| T5 | COMMIT，P 写 rd | C 在 MEM1 | 正常退休 P |
| T6 | 已退休 | C 进入 MEM2 owner | |
| T7 | 已退休 | C 进入 COMMIT packet | |
| T8 | 已退休 | C 退休 | R=T8−T5=3 |

### 4.2 隔一条、隔两条

隔一条时，C 在 T2 才到 D，因此跳过 resident 阶段的等待，但仍碰到 EX 输出 hard-block；T3 放行。隔两条时，C 恰好 T3 到 D，直接走 MEM1 late-load 分支。三种情况都在 T4 使用结果，所以 R 同为 3，但中间已完成的独立指令数不同。

### 4.3 隔三条（case 53）

T4：C 到 D，P 在 MEM2 owner，LQ 唯一有效项已经 done；但是 `hazard_ready_o = !exception_valid_r && result_ready_r`，Load packet 中该 ready 没更新，且 `hazard_late_load_o=0`。C 被 hard-block。

T5：P 到 COMMIT，COMMIT 直接查 LQ、提供 ready/value，C 才能离开 DECODE；T6 执行，T10 退休。不是 Cache 又慢了一拍，而是**同一条 Load 在不同 producer observation 中的完成状态不一致**。

对应源码：[core Load 属性](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/core/edrv32_core.v:335>)、[DECODE resident 条件](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/decode/edrv32_decode_stage.v:217>)、[MEM2 hazard](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_mem2_stage.v:178>)、[COMMIT bypass](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/commit/edrv32_commit_stage.v:423>)。

## 5. Load 的消费者不同，EX 行为也不同

| C 类型 | g=0 的 D/X/R | g=1 | g=2 | g=3 | 机制 |
|---|---|---|---|---|---|
| ALU rs1 或 rs2 | 2/0/3 | 1/0/3 | 0/0/3 | 1/0/5 | LQ ready 后可在同拍进入 ALU |
| Branch | 2/1/4 | 1/1/4 | 0/1/4 | 1/0/5 | late-load 标记要求先本地捕获，再比较 |
| JALR | 2/1/4 | 1/1/4 | 0/1/4 | 1/0/5 | late-load 基址先捕获，再加立即数算 target |
| Store data | 2/0/3 | 1/0/3 | 0/0/3 | 1/0/5 | rs2 的正确值进入 store packet |
| Store address | 2/0/3 | 1/0/3 | 0/0/3 | 1/0/5 | rs1 的正确值进入地址加法器 |
| 下一条 Load address | 2/0/3 | 1/0/3 | 0/0/3 | 1/0/5 | pointer chasing；消费者目标行本实验已预热 |

g≥4 时本次各类型额外 D/X 等待均为零，R=g+1。

为什么 g=3 的 branch/JALR 没有 EX 捕获等待？因为 C 在 D 被挡到 COMMIT bypass ready，进入 EX 时拿的是普通完整 operand，不再携带 late-load 标记。

这里的 branch/JALR 是预热后的特定程序，取指无 miss。前次独立控制流微基准测得 Load→branch gap=5；那是另一段程序的结果，不能当作本核所有 Load→branch 的固定值。本表把程序布局、前端预热和间隔固定，才可比较。

## 6. DCache clean miss：谁在等、什么时候停止退休

以 g=0、C=ADDI 为例（case 99）：

| 周期 | Cache/LQ | 指令流水 |
|---|---|---|
| T2 | MEM1 分配 LQ；启动 lookup | C 仍在 D 等 EX 输出记录 |
| T3 | lookup 判 miss，LQ 尚未 done | C 通过 MEM1 late-load 路径进入 EX |
| T4 | REFILL_REQ，发送 AR | P 在 MEM2 owner；C 在 EX 等结果 |
| T5..T26 | REFILL_WAIT，逐步接收响应 | P 占 COMMIT 但不能退休；C 占 EX；后续逐步受到反压 |
| T27 | lookup response 提供结果；本边沿写 LQ | P/C 在边沿前仍看到未完成状态 |
| T28 | LQ done=1 | P 正常退休；C 同拍使用 LQ 数据完成 EX |
| T29..T31 | miss 已结束 | C 继续经 MEM1/MEM2 |
| T32 | | C 退休，R=4 |

本模型中 D 等 2 拍、X 等 24 拍，P 在 COMMIT 等 23 拍。**这些等待彼此重叠，不能相加成“总共损失 49 拍”。**

R=4 也不表示 miss 只花 4 拍：R 只从已经被 miss 延迟的 P 退休时刻开始算。P 自己的退休从 hit 的 T5 延迟到了 T28。

### 6.1 miss 与间隔的交互

| g | C 首次到 D | D/X | P 退休 | C 退休 | 说明 |
|---:|---:|---|---:|---:|---|
| 0 | T1 | 2/24 | T28 | T32 | 先到 EX，等 LQ |
| 1 | T2 | 1/24 | T28 | T32 | 同上 |
| 2 | T3 | 0/24 | T28 | T32 | 同上 |
| 3 | T4 | 25/0 | T28 | T34 | 错过 late-load 入口，在 D 等 COMMIT，另有容量等待 |
| 4 | T5 | 25/0 | T28 | T35 | 首先等 COMMIT 值，之后还受填满的后端影响 |
| 5 | T6 | 25/0 | T28 | T36 | 同样存在结构性等待 |
| 6 | T32 | 0/0 | T28 | T37 | C 到 D 之前就被反压挡住；不能把 0/0 当作 miss 无损失 |

g=3 在 T28 数据已 ready，但 DECODE 的 `issue_block_i=mem1_to_mem2_full_w` 仍会挡一拍。当前判断不因为同拍 pop 就允许 DECODE 前进。它减少 ready 长路径，但有可见性能代价。

还必须检查正确性前提：当前给 DECODE 的 MEM1 bypass 主要是 FIFO head，没有独立暴露 tail producer 记录。full 时停止 DECODE 也构成保守保护；如果为省拍允许 full+pop 时提前译码，就必须证明当拍 tail 中的更年轻 older writer 不会被漏掉。不能只把 `full` 改成 `full && !pop` 就认定优化完成。

这些绝对时间取决于内存模型。换成 DDR、不同 AXI 仲裁/时钟、不同 burst backpressure，24 会变；“在哪个阶段等待、哪些等待重叠、C 到达前也可能已被延迟”的分析方法不变。

## 7. Dirty miss：写回不是和 refill 同时自动完成

本次先将同 set 两个 way 写脏，再请求第三条 line；每例明确检查恰好发生一次 writeback。

路径是：lookup miss → 等相关 Store/reservation 排空（若有）→ victim 数据/标签保存 → AW/W 各自握手 → 等 B → AR/refill → 安装/返回 LQ。

g=0..2 的 ALU 消费者在 D 分别等 2/1/0 拍，随后 EX 均等 48 拍。P 在 T52 退休，C 在 T56 退休。比 clean miss 多出的 24 拍是本模型写回流程带来的，不应推广成硬件固定 dirty penalty。

g=3..5 在 D 等 49 拍；g=6 直到 T56 才到 D，自身 D/X=0。其规律与 clean miss 一致，只是排空晚了。

特别需要分别考虑：无效 victim、clean victim、dirty victim、存在未排空 Store 的 miss、writeback error、refill error。它们不能合并成一句“miss 停流水”。[DCache FSM](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/cache/edrv32_dcache.v:734>)。

## 8. 下游反压、队列满与 error

### 8.1 外部不接收请求

scenario 3 在测量开始后的前 30 拍阻止 native memory 接受新数据请求。g=0..2 的 C 在 EX 等 50 拍，g=3..5 在 D 等 51 拍。它测试了请求保持与恢复，不是 AXI 每个 channel 独立的随机反压验证。

### 8.2 一个 miss 后跟独立 Load

case 246：P miss，后跟 8 条 Load，最多达到 LQ=4 项。T6 起后端与前端部分阶段停止前进；P 在 T28 退休后，队列中的同 line 请求继续完成，C 在 T32 才到 D，T37 退休。

这验证了“允许多个请求在队列中”不等于“支持多个并行 miss”。本核一个 miss FSM 仍限制实际服务进度；队列用于保留请求、重叠前后处理，填满后必然反压。

### 8.3 一个 miss 后跟独立 Store

case 247：P miss，后跟 8 条 Store，SQ 达到 4 项。年龄仲裁不能让年轻 Store 的 preparation 越过尚未解决的 older Load，后端容量用尽后停止。miss 完成后依次准备/退休 Store，C 的到达时间被延迟。

### 8.4 refill 返回错误

scenario 4 对测量期的 native data response 注入 error，覆盖 g=0..6。7 例都在 P 的 PC 产生 Load access fault，C 不退休。g≤2 的 C 虽已携带 late-load 标记进入 EX，也不能因为“返回了某个 data”而视作成功。

这验证的是被注入的错误路径，不代表已覆盖 RID/RLAST 错误、所有 B 错误、错误与 flush 同拍。后面有明确覆盖表。

## 9. Uncached 与 ICache miss 会改变静态间隔的含义

uncached Load 在 COMMIT 发请求，不走 LQ 提前完成。本实验 g=0..6 的 C 在 D 等待分别为 13、12、11、11、11、11、0 拍；最后一项同样是到达前已被反压。消费者没有 cacheable late-load 释放路径。这不是 TCM/外设/DDR 都固定等待这么多拍，只代表当前路由与模型。

冷启动 scenario 8 不预热 I$，g=0 时 C 在 D 只等 1 拍，看起来比 warm 的 2 拍“更好”，但实际是前端延迟让 C 来得晚，且数据也是冷 miss。**不能只用某一个 RAW counter 比较两次运行。**

ICache miss 时应区分：后端已有多少有效指令可继续执行、IF1 tag 是否满、IF2 是否还有完整指令、32-bit 指令是否缺另一 halfword，以及期间是否 redirect。后端可以先消耗库存，之后才出现空退休；错误路径 refill 也可能仍需 drain。

本次冷启动案例没有单独隔离每一种 cross-line/RVC/redirect 组合，相关机制见概览和既有 frontend 测试；不能说已经做完全部 I$ 边界验证。

## 10. Store→Load：寄存器 RAW 与内存相关必须分开

`sw x12,0(x10); NOP×g; lw x6,0(x10)` 中，C 不读 P 的目的寄存器，普通 RAW 检查不负责它。由 SQ/committed buffer 的地址、byte mask、年龄和 release 逻辑处理。

本次增加 SW、SB、SH 与 LW/LB/LBU/LH/LHU 的 g=0..6 矩阵，分别测 hit 与 Store prepare miss。第二轮 Store 数据增加一，避免把上一轮留在内存里的同值误当作本轮写入成功。

| 模式（hit） | g=0..6 的 R | 原因 |
|---|---|---|
| SW→同字 LW | 1,2,3,4,5,6,7 | 全覆盖可直接转发 |
| SB→对应 LB/LBU | 1,2,3,4,5,6,7 | 所需一个 byte 全覆盖，并做正确符号/零扩展 |
| SH→对应 LH/LHU | 1,2,3,4,5,6,7 | 所需 halfword 全覆盖 |
| SB→包含该 byte 的 LW | 4,4,4,4,5,6,7 | 当前不做跨来源完整 word 合成，等待 Store drain 后再读 |
| SH→包含该 halfword 的 LW | 4,4,4,4,5,6,7 | 同上 |

全覆盖情况下，Store prepare miss 仍可以先把 SQ 中已有的写数据转给 Load；但是 Store 自己尚未 prepared，COMMIT 不能让后继 Load 越过它退休。**Load 数据 ready 和整个窗口不受 miss 影响是两件事。**

多 Store 例：`SW word; SB 同字另一 byte; LW word`，以及两个不同 byte 的 SB 后接 LW，均检查最终合成值；本次 g=1..4 的 R 均为 5，SQ 峰值两项。最新部分覆盖 Store 会要求等待，不会错误地只采用更老完整 SW 的值。

尚需区别：同字不同 byte 但不相交、跨 line、多个 Store token 重用、drain 与 lookup 同地址同拍。当前 DCache 的 shadow/merge 用于处理 RAM read-first 碰撞，不能把它与 SQ 的程序年龄转发当成同一层逻辑。

## 11. 多 producer、两个源和不必要的等待

### 11.1 older Load、younger ALU 都写 x5

```asm
lw   x5, 0(x10)
addi x5, x0, 66
addi x6, x5, 1
```

case 248 得到正确的 67，但 C 仍在 D 多等 1 拍。T2：younger ALU 正在 resident，应该负责 C 的值；外部 `operand_resolve` 却也看到 older Load 的 EX 输出 unready。DECODE 把其 hard-block 无条件 OR 进 dependency stall，没有因 resident producer 覆盖该源而屏蔽旧等待。

这是**结果选择正确但等待判断仍受被覆盖的旧 producer 影响**的例子。优化应使“选哪个 producer”和“等哪个 producer”一致，不应只调 mux 优先级。

### 11.2 older ALU、younger Load 都写 x5

`ADDI x5,1; LW x5,...; ADDI x6,x5,1` 得到 Load 值+1，而不是旧 ALU 值+1。年轻 Load 未 ready 时必须阻塞/late-wait，不能因为旧 ALU 已 ready 就放行。

### 11.3 两个源来自不同 producer

`ADDI x5,65; LW x7,...; ADD x6,x5,x7`，g=1..4 的定向场景检查了双源组合结果。真实控制必须分别选 rs1、rs2 的 producer，直到两个源都满足消费条件；不能用一个总的“有 bypass”信号代替。

### 11.4 同 PC 多个动态实例

静态 PC 不是动态 instruction ID。当前 LQ probe 对物理四项并行比较 PC，再按环形队列年龄选 newest hit；不能选“最先找到的 ready hit”。此前 load-queue 单元测试覆盖过重复 PC 情形，本次没有重新构造所有跨 flush/回绕的动态实例排列；新 producer contract 应优先使用可证明生命周期的 token/generation。

## 12. MUL/DIV/CSR：不能套用 ALU 的间隔表

以下是本模型指定操作的 D 等待，X 等待均为零。D 包含结构等待。

| P→ADDI | g=0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---:|---:|---:|---:|---:|---:|---:|
| MUL 7×9 | 3 | 2 | 1 | 0 | 0 | 0 | 3 |
| DIV 441/7 | 33 | 32 | 31 | 30 | 31 | 31 | 31 |
| CSR 读 mscratch | 5 | 4 | 3 | 3 | 3 | 3 | 0 |

MUL g=6 的 3 拍**不是结果仍没算好**。extra.csv 显示这是 DECODE 看到 MEM1 FIFO full 的 structural block；更早的一拍 MDU 授权/写回等待造成下游积压。不能通过这个数字得出“间隔六条仍有三拍乘法 RAW”。

CSR 的 `hpm_stall_load_o` 也会在等待 CSR 时置位，因为源码检查的是非 MDU 的 hard-block，并未严格限定 producer 是 Load。这进一步说明事件名字不等于准确原因。

MDU token 的退休/授权可能先于物理写回，因此 MDU 的 R 不能和普通 ALU 的“rd 写回间隔”直接等同。DIV 的数值只适用于该输入和该 backend；除零、±1、零被除数、signed overflow 有独立快速处理分支。

## 13. 反压后不能继续用静态 g 判断来源

在 warm straight-line 条件下，可以用第 2 节把 g 映射到某个 producer slot。发生 miss/MDU/CSR 等待后，必须按每拍实际 valid/身份判断：

1. C 是否已经到 DECODE？如果没有，延迟可能被记在前端/结构反压，而非 RAW。
2. resident 是否是匹配的最新 producer？它是否覆盖了外部记录？
3. 外部 EX/MEM1/MEM2/COMMIT 哪个有效且匹配？未 ready 的最近 producer 必须阻止更老值。
4. C 是否已经携带 producer 身份到 EX？此时等待点从 DECODE 迁移到了 EX。
5. 数据来时下游是否允许 C 前进？若不能，捕获的数据必须保存到 C 离开或被 kill。
6. 队列与指令 packet 是否仍属于同一动态指令？flush、pop+push、generation 变化要一起检查。

这六步比只看 `rd==rs1` 或一个 HPM stall 值更接近实际电路行为。

## 14. Cache/依赖与撤销交叉时的控制规则

| 组合 | 必須守住的规则 | 当前证据 |
|---|---|---|
| Load miss，依赖 C 已进 EX，P 最后 fault | C 不得用 error data 继续架构提交 | 本次 7 个 error 场景覆盖不同间隔 |
| older trap，年轻 Load 已发 AXI | 清年轻 LQ 所有权；已接受 AXI 必须 drain，旧返回不污染新槽 | 源码分析；既有 Cache cancel 测试有覆盖，非本次全相位枚举 |
| EX branch mispredict | 只 kill 比该 branch 年轻的工作，保留 older Load/Store | 源码和既有前端/控制流测试；本次 branch 测错路标记 |
| IRQ 与 Store 正常提交判定同拍 | IRQ 抢占指令不得进入 committed buffer；真正 older Store 必须保留 | 前次已复现缺陷，尚未修复 |
| FENCE 遇到 younger speculative miss | 先取消年轻 LSU，再等 older committed stores，避免相互等待 | 源码分析，已有 FENCE 测试；cached IRQ 组合仍失败 |
| refill 完成与 cancel 同拍 | data/error/valid 的优先级属于同一个事务 | 需新增相位扫描或形式验证 |
| queue full 与 pop+push 同拍 | valid、head/tail、generation、payload 对容量的判断一致 | 本次触及 full/恢复；没有覆盖全部 token 回绕 |
| 存储同地址 read/write 同拍 | 明确 read-first 模型并正确 shadow merge | 既有 cache-blocking/array 契约测试；需 vendor IP 对照 |
| MDU 已授权与中断同时待处理 | 已授权 older MDU 完成后才建立精确边界 | 源码分析；本次只做 RAW 周期矩阵 |
| 32-bit 指令跨块，第二半字 miss/错误/redirect | 不拼错、不重复发射，错误路径 fault 被丢弃 | 机制分析；本次冷启动不能替代完整 RVC 矩阵 |

这张表把“有分析”和“已用本次测试验证”分开；不能因 365 个案例通过就宣称全部交叉情况已经正确。

## 15. 对设计优化的具体含义

- **确定的 Load hit 机会**：统一 MEM2 的 LQ completion 可见性，消除 g=3 多一拍；同时保证 miss/error/flush 不会把未完成 Load 标为 ready。
- **相邻 Load-use**：两拍分别来自 resident 与 EX 输出属性未知，不能简单把 `ex_bypass_is_load` 固定为 1，否则 uncached/MMIO 会错误进入提前消费通路。需要更早的合法属性/身份传递。
- **resident 覆盖**：对每个源统一最新 producer 的 value 与 blocked，消除 older unready producer 导致的不必要等待。
- **结构反压**：MEM1 FIFO full 即阻止 DECODE，即便同拍 pop 可释放容量。这是性能/ready 时序的取舍；不能不看 STA 就把 pop 组合接回所有前级。
- **FIFO tail 的 producer 可见性**：放松 full 阻塞前，必须同时覆盖隐藏在第二项中的 RAW/WAW 年龄关系；容量允许接收与操作数已经正确解析不是同一个条件。
- **控制流 late-load**：EX 多一拍 capture 是现有时序切断点；减少捕获拍数必须同时缩短 LQ 选择、比较/目标和 redirect/HPM 事件路径。
- **部分 Store forwarding**：全覆盖和部分覆盖的代价已不同；如果真实 workload 中部分覆盖频繁，再评估按 byte 合并多个来源，不能仅因为多拍就无条件加大转发比较网络。
- **miss 优化**：优先分开 clean、dirty、协议反压、队列容量、到达前阻塞；要隐藏长 miss，需要允许独立工作推进且管理好程序顺序，而不仅是扩大 FIFO。

## 16. 覆盖清单与下一步缺口

本次新增数量：ALU/Load hit × 7 消费者 × 7 间隔=98；Load clean/dirty miss × 7 消费者 × 7 间隔=98；MUL/DIV/CSR × 7=21；反压/error × 7=14；uncached 7；冷启动 7；LQ/SQ full 2；多 producer/双源 12；7 种 Store→Load × hit/miss × 7=98；两个多 Store 组合 × 4=8，共 365。

尚未形成逐周期全矩阵的项目：独立 I$ miss 与跨 line RVC、非恒定 branch 方向/目标、所有 CSR 特权边界、APM 真实 IP、所有 DIV 快速路径、同 rd/PC 长循环回绕、AW/W/B/AR/R 独立随机反压与畸形响应、所有 flush/response 同拍、TCM 全路径、DMA 并发一致性。它们的必要规则已在本文/概览列出，但仍需要专项验证。

本次保证的是**分类和分析维度明确，并对上述 365 个指定场景提供源码与逐拍证据**；不是用有限 directed tests 替代完整正确性证明。前次发现的 cached Store/IRQ 故障仍然应排在性能优化之前。

## 17. 完整测量表

以下内容由 results.csv 自动生成；单元格统一为 D/X/R，便于核对所有消费者与间隔。

<!-- GENERATED_TABLES -->

### ALU producer，warm

| g | ALU rs1 | ALU rs2 | Branch | Store data | JALR | Store address | Load address |
|---:|---|---|---|---|---|---|---|
| 0 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/1 |
| 1 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/2 |
| 2 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/3 |
| 3 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 |
| 4 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 |
| 5 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 |
| 6 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 |

### Load producer，hit

| g | ALU rs1 | ALU rs2 | Branch | Store data | JALR | Store address | Load address |
|---:|---|---|---|---|---|---|---|
| 0 | 2/0/3 | 2/0/3 | 2/1/4 | 2/0/3 | 2/1/4 | 2/0/3 | 2/0/3 |
| 1 | 1/0/3 | 1/0/3 | 1/1/4 | 1/0/3 | 1/1/4 | 1/0/3 | 1/0/3 |
| 2 | 0/0/3 | 0/0/3 | 0/1/4 | 0/0/3 | 0/1/4 | 0/0/3 | 0/0/3 |
| 3 | 1/0/5 | 1/0/5 | 1/0/5 | 1/0/5 | 1/0/5 | 1/0/5 | 1/0/5 |
| 4 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 |
| 5 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 |
| 6 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 |

### Load producer，clean miss

| g | ALU rs1 | ALU rs2 | Branch | Store data | JALR | Store address | Load address |
|---:|---|---|---|---|---|---|---|
| 0 | 2/24/4 | 2/24/4 | 2/25/5 | 2/24/4 | 2/25/5 | 2/24/4 | 2/24/4 |
| 1 | 1/24/4 | 1/24/4 | 1/25/5 | 1/24/4 | 1/25/5 | 1/24/4 | 1/24/4 |
| 2 | 0/24/4 | 0/24/4 | 0/25/5 | 0/24/4 | 0/25/5 | 0/24/4 | 0/24/4 |
| 3 | 25/0/6 | 25/0/6 | 25/0/6 | 25/0/6 | 25/0/6 | 25/0/6 | 25/0/6 |
| 4 | 25/0/7 | 25/0/7 | 25/0/7 | 25/0/7 | 25/0/7 | 25/0/7 | 25/0/7 |
| 5 | 25/0/8 | 25/0/8 | 25/0/8 | 25/0/8 | 25/0/8 | 25/0/8 | 25/0/8 |
| 6 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 |

### Load producer，dirty miss

| g | ALU rs1 | ALU rs2 | Branch | Store data | JALR | Store address | Load address |
|---:|---|---|---|---|---|---|---|
| 0 | 2/48/4 | 2/48/4 | 2/49/5 | 2/48/4 | 2/49/5 | 2/48/4 | 2/48/4 |
| 1 | 1/48/4 | 1/48/4 | 1/49/5 | 1/48/4 | 1/49/5 | 1/48/4 | 1/48/4 |
| 2 | 0/48/4 | 0/48/4 | 0/49/5 | 0/48/4 | 0/49/5 | 0/48/4 | 0/48/4 |
| 3 | 49/0/6 | 49/0/6 | 49/0/6 | 49/0/6 | 49/0/6 | 49/0/6 | 49/0/6 |
| 4 | 49/0/7 | 49/0/7 | 49/0/7 | 49/0/7 | 49/0/7 | 49/0/7 | 49/0/7 |
| 5 | 49/0/8 | 49/0/8 | 49/0/8 | 49/0/8 | 49/0/8 | 49/0/8 | 49/0/8 |
| 6 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 |

### Store→Load，hit

| g | SW→LW | SB→LW | SB→LB | SB→LBU | SH→LH | SH→LHU | SH→LW |
|---:|---|---|---|---|---|---|---|
| 0 | 0/0/1 | 0/0/4 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/4 |
| 1 | 0/0/2 | 0/0/4 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/4 |
| 2 | 0/0/3 | 0/0/4 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/4 |
| 3 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 |
| 4 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 | 0/0/5 |
| 5 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 | 0/0/6 |
| 6 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 | 0/0/7 |

### Store→Load，Store prepare miss

| g | SW→LW | SB→LW | SB→LB | SB→LBU | SH→LH | SH→LHU | SH→LW |
|---:|---|---|---|---|---|---|---|
| 0 | 0/0/1 | 0/0/4 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/1 | 0/0/4 |
| 1 | 0/0/2 | 0/0/4 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/4 |
| 2 | 0/0/3 | 0/0/4 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/3 | 0/0/4 |
| 3 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 | 0/0/4 |
| 4 | 0/23/5 | 0/23/5 | 0/23/5 | 0/23/5 | 0/23/5 | 0/23/5 | 0/23/5 |
| 5 | 26/0/8 | 26/0/8 | 26/0/8 | 26/0/8 | 26/0/8 | 26/0/8 | 26/0/8 |
| 6 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 | 0/0/9 |
