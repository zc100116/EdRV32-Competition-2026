# CPU 实施方案（P1）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-25 |
| 对应规格 | `docs/spec/cpu-spec.md` v0.2 |
| 对应验证方案 | `docs/testplan/cpu-testplan.md` v0.1 |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 目标和完成标准

实现 `edrv32_cpu_core`，与 cache 集成后跑通 CoreMark，并定稿 CPU 规格。完成标准：

- 验证方案的 smoke 和 full 档位全部通过，覆盖报告中的功能点全部覆盖。
- 与实际 I$/D$ 集成（B2 环境），CoreMark CRC 正确，记录 CoreMark/MHz。
- CPU 最小顶层在 PDS 上完成综合和布局布线，记录 Fmax 和 LUT。
- cpu-spec 第 9 节的 [待定] 项全部定稿，规格升级为 v1.0 并经用户确认。

## 2. 前置条件

- P0 中的 I-02（工具链）、I-03（回归框架）、I-04（风格检查）、I-06（公共原语）、I-07（软件骨架）完成。
- B2 集成和性能测试依赖 cache 实施方案中的 cache RTL 完成。

## 3. 待办清单

### 3.1 RTL（CPU RTL worker）

CPU 内部各单元之间的接口没有在规格中冻结，因此 RTL 由同一个 worker 按顺序完成。

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| C-R1 | 数据通路单元：译码器、RVC 展开、ALU、分支判定、寄存器堆（FF 4 读 2 写）、乘法器（APM 包装 + 行为模型）、除法器、CSR 文件；单元测试 U-01 至 U-07、U-10 | Codex · GPT-6.1 Sol | P0 | 上述单元测试通过；lint 0 告警 | zc100116/task-cpu-datapath \| [x] 1ae5b6e，协调者已评审（小问题并入 C-R2） |
| C-R2 | 前端：F1、F2、指令缓冲、BTB/gshare/RAS、I$ 接口（3.2）；单元测试 U-08、U-09 | Codex · GPT-6.1 Sol | C-R1 | U-08、U-09 通过 | zc100116/task-cpu-datapath \| [x] eee9e2d，U-08/U-09 通过；C-R2b 970412b，F2 误取恢复和 U-11 通过（前端逐行评审并入 C-A1） |
| C-R3 | 后端与顶层：D/E/M/W、配对、冒险和旁路、重定向、异常和中断、D$ 接口（3.3）、HPM、debug_o、退休追踪信号（3.4）；顶层 `edrv32_cpu_core` | Codex · GPT-6.1 Sol | C-R2 | lint 0 告警；能在 C-V2 的环境中跑通一个最简单的程序 | zc100116/task-cpu-datapath | [x] 2a95119，smoke 33/0，两种 RVC 冒烟程序通过 |
| C-R4 | CPU 子系统顶层 `rtl/soc/edrv32_cpu_subsys.v`：core + I$/D$ + cache_ctrl，引出两个 AXI64 主口和 APB；同时搭建 B2 环境和 R-01–R-05 运行入口（C-I3 的环境部分） | Codex · GPT-6.1 Sol | C-R3、cache RTL | 能在 Verilator 中编译；导入脚本可以导入 | zc100116/task-cpu-subsys | [x] 已合入 main（d411035），B2 严格 smoke 两种 RVC 通过，perf 7/0 |

