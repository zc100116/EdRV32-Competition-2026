# EdRV32 八级 CPU 架构与源码阅读教程

> 适用代码：当前工作区 `rtl/` 下的 2026-09-01 重构版。
>
> 读者假设：熟悉经典五级流水线 `IF → ID → EX → MEM → WB`，但尚不熟悉
> Cache、MMIO、精确异常、分支预测、流水线反压和长延迟执行单元。
>
> 本文先解释“CPU 为什么需要这些结构”，再映射到具体模块和信号。它描述的是
> **当前 RTL 的实际行为**；第 18 节单独列出当前实现与冻结目标仍不一致的地方。

## 1. 先建立整机图景

这颗 CPU 可以先记成一句话：

> EdRV32 是一颗单发射、顺序执行、顺序提交的 RV32IMC 处理器；它把经典五级流水线
> 拆成八级，用局部缓冲和 `valid/ready` 控制不定长取指、同步 Cache RAM、Cache miss、
> MMIO、异常、分支恢复和乘除法。

它支持：

- RV32I 整数基本指令；
- RV32M 乘除法；
- RV32C/Zca 压缩指令；
- Zicsr、Zifencei、Zicntr；
- Machine mode、同步异常、机器软件/定时器/外部中断；
- 4 KiB 两路组相联 I$ 和 4 KiB 两路组相联 D$；
- 可选 ITCM/DTCM；
- 阻塞式 Cache 和单槽解耦 MDU。

它不包含 F/D 浮点、双发射、乱序执行、硬件 Cache coherence 或非阻塞 Cache。

```text
取指流
  PC
   │
   ▼
 IF1 ─R1─> IF2 ─R2─> ALIGN ─R3─> DECODE ─R4─> EX ─R5─> MEM1 ─R6─> MEM2 ─R7─> COMMIT
  │          │                    │           │          │          │             │
  │          │                    │           │          │          └─ D$ 查询     ├─ GPR/CSR 写
  │          │                    │           │          └─ PMA 分类              ├─ store/MMIO
  │          │                    │           ├─ ALU/分支/地址/MDU 分派            ├─ trap/interrupt
  │          │                    ├─ 译码/读 GPR/旁路/冒险                         └─ retire
  │          └─ I$ 响应、半字 FIFO
  └─ PC/epoch、I$ 请求、预测查询

支线：
  EX ──控制流实际结果──> redirect controller ──新 PC/epoch──> IF1
  EX ──乘除请求────────> MDU + 单槽 scoreboard ──结果──────> COMMIT 写回口
```

`R1` 到 `R7` 不是另外七个流水级，而是八个阶段之间的七个明确寄存边界，分别由
`rtl/cpu/pipeline/edrv32_pipe_<source>_to_<destination>.v` 所有。

完整的模块例化关系见
[`../design/edrv32-module-instantiation-tree.zh.md`](../design/edrv32-module-instantiation-tree.zh.md)。

## 2. 从经典五级流水线过渡到当前八级

| 经典五级 | 当前阶段 | 为什么拆开 |
|---|---|---|
| IF | IF1 | 只管理 PC/epoch，发起按 4 字节取指块的请求 |
| IF | IF2 | 等待 I$ 同步响应，并把返回块整理成半字流 |
| IF/ID 之间 | ALIGN | 判断 16/32 位长度、跨字拼接、RVC 解压 |
| ID | DECODE | 译码、立即数、组合读 GPR、旁路和发射检查 |
| EX | EX | ALU、分支解析、有效地址、对齐检查、MDU 分派 |
| MEM 前半 | MEM1 | PMA：判断地址区域、权限和 Cache 属性 |
| MEM 后半 | MEM2 | 同步 D$ tag/data 查询、miss/refill 等待、load 数据形成 |
| WB | COMMIT | 最老指令唯一提交点：GPR/CSR、store、MMIO、trap、retire |

拆成八级的主要原因不是“八级一定比五级先进”，而是当前 FPGA 目标需要明确切断几类长路径：

1. 同步 I$/D$ RAM 不能假装成教科书中的组合存储器；
2. RV32C 使 PC 可以加 2 或加 4，一条指令还可能跨越两个 32 位取指块；
3. 地址生成、区域权限判断、Cache tag 比较和数据选择不能全塞在一个 MEM 周期；
4. 分支、异常、MMIO 和 store 需要一个统一的“最终是否允许生效”的位置；
5. 100 MHz 的周期是 10 ns，200 MHz 的周期只有 5 ns，必须为布线和高扇出控制留余量。

因此，八级首先是**时序边界和职责边界**，不是为了提高单条指令延迟。流水越深，分支误预测
代价和控制复杂度通常越大；它只有在能换来更高频率时才值得。

## 3. 理解整颗 CPU 的钥匙：三类状态

阅读任何一个信号前，先问它属于哪一类状态。

### 3.1 体系结构状态

软件能够观察、异常处理必须精确保留的状态：

- 32 个整数寄存器；
- CSR，例如 `mstatus`、`mepc`、`mcause`；
- 已提交的内存写；
- 已退休指令的计数和顺序。

这些状态原则上只能由 `COMMIT` 允许改变。假如一条年轻指令后来被发现走错路径，它绝不能已经
修改了这些状态。

### 3.2 微体系结构状态

软件通常看不到、可以被丢弃或重建的状态：

- pipeline register 中的 uop；
- I$/D$ 的 tag、data、LRU；
- IF2 半字 FIFO；
- 分支预测器的 BTB/BHT/RAS；
- Cache refill 临时行；
- redirect slot 和 MDU 内部迭代寄存器。

例如错误路径上的 load 可以提前把一条普通内存 Cache line 读入 D$，因为这只改变 Cache
内容，通常不改变程序语义；但错误路径不能提前读取“读一次就清状态”的 UART 寄存器。

### 3.3 外部副作用

一旦发生就不能靠清空流水线撤回的动作：

- store 改写 D$ 或外部存储器；
- MMIO 读写触发外设行为；
- CSR 写；
- trap 进入和 `mret`；
- 对外宣告 `retire`。

当前设计把这些动作集中到 `COMMIT`，这就是后面所有控制逻辑的共同出发点。

## 4. 指令不是只带着 32 位编码前进

经典图中常画一个 `IR` 寄存器，但真实流水线需要让一条指令携带一个“档案袋”。本文称它为
uop packet。它大致包含：

```text
身份：PC、规范化 32-bit 指令、是否压缩、epoch
预测：预测 taken、预测 target
寄存器：rd、是否写 rd、两个已解析操作数
执行：op_class、ALU/branch/MDU/CSR 子操作、立即数
访存：有效地址、size、signed/unsigned、store data、cacheable/TCM/MMIO
系统：fence、fence.i、mret、wfi
异常：exception_valid、cause、tval
长延迟：mdu_token
结果：result、result_ready
```

