# EdRV32 单发射八级 CPU 重构架构契约

> 文档关系：CPU 重构的完整功能、配置、时序和验收基线以
> `cpu-rewrite-master-spec.zh.md` 为准；本文只细化八级流水线结构。与总规格冲突时，
> 必须先修订并评审文档，禁止由 RTL 实现自行选择。

状态：2026-09-01 冻结第一版。本文是新 `rtl/cpu` 的实现约束，不是对旧 RTL
的增量修改说明。旧实现只在 `legacy/rtl-pre-rewrite-20260901/` 中作为参考。

流水线冒险、反压、age-qualified kill 以及 cache replay 的完整规则见
`pipeline-control-contract.zh.md`。实现和测试必须同时符合两份契约。
正式数据通路的结构化描述、旧 RTL 复用来源及固定常量运算保留边界见
`cpu-rewrite-rtl-datapath-audit.zh.md`。

## 1. 目标和非目标

本次重构的首要目标是得到边界清晰、能够独立做模块时序收敛的单发射 CPU：

- 器件目标为 PGL50H-6；必须稳定达到 100 MHz，200 MHz 为冲刺目标。
- 固定支持 RV32IMC、Zicsr、Zifencei、Zicntr 和 M-mode。
- 保持现有 SoC 所需的 32-bit Harvard 存储器、TCM、IRQ 和调试观察接口。
- 普通整数指令按顺序发射；每周期至多发射和提交一条流水线指令。
- 乘除法采用解耦执行和专用 pending scoreboard，使无关的年轻整数指令可以继续。

以下内容明确不属于本版：

- F/D 指令、浮点寄存器堆、FCSR、浮点宏和浮点占位端口。
- 双发射 lane、配对矩阵、4R2W 寄存器堆、双写回和双提交。
- 完整乱序执行、通用 scoreboard、ROB、寄存器重命名。
- PMP、S/U-mode、Sv32/MMU 和 Debug trigger module（`tselect/tdata*`、地址/数据断点）。
  基础 M-mode `EBREAK` breakpoint 异常仍属于本版并必须通过。
- 为上述未来功能预留位宽、宏、端口或空模块。

## 2. 八级流水线

| 级 | 唯一职责 | 本级输出/下一级独立pipeline register保存的主要内容 |
|---|---|---|
| IF1 | 选择取指块地址，接受已寄存的 redirect，发起 I$ 查询 | 请求地址、请求 epoch |
| IF2 | 接收 I$ 查询结果并维护顺序取指块缓冲 | 取指块、块地址、错误、epoch |
| ALIGN | 16/32-bit 对齐、跨 32-bit 块拼接、RVC 解压 | PC、规范 32-bit 指令、长度、预测信息、取指异常、epoch |
| DECODE | 译码、立即数、组合读寄存器堆、相关性判断和操作数选择 | 操作类别、操作码、操作数、rd、访存/CSR 属性、异常、epoch |
| EX | ALU、分支条件和目标、有效地址、MDU 请求 | 结果/地址、store 数据、控制流结果、预测校验、异常、MDU token |
| MEM1 | PMA/TCM/cacheability 分类并发起 D$ 阵列查询 | 已寄存地址、访问属性、PMA 结果、异常和提交信息 |
| MEM2 | D$ tag/data 命中判定、load 格式化、miss/响应缓冲 | 写回值或待提交的 store/MMIO/CSR/control packet |
| COMMIT | 唯一架构提交点 | 无下一级uop寄存器；直接生成GPR/CSR写、trap/IRQ/mret、store/MMIO、fence和调试提交事件 |

“一级”必须同时对应逻辑边界、寄存器边界和文件边界，但stage逻辑文件与stage-to-stage
寄存器文件分离。八个stage之间固定建立七个具名模块：

- `edrv32_pipe_if1_to_if2.v`
- `edrv32_pipe_if2_to_align.v`
- `edrv32_pipe_align_to_decode.v`
- `edrv32_pipe_decode_to_ex.v`
- `edrv32_pipe_ex_to_mem1.v`
- `edrv32_pipe_mem1_to_mem2.v`
- `edrv32_pipe_mem2_to_commit.v`