### 3.2 验证（独立的验证 worker，与 RTL 并行）

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| C-V1 | 参考模型和工具：配置 Spike（与测试环境内存映射一致）；RTL 追踪与 Spike 提交日志的比对脚本；riscv-tests 和 riscv-arch-test 的构建流程（含参考签名生成） | Codex · GPT-6.1 Sol | I-02、I-07 | 在 Spike 上跑通 rv32ui 全部测试并产生提交日志；比对脚本能发现人为制造的不一致 | zc100116/task-cpu-verif-ref | [x] 144949a，65 项 riscv-tests 与 92 份 arch-test 签名在 Spike 上通过 |
| C-V2 | B1 环境：I$/D$ 接口模型（可配置缺失、反压、错误注入）、内存模型、中断激励、退休追踪器、接口协议检查器 | Codex · GPT-6.1 Sol | I-03、cpu-spec 3.2–3.4 | 用一个只实现 3.2–3.4 接口时序的桩 core 自测通过 | zc100116/task-cpu-verif-env | [x] e018b1c，桩 core 自测 6 正向 + 3 违规通过 |
| C-V3 | 随机指令流生成器（4 种配置，可控相关密度和指令比例） | Codex · GPT-6.1 Sol | C-V1 | 生成的程序在 Spike 上运行正常结束 | zc100116/task-cpu-verif-rand | [x] b202651，4 种配置 × 50 种子 × 有无 C 共 400 个程序在 Spike 上通过 |
| C-V4 | 定向汇编测试：验证方案 3.3 至 3.7 的全部测试项 | Codex · GPT-6.1 Sol | C-V1 | 每个测试在 Spike 上运行通过（中断类为自检） | zc100116/task-cpu-verif-directed | [x] 7444c0b，31 项定向测试，32 个配置在 Spike 上通过 |
| C-V5 | 覆盖统计：第 4 节的功能点计数器和覆盖报告 | Codex · GPT-6.1 Sol | C-V2 | 报告格式正确 | zc100116/task-cpu-verif-cov | [x] bab2da9，57 项覆盖计数与合并报告，桩 core 自测通过 |

