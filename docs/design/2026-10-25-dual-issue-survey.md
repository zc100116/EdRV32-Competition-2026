# 开源多发射 RISC-V CPU 发射策略调研

| 项 | 内容 |
|---|---|
| 状态 | 调研 |
| 日期 / 检索截止 | 2026-10-25 |
| 任务 | C-E6 |
| 范围 | 顺序双发射为主；乱序发射与商用 Arm 顺序双发射为对照 |
| 本仓库基线 | `08f7573bf22145799a397a78ac4ea90fbb87b86d`，cpu-spec v0.9 |
| 关联 | [CPU 规格](../spec/cpu-spec.md) §2.2–2.3、§4.1–4.5；[微结构优化方向](2026-10-25-cpu-uarch-optimization.md)；C-E4 报告 `docs/reports/2026-10-25-perf-cpu-uarch-eval.md`（本 worktree 无该文件，读取 `zc100116/task-cpu-uarch-eval` 分支版本） |
| 结论边界 | 记录事实、可见机制和定性代价，不作采纳决定，不修改规格 |

## 1. 背景和问题

EdRV32 当前是 F1/F2/D/E/M/W 六级、顺序双发射、顺序退休结构；较老指令固定进入管线 0，较年轻指令进入管线 1。管线 0 全功能，管线 1 只有 ALU；组内 RAW 拆对，WAW 允许且较年轻写入生效；load 结果延迟 2，乘法 3，E 级误预测代价 3 周期，BTB/gshare/RAS 为 32/512/4。[CPU 规格](../spec/cpu-spec.md) §2.2–2.3、§4.1–4.4。

C-I3/C-E4 所见 IPC 约 1.03，CoreMark/MHz 为 3.585（O2）/4.307（tuned）。任务所述“类型不支持 53%、组内 RAW 36%”的分母是单发射原因；设计记录对应事件占总周期分别为 23.7%、16.1%，load-use 占周期 10.0%，事件可重叠。用户已决定管线 1 增加条件分支/JAL、一组最多一条控制转移，本文不重新决策。[微结构优化方向](2026-10-25-cpu-uarch-optimization.md) §1、§4。

调研围绕四个问题：第二槽如何承接更多类型；哪些相关指令可以同组发射；如何把消费者推迟到数据可用时执行；预测、分支槽位与精确异常如何共同限制双发射。

## 2. 约束、口径和证据版本

- 只检索、下载和阅读公开资料；未上传本仓库内容，未编译、仿真或综合任何被调研核。下载物在忽略目录 `build/survey/`，仅本报告入库。
- **槽位与执行单元分开**：第二发射槽可以复用唯一 LSU/MUL，并不等于增加第二套 LSU/MUL。乱序核的 decode/dispatch/issue/retire 宽度分别注明，不把“2 decode”叫“最多 2 issue”。
- **延迟口径保留原文**：EdRV32 的“结果延迟”按消费者进入 E 的间隔定义；late ALU 的“无停顿发射”不表示 load 数据零周期可用。文档未定义统一 load-use 或误预测周期时写“未查到”，不从级数相减推算。
- 性能、频率、资源只绑定原来源配置；未知编译条件明确列出。ASIC GHz、FPGA 工作时钟、FPGA Fmax 分开；CoreMark-Pro 不当作 CoreMark。
- 以下源码事实按固定 commit 引用；路径后 `:Lx–Ly` 是该 commit 的行号。标“源码读取”的结论仅描述已读逻辑，未做运行验证。在线文档按下表版本/章节引用，未固定到 RTL 的性能结果不声称可由该 RTL 重现。

| 代号 | 原始来源 / 固定版本 | 本地阅读位置 |
|---|---|---|
| B | [biRISC-V][B] `6af9c4be5a0807d368eaad5e49af52322e31d073` | `build/survey/biriscv/` |
| E1 | [VeeR EH1][E1] `d04b1c7ae675a63dc4307cacfd10547ec937b928`；仓内 PRM Rev.1.9，2022-12-22 | `build/survey/eh1/` |
| E2 | [VeeR EH2][E2] `32bdfe24c0194a5b625a70624144e4c6dec5f682`；仓内 PRM Rev.1.4，2022-12-22 | `build/survey/eh2/` |
| C | [OpenHW CVA6][C] `742dc82a0c706e0a3bfb98b709fd3ee06d50d12a`（2026-10-23） | `build/survey/cva6/` |
| CS / CSP | [Allart 等 CVA6S 论文][CS]，arXiv:2410.01442；[Tedeschi 等 CVA6S+ 论文][CSP]，arXiv:2505.03762v1 | `build/survey/cva6s.pdf`；公开论文 |
| V / VD | [VexiiRiscv][V] `d8b2775b903732c586f0c50efd651ee9b7f4e72c`；[官方文档源码][VD] `50fa0729d89cc63232b54db95e81224f2054f4d5` | `build/survey/vexii/`、`vexii-doc/` |
| O | [BOOM][O] `ba03175e0a3cf5c0d5a7f14d385ac1c8998c4428`；配置以 `v3/WithNMediumBooms` 为例 | `build/survey/boom/` |
| N / ND | [NaxRiscv][N] `9f452d50560d02fb391bc8039f5453c54e0911af`；[官方文档源码][ND] `c27dcc26963f9f44675425068310702007fed16b` | `build/survey/nax/`、`nax-doc/` |
| X | [香山南湖官方设计文档][X]，以 Nanhu 为界；[集成参数表][XI] 检索于 2026-10-25 | 在线文档；不混入昆明湖参数 |
| T | [OpenC910][T] `b91c90914c19f114d35c8f6b73408eb241ed847c`；仓内用户手册 2024-06-27 | `build/survey/c910/` |
| M7 / A53 | [Cortex-M7 TRM][M7] DDI0489F；[Cortex-A53 TRM][A53] DDI0500J | `build/survey/m7-trm.pdf`、`a53-trm.pdf` |

阅读复现命令（只下载公开内容；无需初始化依赖子模块）：

```sh
mkdir -p build/survey
git clone --depth 1 https://github.com/ultraembedded/biriscv.git build/survey/biriscv
git -C build/survey/biriscv rev-parse HEAD
nl -ba build/survey/biriscv/src/core/biriscv_issue.v | sed -n '630,735p'
pdftotext -layout build/survey/eh1/docs/RISC-V_VeeR_EH1_PRM.pdf build/survey/eh1-prm.txt
git show zc100116/task-cpu-uarch-eval:docs/reports/2026-10-25-perf-cpu-uarch-eval.md
```

其余仓库按上表链接克隆，阅读前核对所读 commit；本文不引入哈希校验或自动门禁。

## 3. 顺序发射设计：逐核事实