stage模块负责本级组合语义和本级固有状态；pipeline register模块单独负责payload、
`valid`/occupancy、capture/hold/kill及边界断言。不能用一个集中式模块写全部七级，也不能以
无语义的超宽通用寄存器隐藏各边界差异。`edrv32_core.v`只做模块例化和命名连线，不放译码、
旁路、ALU、PMA、异常或提交组合逻辑。

## 3. 时序硬约束

1. 任意组合数据路径只能跨越一个命名 stage，不能穿透两个流水寄存器边界。
2. EX 只产生寄存化的 redirect event；禁止 `EX -> IF1 -> I$` 同周期组合路径。
3. COMMIT 的 trap/IRQ/mret/fence redirect 同样先进入 redirect 寄存器，再由 IF1 接受。
4. 禁止用 `ready_o = !valid_r || ready_i` 串起全流水线。可以停顿的边界必须用
   本地 hold/skid 容量或寄存化 credit，不能形成 COMMIT 到 IF1 的组合反压链。
5. 旁路比较和选择只存在于 DECODE 内部。EX 不接收会继续变化的全局 forward select。
6. 高扇出控制信号在使用域入口复制或寄存；不得用一个组合 flush/stall 网驱动全核。
7. reset 只复位 `valid`、FSM、epoch、scoreboard valid 和架构上要求的 CSR。
   指令 payload、GPR 数据、cache data/tag、预测器数据阵列不做全量复位。
8. 一个时序 `always` 块只拥有一类语义相近的寄存器。边界 `valid`/occupancy、payload、
   FIFO 指针、FSM、请求上下文、响应数据和 cache array/meta 分块书写；payload 只在明确的
   capture 事件更新，不能与 valid 的 reset/kill/hold 生命周期混在同一块。
9. pipeline register是明确的launch/capture端点；它的capture mux不能组合依赖两个以上下游边界，
   同步RAM地址在RAM前注册，RAM响应不能绕过后一边界。
10. 从Phase 1开始同时生成100 MHz和200 MHz两套报告；100 MHz阶段门禁失败立即停止集成，
    200 MHz超预算立即登记结构措施，不能留到最后才第一次检查。

模块级目标以 post-route 为准。实现过程中先使用下列门槛阻止明显过长的逻辑进入集成：

- 100 MHz 基线：单级综合组合延迟目标不超过 7.0 ns，并保留布局布线余量。
- 200 MHz 冲刺：关键单级目标不超过 3.5--4.0 ns。
- 七个pipeline register逐一报告launch→capture数据路径与valid/kill控制路径；不得只报告整核最差一条。
- 每加入一个 stage，必须有功能边界或 STA 证据；不得只靠增加级数掩盖跨级组合路径。

## 4. 流动控制

流水线分为三个局部流控域，而不是一条透明 ready 链：

- 前端域：IF1/IF2/ALIGN。I$ 返回和半字缓冲具有本地容量；DECODE 暂停时
  ALIGN 保持自己的输出，IF2 的块缓冲吸收已经返回的查询。
- 发射域：DECODE/EX。DECODE 只有在 EX 输入槽可接收且依赖满足时发射。分支 redirect
  在 EX 边界杀死年轻的 DECODE 输出，不向前端传播组合 ready。
- 后端域：MEM1/MEM2/COMMIT。可变延迟 load/store/MMIO 状态由 MEM2/COMMIT
  的显式 FSM 和响应缓冲
  保存；在阻塞状态建立前必须有能力保存已经进入相邻边界的至多一条指令。

每条边界分别定义 `valid`、`accept/advance`、`kill`。三者的优先级固定为：

1. reset 清 valid；
2. kill 清 valid，且禁止该条目产生请求或副作用；
3. advance 更新 payload/valid；
4. 否则原样保持 payload/valid。

不得用清空 payload 代替清 `valid`。

## 5. 控制流和 epoch

redirect 只有一个仲裁点，事件至少包含 `valid`、`target_pc`、`reason` 和 `epoch_next`。
同周期优先级固定为：

1. COMMIT 级同步异常；
2. COMMIT 级已接受的中断；
3. COMMIT 级 mret；
4. COMMIT 级 fence.i；
5. EX 级分支/JAL/JALR 预测修正。

