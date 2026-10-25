# EdRV32 八级流水线控制与冒险契约

> 文档关系：本文从属于 `cpu-rewrite-master-spec.zh.md`。总规格中的 PMA、CSR、
> FENCE/FENCE.I、Cache、MDU、精确提交和验证要求同样是控制契约的一部分。

状态：2026-09-01 第一版。本文补充
`cpu-rewrite-8stage-architecture.zh.md`，是所有流水线控制 RTL、断言和测试的共同依据。
若测试暴露本文未覆盖的情形，应先补全控制模型并审计同类路径，再修改 RTL；禁止按测试名
增加特殊条件。

## 1. 基本事件与不变量

每个边界只使用以下事件定义：

- `transfer = valid && accept`：本级条目被下一级接受。
- `capture = in_valid && in_ready`：本级从上一级接收新条目。
- `kill`：按年龄域清除条目，优先级高于 `transfer` 和 `capture`。
- `hold`：没有 `capture/transfer/kill` 时，`valid` 和全部 payload 保持不变。

对每一级都必须成立：

1. `valid && !accept` 时 payload 稳定；请求地址、写数据、异常和 rd 均不得变化。
2. 条目只有在 `transfer` 时离开；下游不得仅凭 `valid` 重复执行副作用。
3. 被 `kill` 的条目从该时钟沿起不能再发请求、分配 MDU、写 GPR/CSR/cache 或 retire。
4. 同一条指令最多产生一次 redirect、一次存储器请求、一次 GPR/CSR 写和一次 retire。
5. reset 与 kill 只要求清除 valid/FSM/epoch 等控制状态，不要求清空无效 payload。

所有边界的顺序状态优先级固定为：`reset > age-qualified kill > capture/transfer > hold`。
这些事件的时序所有者是 `pipeline/edrv32_pipe_<source>_to_<destination>.v`，不是source或destination
stage文件。stage只计算事件条件和payload候选；边界模块唯一写入该边界的valid/occupancy与payload。

`kill` 是边界 valid/occupancy 的同步最高优先级事件，不得作为跨级 `in_ready` 的组合反压条件。
尤其 `DECODE→EX.in_ready` 只能由本边界容量和 EX 接受条件决定；若 kill 与输入握手同拍，允许上游
把该年轻条目视为已丢弃，但边界 valid 必须保持无效。这样 EX redirect 只能到达最近边界的同步
清除端，不能再沿 ready 网络反向穿透 ALIGN/IF2。

## 2. 阶段流动和反压所有权

| 阶段 | 可变延迟来源 | stage本地状态 | 输出边界状态所有者 | 允许向上游传播的条件 |
|---|---|---|---|---|
| IF1 | I$ 请求/响应握手 | architectural PC/epoch | IF1→IF2 pipe保存两个请求tag/epoch owner | 只受tag容量限制，不接收执行后端ready |
| IF2 | 已返回取指块 | 半字FIFO、消费PC/epoch | IF2→ALIGN pipe保存可见halfword窗口/metadata | 队列满时停止I$响应 |
| ALIGN | 跨字指令、DECODE暂停 | 无跨级uop状态 | ALIGN→DECODE pipe保存一条规范指令记录 | 只向IF2传播本地域容量 |
| DECODE | RAW/WAW、MDU slot、EX容量 | GPR组合读/相关性组合结果 | DECODE→EX pipe保存完整uop/operand | 依赖和结构条件都满足才发射 |
| EX | redirect/MDU请求、MEM1容量 | MDU dispatch/redirect局部握手状态 | EX→MEM1 pipe保存执行结果/异常/token | redirect和MDU请求必须与指令接收原子发生 |
| MEM1 | PMA/阵列查询、MEM2容量 | PMA组合候选 | MEM1→MEM2 pipe拥有2-entry head/tail FIFO | 不直接观察COMMIT复杂完成条件 |
| MEM2 | hit/miss/refill/响应、COMMIT容量 | miss owner、Cache transaction/响应 | MEM2→COMMIT pipe保存精确提交packet | miss期间只靠本地状态反压MEM1 |
| COMMIT | MMIO/store响应、redirect、授权MDU | memory FSM、redirect event | 无下一级uop pipe；直接生成精确retire/状态写 | 是后端反压终点，不向前端形成透明组合链 |