### 3.3 评估（为规格定稿提供数据）

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 / 任务卡 | 状态 |
|---|---|---|---|---|---|---|
| C-E1 | ISA 评估：CoreMark 分别以 rv32im、rv32imc、rv32im_zba_zbb、rv32imc_zba_zbb、rv32im_zba、rv32imc_zba 编译，在 Spike 上统计动态指令数、代码体积、取指字节数 | Codex · GPT-6 Luna | C-V1、I-07 | 测量报告 `docs/reports/…-perf-isa-eval.md` | zc100116/task-cpu-eval | [x] 7584c11（分支 zc100116/task-cpu-eval，报告待合入） |
| C-E2 | 预测器规模：从 Spike 提交日志提取 CoreMark 的分支轨迹，用轨迹模拟器比较 BTB 16/32/64、gshare 256/512/1024、RAS 2/4/8 的误预测率 | Codex · GPT-6.1 Sol | C-V1 | 测量报告，含误预测率曲线 | zc100116/task-cpu-eval | [x] 7584c11（分支 zc100116/task-cpu-eval，报告待合入） |
| C-E3 | 配对机会统计：在 CoreMark 轨迹上统计不同配对规则（管线 1 是否支持分支、是否允许组内 RAW 等）下的可配对比例和各类失败原因 | Codex · GPT-6.1 Sol | C-V1 | 测量报告 | zc100116/task-cpu-eval | [x] 7584c11（分支 zc100116/task-cpu-eval，报告待合入） |
| C-E4 | 微结构优化方向评估：周期近似轨迹模型（与 C-I3 HPM 校准）评估发射交换、管线 1 支持分支、加宽取指/IB、预测器加大 | Codex · GPT-6.1 Sol | C-I3 | 测量报告 `docs/reports/2026-10-25-perf-cpu-uarch-eval.md` | zc100116/task-cpu-uarch-eval | [x] d5c75e3（已合入 main），模型校准误差 <1%；结论见设计记录 `2026-10-25-cpu-uarch-optimization.md` |
| C-E5 | 流水线损耗分解：V2 受限形式（一对最多一条控制转移）和 V2s+V5 补测、CPI 损耗栈、理想化上限、流水参数敏感性（误预测代价、load/乘法延迟） | Codex · GPT-6.1 Sol | C-E4 | 测量报告 `docs/reports/2026-10-25-perf-cpu-pipeline-analysis.md` | zc100116/task-cpu-uarch-eval | [x] b0353bb（已合入 main），88 项测量；V2s 1.042–1.045，V2s+V5 1.059–1.069 |
| C-E6 | 开源多发射 CPU 调研：顺序双发射核（biRISC-V、VeeR EH1/EH2、CVA6 双发射等）的配对规则、组内相关、load-use 隐藏、分支策略、性能数据；乱序核与商用核作对照 | Codex · GPT-6.1 Sol | — | 调研报告 `docs/design/2026-10-25-dual-issue-survey.md` | zc100116/task-cpu-dual-survey | [x] 9be707b（已拣入协调者分支），覆盖 11 个核 |
| C-E7 | 后段 ALU 评估（模型）：V2s 基础上 M 级后段 ALU，仅管线 1 / 两条管线、后段分支、store 数据晚旁路，各自与 V5 组合 | Codex · GPT-6.1 Sol | C-E5 | 测量报告 `docs/reports/2026-10-25-perf-cpu-late-alu.md` | zc100116/task-cpu-uarch-eval | [x] da0f078（已合入 main）；L2b+V5 相对 V0 1.156–1.193 |
| C-E8 | 乱序双发射周期模型评估（不写 RTL）：ROB/发射队列/误预测代价矩阵，与顺序 V2s+V5 及 C-E7 最佳配置对比；结果决定是否开发乱序 RTL | Codex · GPT-6.1 Sol | C-E5 | 测量报告 `docs/reports/2026-10-25-perf-cpu-ooo-model.md` | zc100116/task-cpu-ooo-model | [x] ed7dea6（已合入 main）；默认点相对 V0 1.108–1.275 |
| C-E9 | 顺序双发射极致评估（模型）：L2b+V5 基础上叠加发射交换、槽 1 访存/乘法路由、一对两条分支、乘法延迟 2、预测器再加大、后段 JALR 及组合 | Codex · GPT-6.1 Sol | C-E7 | 测量报告 `docs/reports/2026-10-26-perf-cpu-inorder-max.md` | zc100116/task-cpu-inorder-max | [x] 已合入 c590fd0（含后端 B9–B13） |
| C-Y1 | Yosys 结构性时序预估：LUT6 映射后的路径逻辑级数、高扇出网络、资源分布（cpu_core RVC 0/1、cpu_subsys、sys_subsys、测量顶层），作为每次 CPU 改动的对比基线 | Codex · GPT-6.1 Sol | — | 测量报告 `docs/reports/2026-10-26-timing-yosys-cpu.md` | zc100116/task-cpu-yosys | [x] 已合入 4fc3de8 |
| C-W2 | CPU 最小顶层综合与布局布线：Fmax、LUT、关键路径、资源分布（Windows 任务卡） | 用户 + Windows Codex | C-R4 | 任务卡结果 | `tasks/win/20261025-01-cpu-sys-synth`（与 S-P1 合并：IP 生成 + CPU+系统子系统测量顶层综合） | [~] IP 已生成、包装已适配；第二版任务卡已下发 |