最重要的观念是：异常不是一发现就立即跳转。前级只在档案袋上贴一张
`exception_valid/cause/tval` 标签，同时关闭该指令的普通写回意图；档案袋继续按年龄到达
`COMMIT`，在那里才精确进入 trap。

## 5. 流水线如何“走、停、清”

### 5.1 `valid/ready` 表示什么

相邻阶段之间不是默认每拍强制移动，而是一次握手：

```text
上游 valid = 我手里有一条有效记录
下游 ready = 我这拍能接收这条记录
fire        = valid && ready，时钟沿发生所有权转移
```

在 stage 文件中常看到两侧接口：

- `valid_i/ready_o`：stage 正在观察上一个 pipeline register；
- `candidate_valid_o/candidate_ready_i`：stage 产生候选结果，交给下一个 pipeline register。

`candidate_valid_o` 不能因为下游暂时不 ready 就随意消失；原输入记录会被上游边界保持。对一个
普通单项 pipeline register，核心容量规则近似为：

```verilog
ready_o = !kill_i && (!valid_r || ready_i);
```

含义是：寄存器为空，或者旧记录本拍会被下游取走，才能接收新记录。

### 5.2 `capture`、`transfer` 和 `hold`

源码中常见：

- `capture_w = valid_i && ready_o`：输入被这个边界接收；
- `transfer_w = valid_r && ready_i`：已有记录被下游接收；
- 两者都为 1：旧记录离开、新记录同拍补入，维持满吞吐；
- `valid_r && !ready_i`：保持，payload 必须稳定；
- `kill_i`：当前记录变无效，payload 可以不清零，因为 `valid=0` 时不可观察。

这也解释了为什么代码把 valid/occupancy 和 payload 分开写 `always` 块：二者的复位、清除和写使能
语义不同。

### 5.3 反压不是“全流水线一根 stall 线”

当 COMMIT 等待 MMIO 响应时，首先是 `MEM2→COMMIT` 满；接着 MEM2 无处交付；再接着两项的
`MEM1→MEM2` FIFO 被填满；最后 DECODE 因容量耗尽而停。停顿是逐段传播的，不应在一个周期内从
COMMIT 透明穿过七级回到 IF2。

R6 边界 `edrv32_pipe_mem1_to_mem2` 特别做成两项 FIFO。即使下游本拍取走 head，满队列也故意不在
同拍向 MEM1 暴露 ready，目的是切断长的反向组合路径。它牺牲极少的瞬时吞吐，换取可综合时序。

## 6. 一条普通 `ADD` 怎样通过 CPU

以 `add x5, x6, x7` 为例，忽略 Cache miss 和所有停顿：

1. **IF1** 用当前 `fetch_addr_r` 发 4 字节取指块请求，并给请求附上 epoch 和两个半字位置的预测信息。
2. **IF2** 把 I$ 返回数据与 R1 中最老请求 tag 配对，拆成两个 16 位半字加入 FIFO。
3. **ALIGN** 看到低两位是 `11`，知道这是 32 位指令，消费两个半字并输出规范指令。
4. **DECODE** 认出 OP/ADD，组合读 `x6/x7`，检查最近的旧指令是否正在写它们。
5. **EX** 的结构化加法器产生和，设置 `result_ready=1`。
6. **MEM1** 对非访存指令只传递 packet。
7. **MEM2** 对非访存指令不发 D$ lookup，也只传递 packet。
8. **COMMIT** 若没有更高优先级异常/中断，写 `x5` 并产生一次 `retire`。

流水线装满后，多条互不相关的简单整数指令可以分别占据不同阶段，目标吞吐是每拍一条；“一条
指令经过八级”不等于“每八拍才能执行一条”。

## 7. 前端：为什么取指比教科书复杂

### 7.1 IF1 取的是块，不是已经对齐好的指令

IF1 的地址始终 4 字节对齐，每次候选地址固定 `+4`。原因是 I$ 和外部存储按 32 位块返回，而
RV32C 指令可能从地址 `...2` 开始。IF1 同时查询块内 `PC` 和 `PC+2` 两个半字位置的预测器。

R1 是一个两项 accepted-request tag 队列，保存地址、epoch 和两组预测 metadata。它保存的是
“已经被 I$ 接收、将来必有响应”的请求身份，而不是指令本身。即使发生 redirect，也不能凭空
删除已接受请求；否则迟到的响应会与错误的地址配对。

### 7.2 epoch 是取指流的版本号

每次预测跳转或实际 redirect，IF1 都增加两位 epoch。旧请求仍可能返回，但 IF2 比较
`block_epoch_i` 与 `active_epoch_r`，发现版本不符便接收后丢弃。

这类似给每一批快递贴“第 3 版路线”标签。路线改成第 0 版以后，第 3 版的迟到包裹必须签收后
作废，不能混入新队列。两位 epoch 会回绕，但在当前阻塞前端和最多两项已接受 tag 的边界下，
旧事务生命周期受到限制。

### 7.3 IF2 是六半字流缓冲

IF2 最多保存六个 16 位半字。这样做有三个作用：

- 吸收 I$ 响应与 ALIGN 消费速度的短暂不匹配；
- 自然处理 16 位和 32 位指令混排；
- 让一条跨 32 位块的指令等待下一个半字，而不丢掉第一个半字。

`consume_pc_r` 表示 FIFO 头半字对应的真实指令 PC，`expected_block_addr_r` 表示下一块应是什么
地址。旧 epoch 或地址不连续的块会被消费并丢弃。

### 7.4 ALIGN 做“指令成形”

ALIGN 根据第一半字的 `[1:0]` 判断长度：

- 不等于 `2'b11`：16 位压缩指令，消费一个半字，由 `edrv32_rvc_decompress` 解压成等价的
  32 位基础指令；
- 等于 `2'b11`：32 位指令，必须等第二半字有效，消费两个半字并拼接；
- 压缩编码保留/非法：保留原始 16 位编码并贴上非法标签，交给 DECODE 形成异常。

从 ALIGN 往后，执行数据通路基本只看规范化 32 位指令；`is_compressed` 仍随包前进，用于计算
fall-through PC 是 `PC+2` 还是 `PC+4`。

## 8. DECODE：译码、读寄存器和发射许可

DECODE 由四个主要子模块组成：

| 模块 | 问题 |
|---|---|
| `edrv32_decoder` | 这是什么指令，要使用哪些资源？ |
| `edrv32_immgen` | I/S/B/U/J/Z 立即数是多少？ |
| `edrv32_regfile` | 当前 GPR 中的 `rs1/rs2` 值是多少？ |
| `edrv32_operand_resolve` | GPR 值是否过时，应从哪个更年轻的 producer 旁路？ |