实现约束：从 COMMIT 到 DECODE/ALIGN 不得形成连续的
`ready = !valid || downstream_ready` 组合链。需要满速吞吐的断点采用本级拥有的 elastic/skid
容量，且所有额外驻留条目必须进入年龄排序和 RAW 比较；不能用遗漏 producer 的缓冲换时序。

七个具名pipeline register逐个绑定本节断言；禁止把所有边界的valid集中到一个always块，
也禁止把stage本地FSM或Cache array状态搬入通用pipeline模块。

正式时序审计的控制路径上限：任一ready/accept组合路径最多依赖一个相邻pipeline register的
局部状态，不能透明穿过第二个边界；满吞吐需要用本地skid/credit实现。该路径也不能穿过CSR、
trap、cache tag/data选择或redirect仲裁后继续传播。Phase 2开始即按100/200 MHz双约束检查该断点。

## 3. 数据冒险矩阵

DECODE 是普通整数相关性的唯一判断点。`uses_rs1/uses_rs2` 必须覆盖 ALU、branch、JALR、
load 地址、store 地址和 store data；不实际读取的编码不得制造假相关。

按“离消费者最近，即最新老指令优先”检查 producer：

| producer 位置 | ALU/JAL/JALR 结果 | load 结果 | CSR 旧值 | MDU 结果 | DECODE 行为 |
|---|---|---|---|---|---|
| DECODE 驻留输出 | 尚未形成寄存化 EX bypass | 尚未形成 | 尚未形成 | 由分配握手决定 | 命中 rs1/rs2 时停一拍，禁止同沿读旧 GPR refill |
| EX 输出 | `ready=1` 可旁路 | `ready=0` | `ready=0` | 不进入普通旁路 | 命中且不 ready 时停顿 |
| MEM1 输出 | `ready=1` 可旁路 | `ready=0` | `ready=0` | 不进入普通旁路 | 同上 |
| MEM2/COMMIT 输入 | `ready=1` | 响应完成后 `ready=1` | 合法访问时 `ready=1` | 不进入普通旁路 | 同上 |
| 已写 GPR | 组合读 | 组合读 | 组合读 | scoreboard 清除后的下一周期组合读 | 无流水线 producer 命中时使用 |

选择器必须先判断“最近的 producer 是否命中”，再判断该 producer 是否 ready；不能绕过一个
未就绪的新值去选择更老的已就绪值。x0 永不构成相关。

冲突类型固定如下：

- 普通顺序流水线 RAW：由上述所有驻留 producer 和旁路处理。
- 普通 WAW：提交严格有序，不需要停顿。
- WAR：操作数在 DECODE 边界锁存，不存在 WAR。
- MDU RAW/WAW：pending scoreboard 精确比较 rd；无关指令可继续。
- MDU WAR：MDU 操作数在请求握手时锁存，不存在 WAR。
- store 的地址 rs1 和数据 rs2 与普通 ALU 源完全同等，不能另走无冒险旁路。

若 stage 增加第二个 elastic 条目，该条目是正式 producer，必须按年龄插入上表；未经依赖网络
覆盖，不得增加队列深度。

## 4. 结构冲突和长延迟操作

| 资源 | 分配点 | 满/忙时行为 | 完成/释放点 |
|---|---|---|---|
| MDU 单 slot | EX 接收 MDU 的同一沿 | 只停新的 MDU；pending rd 的 RAW/WAW 停 DECODE | COMMIT 授权后结果实际写入 GPR |
| D$ miss owner | MEM2 判定 miss | 保持 owner；停止新的会越过该访问的 MEM1 | refill 完成并生成唯一响应 |
| uncached/MMIO | COMMIT 成为最老条目 | COMMIT 保持请求 payload；后端停止 | 总线响应或错误被接收 |
| store | COMMIT 成为最老条目 | 与 MMIO 相同；不得在 MEM1/MEM2 提前写阵列 | 写请求被架构接受并得到所需响应 |
| redirect slot | EX 或 COMMIT event | 同时只能保存一个；COMMIT 优先，EX 必须保持 | IF1 接受已寄存 event |

MDU 允许“计算与普通流水线重叠”，但不允许精确状态破坏：有已授权未写回 MDU 时，trap、IRQ、
mret、fence.i 和 WFI 必须等待；未授权 slot 被更老 COMMIT redirect 取消。

## 5. 控制流、年龄和 kill 矩阵

