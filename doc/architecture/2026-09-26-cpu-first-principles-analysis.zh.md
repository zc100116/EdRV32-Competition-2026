# EdRV32 CPU 自顶向下推导：从语义、顺序和生命周期到八级流水线

日期：2026-09-26。本文重新建立分析主线。**前半部分不以当前 RTL 的分支、FSM 状态或测试数量为需求来源；先给约束和明确的参考模型，再推导必须处理的关系，最后对照当前实现。**

本文是分析用的参考模型及设计建议，不修改 RTL，不将建议自动宣布为新的冻结实现规范。此前的执行概览、周期矩阵和测试日志保留为实现证据，阅读顺序应放在本文之后。

## 1. 固定问题范围，区分三种“必须”

用户选择的范围是单发射、八级、RV32IMC、CSR/FENCE.I、M-mode、Cache/TCM/外设接口，并兼顾 CoreMark、频率和资源。暂不引入通用乱序执行、寄存器重命名、分页、浮点或原子扩展。

| 层次 | 内容 | 能否因性能调整 |
|---|---|---|
| 架构/平台约束 | 指令结果、允许的访存与控制行为、异常、地址属性、外设协议 | 不能通过改 RTL 偷换语义 |
| 微架构选择 | 八级职责、操作数绑定级、Cache 延迟、是否允许早发 Load、是否有队列、何时退休 | 可以，但必须重新推导受影响的关系 |
| 实现细节 | mux 组织、寄存复制、FIFO 深度、编码、RAM/IP 映射 | 可以，但不能破坏前两层契约 |

例如：消费者得到正确 x5 是约束；在 DECODE 等待还是到 EX 等待是选择；用 PC 比较还是 token 索引是实现。不能从“现在有两个 PC probe”推导“CPU 本来就需要两个 PC probe”。

## 2. 正确性的起点是可观察行为，而不是流水级

先想象一个不重叠执行指令的参考 CPU。它有 GPR、PC、CSR，发起规定的内存/设备操作，并在合法边界处理中断。流水实现必须产生符合相同架构与平台约束的可观察行为，允许微架构在时间上重叠工作。