### 3.4 联调、评审与定稿

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| C-I1 | 联调：RTL 与 B1 环境对接，跑 smoke；失败时判断属于 RTL 错误、测试错误还是规格歧义 | Codex · GPT-6.1 Sol | C-R3、C-V2、C-V4 | smoke 全部通过 | zc100116/task-cpu-integ | [x] smoke 135、full 820、覆盖 57/57；已合入 main（1c73c35） |
| C-I2 | full 回归和覆盖收敛 | Codex · GPT-6.1 Sol | C-I1、C-V3、C-V5 | full 全部通过，覆盖报告中的功能点全部覆盖 | zc100116/task-cpu-integ | [x] 同 C-I1 |
| C-I3 | B2 环境（core + 实际 cache）和性能测试 R-01 至 R-05 | Codex · GPT-6.1 Sol | C-I2、cache RTL | CoreMark CRC 正确；测量报告 | zc100116/task-cpu-perf | [x] 7c63c3b（已合入 main）：-O2 3.585、调优 4.307 CoreMark/MHz，IPC 约 1.03 |
| C-A1 | 评审：流水控制、配对、冒险、重定向、异常部分由协调者逐行评审；其余部分交叉评审 | 协调者；Codex · GPT-6.1 Sol | C-R3 起，逐项进行 | 评审意见全部处理 | — | [x] 协调者逐行评审 core，意见（FENCE.I 中断、记录字段命名、组合环、槽 1 异常）全部处理 |
| C-R5 | 时序优化：HPM 事件寄存一拍；前端取指缓冲改为环形结构 + 块元数据；MRET/WFI/FENCE.I 提交与 D$ 解耦 | Codex · GPT-6.1 Sol | C-W2 | 定向回归通过，CoreMark 不降；报告 `docs/reports/2026-10-26-perf-cpu-timing.md` | zc100116/task-cpu-timing | [x] 协调者逐行审查通过，CoreMark 周期不变；2026-10-27 与 C-R6 一起合入 main |
| C-R6 | 切断 D$ 命中到前端的组合路径：P1 访存错误不经 valid（cpu-spec v0.11、cache-spec v0.5）、P2 前端停顿不依赖本拍 M 等待、P3 E 级重定向在 M 停顿时先行、P4 D 级重定向在后级停顿时先行；Yosys 结构路径分析 | Codex · GPT-6.1 Sol | C-R5 | 同上，另有 D$→前端路径分析 | zc100116/task-cpu-timing | [x] 协调者逐行审查通过；全核最长 59→49 级、D$→前端 59→38 级（Yosys 参考）；残留 IB 空位同拍反馈；2026-10-27 合入 main |
| C-W3 | Windows 第二轮综合与布局布线（SRAM 8192×64、C-R5/C-R6 之后） | 用户 + Windows Codex | C-R6 | 任务卡 `tasks/win/20261027-02-cpu-npu-synth` A 部分结果回传（原 20261027-01 并入） | win/20261027-02-cpu-npu-synth | [x] 94.46 MHz（WNS −3.920 ns），14879 LUT；报告 `reports/2026-10-27-timing-cpu-sys-r2.md` |
| C-R7 | 第三轮时序优化（依据 C-W3 PDS 路径）：D$ 装载结果 → CSR 写数据 → 64 位计数器、E 级操作数 → 重定向（RAS、F1 PC、I$ 读使能）、F2 PC 扇出；只做周期等价修改，需要改周期行为的方案先 ask | Codex · GPT-6.1 Sol | C-W3 | 定向回归通过，CoreMark 周期不变；Yosys 对比；报告追加到 `docs/reports/2026-10-26-perf-cpu-timing.md` | zc100116/task-cpu-timing-r3 | [x] 2026-10-27 合入协调者分支（974e8ae 等 6 个提交）：CoreMark 四配置周期不变，block/cpu full 747 PASS；Yosys 最深 47→36 级，LUT 29817→29974；实际时序待 C-W4 PDS |
| C-D1 | unit/cpu_f2_recover U-11 失败（自 e3c67f4 起，main 也失败）：判定测试过时或 RTL 缺陷并修复，调试记录 | Codex · GPT-6.1 Sol | — | cpu_f2_recover smoke/full 通过，调试记录 | task-cpu-f2-recover | [x] 2026-10-28：测试模型过时（cpu-spec 4.4），只改 tb，RTL 未改；CPU 单元 19/19 PASS；调试记录 `docs/debug/2026-10-28-cpu-f2-recover-u11.md` |
| C-W4 | Windows：C-R7 后的 CPU 子系统 PDS 综合 + 布局布线，导出每个路径组的明细（第三轮复测） | 用户 + Windows Codex | C-R7、合入 main | 时序报告 | win/<任务号> | [x] 2026-10-28：slow WNS −2.324 ns（约 111.2 MHz，上一轮 −3.920 / 94.5），违例端点 9196/39621，fast 无违例；15426 LUT、8369 FF、26 DRM36K。最差链：E 级地址加法 → D$ PMA → `dc_req_ready` → E 级推进 → IB 空位 → 前端寄存器使能。报告 `docs/reports/2026-10-28-timing-cpu-r3.md` |
| C-R8 | 第四轮时序优化，允许改变周期行为（用户确认 2026-10-28）：IB 只写入本周期开始时的空位（cpu-spec v0.12 4.1）；`dc_req_ready` 不取决于请求地址、类型、大小，维护期间照常接受请求（cpu-spec v0.12 3.3、cache-spec v0.6 5.4）；IB 容量按 CoreMark 实测在 4–6 中选定 | Codex · GPT-6.1 Sol；协调者逐行评审 | C-W4 | CoreMark/MHz（SRAM -O2）≥ 3.45（比 3.557 最多低 3%），超出就停下汇报；U-08、MT-07 及受影响目录回归通过；Yosys 对比 | task-cpu-timing-r4 | [x] 2026-10-28：IB 保持 4 条；CoreMark/MHz 3.5529 / 4.3372 / 3.5493 / 3.5416（SRAM -O2 比 C-R7 低 0.11%）；回归 817 PASS；Yosys 最长 36→35 级，地址加法经 PMA 到 D$ RAM 读使能 15 级；协调者逐行评审通过 |
| C-W5 | Windows：C-R8 后的 CPU 子系统 PDS 综合 + 布局布线（第四轮复测） | 用户 + Windows Codex | C-R8 | 时序报告 | 任务卡 `tasks/win/20261028-03-cpu-sys-synth-r4/`，win/20261028-03-cpu-sys-synth-r4 | [~] 2026-10-28 下发（main 6a9cd92） |
| C-S1 | 规格定稿：依据 C-E1/E2/E3、C-W2、C-I3 的数据，确定第 4 节中的各项；删除 `RVC_EN` 等评估参数；cpu-spec 升级 v1.0，cpu-testplan 同步修订 | 协调者 + 用户确认 | 上述数据齐全 | 用户确认 v1.0 | — | [ ] |
| C-M1 | 合入 main，打里程碑 tag `m1-cpu-isa-pass` | 协调者 | C-I2，用户批准 | — | main | [ ] |