GPR 是 32×32 位、两个组合读口、一个 COMMIT 同步写口。`x0` 永远为零；若 COMMIT 本拍写的
寄存器正好被 DECODE 读取，显式 write-first 旁路让 DECODE 看到新值。

译码器采用“默认非法且无副作用”策略：只有某个完整 case 明确匹配后才清除 `illegal` 并打开
`rd_write`、memory 或 MDU 意图。这样漏写一个编码时更可能变成可控的非法指令异常，而不是误写
寄存器或内存。

DECODE 只有同时满足两类条件才允许进入 EX：

- **依赖条件**：所有源操作数已经可用，没有普通 RAW、DECODE→EX resident RAW、MDU RAW/WAW；
- **结构条件**：R6 FIFO 未满，若为 MDU 指令则 MDU slot 可分配。

## 9. 普通 RAW 冒险与旁路

假设：

```asm
add x5, x1, x2
sub x6, x5, x3
```

第二条在 DECODE 读 `x5` 时，第一条还没写回。CPU 从最近的旧 producer 向最远处依次找：

```text
EX→MEM1 边界  >  MEM1→MEM2 FIFO head  >  MEM2 本地 owner  >  COMMIT
     最新                 较旧                 更旧              最旧
```

源码现在直接使用正式阶段名，并在流水线边界记录上加 `packet`：

| `edrv32_core.v` 信号前缀 | 实际含义 |
|---|---|
| `ex_*` | EX→MEM1 边界中已执行的记录 |
| `mem1_packet_*` | MEM1→MEM2 两项 FIFO 的 head |
| `mem2_hazard_*` | MEM2 本地 owner |
| `mem2_packet_*` | MEM2→COMMIT 边界记录 |
| `commit_*` | COMMIT 当前最老记录 |

年龄优先级不能颠倒。例如两条旧指令都写 `x5`，最近的一条结果尚未 ready，较老的一条已经
ready，DECODE 仍必须等待最近者；若错误地取较老值，程序会得到过期数据。

ALU/JAL/JALR 在 EX 已有结果，可以旁路。load 的结果要等 MEM2 Cache 响应；CSR 当前要等
COMMIT 组合读；MDU 走独立 scoreboard，不进入这组普通旁路。

另有一个容易遗漏的 `resident_*` 检查：当 DECODE→EX 边界原有指令被 EX 取走、DECODE 想同拍
补入下一条时，原有 producer 尚未出现在注册的 EX bypass 记录中。如果新指令依赖它，必须先停
一拍。这不是重复检查，而是在两个注册观察点之间补上年龄空隙。

## 10. EX：真正“算”的阶段

EX 同时处理四类工作，但每类都有明确子逻辑：

1. `edrv32_alu`：加减、逻辑、移位、比较；
2. `edrv32_branch_unit`：比较分支条件；
3. 地址/目标计算：load/store 有效地址、`PC+imm`、JALR 目标；
4. MDU 请求：把乘除法操作数和目的寄存器交给解耦 MDU。

正式 ALU 是结构化传输级实现：加减使用 `edrv32_adder32`，移位使用
`edrv32_shifter32`，比较使用 `edrv32_compare32`。`edrv32_alu_behavioral` 只作为等价验证
对照组。固定的 `PC+2/PC+4` 仍直接表达为常量加法，因为它不是需要复用的通用运算单元。

### 10.1 load/store 的有效地址

对 `lw x5, 12(x6)`，DECODE 已准备 `lhs=x6`、`rhs=12`，ALU 在 EX 得到有效地址。
EX 同时检查自然对齐：

- byte 永远不会地址不对齐；
- half 要求 `addr[0]=0`；
- word 要求 `addr[1:0]=0`。

若不满足，EX 把指令改成 `LOAD_MISALIGNED` 或 `STORE_MISALIGNED` 异常 packet，并取消
`rd_write`。它不会向 D$ 或外部总线发请求。

### 10.2 分支的实际结果

EX 计算：

```text
fallthrough     = PC + (compressed ? 2 : 4)
actual_next     = taken ? target : fallthrough
predicted_next  = predicted_taken ? predicted_target : fallthrough
mispredict      = actual_next != predicted_next
```

预测器只是猜测，EX 是唯一裁判。即使预测“方向”相同但 target 错了，也算误预测。

redirect 和 MDU dispatch 都必须与 EX 接收这条指令原子发生。如果 redirect slot 或 MDU slot
暂时不能接收，EX 就不能一边把 packet 送到 MEM1、一边丢掉对应事件。

## 11. 分支预测、redirect 和 kill

### 11.1 预测器的三部分

| 结构 | 当前规模 | 回答的问题 |
|---|---:|---|
| BTB | 32 项，半字粒度 | 这个 PC 是否见过控制流？目标地址是什么？ |
| BHT | 256 项，两位饱和计数器 | 条件分支更可能 taken 还是 not-taken？ |
| RAS | 8 项 | return 更可能回到哪个调用返回地址？ |

IF1 对一个 32 位取指块的两个半字位置并行查询。IF2 的最老 window 被下游接收时，如果该位置
预测 taken，就向 IF1 发一次 prediction redirect，清掉 IF2 中更年轻的顺序半字并从目标取指。
包含分支本身的 window 已经进入后续边界，不会被这次早期预测清除。

EX 最终解析控制流并训练预测器。异常或被 kill 的控制指令不得训练。

### 11.2 为什么 redirect controller 是一个寄存槽

可能同时请求改 PC 的事件有：

```text
COMMIT exception
COMMIT interrupt
COMMIT mret
COMMIT fence/fence.i
EX branch/jump correction
```

固定优先级是上面从高到低；COMMIT 事件来自更老指令，所以必须压过 EX 的年轻分支。控制器先把
target、reason 和新 epoch 寄存，下一拍再让 IF1 应用。输出槽不做透明同拍 refill，目的是切断
`IF1 ready → redirect → EX ready` 的组合链。

### 11.3 “发现走错”和“开始新取指”是两个时刻

以 EX 误预测为例：

1. **事件被 controller 接受的时钟沿**：清除 DECODE→EX 中比该分支年轻的指令；分支自身正常
   进入 EX→MEM1；
2. **已寄存 redirect 被 IF1 应用的时钟沿**：IF1 更新 PC/epoch，清除 IF2→ALIGN 和
   ALIGN→DECODE 等前端残留；
3. **以后到达的旧 epoch I$ 响应**：仍完成协议握手，但被 IF2 丢弃。

COMMIT 异常/中断/mret/fence 的第一步更强：它会清除 EX、MEM1、MEM2 等所有年轻后端状态。
第二步仍只负责让前端采用新 PC。这种按年龄分层的 kill 能避免杀掉发起 redirect 的指令自身，
也避免把高扇出 kill 塞进所有 payload 数据路径。