COMMIT 中的指令比 EX 中的指令老，因此 COMMIT 事件出现时必须抑制 EX redirect 和该分支的
预测器更新。IF1 只看仲裁后已经寄存的 redirect。所有前端块和 ALIGN/DECODE 指令携带 epoch；
返回 epoch 不匹配的 I$ 数据只能丢弃，不能改变队列状态。

分支方向、目标、顺序下一 PC 和预测元数据全部在 EX 内比较。EX 输出的是“实际下一
PC 是否不同于预测下一 PC”，而不是向顶层暴露多组 taken/target/miss 组合网。

## 6. 依赖和旁路

DECODE 级组合读取 2R1W 整数寄存器堆，并在 DECODE 内完成依赖判断和操作数选择：

- x0 永远读零，写 x0 被丢弃。
- DECODE 自身驻留的 DECODE/EX producer 尚未形成寄存化 EX 旁路；同沿 refill 若命中其 rd，
  必须停一拍，等该 producer 进入 EX 旁路后再接收消费者。
- ALU 结果可从 EX/MEM1、MEM1/MEM2 或 MEM2/COMMIT 的已寄存结果旁路。
- load 只有在 MEM2 数据有效后才可旁路；否则 DECODE 保持。
- CSR、异常、store 和控制流信息不能伪装成普通 ALU 写回参与旁路。
- 同一个源操作数只做一次并行 rd 比较，选择器使用明确的“最新老指令优先”编码。
- MDU pending rd 的 RAW 和 WAW 在 DECODE 停顿；与该 rd 无关的指令可以发射。

不实现 MDU-result 到 DECODE 的同周期组合旁路。完成结果在 COMMIT 写 GPR 并清 pending 后，
依赖指令最早下一周期继续，以换取更短、更稳定的时序。

## 7. 乘除法契约

MDU 是 EX 外的解耦单元，不是 EX ALU 的一个长组合分支：

- EX 在请求被接受时分配一个 MDU slot，并产生随普通流水线向 COMMIT 移动的 token。
- slot 保存 rd、操作类型、必要的 kill/授权标记；结果进入一个完成缓冲。
- token 到达 COMMIT 且未被更老异常冲刷后，该 MDU 指令才获得架构写回授权。
- 结果先到时必须等待授权；授权先到时 scoreboard 保持 rd pending，等待结果。
- 普通 COMMIT 写回优先，MDU 结果在独立完成缓冲中保持，直到 COMMIT 写端口空闲。
- 只有实际写入 GPR 后才清 pending；RAW/WAW 检查下一周期观察到清除。
- trap、IRQ、mret、wfi、fence/fence.i 在存在已授权未完成 MDU 时等待其清空。
- 更老指令异常冲刷尚未授权的年轻 MDU slot；被杀 slot 的迟到结果必须丢弃。

第一版只允许一个 MDU slot。增加深度必须由乘除法密度和 CPI 数据证明，不能演变成
通用乱序完成系统。

乘法与除法模块不各自实现一套外部背压协议：

- `edrv32_mul_booth4_wallace` 直接改造自 legacy 的同名 Booth/Wallace 实现，内部按
  Stage 1 部分积、Stage 2 Wallace 归约、Stage 3 末级和依次书写。每段 payload 和
  occupancy tag 分属独立时序块；`start`/`result_valid` 是启动与完成标记，不是可停顿
  的 ready/valid 流水，结果背压由外层 MDU slot 承担。
- `edrv32_div_nonrestoring` 直接改造自 legacy 已验证的 `div_nonrestoring.v`，保留
  32 次 radix-2 non-restoring 迭代、可选末次余数校正及特殊值快速完成。模块本身采用
  当前 req/result/cancel 接口，不例化 legacy 模块，也不经过兼容 wrapper。
- `edrv32_mdu` 只负责乘/除分派、COMMIT 授权和统一完成 payload；scoreboard 只负责
  pending rd 及 RAW/WAW，不参与算术。

## 8. 精确异常和副作用

COMMIT 是唯一不可撤销副作用所有者：