可以并行的波次：
- 波次 1：C-R1；C-V1；C-V2
- 波次 2：C-R2；C-V3；C-V4；C-E1、C-E2、C-E3（依赖 C-V1）
- 波次 3：C-R3；C-V5
- 波次 4：C-I1 → C-I2 →（cache 完成后）C-R4、C-I3、C-W2
- 最后：C-S1、C-M1

## 4. 规格定稿项

| cpu-spec 待定项 | 定稿依据 | 对应待办 |
|---|---|---|
| 1 C 扩展、2 Zba/Zbb | ISA 评估 + 资源代价 | C-E1、C-W2 |
| 3 管线 1 是否支持分支 | 配对统计 | C-E3 |
| 4 流水级划分、10 最高频率 | CPU 顶层综合、CoreMark 实测 | C-W2、C-I3 |
| 5 寄存器堆实现与旁路源 | CPU 顶层综合的关键路径和资源分布 | C-W2 |
| 6 load 结果延迟 | CPU 顶层综合的关键路径 | C-W2 |
| 7 乘法结果延迟 | CPU 顶层综合的关键路径 | C-W2 |
| 8 预测器规模 | 分支轨迹仿真 | C-E2 |
| 9 IB 容量 | 前端断流事件计数 | C-I3 |
| 11 写回错误中断的 PLIC 源号 | 用户确认 SoC 规格修订 | — |

定稿结论与开发初值不同时，由 RTL worker 修改实现并重跑 full 回归（对应待办在 C-S1 之后追加）。

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| CPU 顶层综合显示 150 MHz 下 6 级流水不够 | C-S1 时调整流水级划分或频率目标，追加 RTL 修改任务 |
| 双发射使 LUT 超出 10K 预算 | C-W2 后对照资源分布，优先简化旁路网络和配对逻辑 |
| Spike 在本机构建困难 | I-02 中解决；仍不行时另行讨论参考模型 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-25 | v0.1 | 初稿 |