kill 按“事件发起指令的年龄”定义，不能把 redirect 的传输时刻当作年龄。

| 事件 | IF1/IF2/ALIGN | DECODE | EX 输出 | MEM1 | MEM2 | MDU |
|---|---|---|---|---|---|---|
| EX branch/JAL/JALR redirect 被仲裁器接受 | 由本拍关闭的 DECODE→EX 边界隔离，不能形成副作用 | DECODE→EX 本拍清除并禁止年轻条目进入 EX | **保留 redirect 指令本身** | 保留，均更老 | 保留，均更老 | 保留已分配的该指令/更老 slot |
| COMMIT exception/IRQ/mret/fence.i event 被接受 | 由本拍关闭的 DECODE→EX 边界隔离 | DECODE→EX 本拍清除 | 清 | 清 | 清除 COMMIT 当前条目之外的年轻状态 | 取消未授权 slot；已授权状态先等待 |
| 已寄存 redirect 被 IF1 接受 | 清空前端残留，重置取指 PC/tag 消费状态并采用新 epoch | 清空隔离在前端的年轻条目；不再次杀后端 | 不杀 | 不杀 | 不杀 | 不变 |
| I$ 迟到旧 epoch 响应 | 丢弃 | 不变 | 不变 | 不变 | 不变 | 不变 |
| D$ miss/refill | 不变 | 容量耗尽后自然反压 | 保持 | 保持/停止发新请求 | miss owner 保持 | 可继续运算，提交规则不变 |

redirect 优先级固定为：COMMIT exception > COMMIT interrupt > COMMIT mret > COMMIT fence.i >
EX control-flow correction。COMMIT 事件存在时 EX event 不得丢失，EX 输入保持到仲裁器可接收。

EX redirect 的两个时刻含义不同：

1. `event_fire`：确定年龄，此时只在离事件源最近的 `DECODE→EX` 边界执行同步 kill，阻止最老的
   年轻指令进入 EX；redirect 指令正常进入 EX 输出。更远的 IF2/ALIGN/DECODE 条目即使暂存一拍，
   也被该边界隔离，不能发起请求、进入 EX 或产生架构副作用。禁止把 EX 比较结果组合广播到
   多个前端边界。
2. `redirect_apply`：寄存事件下一拍被 IF1 接受，统一更新 PC/epoch 并清空被隔离的前端残留；
   不得再杀 EX 之后的 redirect 指令或更老指令。

predicted-taken是前端本地流切换，不等同于EX/COMMIT架构redirect。IF2允许
在返回块append时对指令长度做预解码并提前切换取指流，但必须保留所有更老
半字和预测分支自身；每个已采用预测的分支携带一次性标记，送入ALIGN时仍
保留原predicted-taken/target供EX校验。高半字开始的32位分支在续半字返回
前不得切换；链式预测同拍时老分支的consume-PC更新优先于年轻流的append。

COMMIT redirect 采用相同的分层原则：事件接受沿立即清所有年轻后端状态并关闭
`DECODE→EX`，远端前端只由已寄存的 `redirect_apply` 清理。这样 kill 的组合路径不会跨越多个
pipeline register，且精确状态与年龄关系不变。

## 6. cache hit/miss/replay 契约

cache 实现前先冻结以下行为：

- I$：请求携带 epoch；hit 和 refill 返回都携带原请求 epoch。redirect 后旧 epoch 响应只消费并
  丢弃，不能追加 IF2、改变新 PC 或占用新 epoch 队列。
- D$：每次只允许一个 MEM2 miss owner。miss 保存完整地址、size、unsigned、rd、store data、
  PC、异常和 epoch；refill 期间上游 payload 不得被组合信号替换。
- cacheable load hit 可在 MEM2 产生 ready 旁路；miss 只在 refill 数据寄存后变为 ready。
- replay 是同一条 instruction 的内部状态迁移，不重新进入 DECODE，不重复 retire，也不重新分配 MDU。
- store 在 COMMIT 前只能做 tag/PMA 检查；真正 cache line 修改或总线写由 COMMIT 授权。
- uncached/MMIO 不分配 cache line，不投机发起；错误响应转换为当前最老指令的精确异常。
- fence.i 必须使此前已提交 store 对后续取指可见，清理/失效 I$ 状态，再以 fallthrough PC 新 epoch
  取指；旧 I$ hit/refill 同样按 epoch 丢弃。