## 12. 先学会区分“内存、Cache 和外设”

教科书常把 MEM 画成一个方框，但地址背后可能是完全不同的东西。

| 区域 | 地址范围 | 允许访问 | CPU 处理方式 |
|---|---|---|---|
| Boot ROM | `0x0000_0000` 起 16 KiB | 取指、只读 | uncached |
| ITCM | `0x0100_0000` 起 64 KiB | TCM 开启时仅取指 | CPU 本地、uncached |
| DTCM | `0x0200_0000` 起 64 KiB | TCM 开启时数据读写 | CPU 本地、uncached |
| SRAM | `0x1000_0000` 起 256 KiB | 取指、数据读写 | cacheable |
| CLINT | `0x2000_0000` 起 64 KiB | 数据读写 | device、uncached |
| PLIC | `0x3000_0000` 起 4 MiB | 数据读写 | device、uncached |
| APB 外设 | `0x4000_0000` 起 256 KiB | 数据读写 | device、uncached |
| DDR canonical | `0x8000_0000` 起，最多 1 GiB | 取指、数据读写 | cacheable |
| DDR alias | `0xC000_0000` 起 | 仅数据读写 | uncached |
| 空洞 | 其他未映射区域 | 不允许 | access fault，不发总线请求 |

### 12.1 PMA 是什么

PMA（Physical Memory Attributes）回答的不是“Cache 命中了吗”，而是更早的问题：

- 地址有没有映射；
- 这类访问有无权限；
- 可否缓存；
- 是否 TCM；
- 是否 device/MMIO。

MEM1 的 `edrv32_pma_classifier` 用浅的地址前缀比较完成分类。若 store 写 ROM、load 读未映射
空洞、数据访问 ITCM，MEM1 直接贴 access fault 标签，后面不会发任何总线请求。

### 12.2 为什么普通内存 load 能提前，MMIO load 不能

普通 RAM/DDR 的读取通常没有程序可见副作用。错误路径 load 即便提前读取，之后丢掉结果即可；
多出来的 Cache line 只是微体系结构变化。

MMIO 读取可能有副作用。例如读取 UART RX 数据寄存器可能弹出一个字节，读取状态寄存器可能
清某个位。错误路径若提前读，flush 无法把外设状态恢复。因此：

- cacheable load 在 MEM2 查询 D$；
- uncached/MMIO/DTCM load 留到成为最老指令的 COMMIT 才发请求；
- 所有 store 都留到 COMMIT 才真正改写数据。

## 13. Cache 的最小必要知识

### 13.1 当前 Cache 几何

I$ 和 D$ 都是：

- 容量 4 KiB；
- 16 字节一行，即一行四个 32 位 word；
- 两路组相联；
- 128 组、每组 2 路，总共 256 行；
- 精确一位两路 LRU，优先使用 invalid way；
- tag/data 同步读；
- blocking：控制器同时只有一个 lookup/miss owner。

32 位地址拆分为：

```text
31                    11 10             4 3          0
+-----------------------+----------------+------------+
|       tag: 21 bit     | index: 7 bit   | offset: 4  |
+-----------------------+----------------+------------+
```

同一个 index 有两个 way。只有 index 相同且某一路 valid、tag 相等才命中。因此它不是 256 行
直映 Cache。

### 13.2 为什么数组必须同步读

`edrv32_cache_array` 的请求地址在时钟沿进入 RAM，tag/data 下一拍出现。FPGA 综合才能把较大的
存储推断或映射为 DRM，而不是大量 LUT。portable RTL 与 Pango IP 分支都保持这个同步读契约。

这也是 MEM1 和 MEM2 分开的根本原因之一：MEM1 准备地址和属性，MEM2/Cache 接收同步数组
结果并判断 hit。

### 13.3 hit、clean miss 和 dirty miss

对一个 cacheable load：

```text
lookup
  ├─ hit ───────────────────────────────> 返回所选 word
  └─ miss
      ├─ victim 无效或干净 ─────────────> refill 4 个 word ─> 安装新行 ─> 返回
      └─ victim 有效且 dirty ─> 写回 4 word ─> refill 4 word ─> 安装 ─> 返回
```

D$ 是 write-back + write-allocate：store 命中后只修改 D$ 并置 dirty，稍后被替换、FENCE clean 或
软件维护时才写回下层；store miss 先把整行读入，再在 COMMIT 合并 store 字节并置 dirty。

I$ 不需要 dirty/writeback，只在 miss 时 refill；对可执行但不可缓存的 Boot ROM 等地址走
bypass 请求，不安装 Cache line。ITCM 在 `edrv32_cached_core` 中直接路由到本地指令存储端口。

### 13.4 blocking 不等于整颗 CPU 每次都立即全停

blocking 表示每个 Cache 控制器同一时刻不接第二个独立 miss。前端仍有请求 tag/半字缓冲，后端
仍有 pipeline/FIFO，MDU 也可继续计算；只有这些局部容量逐渐耗尽后，反压才传播。它没有
hit-under-miss、多 miss 状态寄存器或 store buffer，因此结构比高性能乱序核简单得多。

## 14. 四种访存流程必须分开理解

### 14.1 cacheable load hit

以 DDR/SRAM 中的 `lw x5, 0(x6)` 为例：

1. EX 算有效地址并检查对齐；
2. MEM1 判定 mapped、readable、cacheable；
3. MEM2 原子接收 packet 并发 D$ lookup；
4. D$ 同步读两路 tag/data，命中后返回 32 位 word；
5. MEM2 根据 byte/half/word 和 signed/unsigned 做抽取、符号或零扩展，设置 `result_ready=1`；
6. packet 进入 COMMIT，COMMIT 不再发内存请求，只写 GPR 并 retire。

若下一条立即使用 `x5`，它在 DECODE 看到最近 load producer 但 `result_ready=0` 时停顿；MEM2
响应完成后从 MEM2/COMMIT 旁路值。这个过程就是 load-use hazard。

### 14.2 cacheable load miss

前 3 步相同。D$ miss 后由同一个 MEM2 owner 等待：必要时写回 dirty victim，再按 4 个 word
补完整行，原子安装成功的 refill line，返回目标 word。所谓 replay 在这里是 Cache FSM 内部让
同一 owner 继续完成，不是把指令重新送回 DECODE；因此不会重复分配、重复 retire。

如果更老的 COMMIT 事件 kill 了该 load：

- 尚未发出的 refill 可以取消；
- 已发出的总线事务必须完成协议；
- 返回数据可以丢弃，不得形成该指令的 GPR 写回；
- 已完成的普通 Cache fill 可以保留，因为它不是该错误路径的体系结构结果。

### 14.3 cacheable store

store 的流程特意分成“准备”和“生效”：