### 3.1 biRISC-V

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 取指 / 队列 | 6 或 7 级，双发射、顺序；64-bit 取指。可选额外 decode 级。取指 FIFO 默认 `DEPTH=2`，每项两个 32-bit 指令槽，即最多 4 条，不能保证跨取指组任意压紧配对。[B] `README.md:L9–L15`；`src/core/biriscv_decode.v:L203–L237,L283–L285,L329–L334`。 |
| b. 管线 / 配对 | 槽 A：ALU、branch、LSU、MUL、DIV、CSR；槽 B：ALU、branch、LSU、MUL。唯一 LSU/MUL 通过 `pipe1_mux_lsu_r/pipe1_mux_mul_r` 接收任一槽；B 没有 DIV/CSR。**配对矩阵有方向性**：A∈{ALU,LSU,MUL} 时 B 可为 ALU/branch；A∈{ALU,MUL} 时 B 可 LSU；A∈{ALU,LSU} 时 B 可 MUL。因此 A 是 branch 时不与 B 同发，两个 LSU、两个 MUL 也不同发。[B] `src/core/biriscv_issue.v:L637–L647,L688–L723`。 |
| c. RAW / WAW | A 发射后即把其非零 rd 置入组合 scoreboard，B 的 rs1/rs2/**rd** 均查 scoreboard；同组 RAW 和 WAW 均阻塞，无同拍级联 ALU。[B] `src/core/biriscv_issue.v:L655–L708`。 |
| d. load-use | E1 的 load/mul rd 阻塞相关消费者；E2 结果可旁路，`SUPPORT_LOAD_BYPASS=0` 时连 E2 也阻塞。这对应命中、无全局停顿条件下紧邻 load 消费者至少在 issue 等一拍（源码读取），不是 late ALU。可关闭 load/mul 旁路以改变时序取舍；全系统访存延迟不固定。[B] `src/core/biriscv_issue.v:L659–L686,L866–L884`。 |
| e. 分支 | 两个执行槽均接分支，但双发射时只能 B 是分支，一组最多一条。默认 BTB=32、BHT=512、RAS=8，`GSHARE_ENABLE=0`、`BHT_ENABLE=1`；支持启用 gshare。误预测统一周期数未查到，不能用 6/7 级直接推导。[B] `src/core/biriscv_issue.v:L637–L647`；`src/core/riscv_core.v:L31–L50`。 |
| f. 异常 / 中断 | 两槽都有异常通路；B 的 `squash_wb_i` 接 A 的 squash，A 的 `squash_wb_i=0`，B 异常因此可以保留较老 A 写回，A 异常则抑制 B。异常 PC 优先 A；接收中断时禁止双发并抑制 LSU。精确性依赖这套逐槽 kill，而非“B 不会异常”。[B] `src/core/biriscv_issue.v:L430–L434,L490–L556,L579–L581,L647,L720–L729`；`src/core/biriscv_pipe_ctrl.v:L372–L415`。 |
| g. 性能 / FPGA | 项目公布 4.1 CoreMark/MHz、1.9 DMIPS/MHz；Dhrystone 只注明 legal compile options、337 instructions/iteration，完整编译器版本/flags 和 CoreMark flags 未查到。README 表示 Artix-7 上 >50 MHz 的目标已达成，并展示 Arty 启动 Linux；具体器件速度级、配置、Fmax 和 LUT/FF/BRAM 未查到，不把 >50 当精确综合结果。[B] `README.md:L23–L24,L49–L60`。 |
| h. 许可 / 源码 | Apache-2.0；[固定源码树][B]，`LICENSE:L1–L4`。 |

**对照意义**：扩充年轻槽的类型，不必把每个专用功能单元复制两份；不过这会带来槽 B 访存异常和共享结果选择问题，源码中已经有对应路径。把“biRISC-V B 不能 LSU”当作事实会漏掉它的核心路由机制。[B] `src/core/biriscv_issue.v:L637–L723,L490–L556`。

### 3.2 SweRV / VeeR EH1

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 取指 / 队列 | PRM 称 9 级、双发射、mostly in-order，允许部分乱序执行；两条 I0/I1 管线各有 EX1、EX4 ALU，共四个。PRM 的 Align 来自 3 个 fetch buffer，Decode 来自 4 个 instruction buffer，Commit 最多 2 条。**内部取指数据为 128 bit**，q0/q1/q2 各 128 bit；外部总线为 64 bit，二者不可混同。[E1] `docs/source/core-overview.md:L4–L5,L15,L35–L40`；`design/ifu/ifu_aln_ctl.sv:L58,L235–L248,L676–L678`；`design/ifu/ifu_mem_ctl.sv:L131–L179`。 |
| b. 管线 / 配对 | ALU/分支、load/store、乘法都可由 I0/I1 发往对应单元；LSU、MUL 各一套，一组不能两个 LSU 或两个 MUL；DIV 的组合请求虽有两槽输入，但 DIV/REM 在 decode 表有 presync/postsync，I1 被相应 block，实际只在 I0 单独发射；CSR 也只在 I0，受同步限制；I0 未预测 JAL 会阻止 I1。并非完全对称。[E1] `design/dec/dec_decode_ctl.sv:L1293–L1302,L1343–L1364,L1404–L1406,L1464–L1476`；`design/dec/decode:L219–L222`。 |
| c. RAW / WAW | **允许特定同组 RAW**：I0 load/MUL→I1 ALU 可同发，I1 改在 secondary ALU 执行；I0 early ALU→I1 store 的数据操作数有晚旁路，地址操作数相关则不适用。普通 I0 ALU→I1 ALU 的特例在该版本被注释掉，注释说对性能不好。WAW 可同发；WB 同 rd 时抑制 I0 写，保留未被 kill 的 I1；非阻塞 load 另有旧目标失效处理。[E1] `design/dec/dec_decode_ctl.sv:L1288–L1289,L1359,L1833–L1854,L808,L2220–L2229`。 |
| d. load-use | 命中/数据按期返回时，load→ALU 可通过 EX4 late ALU 避免 decode 气泡，包括上述同组特例；消费者实际执行仍晚于 load。非 ALU 消费者使用独立的 load block 规则；有 load→load/store 地址旁路和 store-data 旁路，不能概括成所有 load-use 均为零。PRM 另列单个三周期乘法器、流水线外 34 周期除法器；统一“load-to-E 延迟”未查到。[E1] `docs/source/core-overview.md:L35`；`design/dec/dec_decode_ctl.sv:L1795–L1802,L1833–L1858,L1904–L1928`。 |
| e. 分支 | I0/I1 均有分支执行和 flush 路径；配对阻塞表未对两个普通条件分支设置相互排斥项，仍受 RAW、secondary、JAL 等约束（源码读取，不表示任意双分支组合都可发）。BTB+BHT+RAS；BHT 索引使用地址与 GHR 的配置生成散列。`default` 为 BTB32/BHT128/RAS4，`high_perf` 为 512/2048/4；统一误预测代价未查到，early/late 分支不能混成固定数。[E1] `design/dec/dec_decode_ctl.sv:L1343–L1364,L1480–L1484`；`design/ifu/ifu_bp_ctl.sv:L1424–L1427`；`design/lib/beh_lib.sv:L431–L439`；`configs/veer.config:L254–L257,L329–L332`。 |
| f. 异常 / 中断 | I1 的取指异常、非法指令等不直接作为 I1 执行，decode 会拆开；**I1 LSU 异常确实存在**，TLU 按 inst_pipe 区分，I0 的异常/误预测优先，I1 的 kill 可独立于 I0。常规 commit 最多两条，RF 在 WB 更新。非阻塞 load 和 store 的外部总线错误是非精确错误，经 NMI 报告，不能称所有访存错误都精确。[E1] `design/dec/dec_decode_ctl.sv:L1348–L1354,L1404–L1406`；`design/dec/dec_tlu_ctl.sv:L772–L825`；`docs/source/core-overview.md:L39–L40`；`docs/source/memory-map.md:L173–L178,L216–L225`。 |
| g. 性能 / FPGA | RVfpga 作者论文表2列 EH1 4.9 CoreMark/MHz，完整编译 flags/DMIPS 未查到。[RVfpga 原作者论文][RV] §II-A2 表2。作者团队 RVfpga poster 给 Nexys A7/Nexys 4 DDR 平台 50 MHz；这是教学 SoC 的工作时钟，不是独立核 Fmax，核独占资源未查到。[RVfpga poster][RVP] Part 1 系统说明。 |
| h. 许可 / 源码 | Apache-2.0；[固定源码树][E1]，PRM 封面及 `LICENSE`。SweRV 是历史命名，本文按 VeeR 仓库所读版本描述。 |

### 3.3 SweRV / VeeR EH2

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 取指 / 队列 | 9 级、双发射、可双线程，最多两条总发射，非“每线程两条”；PRM 说 3 fetch buffer、4 instruction buffer，最多双提交。**所读 RTL 的 aligner 输入是 64 bit，内部 f0/f1/f2/f3 四个 64-bit 数据寄存器**；PRM 的“3 fetch buffers”与RTL四个暂存寄存器的计数口径如何对应，本轮未查到，不能简单判成容量参数从3改为4，也不以 EH1 的128-bit路径代替EH2。双线程复制取指/IB 等状态。[E2] `docs/source/overview.md:L5–L6,L37–L42`；`design/ifu/eh2_ifu_aln_ctl.sv:L58,L655–L681`；[WD 技术简报][WD] “SweRV Core EH2”段。 |
| b. 管线 / 配对 | ALU、分支、LSU、MUL 可从两槽进入；一组仍不能两个 LSU 或两个 MUL，跨线程也受该资源约束。DIV、CSR 等有 `i0_only` 标记；DIV 的请求只取 I0。相同线程 I1 通常依赖 I0 的可发射性，不同线程 I1 有独立可发条件。[E2] `design/dec/eh2_dec_decode_ctl.sv:L1285–L1319,L1584–L1595,L1635–L1682,L1948–L1949`；`design/dec/decode:L426–L429`（DIV/REM）。 |
| c. RAW / WAW | 同组 load/MUL→ALU 和 early ALU→store-data 特例仍在，未见普通 ALU→ALU 同组特例。相关/CSR/JAL 等限制有 same-thread 区分。WB 的同 rd 抑制旧写条件增加“同 tid”，不同线程同寄存器号不构成 WAW。[E2] `design/dec/eh2_dec_decode_ctl.sv:L1668–L1682,L2388–L2405,L2821–L2823`。 |
| d. load-use | 保留 secondary ALU、load/store data bypass 和非阻塞 load；双线程提供另一独立指令流，但共享 LSU/MUL 仍限制并发。统一 load-use 周期未查到；不能把 EH2 双线程吞吐量提升等同于单线程 load-use 缩短。[E2] `docs/source/overview.md:L37`；`design/dec/eh2_dec_decode_ctl.sv:L1624–L1652,L2388–L2405`；[WD][WD] EH2 段。 |
| e. 分支 | 两槽均有 branch/flush 逻辑，同线程受 I0 JAL 等限制；全部“双分支组合”公开矩阵未查到。BTB/BHT/RAS 默认参数 512/512/4，BHT 散列含 GHR；可配置，不能把 EH1 high_perf 的 2048 表项直接移植成 EH2 默认。误预测统一周期未查到。[E2] `design/dec/eh2_dec_decode_ctl.sv:L1671–L1682`；`configs/veer.config:L254–L259`；`design/lib/eh2_lib.sv:L58–L74`。 |
| f. 异常 / 中断 | 每线程独立机器 CSR、软件/计时器中断，NMI 可分配线程；TLU 有独立两槽 kill，并考虑线程的提交和 flush。非阻塞 load/store 系统总线错误仍属非精确错误。跨线程没有单一的程序提交顺序，不能照搬成 EdRV32 单线程槽位。[E2] `docs/source/multi-threading.md:L26–L61`；`design/dec/eh2_dec_tlu_ctl.sv:L765–L779,L915–L922`；`docs/source/memory-map.md` “Imprecise Data Bus Errors”节。 |
| g. 性能 / FPGA | **6.3 CoreMark/MHz 是双线程合计、模拟结果**，不是每 hart 单线程得分；WD 原文明确 combined/dual threaded。完整编译选项、单线程对应数字、DMIPS、FPGA 频率/器件/资源未查到；PRM 的 1.2 GHz@16nm 是 ASIC 目标。[WD][WD] EH2 段；[E2] `docs/source/overview.md:L19`。 |
| h. 许可 / 源码 | Apache-2.0；[固定源码树][E2]，PRM 封面及 `LICENSE`。 |

### 3.4 CVA6 superscalar：区分 CVA6S、CVA6S+ 与当前上游

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 取指 / 队列 | CVA6S 保留六级结构：取指、PC/预测、decode、issue/读操作数、execute、commit；64-bit 取指，双 decode/issue/commit，issue buffer 两条。[CS] §2、§3a–b。当前上游 `SuperscalarEn` 强制两个 issue/commit port、两 ALU、64-bit fetch；不能仅看用户配置里 `NrCommitPorts=1`。[C] `core/include/build_config_pkg.sv:L48–L54,L188–L191`。当前取指队列每个 `INSTR_PER_FETCH` bank 深 4；有 C 时 4 banks，即 16 指令项，无 C 时 2 banks，即 8 项（源码参数相乘），另有地址 FIFO 深 2。[C] `core/frontend/instr_queue.sv:L472–L477`；`core/include/ariane_pkg.sv:L169–L170`。 |
| b. 管线 / 配对 | 两 issue port 面向共享功能单元，以 FU busy 和返回总线冲突限制配对；CSR/CVXIF 不能从第二 issue port 发射；两个 LSU 不同发。ALU2 优先供一般 ALU 指令使用，原 ALU/branch/CSR/MUL 还受共用结果总线限制。第二 ALU 的存在不代表只有第一槽能 LSU/MUL/branch。[C] `core/issue_read_operands.sv:L315–L325,L370–L422,L434–L464`；[CS] §2b、§3b–d。 |
| c. RAW / WAW | **2024 CVA6S** 检测同组相关，WAW 尚靠阻塞，论文把重命名列为后续工作。[CS] §2b、§5–6。**2025 CVA6S+** 增加重命名和同周期 ALU→ALU 前递。[CSP] §2。**当前上游** 有 `ALUBypass`，只在两条 FU 都为 ALU、两者都不是 CPOP/CPOPW 时放行同组 RAW，`alu_wrapper` 直接把第一 ALU 结果接第二 ALU 输入；`raw_checker` 选择环形 scoreboard 中最新匹配生产者，当前发射条件不再以同 rd 阻止 WAW（源码读取）；最终仍按序提交，FF 寄存器堆同地址多写按较高提交端口生效。[C] `core/issue_read_operands.sv:L305–L312,L475–L530,L633–L655`；`core/alu_wrapper.sv:L42–L67`；`core/raw_checker.sv:L48–L71`；`core/issue_read_operands.sv:L859–L887`；`core/ariane_regfile_ff.sv:L64–L73`。 |
| d. load-use | 2024 论文模型把 load/store 和 MUL 按两周期执行建模，采用一周期 cache 延迟配置；这不是所有 CVA6 cache 的通用 load-use 保证。scoreboard/FU 结果前递允许生产者未 commit 时被消费，但顺序 issue 的队头 RAW 仍阻塞后继。CVA6S+ 的 HPDCache 是三段、非阻塞并支持多个未命中，作用也包括访存重叠；统一单值 load-use 未查到。[CS] §2b–e；[CSP] §2；[C] `docs/design/design-manual/source/cva6_issue_stage.adoc:L138–L142,L227–L229`。 |
| e. 分支 | 共享一个 branch FU，从任一 issue port 路由，一组最多一条；第一 port 是分支时，speculative scoreboard 可接收部分年轻指令，store 因无法部分 flush 仍受限。2024 模型按误预测后 6 周期阻塞 issue 建模，**只属于论文模型口径**。CVA6S+ 用 128 项、每项 3-bit 私有历史的两级预测，论文称 Embench 上误预测损失降低 30%，不是单次误预测周期缩短 30%。当前 `cv32a65x` 的 BHT 是 32、历史 3、RAS2、BTB0，不等于论文配置。[CS] §2b、§3c；[CSP] §2；[C] `core/issue_read_operands.sv:L375–L395`；`core/include/cv32a65x_config_pkg.sv:L65–L69`。 |
| f. 异常 / 中断 | 顺序 issue、可乱序完成、顺序 commit；scoreboard 是带序号的完成/异常跟踪。2024 增加每项 cancelled 位，分支只标记年轻项，避免旧的迟到结果污染复用项；commit 取消项不改架构状态。当前第二 commit port 只有第一 port 已 ack、且第二条无异常并为允许 FU 时才能退休；第二条异常留到成为队头处理。[CS] §3c；[C] `core/commit_stage.sv:L317–L344,L378–L415`。 |
| g. 性能 / FPGA | 2024 CVA6S 3.10→4.35 CoreMark/MHz，配置基于 cv32a6_imac_sv0+Zb、低 cache 延迟；论文没有完整 CoreMark 编译 flags。877 MHz、278 kGE 是该论文 PPA 数字，不能当 FPGA 结果。[CS] §2e、§4 表1。2025 同一 Cheshire/Genesys2 Kintex-7 实验中，CVA6/CVA6S/CVA6S+ 为 **2.83/3.41/3.69**；I$16 KiB 4路、D$32 KiB 8路，完整 flags、FPGA Fmax/LUT 未查到；表1 的 960–1095 MHz 是 GF22FDX 综合估计。[CSP] §3、表1。DMIPS 的绝对值未查到，2024 仅报 Dhrystone 相对 +24%。 |
| h. 许可 / 源码 | 当前 OpenHW 仓库包含 Solderpad 系列许可及旧文件头，**按文件**区分；例如配置文件标 `Apache-2.0 WITH SHL-2.0`，`core/alu.sv` 仍标 Solderpad 0.51。[C] `core/include/cv32a65x_config_pkg.sv:L1–L6`、`core/alu.sv:L1–L9`。当前双发射入口是 `cv32a65x`（superscalar 和 ALUBypass 都开启）；CVA6S+ 论文对应精确 RTL commit 未查到，不把当前上游等同于该论文快照。[C] `core/include/cv32a65x_config_pkg.sv:L24–L29`。 |

**文档与代码差异**：当前上游的 `cva6_issue_stage.adoc:L147–L157` 仍写同组无前递、WAW 阻塞；实际源码已有上述 ALUBypass 和最新生产者选择。本文用 RTL 描述当前行为，用论文描述论文版本，不用旧文档覆盖新实现。没有据此宣称完成了 CVA6 的功能验证。[C] 上述源码与文档行号。

### 3.5 VexiiRiscv：补充的 FPGA 顺序双发射参照

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 取指 / 队列 | 可配置顺序单/双发射；官方示例是双发射、early+late ALU、6 级，但不是所有配置固定 6 级。`decoders=lanes=2` 可生成双发；取指宽度为 `max(32*decoders, fetchMemDataWidthMin)`，典型双发为 64 bit。没有一个固定深度的统一 IB：Aligner 可加一个 fetch-word buffer，dispatcher 可加 `Decode.LANES-1` 个槽，双 decode 即 1 个暂存槽，另有流水寄存器。[VD] `source/VexiiRiscv/Introduction/index.rst:L91–L113`；[V] `src/main/scala/vexiiriscv/Param.scala:L365,L904–L909`；`src/main/scala/vexiiriscv/decode/AlignerPlugin.scala:L20–L21,L226–L228`；`src/main/scala/vexiiriscv/schedule/DispatchPlugin.scala:L226–L237`。 |
| b. 管线 / 配对 | ParamSimple 的 lane0 有 ALU/branch、LSU、MUL/DIV、CSR，lane1 有 ALU/branch；可给两条 lane 都加 late ALU/branch，late branch 不含 JALR。dispatcher 可以按年龄、layer priority 把候选路由到兼容 lane，非固定“较老永远物理 lane0”；它不要求 lane 对称。[V] `src/main/scala/vexiiriscv/Param.scala:L1110–L1119,L1175–L1284,L1306–L1367`；[VD] `source/VexiiRiscv/Decode/index.rst:L66–L97`。 |
| c. RAW / WAW | 所读 dispatcher 对候选间的旧 rd 与年轻指令所有 register access 做冲突判断，匹配则不发；该逻辑覆盖同组 RAW/WAW，并没有 CVA6 那样的组内组合 ALU 级联。late ALU 的跨周期相关由“生产者何时 broadcast、消费者何时读 rs”判断。[V] `src/main/scala/vexiiriscv/schedule/DispatchPlugin.scala:L261–L281,L418–L432`；`src/main/scala/vexiiriscv/decode/DecoderPlugin.scala:L85–L99`；[VD] `source/VexiiRiscv/Decode/index.rst:L83–L91`。 |
| d. load-use | 有 E1/E3 两层可选执行位置；调度根据消费者的操作数使用时间选择层，满足 load/MUL 的较晚前递。early 层优先，late 层可能占用 LSU/MUL 路径，因此不是免费提高所有组合吞吐。统一 load-use 周期未查到，受 cacheless/cache 与参数影响。[VD] `source/VexiiRiscv/Decode/index.rst:L74–L87`；[V] `src/main/scala/vexiiriscv/Param.scala:L1306–L1351`。 |
| e. 分支 | early 两 lane 都实例化 BranchPlugin；late 两 lane 可处理非 JALR branch。一组允许几条控制转移、统一误预测代价未查到；不能仅由两个 BranchPlugin 推断所有双分支都可同发。参数给 BTB512、gshare4 KiB、RAS4。官方说明 relaxed-btb 把预测扩为两拍、每次正确跳转多一拍；relaxed-branch 在 ALU 与 flush/setPc 间加一拍以改善时序。[V] `src/main/scala/vexiiriscv/Param.scala:L176,L186,L980–L997,L1119,L1314,L1336,L1351`；[VD] `source/VexiiRiscv/Performance/index.rst:L110–L120`。 |
| f. 异常 / 中断 | 统一以流水 age、laneAge 仲裁，trap 取最老请求；同一级 flush 按 laneAge 抑制更年轻指令，WB 受 cancel/COMMIT 控制。dispatcher 还防止年轻指令在旧指令可 flush 前产生不可撤销副作用。不是仅用物理 lane 编号作提交顺序；中断插入的完整逐槽矩阵未查到。[V] `src/main/scala/vexiiriscv/misc/TrapPlugin.scala:L364–L369,L424–L430`；`src/main/scala/vexiiriscv/schedule/ReschedulePlugin.scala:L28–L36`；`src/main/scala/vexiiriscv/schedule/DispatchPlugin.scala:L316–L330`；`src/main/scala/vexiiriscv/execute/WriteBackPlugin.scala:L93–L100`。 |
| g. 性能 / FPGA | 官方 max-IPC 表为 5.24 CoreMark/MHz、2.50 Dhrystone/MHz，issue2/late-ALU2、BTB512/RAS4/gshare4 KiB；完整 flags 未查到。另一个 `rv32im_branchPredictStressed_cached8k8k_ipcMax_lateAlu` 综合配置为 3.41/1.74、Artix-7 140 MHz、3247 LUT/3755 FF；使用系列最高速度级、带 I/O 串并转换，具体料号/BRAM/DSP 未列。**不把 5.24 与 3247 LUT/140 MHz 拼成同一配置**。[VD] `source/VexiiRiscv/Performance/index.rst:L6–L24,L28–L37,L95–L101`。 |
| h. 许可 / 源码 | MIT；[固定源码树][V] `LICENSE`，官方文档源码见 [VD]。 |

### 3.6 检索后未纳入双发射详表的候选

- **WARP-V**：所读 [主仓库](https://github.com/stevehoover/warp-v/tree/f2cbd1a1d9311644f3475d870c856d260ffaddbf) `README.md:L6–L10` 描述 1–7 级可配置生成器；本轮未查到主仓库可复现的双发射配置或对应配对规格，因此不当作已有双发射核。不能把“可配置流水深度”推成“可配置发射宽度”。
- **Kronos（SonalPinto）**：[主仓库](https://github.com/SonalPinto/kronos/tree/13678d47ccae4f889690ec1e0ba648299c7027d8) `README.md:L3,L22–L25,L33` 为 FPGA 三段顺序、单发射比较；dual Wishbone 是指令/数据双总线。本轮未查到它的双发射版本，按任务允许略过。

## 4. 乱序核对照：只展开与发射/配对有关的部分

### 4.1 BOOM（以 v3 Medium 配置为例）

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 宽度 / 队列 | 官方概念图分 10 个功能阶段，文档所述合并实现为 7 级、commit 异步于主流水；不代表所有 BOOM 版本相同。v3 Medium：decode/retire2、fetchWidth4（RVC 半字位置，I$ fetchBytes8）、ROB64、FetchBuffer16，FTQ32；独立 IQ 为 MEM 12项/1发、INT20项/2发、FP16项/1发，因此执行峰值不叫“最多两发”。[O] `docs/sections/intro-overview/boom-pipeline.rst:L13–L18`；`src/main/scala/v3/common/config-mixins.scala:L153–L184`；`src/main/scala/v3/common/parameters.scala:L116`。 |
| b. 类型 / 配对 | 按整数、浮点、访存分开 IQ，issue port 只选自己支持且 ready 的 FU；无顺序相邻配对矩阵。CSR 只非推测执行。精确每个 Medium FU 的完整映射未查到，文档 execution-stages 图是示例，不能当该配置端口表。[O] `docs/sections/issue-units.rst` “Issue Select Logic”；`docs/sections/execution-stages.rst` “Control/Status Register Instructions”。 |
| c. RAW / WAW | rename 去除 WAW/WAR，RAW 保留物理生产者依赖、等就绪后发射；同一 decode 包含 RAW 不必拆 decode，但不代表消费者与生产者能在同拍级联执行。[O] `docs/sections/rename-stage.rst:L15–L36`；`docs/sections/issue-units.rst` “Issue Slot/Wake-up”。 |
| d. load-use | IQ 中独立指令可越过未就绪消费者，LSU 有 store→load forwarding；固定配置的 load-use 周期未查到。官方旧版 IQ 文档把投机 load-hit issue 写为未来功能，本文不把它认作该版已实现。[O] `docs/sections/load-store-unit.rst` “Load Instructions”；`docs/sections/issue-units.rst` “Speculative Issue”。 |
| e. 分支 | 分支从支持的 FU 发射，用 branch mask/tag 跟踪推测；固定槽号/每 decode 组分支上限、统一误预测代价未查到。Medium 配置选 TAGE-L BPD，maxBrCount12（在途分支上限，不是每组分支数）；预测器各表完整容量未在此展开，未查到同一配置汇总。[O] `src/main/scala/v3/common/config-mixins.scala:L153–L176`；`docs/sections/execution-stages.rst` “Branch Unit”。 |
| f. 异常 / 中断 | ROB 记录最老异常，直到队头才抛出；顺序提交，年轻结果先写物理寄存器不代表架构提交。槽 1 的异常没有固定物理槽特例，按 ROB 顺序。[O] `docs/sections/reorder-buffer.rst:L75–L85`、“The Commit Stage”。 |
| g. 性能 / FPGA | 本轮未查到能同时绑定上述配置、flags 的 CoreMark/DMIPS。官方站给 FireSim/Amazon EC2 F1 上 90+ MHz，未给同项核独占资源，且不是 PG2L200H 可比 Fmax。[BOOM 官网][OW] Features/介绍。 |
| h. 许可 / 源码 | 主许可 BSD-3-Clause，另有 `LICENSE.SiFive` Apache-2.0 文件；[固定源码][O] `LICENSE`、`LICENSE.SiFive`，依文件适用。 |

### 4.2 NaxRiscv（官方 RV32 性能配置）

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 宽度 / 队列 | 64-bit fetch、2 decode、**3 issue**、2 retire；共享 IQ32、物理寄存器64、LQ16/SQ16。统一整数级数和独立 FetchBuffer 容量未查到，不能拿 IQ32 充当取指队列容量。[ND] `source/NaxRiscv/performance/index.rst:L18–L30`；`source/NaxRiscv/introduction/pipeline.rst`。 |
| b. 类型 / 配对 | 两个 Int/Shift/branch 执行单元，另一个共享 load/store/mul/div/csr/env 单元。统一 IQ 以年龄择就绪者，二维队列每次按 decode 行分配，空位置不压缩；这是动态调度，并非只检查相邻两条。[ND] `source/NaxRiscv/performance/index.rst:L21–L25`；`source/NaxRiscv/frontend/dispatch.rst:L9–L17`。 |
| c. RAW / WAW | 有寄存器重命名；IQ 用依赖矩阵并按 ROB ID 唤醒。WAW 通过独立重命名结果消除；同 decode RAW 只建立依赖，未查到同拍组合级联 ALU 特例。[N] `README.md:L11`；[ND] `source/NaxRiscv/frontend/dispatch.rst:L10–L15`。 |
| d. load-use | 官方给 **3 周期 load-to-use**，利用 speculative load-hit predictor；非阻塞 D$、多 refill/writeback slot，store→load bypass。隐藏靠动态选择独立指令和投机唤醒，而非所有 RAW 无条件同发。[ND] `source/NaxRiscv/performance/index.rst:L25–L28`；[N] `README.md:L19–L22`。 |
| e. 分支 | 两 Int 单元均能 branch；该配置 BTB512（1路）、gshare4 KiB、RAS32。fetch/decode 两级预测，decode 可补静态跳转、RAS；每组控制转移上限和总误预测代价未查到。RAS 重定向只修指针，不修所有推测写入值。[ND] `source/NaxRiscv/performance/index.rst:L24,L30`；`source/NaxRiscv/branch_prediction/index.rst:L10–L13,L34–L49`。 |
| f. 异常 / 中断 | commit 等较老 ROB 指令完成，记录最老待 trap/jump 的 ROB ID，并在顺序提交边界应用 reschedule。不存在固定槽1异常豁免。[ND] `source/NaxRiscv/backend/commit.rst:L7–L10`；[N] `src/main/scala/naxriscv/misc/CommitPlugin.scala:L187–L227`。 |
| g. 性能 / FPGA | 5.02 CoreMark/MHz（O3，作者未列全其余 flags）、2.93 DMIPS/MHz（`-O3 -fno-common -fno-inline`、318 instructions/iteration）；Artix-7 -3：155 MHz、13.3 KLUT、10.3 KFF、12 BRAM、4 DSP，完整料号未查到。与 EdRV32 的无 cache RAM 10K LUT 预算边界不等同。[ND] `source/NaxRiscv/performance/index.rst:L18–L41`。 |
| h. 许可 / 源码 | RTL 生成代码 MIT，例如 [N] `src/main/scala/naxriscv/Gen.scala:L1–L3`；README 等部分文件 CC0-1.0，见仓内 `LICENSES/`，不是全仓只有一种许可。 |

### 4.3 XiangShan（南湖，非昆明湖）

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 宽度 / 队列 | 南湖集成表给 11 级、6 decode/rename、ROB256、整数/浮点物理寄存器各192；IFU 4级处理 32-byte 指令块。独立 IBuffer 容量、所有 FU 同时 issue 宽度本轮未查到，**不把 6 decode 直接叫 6 issue**。[XI] “Typical Configurations”；[X] `frontend/ifu/` 开头。 |
| b. 类型 / 配对 | 保留站等待操作数，选择就绪指令并读 DataArray；ALU 含条件分支，MISC 含 CSR/JUMP，另有 MUL、DIV 与 load/store 流水。具体 FU 数和每端口能力矩阵未查到同一版本的完整表，不套用新的昆明湖配置。[X] `backend/issue/` “选择/读数据/监听与唤醒”；`backend/exu_int/` “ALU/MUL/DIV/MISC”。 |
| c. RAW / WAW | rename 以物理寄存器映射消除假依赖，保留站监听写回并唤醒真实相关；同 decode RAW 与同拍级联执行是不同问题，后者未查到。[X] `backend/rename/`；`backend/issue/` “监听与唤醒”。 |
| d. load-use | 集成表列 load→ALU/LD 为 4 周期、→其他为 5 周期；调度保留站与 LQ/SQ 支持跨过不就绪消费者，具体全部 replay 条件未展开。[XI] “Instruction Latency”；[X] `backend/issue/`。 |
| e. 分支 | 条件分支走 ALU，JUMP 走 MISC；预测采用 uBTB、FTB、TAGE-SC、ITTAGE、RAS，FTB 每项最多两条分支、第一条为条件分支。预测块两分支不等于一个 issue 组两分支。各表容量、每组可执行分支数、总误预测代价本轮未查到。[X] `frontend/bp/` “顶层模块/FTB/TAGE-SC”；`backend/exu_int/`。 |
| f. 异常 / 中断 | ROB 按队头依次提交，异常指令阻塞提交并输出 exception；条目有 interrupt_safe，文档说明当时为了简化设计避免在访存指令上触发中断。该限制有版本边界，不外推所有香山版本。[X] `backend/rob/` “派遣/提交”。 |
| g. 性能 / FPGA | 本轮未查到绑定本版和完整 flags 的 CoreMark/MHz、DMIPS/MHz、FPGA Fmax/资源；集成表 2 GHz@14nm 等是 ASIC 目标，不属于 FPGA 测量。[XI] 总览。 |
| h. 许可 / 源码 | 硬件使用 Mulan PSL v2，源码 [OpenXiangShan/XiangShan][XS] `LICENSE`；引用南湖设计文档，文档自身 CC BY 4.0。本文未固定南湖 RTL commit，未把在线文档参数声称为当前 master 默认。[X] 页面许可。 |

### 4.4 OpenC910

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 宽度 / 队列 | 用户手册给 9–12 级、3 decode、8 execution、3 retire；IFU 每次最多提取8条。源码 IBuffer 有32项、每项16-bit 指令片段，不能写成“32条完整32-bit指令”；32-bit 指令消耗两片段。[T] `doc/玄铁C910用户手册_20240627.pdf` §1.2.2、§2.2.1、§2.2.5；`C910_RTL_FACTORY/gen_rtl/ifu/rtl/ct_ifu_ibuf.v:L3134–L3188,L3452`；`ct_ifu_ibuf_entry.v:L78`（同目录）。 |
| b. 类型 / 配对 | 按序取指、乱序发射完成、顺序退休；有 ALU、MUL、DIV、BJU、FPU 与双发射标量 LSU。不能把 8 execution 当 8 decode。完整八条执行管线的 opcode/CSR 归属矩阵本轮未查到，故不声称对称。[T] 用户手册 §1.2.2、§2.2.2–§2.2.5。 |
| c. RAW / WAW | 基于物理寄存器重命名；真 RAW 的消费必须等对应结果，WAW 的架构寄存器号复用不必阻塞。未查到同拍依赖 ALU 级联特例。[T] 用户手册 §1.2.2、§2.2.2、§2.2.5。 |
| d. load-use | LSU 乱序、非阻塞 cache、支持多路总线并发与预取，用访存及运算重叠隐藏延迟；统一 load-use 延迟未查到，不从“单周期存取吞吐”推出一周期 load-use。[T] 用户手册 §2.2.4。 |
| e. 分支 | BJU 执行跳转，预测有 64 **Kb** BI-MODE BHT、1024项 BTB、256项间接预测、12层 RAS；注意 Kb 非 KiB。每组分支数与总误预测代价未查到；手册说 BJU 单周期处理错误，不表示从错误到正确指令 issue 只需一周期。[T] 用户手册 §2.2.3、§7.2.4–§7.2.8。 |
| f. 异常 / 中断 | ROB 按序退休，最多3条；异常可在早期识别但在对应指令退休边界响应，后续指令不能改变状态。手册另区分非精确异常，因此不概括为所有总线错误都精确。[T] 用户手册 §2.2.5、§5.1、§5.2.3。 |
| g. 性能 / FPGA | 本轮未查到能绑定开源这个 commit、编译 flags 和 FPGA 器件的 CoreMark/DMIPS/Fmax/资源；不引入商业宣传的其他 C910/910V 结果。[T] 所读 datasheet、用户手册未提供满足此条件的表。 |
| h. 许可 / 源码 | Apache-2.0；[固定源码树][T] `LICENSE`、`README.md:L60–L72`。 |

## 5. 商用顺序双发射参照

### 5.1 Arm Cortex-M7

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 取指 / 队列 | 6级、顺序双发射；64-bit instruction fetch、4×64-bit prefetch queue。队列按字计，不是固定8条 Thumb 指令。[Arm 原作者演讲][M7S] slide35；[M7] §1.2.2。 |
| b. 类型 / 配对 | 两 ALU（一个支持 SIMD）、单 MAC、单 divider；LSU 有双32-bit load channel、单64-bit store channel。支持 load/load 与 load/store 配对；DTCM 的两个 load 要地址 bit2 不同。ACTLR 的 DISISSCH1 可分别禁止 channel1 直接/间接分支、load-to-PC、MAC/MUL、VFP，表明这些类型可进入 channel1，不能把它简化为“槽1仅ALU”。完整合法配对表、除法和系统指令槽位未查到。[M7] §1.1、§1.2.1–§1.2.3、§3.3.1 表3-3；[M7S] slide36。 |
| c. RAW / WAW | TRM 明确 extensive forwarding；ACTLR.DISDYNADD 显示部分 ADD/SUB 可在 EX1 提前完成，禁用后都在 EX2。但同组 RAW 的完整可配对集合、WAW 处理本轮未查到，不以 extensive forwarding 推断任意同组依赖 ALU 都能发。[M7] §1.2.1、§3.3.1 表3-3。 |
| d. load-use | 双 load 通道和 store buffering 提升访存吞吐；有 flags 前递供早期 direct branch。统一 load-use 数字及普通 ALU 是否有与 SweRV 等价的 load→late-ALU 规则未查到。[M7] §1.2.2–§1.2.3。 |
| e. 分支 | channel1 可 direct/indirect branch；PFU 有 BTAC、可用静态预测，支持 decoder/first execution 早期解分支。BTAC容量、方向预测表规模、一组控制转移数与总误预测代价未查到于所读官方资料，不采信二手“2K BTB”等说法。[M7] §1.2.2、§3.3.1 表3-3。 |
| f. 异常 / 中断 | 所读官方资料给 NVIC 和异常架构；**双发射内部逐槽 exception/commit 规则未查到**，没有公开 RTL 可据此还原。不能以 Arm 的架构接口等同 EdRV32 槽1异常机制。[M7] §1.2.5、§2.7、§7.2。 |
| g. 性能 / FPGA | Arm 演讲 slide5 报 5 CoreMark/MHz：CoreMark1.0、IAR Embedded Workbench7.30.1，`--endian=little --cpu=Cortex-M7 -e -Ohs --use_c++_inline --no_size_constraints`，代码/数据都在 TCM。满足完整 flags 的 DMIPS 与可综合软核 FPGA Fmax/资源未查到；演讲工艺指标是 ASIC。[M7S] slide5–6。 |
| h. 许可 / 源码 | 商用 Arm IP，所读 TRM 为 Arm 版权文档；未查到公开开源 RTL，不赋予其开源许可证。[M7] 版权页。 |

### 5.2 Arm Cortex-A53

| 项 | 事实及出处 |
|---|---|
| a. 流水 / 取指 / 队列 | 8级、顺序、对大部分指令对称双发射。[TI AM62Ax 数据手册][A53B] §7.2.1；[A53] §1.1。取指宽度、IB容量本轮在所读官方资料中未查到，未采用网络图流传的队列数值。 |
| b. 类型 / 配对 | TRM 确认 symmetric dual-issue of most instructions，未公布完整槽位矩阵。作为补充，**GCC 的编译调度模型**允许一般数据处理和 branch 与其他指令配对、LSU 不能两条同发；这只是编译器建模约束，不视为对全部硬件组合的证明。乘除、NEON、系统寄存器指令在物理管线的完整限制未查到。[A53] §1.1、§2.1.2–§2.1.3；[GCC A53 machine description][A53G] `cortex_a53_slot0/slot1`、`cortex_a53_ls_agen`、`cortex_a53_branch` 定义。 |
| c. RAW / WAW | 同组 RAW 特例与 WAW 处理本轮未查到可核对的公开官方表；不把“对称双发射”理解为依赖可同发。 |
| d. load-use | 统一 load-use、late ALU、地址提前生成的明确公开时序未查到。GCC 中指令 latency 是编译器调度模型，不在本文换算为硬件精确周期。 |
| e. 分支 | IFU：256项 BTAC（间接分支目标）、全局分支历史+3072项模式历史表、8项 return stack，另有单项 BTIC，可存两次 I$ fetch。槽位/每组控制转移数/误预测代价本轮未查到官方完整值。[A53] §2.1.1、§6.4.2。 |
| f. 异常 / 中断 | TRM 列 synchronous Data Abort 的故障地址与 asynchronous external Abort/SError；内部双发射逐槽退休细节未查到，不把异步 SError 强行归入精确槽1异常。[A53] §4 System Control 中 FAR_ELx/HCR_EL2 的字段说明，§5.4 External aborts。 |
| g. 性能 / FPGA | TI AM62x：DMIPS/MHz每核为3（表中四舍五入），1.2 GHz、GCC9.2、`-march=ARMv8 -O3`、Linux5.10，原表 DMIPS3557。CoreMark/MHz 未查到满足本轮条件的数值；TI 同页给的是 CoreMark-Pro，不换算。FPGA 上硬核工作频率也不作为 A53 软核 Fmax/资源。[TI][A53TI] §2.1 表2-1、§2.2。 |
| h. 许可 / 源码 | 商用 Arm IP，未查到开源 RTL；TRM 为 Arm 版权文档。[A53] 版权页。 |

## 6. 决策与影响

**本记录没有新增采纳决定。** 任务已明确的“槽1条件分支/JAL、一组最多一条控制转移”仍以现有设计决策为准。本报告不改变 cpu-spec、RTL 或验证方案。

后续如要把事实转成实现方案，需要分别说明发射槽和物理管线的年龄关系、跨槽前递的组合路径、异常提交边界、预测器每拍可更新几条。这些工作属于之后的方案评估和规格确认，不由本调研替代。相关已有实现分别见 §3.1 的共享单元路由、§3.2 的晚执行、§3.4 的组合前递/取消 scoreboard、§3.5 的 age 仲裁。

## 7. 状态与复核

- 状态：调研；只提交本报告。所读来源、commit、章节和源码行号在 §2–5；“未查到”表示本轮证据不足，不能理解为硬件没有该能力。
- 未产生额外保护、哈希清单或门禁；公开下载物不入库。对被调研核未运行任何编译或仿真。
- 文档检查：`git diff --check`；仓库既有风格/lint：`. ~/.local/opt/edrv32/env.sh && make lint`。结果：`make lint` 退出码0，31个RTL文件风格检查0告警，common目录的Verilator lint通过；`git diff --check` 通过。不因纯文档新增 RTL 定向测试。
- 本轮局限：商业核未公开完整 pairing 表；部分项目没有完整 benchmark flags 或明确 FPGA 资源边界；CVA6 论文、当前上游和其旧设计文档存在版本差异；EH2 PRM 的fetch-buffer抽象与aligner RTL暂存寄存器计数的对应关系未查清。上述差异均在对应核条目中保留，没有补造数字。

## 8. 汇总对比与 EdRV32 损耗对应

### 8.1 一核一行汇总

缩写：IO=顺序发射；OOO=乱序发射；L/S=load/store；“—”表示本轮未查到。数字仍受前文配置条件约束，表内性能不用于直接排名。

| 核 / 版本 | 级数；取指；队列 | 发射与第二槽能力 | 同组 RAW / WAW | load-use 手段 | 分支与预测（容量） | CoreMark / DMIPS 每 MHz；FPGA | 主要来源 |
|---|---|---|---|---|---|---|---|
| EdRV32 v0.9 | 6；64b；IB4 | IO2；槽1 ALU | RAW拆对 / 年轻写优先 | 延迟2、旁路 | 槽0；一条；BTB32/gshare512/RAS4 | 3.585 O2、4.307 tuned / —；150MHz目标 | CPU规格§2/4；优化记录§1 |
| biRISC-V | 6/7；64b；2×双槽FIFO | IO2；B可ALU/branch/LSU/MUL | RAW拆对 / WAW拆对 | E2旁路，可配置 | 双发时仅B分支；BTB32/BHT512/RAS8默认 | 4.1 / 1.9；Artix7 >50MHz声明，精确资源— | §3.1 [B] |
| VeeR EH1 | 9；内部128b；3×128b fetch+IB4 | IO2 mostly；I1可LSU/MUL/branch，DIV/CSR I0 | 特定load/mul→ALU、ALU→store数据 / 年轻写优先 | EX4 secondary ALU、非阻塞load | 两槽分支；默认32/128/4，high_perf512/2048/4 | 4.9 / —；RVfpga Nexys A7工作50MHz，核资源— | §3.2 [E1][RV][RVP] |
| VeeR EH2 | 9；64b；RTL暂存4×64b、PRM3 fetch buffers（口径待对应）；IB4/线程 | 总IO2、可2线程；DIV/CSR I0，LSU/MUL共享 | 同线程特例 / 按tid年轻写优先 | secondary ALU、SMT、非阻塞load | 两槽有分支；默认512/512/4 | 6.3双线程合计模拟 / —；FPGA— | §3.3 [E2][WD] |
| CVA6 superscalar（S/S+/当前） | 6；64b；当前C开启时16取指项+双issue buffer | IO2、乱序完成；共享FU，CSR仅port0 | 2024拆RAW/WAW；S+及当前ALU级联/重命名 | scoreboard前递；HPDCache | 单branch FU；S+128×3bit私有历史；当前cv32a65x另配 | 2024 S4.35；2025 S3.41/S+3.69 / —；Genesys2，Fmax资源— | §3.4 [CS][CSP][C] |
| VexiiRiscv | 可变，示例6；典型64b；可选word buffer+dispatcher槽 | IO2；路由到非对称lane，双ALU/branch | 候选RAW/WAW阻塞 | 可选early/late ALU | 两lane branch；BTB512/gshare4KiB/RAS4 | 最高5.24/2.50；另一综合配置3.41/1.74、Artix7 140MHz/3247LUT | §3.5 [V][VD] |
| BOOM v3 Medium | 文档示例7；8B；FetchBuffer16/FTQ32 | decode2、IQ分INT2/MEM1/FP1 | 同decode建依赖 / rename | 动态调度、旁路 | branch mask；TAGE-L，完整容量— | — / —；FireSim F1 90+MHz（非绑定Medium资源） | §4.1 [O][OW] |
| NaxRiscv RV32 | 多流水，统一级数—；64b；IQ32（非IB） | decode2/issue3/retire2；2Int+共享LSU等 | 同decode建依赖 / rename | 3周期、hit预测、OOO | 2Int可branch；BTB512/gshare4KiB/RAS32 | 5.02 / 2.93；Artix7 -3 155MHz/13.3KLUT | §4.2 [N][ND] |
| XiangShan 南湖 | 11；32B块；IB—、ROB256 | decode6，具体FU总issue—；分布RS | 同decode建依赖 / rename | 4周期到ALU/LD、5到其他；OOO | ALU/MISC；uBTB/FTB/TAGE-SC/ITTAGE/RAS | — / —；FPGA— | §4.3 [X][XI] |
| OpenC910 | 9–12；最多8指令；IB32×16b片段 | decode3/execute8/retire3 | 同decode建依赖 / rename | 非阻塞LSU、OOO、预取 | BJU；BHT64Kb/BTB1024/间接256/RAS12 | — / —；FPGA— | §4.4 [T] |
| Cortex-M7 | 6；64b；4×64b预取 | IO2；channel1支持分支等，双load | 完整RAW/WAW规则— | 多旁路/双load；统一延迟— | BTAC，规模—；早期解分支 | 5（IAR7.30.1） / —；软核FPGA— | §5.1 [M7][M7S] |
| Cortex-A53 | 8；取指/IB— | IO2，多数指令对称；完整矩阵— | 细节— | 统一延迟— | BTAC256/PHT3072/RAS8/BTIC1 | — / 3（TI GCC9.2 O3）；软核FPGA— | §5.2 [A53][A53B][A53TI] |

### 8.2 与 EdRV32 损耗的对应

下表“代价”全部为**定性分析**，依据列出的硬件结构推导，未综合、没有 LUT 或频率收益承诺；只列观察到的做法，不作优先级或采纳建议。

| EdRV32 损耗 | 调研见到的做法 / 适用边界 | 可核对出处 | 实现代价（定性分析） |
|---|---|---|---|
| 槽1类型不支持 | 两槽均接条件分支/JAL，限制一组最多一条；biRISC-V 实际双发只允许较年轻槽分支，CVA6 是两个issue port共享一个branch FU，二者年龄约束不同 | [B] `src/core/biriscv_issue.v:L637–L647`；[C] `core/issue_read_operands.sv:L375–L403` | 增加第二槽分支能力或跨槽FU输入选择；需按年龄处理重定向，仍只需一组预测更新能力；不是必然需要两套预测器 |
| 槽1类型不支持 | 任一发射槽路由到**唯一** LSU/MUL；每组最多一个同类共享单元请求 | [B] `src/core/biriscv_issue.v:L704–L723`；[E1] `design/dec/dec_decode_ctl.sv:L1467–L1476` | 专用运算单元不复制，但需操作数/结果选择、槽标签和第二槽访存异常，验证范围超过纯ALU/分支扩充 |
| 槽1类型不支持 | 动态把较老/较年轻候选映射到兼容的非对称物理lane，优先使用不占LSU的ALU层 | [VD] `source/VexiiRiscv/Decode/index.rst:L66–L97`；[V] `src/main/scala/vexiiriscv/schedule/DispatchPlugin.scala:L408–L446` | 增加候选选择和宽数据mux；年龄不再由物理lane隐含，flush/trap/提交需显式年龄仲裁 |
| 组内RAW | 同拍 ALU0结果直接送 ALU1；CVA6 当前排除两侧 CPOP/CPOPW，其余仍受FU条件限制 | [C] `core/issue_read_operands.sv:L305–L312,L633–L655`；`core/alu_wrapper.sv:L42–L67`；[CSP] §2 | 连续两个ALU组合路径及输入选择，可能影响Fmax；属于数据路径级联，不能仅删RAW比较逻辑 |
| 组内RAW | load/MUL→晚ALU 同组发射，消费者到 EX4 才计算；**没有放开普通 ALU→ALU 特例** | [E1] `design/dec/dec_decode_ctl.sv:L1833–L1846`；[E2] `design/dec/eh2_dec_decode_ctl.sv:L2388–L2399` | 增加late ALU与晚前递、操作数使用时刻跟踪；相关链可能被拖到后段，branch/后继消费者时刻也变化 |
| 组内RAW | 单独处理 ALU→store-data RAW，地址无相关时允许同组，用晚store-data旁路 | [E1] `design/dec/dec_decode_ctl.sv:L1841,L1851–L1858`；[E2] 同模块 `L2396–L2405` | 将store地址与数据依赖分开；新增数据携带/旁路和异常冲刷验证，不能消除store地址RAW |
| 组内RAW | OOO在同decode包中建立物理依赖，独立指令越过未就绪指令；不是依赖指令同拍执行 | [O] `docs/sections/rename-stage.rst`；[ND] `source/NaxRiscv/frontend/dispatch.rst:L9–L17` | rename、物理RF、IQ唤醒选择、ROB及恢复；超出固定顺序双发射的局部改动范围 |
| load-use | 把能晚读操作数的 ALU 调到 late layer，early layer优先；不能晚执行的load地址/特殊指令仍停 | [E1] `design/dec/dec_decode_ctl.sv:L1795–L1802,L1904–L1928`；[VD] `source/VexiiRiscv/Decode/index.rst:L74–L87` | 增加后段ALU和跨层调度，旁路路径加长；需要证明晚执行的副作用、精确异常与后继消费者时序 |
| load-use | load→load/store 地址专用旁路、store-data 晚取数；分别放宽地址和数据的等待窗口 | [E1] `design/dec/dec_decode_ctl.sv:L1907–L1916,L1851–L1858` | 地址生成/LSU路径的新前递和独立hazard条件；针对确定消费者类型，非全局零load-use |
| load-use | 非阻塞load/D$，让独立工作重叠；EH2进一步用另一hart填空；Nax有load-hit预测 | [E1] `docs/source/low-level-core-control.md` “non-blocking loads”字段；[WD] EH2段；[ND] `source/NaxRiscv/performance/index.rst:L25–L28` | outstanding跟踪和返回匹配；若保持全部精确访存异常，不能照搬SweRV的非精确bus-error NMI；SMT另需每线程RF/CSR/前端状态 |
| 误预测 | 保留单branch FU但允许部分年轻指令随分支发射；分支失败时只取消年轻scoreboard项，取消项仍占到安全释放 | [CS] §3c；[C] `core/issue_read_operands.sv:L375–L395` | 每项cancelled位、年龄区间选择及迟到结果隔离；store等不可撤销操作另有限制 |
| 误预测 | 私有历史两级预测器；CVA6S+实验为128项×3-bit历史，Embench错误损失减少30% | [CSP] §2 | 历史状态、模式表与训练/恢复；总收益依负载，不把论文30%换成EdRV32周期收益 |
| 误预测 | 快/慢多级覆盖预测：香山uBTB先给目标，FTB/TAGE-SC/ITTAGE后续覆盖，保存历史供恢复 | [X] `frontend/bp/` “顶层模块/全局分支历史管理” | 多套表、FTQ、推测历史和覆盖恢复；远高于只扩BTB/gshare容量的结构改动 |
| 误预测 / 频率约束 | Vexii把BTB查询或branch到flush路径拆拍，明确用成功跳转多一拍/恢复更晚换Fmax | [VD] `source/VexiiRiscv/Performance/index.rst:L110–L120` | 加流水寄存器、调整预测元数据和冲刷延迟；必须同时比较每MHz性能与Fmax，公开材料不能证明适合PG2L200H |

[B]: https://github.com/ultraembedded/biriscv/tree/6af9c4be5a0807d368eaad5e49af52322e31d073
[E1]: https://github.com/chipsalliance/Cores-VeeR-EH1/tree/d04b1c7ae675a63dc4307cacfd10547ec937b928
[E2]: https://github.com/chipsalliance/Cores-VeeR-EH2/tree/32bdfe24c0194a5b625a70624144e4c6dec5f682
[C]: https://github.com/openhwgroup/cva6/tree/742dc82a0c706e0a3bfb98b709fd3ee06d50d12a
[CS]: https://arxiv.org/pdf/2410.01442
[CSP]: https://arxiv.org/html/2505.03762v1
[V]: https://github.com/SpinalHDL/VexiiRiscv/tree/d8b2775b903732c586f0c50efd651ee9b7f4e72c
[VD]: https://github.com/SpinalHDL/VexiiRiscv-RTD/tree/50fa0729d89cc63232b54db95e81224f2054f4d5
[O]: https://github.com/riscv-boom/riscv-boom/tree/ba03175e0a3cf5c0d5a7f14d385ac1c8998c4428
[OW]: https://boom-core.org/
[N]: https://github.com/SpinalHDL/NaxRiscv/tree/9f452d50560d02fb391bc8039f5453c54e0911af
[ND]: https://github.com/SpinalHDL/NaxRiscv-Rtd/tree/c27dcc26963f9f44675425068310702007fed16b
[X]: https://docs.xiangshan.cc/projects/design/zh-cn/nanhu/
[XI]: https://docs.xiangshan.cc/zh-cn/dev/integration/overview/
[XS]: https://github.com/OpenXiangShan/XiangShan
[T]: https://github.com/T-head-Semi/openc910/tree/b91c90914c19f114d35c8f6b73408eb241ed847c
[WD]: https://documents.westerndigital.com/content/dam/doc-library/en_us/assets/public/western-digital/collateral/tech-brief/tech-brief-western-digital-risc-v.pdf
[RV]: https://diposit.ub.edu/bitstreams/71880287-b56d-45a7-8b4a-eb7486f611b9/download
[RVP]: https://open-src-soc.org/2022-05/media/posters/4th-RISC-V-Meeting-2022-05-03-Daniel-Chaver-poster.pdf
[M7]: https://documentation-service.arm.com/static/5e906dc68259fe2368e2abbe
[M7S]: https://community.arm.com/cfs-file/__key/telligent-evolution-components-attachments/01-2142-00-00-00-00-59-23/ARM_5F00_Cortex_5F00_M7_5F00_MCU_5F00_Johnson.pdf
[A53]: https://documentation-service.arm.com/static/6040c321ee937942ba301626
[A53B]: https://www.ti.com/lit/ds/sprsp77a/sprsp77a.pdf
[A53G]: https://github.com/gcc-mirror/gcc/blob/master/gcc/config/arm/cortex-a53.md
[A53TI]: https://www.ti.com/lit/an/sprad45b/sprad45b.pdf