需要覆盖 hit-under-miss、多个 miss、store buffer 或 non-blocking cache 时，必须另行扩展所有权、
年龄和 replay 表，不能从单 miss 机制暗中演化。

## 7. 验证准入矩阵

每一类控制规则至少有一个模块测试、一个整核随机等待测试和一个提交级 reference check：

| 类别 | 必测组合 |
|---|---|
| RAW | rs1/rs2；ALU/load/CSR/MDU；每个 producer 距离；连续同 rd；x0；store addr/data；JALR base |
| WAW/MDU | pending rd 同名、无关 rd 越过、结果早/迟于授权、普通写端口冲突、cancel |
| 反压 | 每个边界单独停；连续随机停；valid/payload 稳定；解除反压首条不丢不重 |
| redirect | EX event 与 COMMIT event 同周期；redirect slot 忙；分支本身保留；所有更老指令保留；年轻副作用为零 |
| 异常/IRQ | 每个 stage 已有老/年轻条目；load/store 等待期；MDU 未授权/已授权；mret/fence.i |
| I$ | hit/miss、跨字 RVC、redirect 同周期响应、迟到两个旧 epoch、队列满 |
| D$ | load/store 各 size、hit/miss/refill/error、backpressure、replay、fence.i 可见性 |

必须加入的通用断言：

- stall 稳定：`valid && !accept && !kill |=> valid && $stable(payload)`。
- no ghost side effect：任何请求/写回/retire 都能追溯到一个未被 kill 的有效条目。
- no duplicate：同一 sequence id 的 memory request、redirect、retire 不超过一次。
- age-correct kill：EX redirect 后所有更老 sequence id 继续且 redirect 自身最终 retire；所有年轻 id
  不得 retire。
- bypass correctness：选中值来自最近匹配 producer；最近匹配但未 ready 时 DECODE 不 transfer。
- liveness（有界环境）：响应最终到达且下游最终 ready 时，有效条目最终 retire 或被更老事件 kill。

测试程序 PASS 只是这些机制检查之后的系统证据，不能替代断言和冲突矩阵。

## 8. 2026-09-01 实现审计

当前 RTL 与本契约相比有三项必须先解决的问题：

1. 已修正：DECODE 同沿 refill 未检查驻留 DECODE/EX producer，导致背靠背 RAW 读旧 GPR。
2. 已修正：顶层曾把 `redirect_apply` 接到 EX/MEM1/MEM2 kill，误杀 EX redirect 指令本身
   和更老条目。现已按第 5 节拆分 age-qualified kill 域；core smoke 同时检查 JAL link 保留、
   年轻指令清除和老 store/load 保留，RV32UI `jal/jalr/fence_i/sb/sh/sw` 均覆盖通过。
3. 已修正：MEM1 输出边界改为两槽 elastic queue，`in_ready` 只由本地容量产生，切断
   COMMIT/MEM2 的复杂 ready 向 EX/DECODE 传播。第二槽有效时 DECODE 停止新发射，避免隐藏
   producer；定向测试覆盖满载反压、head/tail 提升、稳态每拍替换和 kill 清空。新增 queue 不改变
   八个命名 stage，也不增加正常稳态延迟，只在满载恢复时引入一个明确 bubble。
4. 已修正：IF2 满载判断曾用 3 位计算 `6 + 2`，溢出后错误接受并覆盖队首。现使用 4 位
   occupancy；frontend 定向测试覆盖六半字满载、持续反压、同沿 consume/append 及顺序保持，
   RV32M 长除法造成的前端停顿也已通过 8/8 标准测试。
5. 已修正：阻塞式 D$ miss 期间，`MEM2` 为避免提前向 `COMMIT` 传输而压低 `out_valid`，
   但这也曾让 DECODE 的 RAW 网络看不见仍驻留的 load producer。现将“hazard residency”和
   “COMMIT transfer valid”定义为两个独立信号：前者从 packet 驻留起持续有效，结果未 ready
   时阻塞最近匹配 consumer；后者只在 cache 响应寄存后有效。缓存整核 smoke 固化连续
   `load -> ALU consumer`，缓存架构回归覆盖 LB/LBU/LH/LHU/LW、SB/SH/SW 及 RV32C 长等待窗口。

后续 RTL 变更必须在本节记录“契约项、覆盖测试、时序影响”，不能只记录某个 ISA 用例由 FAIL
变为 PASS。