1. EX 算地址，保存 `rs2` 的 store data；
2. MEM1 做 PMA；
3. MEM2/D$ 做 lookup。命中时保存 set/way/address/line reservation；miss 时可写回旧 dirty line、
   refill 新行，然后建立 reservation；**此时尚未把当前 store 数据写入该行**；
4. store 到 COMMIT 成为最老、且没有异常/中断取代它时，COMMIT 发 cacheable store 请求；
5. D$ 检查请求与 reservation 相符，按 byte enable 合并数据、置 dirty，返回完成响应；
6. COMMIT 收到完成后 retire。

为什么允许 store miss 在 MEM2 提前 refill？因为 refill/替换只改变 Cache 状态；为什么不允许
提前合并 store 数据？因为那是程序可观察的内存写，错误路径无法撤销。

### 14.4 uncached/MMIO/DTCM load 或 store

MEM2 不查询 D$，只把 `result_ready=0` 的 load 或 store packet 交给 COMMIT。COMMIT 的三态
memory FSM 负责：

```text
MEM_IDLE --请求被接收且未同拍响应--> MEM_WAIT
MEM_IDLE/WAIT --响应被接收----------> MEM_DONE
MEM_DONE --当前指令完成提交----------> MEM_IDLE
```

请求期间地址、写数据、字节使能和读写方向都由当前最老 packet 保持。响应错误转换为精确的
load/store access fault。MMIO 只允许单次请求，避免重复弹 FIFO、重复清状态或重复启动外设。

## 15. COMMIT 到底做什么

COMMIT 不是“所有指令都在这里重新执行”，而是“检查最老指令已经准备好的结果，并决定这一拍
究竟允许哪个不可撤销事件发生”。

| 指令类型 | 前级已经做了什么 | COMMIT 真正做什么 |
|---|---|---|
| ALU | EX 已算出结果 | 写 GPR，retire |
| JAL/JALR | EX 已算 link 和目标、必要时 redirect | 写 link 寄存器，retire |
| branch | EX 已解析并恢复 | retire，不写 GPR |
| cacheable load | MEM2 已得到格式化结果 | 写 GPR，retire |
| cacheable store | MEM2 已建 reservation | 授权 D$ 改行，等响应，retire |
| uncached/MMIO load | 只有地址和控制 | 发读请求、等响应、格式化、写 GPR、retire |
| uncached/MMIO store | 只有地址和数据 | 发写请求、等响应、retire |
| CSR | DECODE 已给地址/操作数 | 当前 RTL 在此读、合法性检查、RMW、写 CSR/GPR |
| exception | 前级已带 cause/tval | 写 trap CSR、redirect 到 `mtvec`，不普通 retire |
| interrupt | CSR/pin 表示 pending | 在精确边界进入 trap |
| MRET | 已译码 | 恢复中断使能、redirect 到 `mepc` |
| WFI | 已译码 | 无可唤醒源时保持队首和 sleep |
| FENCE/FENCE.I | 已译码 | 当前 RTL 先 retire/flush，再由 cached top 发维护 |
| MDU token | EX 已分派运算 | 当前 RTL 授权 MDU，结果完成后经共享写口写 GPR |

COMMIT 每拍的优先思路是：

```text
当前 packet 已有同步异常？
  是：等待可接受 redirect，进入 exception
  否：此边界是否应取 interrupt？
      是：进入 interrupt
      否：完成 memory/CSR/MDU/WFI/fence 等义务后正常 retire
```

同步异常必须压过同边界中断，否则 `mepc/mcause/mtval` 会记录错误的事件。正在等待已接受的
不可撤销 memory transaction 时，中断也不能把 owner 抢走。

### 15.1 CSR 可以先这样理解

CSR 是 CPU 内部用地址编号访问的一组控制/状态寄存器，不在普通 GPR 的 `x0...x31` 空间中。
当前实现中的主要类别是：

| 类别 | CSR | 用途 |
|---|---|---|
| 机器状态 | `mstatus`、`misa` | 全局中断状态、报告 RV32IMC 能力 |
| 中断 | `mie`、`mip` | 各中断源 enable 和 pending |
| trap 向量 | `mtvec` | 异常/中断入口基址及 direct/vectored 模式 |
| trap 上下文 | `mepc`、`mcause`、`mtval` | 返回 PC、原因和附加值 |
| 软件暂存 | `mscratch` | trap handler 自由使用 |
| 基本计数 | `mcycle/minstret` 及高 32 位 | 周期数和成功退休数 |
| 用户只读视图 | `cycle/time/instret` 及高 32 位 | 读取基本计数和外部时间 |
| 性能计数 | `mhpmcounter3...16` | 固定映射的 Cache、分支、停顿等事件 |
| 实现身份 | `mvendorid/marchid/mimpid/mhartid` | 实现和 hart 标识 |

CSR 指令的 `rd` 得到修改前的旧值，同时按 WRITE/SET/CLEAR 计算新值；SET/CLEAR 的源为零时不产生
写意图。不存在的地址，或试图写只读地址，会在 COMMIT 转成非法指令异常。当前 CSR file 是小量
寄存状态的组合读、同步写，不是需要例化大块 RAM 的结构。

## 16. 异常、中断和精确 trap

### 16.1 异常和中断不是一回事

| 项目 | 同步异常 exception | 异步中断 interrupt |
|---|---|---|
| 来源 | 当前指令自身 | 外部事件，与当前指令无直接因果 |
| 例子 | 非法指令、地址不对齐、访问错误、ECALL | 软件、定时器、外部中断 |
| `mepc` | 出错指令 PC | 被打断边界的 PC；WFI 特例取 fall-through |
| `mtval` | 指令编码或错误地址等附加信息 | 0 |
| 同拍优先级 | 高 | 低 |

“精确”的含义是：进入 trap 的瞬间，出错/被打断指令之前的指令都已经生效，之后的指令都没有
留下体系结构副作用。于是软件看到的状态就像 CPU 在某两条指令之间整齐停下，而不是半条 store
已经写了、年轻 CSR 也改了一半。

### 16.2 异常可能在哪一级被发现

| 发现位置 | 场景 | `tval` |
|---|---|---|
| DECODE | 取指错误 | 当前 PC |
| DECODE | 非法 16/32 位编码 | 原始指令编码 |
| DECODE | EBREAK / ECALL | 0 |
| EX | load/store 地址不自然对齐 | 有效地址 |
| MEM1 | PMA 未映射或权限不允许 | 有效地址 |
| MEM2 | cacheable 访问的 refill/writeback 错误 | 有效地址 |
| COMMIT | CSR 地址非法/写只读 CSR | 当前指令编码 |
| COMMIT | uncached/MMIO/DTCM 响应错误 | 有效地址 |