对于计时器、外部输入和中断，不要求两种实现逐时钟完全相同；应在相应输入/事件边界下比较架构允许的行为。对于多观察者内存，也不能把“任意系统必须全局顺序一致”当成 RISC-V 的要求。本项目可以选更保守的访存顺序，但仍需要说明 DMA/外设的可见性边界。[RVWMO 官方说明](https://docs.riscv.org/reference/isa/v20260120/unpriv/rvwmo.html)

首先列出每类指令读写什么状态：

| 类别 | 输入依赖 | 产生的效果 | 必须确定后才能正常完成的事实 |
|---|---|---|---|
| 整数运算 | 实际使用的 GPR、立即数；AUIPC 还读本条 PC | rd、顺序 next PC | 操作合法、正确输入、计算完成 |
| 条件分支 | 两个 GPR、本条 PC、长度、立即数 | 实际 next PC | 条件与目标已确定 |
| JAL | PC、长度、立即数 | link rd、next PC | 目标/link 已确定 |
| JALR | rs1、立即数、PC、长度 | link rd、next PC | rs1 正确、目标/link 已确定 |
| Load | 基址 GPR、立即数、访问属性、所读内存字节 | rd 或访问异常 | 地址合法、访问结果/错误已确定 |
| Store | 基址 GPR、数据 GPR、立即数、byte mask | 内存/设备写效果或错误 | 地址/数据/权限与授权边界成立 |
| MUL/DIV | 实际使用的 GPR、操作类型 | rd | 算术结果已确定，或有明确的延后兑现契约 |
| CSR | CSR 旧值、GPR 或 zimm、访问权限 | CSR 新值、旧值写 rd；可能影响中断条件 | 访问合法，读写顺序与副作用符合定义 |
| FENCE/FENCE.I | 此前/此后的访问或取指关系 | 对顺序/指令可见性的约束 | 相应顺序条件已经建立 |
| ECALL/EBREAK/MRET/WFI | PC、机器态与中断状态 | trap、返回、等待/唤醒 | 对应特权语义成立 |

该表中的指令语义依据 [RV32I](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)、[M](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)、[CSR](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html) 和 [机器态规范](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)；阶段分配是后续设计选择，不由 ISA 指定。

两个直接推论：编码中出现某个寄存器编号，不代表该指令真的读取它；rd=x0 只意味着不保留 GPR 结果，不能因此删除 Load 访问或 JAL 控制流效果。

## 3. 先建立一条动态指令的生命周期

用概念身份 `u` 表示一个动态实例。同一 PC 的两次循环执行是不同的 `u`。下面不是要求新增硬件 FSM，而是用来检查状态含义：

```text
被接收 → 输入已确定 → 执行/请求已启动 → 结果或错误确定
      → 达到不可撤销授权边界 → 架构提交完成

授权前可能被取消；已经承诺的外部事务还可能需要在后台排空。
```

必须区分六个事实：

| 事实 | 含义 |
|---|---|
| live | 该动态实例还有效，没有被所属年龄范围的恢复事件撤销 |
| operands_ready | 它需要的输入已经正确确定，或在允许的截止点可取得 |
| issued | 运算/外部请求已经真实启动，不能因为 valid 保持而重复启动 |
| completed / faulted | 运算/访问已经得到结果或错误 |
| authorized | 允许产生规定的不可撤销效果 |
| retired | 按本设计定义，已经越过架构提交边界；不能再把它当作普通年轻指令清除 |

valid、ready、done、authorize 不是同一个量。一个 packet 被异常处理路径接走，不等于该指令正常退休。

最简单的分析基线把 completed/无异常作为普通退休前提，并使所有 GPR 写在退休时发生。若要允许 MDU 先授权再写回，则必须另行定义延后兑现期间的 RAW/WAW、异常边界、计数/trace 和队列释放，不能继续沿用这个简单退休含义。

## 4. 由语义推出的不变量

| 编号 | 不变量 | 违反后会怎样 |
|---|---|---|
| I1 | 最终产生架构效果的消费者，其源值来自此前最近的有效写入者，或已提交 RF | 读旧值/读到别的动态实例 |
| I2 | 不可撤销的效果按选定架构/平台顺序授权；较老未解决的 fault 不能被年轻提交越过 | 无法建立精确恢复边界 |
| I3 | 某动态实例的每个架构动作最多一次；请求拆成多个 bus beat 时，beat 仍有唯一身份 | 重复写、重复中断、重复退休 |
| I4 | 阻塞不能丢失事务身份、已确定操作数和协议要求保持的 payload | 反压后结果改变 |
| I5 | 取消只作用于属于该年龄范围、尚可撤销的工作 | 杀掉 older 工作或漏掉错误路径 |
| I6 | 外部在途请求始终有负责排空/接收/丢弃结果的 owner | 迟到响应污染新事务，或总线挂死 |
| I7 | 非幂等访问不能错误推测、重复或被任意重放 | 外设读清零、FIFO pop、命令写出现多次 |
| I8 | 在外部最终响应、消费者最终接受等环境假设下，内部等待关系不能形成永久环 | 队列死锁 |

非幂等属性不能简单由“有无 Cache”代替；某些 uncached RAM 是幂等的，某些 MMIO read 有副作用。采用“所有 MMIO/uncached 都在 COMMIT 串行执行”是保守策略，而非二者本质相同。[Idempotency PMA](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#_idempotency_pmas)

从这里开始，数据冒险、flush、队列、旁路都是维护这些规则或提高满足规则时的吞吐，不能反过来用这些模块的存在定义规则。

## 5. 推导所用的八级参考模型

为了谈周期，必须先公开假设。定义参考模型 R0：

- 单发射、顺序推进、顺序退休，无 rename/ROB；先不附加第二个 MEM2 owner 或隐式额外级。
- 八个逻辑阶段为 IF1、IF2、ALIGN、D、X、M1、M2、C，每个相邻边界有明确寄存。
- 基础 GPR 写在 C；ALU/link 在 X 产生，Load 命中结果在 M2 产生；旁路只使用边沿后稳定的结果。
- 以下固定拍数只用于 I$/D$ hit、前端不断供、资源可用、无 kill、无额外反压的情形。
- 可变延迟操作保持其 owner，不能靠假定下一拍一定有结果维持正确性。

把 P 所在 D 周期记为 T0，则 X=T1、M1=T2、M2=T3、C=T4。ALU 注册结果从 T2 起可用；Load hit 注册结果从 T4 起可用。

**R0 是推导坐标，不声称当前 RTL 已经如此实现，也不证明该模型在目标 FPGA 上达到某个频率。** 八级只是选定的分工，若 IP 必须另加一拍，就应显式修改时间表，再重新推导，不能保留旧延迟口径。

| 阶段 | 从功能需求分配的工作 | 应避免混入的职责 |
|---|---|---|
| IF1 | 选择 fetch PC、登记请求身份/容量 | 接收未经寄存的全后端长控制链 |
| IF2 | 接收/匹配取指 block、保存错误与流身份 | 对错误路径立即提交 trap |
| ALIGN | 识别长度、跨块拼接、RVC 解压 | 丢失原指令长度与原始异常信息 |
| D | 译码、源/目的身份、绑定输入或生产者身份 | 用 rd 命中但年龄不正确的值“凑 ready” |
| X | 计算、地址生成、真实控制流解析 | 未授权的不可撤销 Store/MMIO 效果 |
| M1 | 地址属性/访问合法性、发起合适存储访问 | 假定所有地址都可投机访问 |
| M2 | 命中/返回值与错误的完成边界 | 产生与真实 completion 相矛盾的 ready |
| C | 按序裁决提交/trap，更新架构状态 | 用 transfer-ready 代替正常提交许可 |

Queue-decoupled LSU 可以把 M2 的存储完成转交给 LQ/Cache；一旦这样选择，就必须把 M2 的角色和 producer observation 一起重定义。

## 6. 数据相关首先按资源读写关系推导

两个动态实例 `P < C`，针对同一个状态资源，只有以下基础关系：

| P/C 的访问 | 关系 | 在本设计中的含义 |
|---|---|---|
| 写/读 | RAW | C 需要 P 的结果 |
| 读/写 | WAR | C 的写不能破坏 P 尚未取得的输入 |
| 写/写 | WAW | 后写的最终效果不能被前写迟到覆盖 |
| 读/读 | 无寄存器值冲突 | 仍可能争用物理读端口；设备 read 另有副作用语义 |

GPR、CSR 都适用，但 CSR 还可能存在隐式读写、别名和异步更新。内存地址在执行前可能未知，并且要按 byte 判断覆盖，不能只按指令编码的寄存器编号比较。

对于基本顺序流水：源值及时捕获、GPR 在 C 顺序写回，可以结构性消除普通 WAR/WAW 的风险。但若允许晚写回 MDU、操作数延后读取或其他独立完成通道，这些前提改变，必须重做 WAR/WAW 推导。

### 6.1 RAW 的唯一选择规则

对消费者 C 的每个实际读取源 r，定义：

```text
producer(C,r) = C 之前、仍有效、写 r 的最近动态实例
```

若它不存在，使用合法的架构 RF 值；若它存在，必须先锁定其身份，再判断结果能否在截止时刻取得。不能跳过一个未 ready 的最近 producer，去选更老的 ready producer。

这一规则必须覆盖所有储存中的实例：普通 pipe、FIFO head 和 tail、LQ/MDU completion slot、尚未实际完成写回的授权项。未把 FIFO tail 暴露到比较网络时，必须用阻塞等方式保证它不会被漏掉。

## 7. 先决定“操作数什么时候必须拿到”，再推导间隔

有两种自洽选择：

**D 绑定模型：** C 只有在 DECODE 得到完整正确值后才能进入 EX。简单，但相邻 ALU 若只能从寄存结果旁路，就需等一拍。

**X 使用模型：** D 可以保存已就绪值或明确的 producer 身份；C 在 EX 真正计算之前必须拿到正确值。这样可以避免相邻 ALU 停顿，但增加 EX 取值/保持/取消逻辑。

不能在 D 放行时按 X 使用模型承诺“后面能取到”，后面却只实现 D 绑定模型的 ready/value。

| 源的用途 | R0 中真正的使用截止点 | 可以选择的变化 |
|---|---|---|
| ALU rs1/rs2 | X 计算前 | D 提前绑定以简化 X |
| Branch rs1/rs2 | X 比较前 | 增加独立比较级，但分支恢复变晚 |
| JALR rs1 | X 目标加法前 | 本地先捕获一拍，需修改延迟定义 |
| Load/Store base | X 地址加法前 | 地址生成另级，需全路径重推 |
| Store data | R0 选 X 形成 packet 前 | 可延到 M1/SQ 填充，但队列必须独立记录 data-ready |
| CSR GPR source | 正式 CSR 更新前 | 通常较早捕获；CSR 旧值按提交顺序读取 |

### 7.1 不依赖当前 RTL 的间隔公式

g 为 P/C 之间独立指令数。无其他阻塞时，C 的 D 在 T(g+1)，X 在 T(g+2)。令 P 的注册结果从 T(a) 起可用：

```text
仅 D 绑定所需等待 = max(0, a − (g+1))
允许 X 取值所需等待 = max(0, a − (g+2))
```

这是给定 R0 和可达旁路网络下的数据就绪下界，不含容量/控制流损失，也不保证相关 mux 满足时序。代入 ALU a=2、Load hit a=4：

| 模型与生产者 | 相邻 g=0 | 隔1条 | 隔2条 | 隔3条 | 隔4条及以后 |
|---|---:|---:|---:|---:|---:|
| D 绑定，ALU | 1 | 0 | 0 | 0 | 0 |
| X 使用，ALU | 0 | 0 | 0 | 0 | 0 |
| D 绑定，Load hit | 3 | 2 | 1 | 0 | 0 |
| X 使用，Load hit | 2 | 1 | 0 | 0 | 0 |

表格由“结果何时出现”和“何时必须使用”相减得到，不从测试统计反推。选择增加 Load 返回寄存、Branch operand capture 等阶段时，修改相应 a/截止点，并将该代价纳入模型。

### 7.2 反压后的通用形式

静态 g 只在无阻塞假设下给出时间。一般情况下，应按实际事件计算：

```text
可执行(C) = live(C)
          && 每个必需输入在本次使用前可正确取得
          && 本次所需资源有容量
          && 本次执行/请求的授权条件成立
```

因此，测试“隔几条”是覆盖这些状态转移的手段，不是基本冲突分类本身。

## 8. 多生产者、双源与保持状态由同一规则得到

`ALU→同 rd Load→consumer`：最近 Load 未完成时，不能用旧 ALU；`Load→同 rd ALU→consumer`：应选择较新的 ALU，不应无理由继续等已被覆盖的旧 Load。两个源来自不同 producer 时分别解析，不能只用一个笼统 ready。

如果 C 已取得某一源但另一源没好，或下游暂不接收，有两种合法实现：来源一直保持到 C 真正使用，或 C 本地捕获已确定的值。不能在下一拍重新从不同 producer 取同名 rd。

Producer 的架构 rd、静态 PC、动态身份不是同一个东西。身份可以由顺序位置隐含，也可以使用 token/generation；具体编码是实现选择。约束只有一个：迟到完成不能被另一个动态实例消费，有限位宽重用前必须证明旧事务已不可能误匹配。

## 9. 访存相关从“地址、覆盖、顺序、可见性”推出

先不要讨论 Cache hit/miss。Load 的基本问题是：它应该看到哪些字节、来源于哪个允许的写入；Store 的基本问题是：它何时允许对观察者生效。

对无外部并发写的单 hart 普通内存窗口，每个 Load byte 应反映最近的 older 对应 Store 或更早的内存值；存在其他观察者时，必须回到系统内存模型与一致性约定。硬件转发通常按 byte 合并/优先，而不是仅比较整个 word 地址。[Load value 规则](https://docs.riscv.org/reference/isa/v20260120/unpriv/rvwmo.html#_load_value_axiom)

| older / younger | 从语义推出的问题 | 保守基线策略 |
|---|---|---|
| Load / Load | 两个地址/值的依赖，设备副作用，物理端口竞争 | 按序发请求；只在证明合法后增加重叠 |
| Load / Store | younger 写不能破坏 older 读取应见的值 | 不让年轻 Store 提前不可撤销生效 |
| Store / Load | 地址可能相同；Load 不能读旧数据 | 等 Store 可见，或做正确的 Store-to-Load forwarding |
| Store / Store | 重叠 byte 的最终顺序；设备命令顺序 | committed stores 按序 drain |

若 older Store 地址未知，不能以“不知道相同”当成“已知不同”。要么等待地址确定，要么引入带检测和恢复的内存推测；后者是额外设计选择，本项目不必为了性能默认采用。

### 9.1 转发是怎样推导出来的

1. 找到所有可能影响所需 byte 的 older Store。
2. 按年龄确定每个 byte 的最新来源。
3. 对需要使用的来源检查地址/数据是否已就绪。
4. 全部 byte 能得到正确值则可转发；否则等待，或与已确认的 Cache 值合并。

“只转发一个完整覆盖的最新 Store；部分覆盖等待 drain”是该规则的简单实现，不是另一种 ISA 规则。若增加跨多个 Store 的 byte gathering，就需要更多年龄选择和数据合并路径。

## 10. Cache miss 是可变完成时间，不是新指令语义

Cache 的实现应使处理器获得符合约束的数据；hit/miss 本身不改变 Load/Store 的指令定义。miss 产生的是 completion 尚未到达，以及一组内部数据保存/协议义务。

由可写回 Cache 的数据保存要求，自然得到：

| 判定 | 必需动作 | 可以优化的部分 |
|---|---|---|
| hit | 获取/更新正确 line 与 byte | way/word 选择、格式化与寄存位置 |
| miss，victim invalid/clean | 请求并接收新 line，验证后建立可见状态 | burst、预取、关键字优先返回 |
| miss，victim dirty | 在丢弃唯一最新副本前保存/写回 dirty 数据，再替换 | 独立 eviction buffer、写回/回填重叠 |
| 访问尚有未落实 Store | 保证取到最近 byte；不能从过期 RAM 输出读旧值 | forwarding、shadow、合并 |
| 请求/响应被阻塞 | owner 和协议 payload 保持，保留接收容量 | FIFO、credit、多个 outstanding |
| refill/writeback error | 不把坏结果当成功、不丢失应保留数据；按平台策略报告 | 重试、错误记录/恢复策略 |
| 所属指令被取消 | 禁止该指令后续架构提交；外部协议仍须完成 | drain 后丢弃，或保留合法缓存填充 |

writeback 失败涉及已经退休的 older 数据，不能简单当作可清除的年轻 Load payload。退休前可精确归属的访问错误，与退休后 drain/写回错误必须分别定义报告策略。

### 10.1 从最简单实现到队列解耦

**阻塞基线：** miss 的 owner 留在存储完成阶段，older 指令继续退休，younger 工作最多填满有限本地缓冲，随后被反压。只要不丢、不重、不错误提交，就是正确实现；不需要先假定必须存在 LQ。

**增加吞吐的选择：** 用 LQ/请求队列保存多个事务，让顺序指令 packet 带身份前进，数据独立完成。此时必须新增 request/result 关联、容量预留、取消和复用规则，以及提交端查询 completion 的契约。一个 miss FSM 配几个 FIFO，仍不等于多个 miss 可以并行服务。

当 miss 增加 L 拍完成延迟时，理想数据等待公式中的 `a_load` 变为 `4+L`；但下游容量可能先耗尽，使 C 更晚到达。必须分别观察“值没好”和“没有位置继续走”，不能将所有空退休拍都叫 Cache wait。

## 11. Store 和 MMIO 的授权边界

普通可缓存 Store 可以提前计算地址、数据，甚至准备 Cache line，但修改架构意义上的内存内容必须满足选定提交契约。若在正常退休后进入 committed buffer，buffer 就承接了必须最终完成的义务，不能再按年轻 speculative 项一起清掉。

MMIO read 也可能不可撤销。对非幂等设备，参考基线是在安全提交位置发起，记录一次请求，等到适当完成状态后再放行。已经被设备执行的 read/write 不能靠清 pipeline valid 回滚。

这里有三个独立时刻：请求获授权、设备/Cache 接受、外部观察者可见。Store 进入 dirty Cache 不等于 DDR 已更新；FENCE/DMA 的要求取决于观察者位于哪个一致性域。

不能用 `valid && ready` 统一表示普通退休和 trap 处理。参考事件应分成 `normal_retire`、`trap_accept`、`cancel`、`background_complete`；只有与该副作用匹配的事件能更新状态。

## 12. 控制流从“真实 next PC 尚未确定”推出

分支与跳转的语义要求是执行正确的后继，不要求预测器存在。先定义无预测基线：等待 next PC，或顺序取指并在解析时取消不正确的 younger 实例。

加入预测只是提前假设 next PC。恢复条件统一为“预测后继与实际后继不一致”，方向、目标、陈旧 BTB、return 都是它的展开。不能让预测器定义实际指令语义。

| 恢复来源 | 为什么发生 | 应取消谁 |
|---|---|---|
| 前端预测选择新流 | 还未提交的取指策略改变 | 该取指流中被替代的 younger 数据；保留仍需执行的分支自身 |
| EX 解析预测错误 | 实际后继与假设不同 | 该控制流指令之后的错误路径实例 |
| COMMIT 同步异常/中断边界 | 建立架构恢复点 | 该边界之后尚未授权的实例；按规则处理边界指令 |
| MRET/FENCE.I 等 | 特权返回/取指可见性更新 | 需要重取的 younger 指令 |

若 older trap 与 younger EX 修复同时发生，older 边界胜出；年轻的跳转目标不能覆盖 older trap 目标。错误路径微架构活动可以改变缓存或预测历史，这与错误路径产生架构写入不同；是否清预测历史是性能/维护策略，不是普通精确异常必须回滚的一切状态。

RVC 使长度和指令起点也成为流身份的一部分。跨 block 的半条指令不能作为完整指令发射；恢复时不能把旧流后半字拼进新流。压缩后的内部 32-bit 表示仍需保留原始长度与异常信息。[C 扩展](https://docs.riscv.org/reference/isa/v20260120/unpriv/c-st-ext.html)

## 13. 异常、中断和长延迟 MDU 的边界

异常检测可以很早，但选择哪条异常产生架构效果必须服从程序年龄。一个年轻非法指令可以被更老分支取消；一个年轻 Load error 不能越过 older 未完成指令直接更新 mepc。

精确边界的参考要求是：边界前的已授权效果保留并按契约完成；faulting/被抢占指令不错误地产生普通副作用；边界后的未授权工作取消。异常原因的优先级还要区分“同一指令的多个候选原因”和“不同年龄指令的事件”，不能只看哪个错误信号先到。

MUL/DIV 本身的算术需要不同时间；除零等规定结果不应被误建模为普通整数算术 trap。[M 扩展](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)

对解耦 MDU 有两种选择：

| 选择 | 退休含义 | 额外证明义务 |
|---|---|---|
| 结果完成后在 C 正常写回并退休 | 与 ALU/Load 统一 | 长操作挡住 C，但 younger 可在有限范围先执行 |
| token 先越过某个授权点，结果随后写回 | authorize 与 architectural completion 要分别定义 | pending rd、RAW/WAW、写口仲裁、trap/IRQ 能否越过、计数/trace、取消归属 |

后者不是天然错误，但它不是“免费解耦”。为了使架构边界更容易审查，建议先以第一种定义为参考，再判断第二种能带来多少实际吞吐收益。不要让 `retire` 一词同时表示普通完成、Store 接管、MDU 请求授权和异常接受。

## 14. CSR、FENCE、WFI 不是普通 GPR 运算的附注

CSR 的读取/写入意图由具体指令形式决定；例如寄存器形式与立即数形式、rd/rs1 是否为零，对 read/write suppression 有不同规定。其操作还可能影响中断资格等隐式消费者。参考基线在提交顺序中读取、修改，避免另建 CSR forwarding；若前移读取，就必须重新引入 CSR RAW/状态一致性约束。[Zicsr](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)

FENCE 要建立规定类别的访问顺序，而不是在所有实现中都要求 clean-all。FENCE.I 要建立此前存储与此后取指之间的可见性，具体可能通过 invalidate、同步缓存、等待请求等实现。[Zifencei](https://docs.riscv.org/reference/isa/v20260120/unpriv/zifencei.html)

本 SoC 的 DMA 不会仅因 CPU 有 FENCE 就自动与 DCache 一致：需要明确硬件一致性域、缓存维护与软件缓冲区所有权。仅等待 Store buffer 空，也不必然等于所有外部观察者已看到最新数据。

WFI 的等待、唤醒与实际采取中断是不同事件；MRET 则同时涉及机器态恢复和控制流。它们应从机器态语义独立列出所读写的状态，然后放入同一年龄/授权模型，而不是为每个指令另造互不相干的 flush 规则。

## 15. 资源冲突和协议生命周期从容量推出

数据没有 RAW 也可能没有位置执行。对每个资源先定义容量、分配事件、释放事件和完成承诺，再决定反压：RF 写口、MDU slot、Cache 查询口、miss owner、请求/响应 FIFO、redirect slot 都如此。

| 生命周期 | 取消/阻塞要求 |
|---|---|
| 只在内部保存、尚未对外承诺 | 可以按年龄取消，并归还对应容量 |
| AXI VALID 已经对外保持但尚未握手 | 必须遵守该接口的稳定/握手契约，不能随内部 kill 任意撤销 VALID |
| 请求已经握手、响应未完成 | 保留协议 owner，继续接收/drain；逻辑取消与协议完成分离 |
| 结果已到但消费者被阻塞 | 保存结果，或者由接口保持，不能丢失一拍完成脉冲 |
| 已正常授权的 Store/MDU | younger flush 不得随意抹掉履约状态 |

注册反压必须预留停止信号生效前还可能到达的数据容量。可以用 skid/credit/响应槽来实现，不能仅把 ready 延迟一拍却没有地方保存额外数据。

full+pop+push 是否允许是选择；所有指针、valid、token 和 hazard observation 必须采用同一决定。允许容量复用之前，先确认 tail/新 head 对 producer 年龄判断是否可见。

死锁检查要画等待关系，例如：older Load 等 Cache、Cache 等 younger Store reservation、younger Store 又等 older Load 退休。若形成环，仅加深 FIFO 不解决根因；要改变授权或发请求顺序。

## 16. 如何判断分类足够完整，而不是凑案例数量

采用三层检查：

1. **状态资源完整性**：所有显式/隐式读写是否进入 GPR、PC/指令流、CSR/机器态、内存/设备的关系表？有没有遗漏 x0 Load、Store data、CSR enable 对 IRQ 等特殊语义？
2. **生命周期完整性**：对每种事务，创建、等待、完成、失败、取消、授权后排空、身份复用都有唯一 owner 和规则吗？
3. **并发事件完整性**：同拍发生这些事件时，是否可能竞争同一状态？若竞争，优先级依据是年龄、协议义务还是容量规则？是否存在内部等待环？

由此才生成测试：RAW 相邻/间隔是时间关系实例，dirty miss 是缓存保存义务实例，flush×response 是生命周期交叉实例。案例数既不能证明模型完整，也不能替代不变量。

可直接从约束生成的检查包括：selected producer 必须是最近 older writer；正常提交和同条 trap 互斥；取消项不可产生新的普通架构效果；请求完成只匹配原 owner；排队数量符合分配/释放守恒；外部最终回应条件下内部最终能释放。

## 17. 现在才对照 EdRV32 当前实现

9 月 1 日的旧八级文档限定普通旁路只在 DECODE，而当前源码已经有 EX resident/late-load 取值，并且存储完成从 MEM2 转移到队列。这里应明确承认契约发生了变化：不能同时用旧文档的操作数绑定时刻、新实现的旁路方式和旧的阶段延迟解释同一条指令。前面的 D/X 两模型正是用来把这一选择重新说清楚。

| 推导出的契约 | 当前实现观察 | 判断 |
|---|---|---|
| 同一 producer 的完成可见性应跨位置一致 | Load 在 MEM1 可 late-release，到 MEM2 却 ready=0/late=0 | 实现不连续，不是架构固有特殊情况 |
| value 与 wait 应由同一最近 producer 决定 | resident ALU 覆盖旧 Load，但旧 Load hard-block 仍可阻塞消费者 | 可优化的多余等待 |
| 不可撤销授权必须区别正常退休与 trap 接受 | Store fire 依赖也用于 trap 的 ready | 已复现正确性缺陷，优先修复 |
| 阶段名应对应清楚职责与时间边界 | M2 内部 owner + 输出 pipe，存储 completion 已转给 LQ | 需重新定义 completion stage/缓冲职责，不能只维持八级名称 |
| 所有额外 producer 槽都要可见或受保护 | MEM1 FIFO tail 未独立暴露，靠 full 阻止 D | 放松 full 之前必须补足年龄观察，不可盲删 stall |
| late result 的退休语义必须明确 | MDU token 授权、实际写回、计数事件分开 | 需要单独写清 contract，再评估简化 |
| 监控不得成为正常执行的背压来源 | HPM 无功能性反压，但事件生成到采样存在长路径 | 就近寄存/裁剪是实现优化；不能用观测规模反过来改变执行语义 |

源码入口：[producer selection](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/decode/edrv32_operand_resolve.v>)、[DECODE](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/decode/edrv32_decode_stage.v>)、[MEM2](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_mem2_stage.v>)、[COMMIT](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/commit/edrv32_commit_stage.v>)、[Core 接线](<G:/claude code/EdRV32-Competition-2026/rtl/cpu/core/edrv32_core.v>)。

先前的 [审计报告](<G:/claude code/EdRV32-Competition-2026/docs/validation/2026-09-26-cpu-cache-rtl-audit.md>) 与 [365 场景周期矩阵](<G:/claude code/EdRV32-Competition-2026/docs/architecture/2026-09-26-cpu-hazards-cache-cycle-matrix.zh.md>)，在本章作为契约符合性证据使用，不作为前面需求的来源。

## 18. 面向当前目标的设计取舍建议

建议保留顺序单发射与明确提交边界，并优先建立以下统一契约：

- DECODE 绑定“值或生产者身份”，EX 在实际使用时检查/取得，普通 ALU 相邻旁路保持；对 Cacheable Load 的身份/属性/完成定义全链一致。
- 所有普通指令按统一的正常退休规则处理。先将 Store 的 normal commit 与 trap 接受分开；MDU 的 authorize/retire/writeback 使用不同事件名字并明确定义。
- MEM1/MEM2 是存储准备/完成阶段，还是只携带 token 的顺序缓冲，必须二选一地讲清职责；可以保留缓冲容量，但不要留下另一套过时 ready 语义。
- Cache 的请求、完成、取消和协议排空有完整事务身份；LQ/SQ 的每个槽、FIFO tail 都进入同一个年龄模型。
- 时序隔断设置在真正的请求包/结果包/本地容量边界，不通过连续组合 ready 或空 FIFO 直通重新串起多个控制域。

每个优化候选先证明不变量仍成立，再比较 `f / CPI`（固定指令流）、CoreMark/MHz 与资源。更多流水级、更多旁路、更多队列项都不是独立目标。

本文完成的是从语义到结构的重新推导和当前实现对照，没有新增 RTL、没有宣称新参考模型已达到目标频率，也没有把旧测试全部通过当成架构已完整证明。
