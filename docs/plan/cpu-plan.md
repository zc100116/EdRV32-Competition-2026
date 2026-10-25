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
| C-R3 | 后端与顶层：D/E/M/W、配对、冒险和旁路、重定向、异常和中断、D$ 接口（3.3）、HPM、debug_o、退休追踪信号（3.4）；顶层 `edrv32_cpu_core` | Codex · GPT-6.1 Sol | C-R2 | lint 0 告警；能在 C-V2 的环境中跑通一个最简单的程序 | zc100116/task-cpu-datapath | [~] dispatch ctx_abec60409d26 |
| C-R4 | CPU 最小顶层：`edrv32_cpu_core` + I$/D$ + AXI64 引出，用于单独综合测 Fmax 和 LUT | Codex · GPT-6.1 Sol | C-R3、cache RTL | 能在 Verilator 中编译；导入脚本可以导入 | task/cpu-minimal-top | [ ] |

### 3.2 验证（独立的验证 worker，与 RTL 并行）

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| C-V1 | 参考模型和工具：配置 Spike（与测试环境内存映射一致）；RTL 追踪与 Spike 提交日志的比对脚本；riscv-tests 和 riscv-arch-test 的构建流程（含参考签名生成） | Codex · GPT-6.1 Sol | I-02、I-07 | 在 Spike 上跑通 rv32ui 全部测试并产生提交日志；比对脚本能发现人为制造的不一致 | zc100116/task-cpu-verif-ref | [x] 144949a，65 项 riscv-tests 与 92 份 arch-test 签名在 Spike 上通过 |
| C-V2 | B1 环境：I$/D$ 接口模型（可配置缺失、反压、错误注入）、内存模型、中断激励、退休追踪器、接口协议检查器 | Codex · GPT-6.1 Sol | I-03、cpu-spec 3.2–3.4 | 用一个只实现 3.2–3.4 接口时序的桩 core 自测通过 | zc100116/task-cpu-verif-env | [~] dispatch ctx_7585ec16e581 |
| C-V3 | 随机指令流生成器（4 种配置，可控相关密度和指令比例） | Codex · GPT-6.1 Sol | C-V1 | 生成的程序在 Spike 上运行正常结束 | zc100116/task-cpu-verif-rand | [~] dispatch ctx_662b637b928f |
| C-V4 | 定向汇编测试：验证方案 3.3 至 3.7 的全部测试项 | Codex · GPT-6.1 Sol | C-V1 | 每个测试在 Spike 上运行通过（中断类为自检） | zc100116/task-cpu-verif-directed | [~] dispatch ctx_fb2842ea164c |
| C-V5 | 覆盖统计：第 4 节的功能点计数器和覆盖报告 | Codex · GPT-6.1 Sol | C-V2 | 报告格式正确 | task/cpu-verif-env | [ ] |

### 3.3 评估（为规格定稿提供数据）

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 / 任务卡 | 状态 |
|---|---|---|---|---|---|---|
| C-E1 | ISA 评估：CoreMark 分别以 rv32im、rv32imc、rv32im_zba_zbb、rv32imc_zba_zbb、rv32im_zba、rv32imc_zba 编译，在 Spike 上统计动态指令数、代码体积、取指字节数 | Codex · GPT-6 Luna | C-V1、I-07 | 测量报告 `docs/reports/…-perf-isa-eval.md` | zc100116/task-cpu-eval | [~] dispatch ctx_741da2459d55 |
| C-E2 | 预测器规模：从 Spike 提交日志提取 CoreMark 的分支轨迹，用轨迹模拟器比较 BTB 16/32/64、gshare 256/512/1024、RAS 2/4/8 的误预测率 | Codex · GPT-6.1 Sol | C-V1 | 测量报告，含误预测率曲线 | zc100116/task-cpu-eval | [~] dispatch ctx_741da2459d55 |
| C-E3 | 配对机会统计：在 CoreMark 轨迹上统计不同配对规则（管线 1 是否支持分支、是否允许组内 RAW 等）下的可配对比例和各类失败原因 | Codex · GPT-6.1 Sol | C-V1 | 测量报告 | zc100116/task-cpu-eval | [~] dispatch ctx_741da2459d55 |
| C-W2 | CPU 最小顶层综合与布局布线：Fmax、LUT、关键路径、资源分布（Windows 任务卡） | 用户 + Windows Codex | C-R4 | 任务卡结果 | 待写 | [ ] |

### 3.4 联调、评审与定稿

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| C-I1 | 联调：RTL 与 B1 环境对接，跑 smoke；失败时判断属于 RTL 错误、测试错误还是规格歧义 | Codex · GPT-6.1 Sol | C-R3、C-V2、C-V4 | smoke 全部通过 | task/cpu-integ | [ ] |
| C-I2 | full 回归和覆盖收敛 | Codex · GPT-6.1 Sol | C-I1、C-V3、C-V5 | full 全部通过，覆盖报告中的功能点全部覆盖 | task/cpu-integ | [ ] |
| C-I3 | B2 环境（core + 实际 cache）和性能测试 R-01 至 R-05 | Codex · GPT-6.1 Sol | C-I2、cache RTL | CoreMark CRC 正确；测量报告 | task/cpu-perf | [ ] |
| C-A1 | 评审：流水控制、配对、冒险、重定向、异常部分由协调者逐行评审；其余部分交叉评审 | 协调者；Codex · GPT-6.1 Sol | C-R3 起，逐项进行 | 评审意见全部处理 | — | [ ] |
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