发现后，`exception_valid/cause/tval` 随 packet 前进。一个已经异常的 packet 会关闭 GPR 写、MDU
dispatch 和 memory/cache 请求，但仍保留 PC/指令身份，直到 COMMIT。

### 16.3 trap 进入具体改变什么

COMMIT 接受 exception/interrupt redirect 的同一事件中，CSR file 原子执行：

- `mepc ← trap_epc`，最低位清零；
- `mcause ← cause`；
- `mtval ← tval`；
- `MPIE ← MIE`；
- `MIE ← 0`；
- PC redirect 到 `mtvec` 目标；
- kill 所有年轻指令。

`mtvec[1:0]=00` 是 direct，所有 trap 去 BASE；`01` 是 vectored，只有 interrupt 去
`BASE + 4*cause`，同步异常仍去 BASE。

`MRET` 做相反的中断使能栈恢复：`MIE ← MPIE`、`MPIE ← 1`，并跳到 `mepc`。

### 16.4 中断如何选择

`mip` 反映外部 pending pin，`mie` 对每个源做局部使能，`mstatus.MIE` 是全局开关。
当前优先级：机器外部 MEI > 机器软件 MSI > 机器定时器 MTI。

WFI 的规则稍有不同：只要 `mie & mip` 有任一局部使能源，就可以唤醒，即使全局 MIE=0；但只有
全局 MIE=1 时才立即进入中断。这避免软件在关闭全局中断但等待事件时永久睡死。

## 17. MDU：为什么它不在普通 ALU 结果链里

MDU 是 Multiply/Divide Unit。当前实现有一个公共 slot：

- MUL/MULH/MULHSU/MULHU：portable 路径为 Booth4 + Wallace，三段流水；MES50HP 可用三段
  Pango APM 实现；
- DIV/DIVU/REM/REMU：radix-2 非恢复迭代除法，通常进行 32 次迭代，必要时多一个余数修正状态；
- 任何时刻只允许一条 MDU 指令占 slot。

若让除法器阻塞 EX 三十多拍，所有无关指令都会停。当前设计改为解耦：EX 把操作数、操作类型、
`rd` 锁存到 MDU 后，主流水线可以继续跑无关整数指令。

### 17.1 为什么只需要一个小 scoreboard

MDU 的结果可能比主流水线晚，所以产生一种普通顺序流水线没有的悬空 producer。scoreboard 只记：

```text
valid + pending rd + authorized
```

它阻塞：

- 年轻指令读取 pending `rd`：MDU RAW；
- 年轻指令也要写 pending `rd`：MDU WAW；
- 第二条 MDU：结构冲突。

它不阻塞与该 `rd` 无关的普通整数指令。WAR 不需要处理，因为 MDU 的两个源操作数已在 EX
请求握手时锁存，年轻写者不会改变它们。

### 17.2 token、authorize 和 cancel

MDU 指令本身仍有一个轻量 `mdu_token` 沿主流水线前进：

1. EX 同拍分配 MDU slot 和 scoreboard，并把 token 写入 packet；
2. 运算在支线进行，主 packet 继续向 COMMIT；
3. 更老 trap 若先发生，未授权 slot 被 `cancel`，错误路径结果不得写 GPR；
4. token 到达 COMMIT，说明该 MDU 已越过所有更老指令，COMMIT 发 `authorize`；
5. 结果必须同时满足 `complete && authorized` 才对 GPR 写回口可见；
6. 实际写回 fire 后 scoreboard 才清除。

结果先算完就等授权，授权先到就等结果。COMMIT 与 MDU 结果共享单个 GPR 写端口；普通 retire 写
优先时，MDU 结果保持到下一拍。

## 18. FENCE、FENCE.I 和 Cache maintenance

### 18.1 概念上它们要解决什么

`FENCE` 约束数据访问先后关系；在本项目的 write-back D$ 中，还需要把旧 dirty data clean 到
下层，确保随后通过 uncached alias、DMA 或外设观察时一致。

`FENCE.I` 还要解决“软件刚写了指令字节，但 I$ 里仍是旧指令”的问题，因此除了数据侧清理，
还要失效 I$，清除前端旧取指流，再从 fence 后一条指令重新取。

本核另外有 CPU-local Cache-maintenance MMIO 窗口，允许软件发 D$ invalidate、clean、
clean+invalidate 和 I$ invalidate，并可指定全 Cache 或地址范围。它是软件管理 DMA 与非一致
Cache 所必需的接口，不是普通外设请求穿过 SoC APB 后再返回。

### 18.2 当前 RTL 实际顺序

当前代码中，两种 fence 到 COMMIT 后都会：

1. 产生 redirect 到 fall-through PC，并 kill 年轻流水线；
2. 产生 `retire`，`edrv32_core` 输出 `fence_retire_o` 或 `fencei_retire_o`；
3. `edrv32_cached_core` 以 retirement pulse 发起全 D$ clean；
4. FENCE.I 同拍失效 I$；
5. `fence_maintenance_active_r` 在 D$ clean 期间关闭新的前端存储访问；
6. D$ 不 busy 后重新允许取指。

因此，年轻 CPU 工作被 flush，并在维护完成前不能重新取指；但 fence 的 `retire` 脉冲本身发生在
clean 完成之前。第 19 节会解释为什么这仍是当前待整改项。

## 19. 必须区分：当前 RTL 与冻结目标仍有差异

下面不是理论假设，而是当前源码可以直接看到的状态。阅读和后续重构时不要把“设计文档要求”
误当成“代码已经实现”。

| 项目 | 当前 RTL | 冻结目标 | 影响 |
|---|---|---|---|
| CSR | `edrv32_csr_file` 在 COMMIT 组合读、合法性检查和 RMW | MEM2 预读并注册，COMMIT 只门控写 | 当前形成 COMMIT 大控制锥形，是已知时序问题 |
| MDU | token 可以先 `retire`/authorize，结果稍后独立写 GPR；年轻提交和 trap 会等已授权结果 | MDU 结果、GPR 写回和该指令 retire 同拍 | 当前 trace 的 retire 点早于寄存器真正更新 |
| FENCE | 先 retire，再由 cached top 后台 clean；前端在 clean 期间关闭 | clean/错误完成后才 retire，FENCE.I 再原子失效/重取 | 当前退休语义和维护错误精确性未达到冻结契约 |
| 两路参数 | Cache 暴露 `WAYS` 参数，但静态检查只允许 2 | 直接固定两路，避免伪可配置 | 功能不变，主要是接口和维护性问题 |
| 时序 | 最新归档 r5 的 100 MHz post-route WNS `-4.773 ns`，估算约 67.69 MHz | 100 MHz 必须闭合，200 MHz 独立冲刺 | 八级结构已存在，但关键组合控制仍穿透多个边界 |