- GPR 和 CSR 只在 COMMIT 写入；MDU late write 也必须经过 COMMIT 写端口仲裁。
- store data、MMIO 请求、fence/fence.i、mret、WFI 完成和调试 commit 只由 COMMIT 发起。
- cacheable load 可以在 COMMIT 之前查询/填充 cache；MMIO/uncached 访问必须等到其成为
  COMMIT 中最老指令后才发起，以避免错误路径读取具有副作用的设备。
- store 在 MEM1/MEM2 只能计算地址、PMA 和查询 tag，不能提前改写 cache line 或总线。
- 指令一旦携带 exception，后续所有写使能和请求使能均保持为零；COMMIT 根据最老异常
  一次性更新 mepc/mcause/mtval/mstatus 并产生 redirect。
- interrupt 只在指令边界接受；存在未完成的 MDU、MMIO 或已提交 store drain 时，
  先等待可精确观察的状态完成。

CSR 指令在 DECODE 形成 `{op, addr, src}`，沿流水线携带到 COMMIT；CSR file 在
COMMIT 做组合旧值读取，`CSRRS/CSRRC` 的新值也在该级形成，只有 `retire_fire` 才写入
CSR 并把旧值写入 GPR。这样连续 CSR 指令按提交次序自然观察最新值，不需要另建 CSR
旁路/计分板。若 post-route STA 证明该读 mux 是关键路径，读端前移必须和 CSR RAW
控制作为同一个完整改造实施，不能只移动计算逻辑。COMMIT 文件归属 `commit/`，
`csr/` 只拥有架构 CSR 状态模块。

## 9. 文件边界

固定的首版模块划分如下；文件名描述所有权，不按历史文件名兼容：

```text
rtl/cpu/
  core/       edrv32_core.v, edrv32_cached_core.v, edrv32_cpu_minimal_top.v
  frontend/   edrv32_if1_stage.v, edrv32_if2_stage.v,
              edrv32_align_stage.v, edrv32_rvc_decompress.v
  decode/     edrv32_decode_stage.v, edrv32_decoder.v, edrv32_immgen.v
  execute/    edrv32_ex_stage.v, edrv32_alu.v, edrv32_branch_unit.v
  pipeline/   edrv32_pipe_if1_to_if2.v, edrv32_pipe_if2_to_align.v,
              edrv32_pipe_align_to_decode.v, edrv32_pipe_decode_to_ex.v,
              edrv32_pipe_ex_to_mem1.v, edrv32_pipe_mem1_to_mem2.v,
              edrv32_pipe_mem2_to_commit.v
  lsu/        edrv32_mem1_stage.v, edrv32_mem2_stage.v, edrv32_lsu_format.v
  mdu/        edrv32_mdu.v, edrv32_mul_booth4_wallace.v,
              edrv32_div_nonrestoring.v
  commit/     edrv32_commit_stage.v
  csr/        edrv32_csr_file.v
  control/    edrv32_redirect_ctrl.v, edrv32_hazard_ctrl.v,
              edrv32_mdu_scoreboard.v
  datapath/   edrv32_regfile.v
  cache/      edrv32_icache.v, edrv32_dcache.v, array wrappers
```

禁止重新出现一个集中实现大部分功能的数千行 `edrv32_core.v`。当组合逻辑属于某个
stage 时，它必须放在该 stage 或该 stage 独占的叶子模块中；跨 stage 的控制器必须
有单一职责和寄存化输出。

## 10. 验证和时序准入

重构按可验证的垂直切片推进：

1. 基础 encodings、GPR、ALU、immgen、decoder 单元测试。
2. IF1/IF2/ALIGN 的连续 RV32C、跨字 32-bit 指令、redirect/epoch 测试。
3. RV32I 五类指令贯通八级，并建立逐指令 commit reference check。
4. Zicsr、异常、中断、mret、WFI、fence.i 精确性测试。
5. cacheable/uncached/MMIO load/store 及错误响应测试。
6. MDU pending RAW/WAW、无关指令越过、早结果、迟结果和 flush 测试。
7. ISA 回归、CoreMark、CPU-minimal 综合、post-route STA 和板级回归。

每个阶段模块在进入整核前需要独立综合。整核每次出现新的最差路径时，先判断是否违反
本文边界，再考虑布尔优化；禁止以跨级旁路、透明 ready 或顶层补丁换取短期功能通过。