当前最差时序路径从 DECODE→EX 的分支操作数，经 EX 比较/redirect/ready，穿到 IF2 payload 写控制；
另一大组从 COMMIT 的 CSR 合法性译码扩散到 D$、前端、MDU 和计数器。这说明“文件已经分级”不
等于“综合后的组合路径已被真正切断”。详细证据见
[`../reports/timing/mes50hp-cpu-100mhz-r5.zh.md`](../reports/timing/mes50hp-cpu-100mhz-r5.zh.md)。

## 20. 控制器面对各种现象时做什么

| 现象 | 谁最先发现/拥有 | 立即措施 | 恢复/完成条件 |
|---|---|---|---|
| ALU RAW，结果已有 | DECODE operand resolve | 从最近 producer 旁路 | 当拍可发射 |
| load-use，结果未到 | DECODE | 保持 ALIGN→DECODE，停止发射 | MEM2/COMMIT `result_ready` |
| MDU RAW/WAW | MDU scoreboard | 停相关指令，不停无关整数指令 | MDU 实际写回 |
| 第二条 MDU | DECODE/MDU slot | 结构停顿 | slot 清空 |
| R6 FIFO 满 | DECODE/MEM1 局部容量 | 停止继续发射 | MEM2 消费 head，随后释放容量 |
| I$ hit | I$ | 返回请求块 | IF2 能接收 |
| I$ miss | I$ miss owner | 保持请求，refill 一行 | 返回或错误 |
| D$ load hit | MEM2/D$ | 返回 word，形成旁路 | MEM2→COMMIT 可接收 |
| D$ miss | MEM2/D$ miss owner | 必要时 writeback，再 refill | 唯一响应产生 |
| store | MEM2 + COMMIT | MEM2 只 reservation；COMMIT 才写 | D$ 或 fabric 响应 |
| MMIO | COMMIT memory FSM | 单次发请求并保持 owner | 响应或 access fault |
| 分支预测正确 | EX | 训练 predictor，不 redirect | 正常前进 |
| 分支误预测 | EX + redirect ctrl | 杀年轻 DECODE，寄存新 PC 事件 | IF1 应用 redirect，新 epoch 取指 |
| 旧 I$ 响应迟到 | IF2 epoch 检查 | 接收并丢弃 | 不进入半字 FIFO |
| 同步异常 | 发现级 + COMMIT | 只贴标签；COMMIT 时 trap | redirect 被接受 |
| 中断 pending | COMMIT/CSR | 等精确边界；同步异常优先 | trap redirect 被接受 |
| WFI 无事件 | COMMIT | 保持队首，输出 sleep | `mie&mip` 有源 |
| 更老 trap 遇年轻 MDU | COMMIT/MDU | 未授权 MDU cancel | slot 清空 |
| FENCE/FENCE.I | COMMIT + cached top | flush、clean；FENCE.I 失效 I$ | 当前实现等 D$ 不 busy 后重取 |

## 21. 九个场景的“脑内仿真”

### 21.1 连续独立 ADD

各指令逐级推进。EX 每拍出一个 ready 结果，后续 MEM1/MEM2 只是延迟线，COMMIT 每拍写一次
GPR。流水线填满后理想 CPI 接近 1。

### 21.2 `ADD x5` 后立刻使用 `x5`

消费者不能相信 regfile 中旧值。DECODE 先因 resident 空隙等待，然后从最近 EX registered
producer 旁路新值。无需等到 COMMIT。

### 21.3 `LW x5` 后立刻使用 `x5`，D$ hit

消费者在 DECODE 命中 load producer，但看到 `ready=0`，保持不动；load 经过同步 D$ lookup，
MEM2 登记结果后 `ready=1`，消费者取得旁路。停顿来自数据真正出现得更晚，不是旁路缺失。

### 21.4 D$ dirty miss

MEM2 owner 不变；D$ 先逐 word 写回 victim，再逐 word refill 新行。R6 两项 FIFO 可短暂容纳更年轻
packet，满后反压。COMMIT 仍按年龄，年轻 packet 不能越过这次访问产生副作用。

### 21.5 分支预测 taken，但实际 not-taken

IF2 曾把取指导向预测 target；EX 发现 `actual_next=fallthrough`，提交 correction event。已经进入
DECODE 的错误目标指令被 kill，旧 epoch 返回被丢弃，IF1 从 fall-through 重新取指。分支本身仍
正常 retire。

### 21.6 错误路径上有 store

store 最多在 MEM2 做 tag lookup/refill/reservation，没有写入 store data。更老分支或 trap kill
使 reservation 取消；因为它没到 COMMIT，内存没有被错误修改。

### 21.7 错误路径上有 UART load

PMA 标记为 device/uncached，MEM2 不发读；到不了 COMMIT 就被 kill，因此 UART FIFO 不会被错误
弹出。这正是 MMIO load 延迟到 COMMIT 的价值。

### 21.8 当前指令非法且外部中断同拍 pending

非法指令的同步异常优先。COMMIT 写 `mcause=illegal instruction`，`mepc` 指向非法指令，`mtval`
保存其原始编码。中断保持 pending，异常处理软件重新允许后仍可被处理。

### 21.9 长除法旁边有无关 ADD

DIV 在 MDU 迭代，若 ADD 不读写 DIV 的 pending `rd`，可以继续通过主流水线。ADD 可能到达
COMMIT，但当前实现对已授权未写回 MDU 会保持精确性等待；与 pending `rd` 相关的指令更早就在
DECODE 被 scoreboard 停下。

## 22. 信号命名快速翻译表

| 形式 | 含义 | 阅读方法 |
|---|---|---|
| `*_i` / `*_o` | 模块输入/输出方向 | 只表示相对当前模块，不表示全局数据方向 |
| `*_w` | 组合线网 | 同拍逻辑，可能进入时序路径 |
| `*_r` | 寄存状态 | 跨时钟保存，是所有权或时序切点 |
| `valid` | payload 是否有意义 | `valid=0` 时不要解释 payload 数值 |
| `ready` | 接收方本拍能否接收 | 不等于“结果已经计算好” |
| `result_ready` | producer 的结果值能否被依赖者使用 | 与握手 `ready` 是两个概念 |
| `candidate_*` | stage 组合形成、等待下一边界接收的记录 | 还不是下一级 resident |
| `capture` | 输入被当前 owner 接收 | 常为 `valid_i && ready_o` |
| `transfer` / `fire` | 一次协议所有权转移或副作用被接受 | 找到它就找到“到底哪一拍发生” |
| `hazard_*` | 向 DECODE 暴露的 producer 身份/可用性 | 不一定是独立执行单元 |
| `kill` | 让年轻记录失效 | 通常只清 valid/occupancy/FSM，不清无效 payload |
| `epoch` | 前端取指流版本 | 用于识别迟到旧响应，不是指令序号 |
| `token` | 主流水线中代表解耦操作的年龄凭证 | 本身不等于运算结果 |

特别注意：握手中的 `ready` 表示“容器能接收”，旁路中的 `result_ready` 表示“数值已算好”。
load 可以已经被 MEM2 接收但数值仍未 ready；二者混淆会让 RAW 控制完全看不懂。

## 23. 推荐的源码阅读顺序

不要从 `edrv32_core.v` 第一行一路读到底。那个文件主要是连线，适合在理解模块后追踪信号。建议
按下面六轮阅读。

### 第一轮：只看骨架

1. `rtl/README.md`：功能和目录边界；
2. `docs/architecture/module-instantiation-tree.zh.md`：例化层次；
3. `rtl/cpu/core/edrv32_core.v`：只看八个阶段和七个边界的例化标题；
4. `rtl/include/edrv32_uop.vh`：认识 op class 和控制编码。

目标：能不看细节画出第 1 节的总图。

### 第二轮：走一条 ADD

依次看 `align_stage → decoder/immgen/regfile/operand_resolve → ex_stage/alu → commit_stage`。只追
`pc/instr/rd/lhs/rhs/result/result_ready/retire`，暂时忽略所有 memory、CSR 和 MDU 字段。

### 第三轮：学习流水线控制

先读最简单的 `edrv32_pipe_decode_to_ex.v`，验证 valid 与 payload 分离，再读两项 FIFO
`edrv32_pipe_mem1_to_mem2.v`。拿纸列出 `capture/transfer/kill` 四种组合，不要先看 Cache FSM。

### 第四轮：走 load/store

依次读：

```text
ex_stage
  → mem1_stage + pma_classifier
  → mem1_to_mem2 FIFO
  → mem2_stage
  → dcache
  → mem2_to_commit
  → commit_stage
  → cached_core 数据路由
```

分别追 cacheable load、cacheable store、MMIO load 三次。若混着追，很容易误以为同一个请求被发了
两遍。

### 第五轮：走一次 redirect 和 trap

分支路径看 `branch_predictor → IF1/IF2 → EX → redirect_ctrl → IF1`；异常路径看
`decode/ex/mem1/mem2` 如何只形成标签，再看 `commit_stage → csr_file → redirect_ctrl`。

### 第六轮：最后看 MDU 和 maintenance

MDU 先看 `edrv32_mdu_scoreboard` 的三条 hazard，再看 `edrv32_mdu` 的 slot/authorize/complete，
最后深入 mul/div 算法。Cache maintenance 先看 `edrv32_cached_core` 的路由，再看 D$ clean FSM。

## 24. 按问题查源码

| 你正在问什么 | 首先打开 |
|---|---|
| PC 为什么变了 | `rtl/cpu/frontend/edrv32_if1_stage.v`、`rtl/cpu/control/edrv32_redirect_ctrl.v` |
| 旧取指响应为何没进入流水线 | `rtl/cpu/frontend/edrv32_if2_stage.v` 的 epoch/address match |
| 16/32 位指令怎样拼 | `rtl/cpu/frontend/edrv32_align_stage.v` |
| 某条编码是否合法 | `rtl/cpu/decode/edrv32_decoder.v`、`edrv32_rvc_decompress.v` |
| 操作数为何不是 regfile 值 | `rtl/cpu/decode/edrv32_operand_resolve.v` |
| DECODE 为什么停 | `rtl/cpu/decode/edrv32_decode_stage.v` 的 dependency/structural stall |
| 分支为何误预测 | `rtl/cpu/execute/edrv32_ex_stage.v` 的 actual/predicted next |
| 一个地址为何 fault/uncached | `rtl/cpu/lsu/edrv32_pma_classifier.v` 和 `rtl/include/edrv32_pma.vh` |
| load 数据何时 ready | `rtl/cpu/lsu/edrv32_mem2_stage.v` |
| store 为什么分两次 | `rtl/cpu/cache/edrv32_dcache.v` 的 reservation 与 local store fire |
| Cache miss 在做什么 | I$/D$ 的 `STATE_*` FSM |
| 异常最终如何写 CSR | `rtl/cpu/commit/edrv32_commit_stage.v`、`rtl/cpu/csr/edrv32_csr_file.v` |
| 除法为何不堵死全核 | `rtl/cpu/mdu/edrv32_mdu.v`、`rtl/cpu/control/edrv32_mdu_scoreboard.v` |
| 反压是否跨了太多级 | 七个 `rtl/cpu/pipeline/` 边界和 `edrv32_core.v` ready 连线 |

## 25. 读懂这颗 CPU 后应能回答的检查题

1. 为什么错误路径普通 load 可以留下 Cache fill，而错误路径 UART load 不允许发出？
2. 为什么 store 在 MEM2 可以发生 miss/refill，却不能合并 store data？
3. 为什么异常在 DECODE 发现后还要继续走到 COMMIT？
4. `ready` 和 `result_ready` 分别回答什么？
5. 为什么旁路必须选择最近的 matching producer，而不能选择任意 ready producer？
6. redirect 为什么分成“事件接受”和“IF1 应用”两个时刻？
7. 为什么已接受的 I$ tag 不能在 redirect 时直接删除？
8. 两项 R6 FIFO 为什么满时不利用同拍下游 transfer 透明放行？
9. MDU 为什么需要 authorize，而普通 ALU 不需要？
10. 当前 CSR、MDU retire 和 FENCE 三处为什么仍是冻结规格中的整改项？

如果这些问题都能独立解释，再回到 `edrv32_core.v`，大多数信号就不再是孤立的线，而会对应到
一种具体的现象：数据还没准备好、容器没有空间、地址不允许、控制流猜错、旧响应迟到、外部动作
不可撤销，或者最老指令正在决定是否真正生效。

## 26. 相关设计与验证资料

- 总冻结规格：[`../design/cpu-rewrite-master-spec.zh.md`](../design/cpu-rewrite-master-spec.zh.md)
- 八级架构设计：[`../design/cpu-rewrite-8stage-architecture.zh.md`](../design/cpu-rewrite-8stage-architecture.zh.md)
- 流水控制契约：[`pipeline-control-contract.zh.md`](pipeline-control-contract.zh.md)
- 数据通路审计：[`../design/cpu-rewrite-rtl-datapath-audit.zh.md`](../design/cpu-rewrite-rtl-datapath-audit.zh.md)
- 模块例化树：[`../design/edrv32-module-instantiation-tree.zh.md`](../design/edrv32-module-instantiation-tree.zh.md)
- 当前 MES50HP 时序报告：[`../reports/timing/mes50hp-cpu-100mhz-r5.zh.md`](../reports/timing/mes50hp-cpu-100mhz-r5.zh.md)
