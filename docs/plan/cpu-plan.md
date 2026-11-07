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
| C-W5 | Windows：C-R8 后的 CPU 子系统 PDS 综合 + 布局布线（第四轮复测） | 用户 + Windows Codex | C-R8 | 时序报告 | 任务卡 `tasks/win/20261028-03-cpu-sys-synth-r4/`，win/20261028-03-cpu-sys-synth-r4 | [x] 2026-10-28：slow WNS −1.789 ns（118.3 MHz，上一轮 111.2），违例端点 7611；最差链 E 级 JALR/分支比较 → E 级重定向 → 前端 F2 恢复判定 → RAS/F1 PC 使能，16 级；报告 `docs/reports/2026-10-28-timing-cpu-r4.md` |
| C-P1 | 时序探针（设计记录 `2026-10-28-cpu-timing-closure.md` 第 5 节第 1 步，用户确认减为 3 个版本）：P1 RVC_EN=0 基线、P2 切断 R1、P3 再切断 R2–R4 并加 core 区域约束；每个版本记录性能代价（P1 实测，P2/P3 周期模型） | Codex · GPT-6.1 Sol | C-W5 | 3 个探针提交 lint 0 告警；报告 `docs/reports/2026-10-28-perf-cpu-probes.md` | task-cpu-probe（评估分支，不合入） | [x] 2026-10-28：P1 15d21f8、P2 2ec4170、P3 3615a7e；P1（RVC=0）实测 CoreMark/MHz 3.592 / 4.291 / 3.587 / 3.576（O2 比 RVC=1 高 1.1%，tuned 低 1.1%）；模型代价 P2 +2.7%/+3.6% 周期，P3 +21.9%/+19.3% |
| C-W6 | Windows：3 个探针版本各跑一次 PDS，导出全部违例端点分组 | 用户 + Windows Codex | C-P1 | 时序报告 | `tasks/win/20261028-04-media-cpu-probes/`（B 部分，与媒体模块合并为一张卡，用户要求），win/20261028-04-media-cpu-probes | [x] 2026-10-28：P1 129.1 MHz（WNS −1.078）、P2 134.6、P3（去区域约束）138.9；净性能 P1 最好或持平，B 类不采用；报告 `docs/reports/2026-10-28-timing-cpu-probes.md`，结论见设计记录 5.1 |
| C-R9 | 按 C-P1/C-W6 数据定清单后一次完成全部时序修改；删除 C 扩展（cpu-spec v0.13） | Codex · GPT-6.1 Sol；协调者逐行评审 | C-W6、用户确认清单 | 待定 | task-cpu-timing-r5 | [ ] |
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

## 7. v0.17（国赛：Fmax 与 IPC）

目标：cpu-spec v0.17、testplan v0.4。完成标准：B1 smoke 与本节新增测试通过；R-05 周期数 ≤ 模型值 105%；卡 59 CPU+L1 独立 150 MHz WNS ≥ 0。集成分支 `zc100116/cpu-n16`（b3 `e54e471e` + v0.16 + 评估模型）。

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| N-FE | 前端时序：F1 下一 PC 环、F2→IB、I$ tag→前端满足 4.9，周期行为不变 | Codex sol | — | 前端/预测器/I$ 单元测试、B1 smoke 子集、Yosys 级数参考 | task-cpu-n-fe | [x] e7fe212e：R01–R05 与 v0.16 周期完全一致，B1 40/40；Yosys F1 环仍 8 级、I$ tag→resp 5 级，待卡 59 |
| N-BE | 后端：寄存重定向、mul4、ALU 旁路环、D$ tag 后选择、扇出复制；再做 4.10 提前地址、4.11 LCB（分步提交） | Codex sol | — | 单元测试、B1 smoke 子集；各步 R-05 周期 | task-cpu-n-be | [x] 0c3ef8e0/c03b5f35/c04919db/66fd009d：R-05 1,955,141 / 1,900,245 / 1,900,158 / 1,900,158；提前查询读口冲突 34% |
| N-VERIF | B1 按 testplan v0.4 修改期望值并新增 B-10/B-11、A-01–A-04、L-01–L-03；B1 D$ 模型加提前访问 | Codex sol（独立验证） | 4.10 接口确认后做 A-02/A-03 | 在 v0.16 上新测试能运行；联调后全部通过 | task-cpu-n-verif | [x] 9897d4a5：v0.16 基线 39/47，8 项按 v0.17 期望失败；接线编译留 N-INT；R-05 上限待模型值 |
| N-MODEL | 周期模型按 v0.17 条款精确实现，给出 R-05 期望值；评估 tournament（计纠正气泡）、宏操作融合、串联 ALU 在 v0.17 上的净收益 | Codex sol | — | 模型定向测试；设计记录 | task-cpu-n-model | [x] f809053c：S2 1,868,156 / S3 1,867,923；推荐 tournament（+3.7%/+4.3%/+2.1%） |
| N-INT | D$ 提前查询副本 RAM（用户 2026-11-05）、删除 4.11 LCB（用户 2026-11-05）、合并 N-FE/N-VERIF、B1 按路模型、回归 | 复用 N-BE 终端（ctx_055d0565607f） | 以上 | 回归通过，R-05 达标 | task-cpu-n-be → cpu-n16 | [x] fcc983f3：B1 46/46、arch 63、单元 15 目录、R01–R05 通过；R-05 1,869,203（模型 S2 +0.056%），提前查询成功率 97.55% |
| N-PDS | 卡 59：v0.17 CPU+L1 独立 150 MHz 探针 | 用户 + Windows Codex | N-INT | WNS ≥ 0，或得到下一轮路径分类 | win/20261105-59-cpu-v017-timing-probe | [x] 110.9 MHz（WNS −2.350，7890 端点），低于 v0.16 的 124.9；结构估计比实测少 4–6 级 |
| N-FIX | v0.17 缺陷：寄存 D 重定向强制单发射时 d_swap 未同步，导致跳过 JAL（tournament 时序下由随机测试暴露） | Codex（N-TOUR 中发现） | — | cpu_v3s scenario21 修复前失败、修复后通过 | cpu-n16 6aae76e5/9cfd69a3 | [x] |
| N-TOUR | v0.18 tournament（用户 2026-11-05）：三张 LUTRAM 表、F2 纠正 1 拍、E 寄存训练 | Codex sol | N-INT | B1 47/47、R01–R05；R-05 1,807,583（模型 +0.33%，比 v0.17 少 3.3%） | task-cpu-n-tour b4fd7a63 | [x] |
| N-PDS2 | 卡 60：v0.18 CPU+L1 独立 150 MHz 探针，新 IP 2 个（local_history 256×10、tournament 1024×2） | 用户 + Windows Codex | N-TOUR | 频率 ≥ 卡 59 的 98% | win/20261105-60-cpu-v018-tournament-probe | [x] 109.0 MHz，卡 59 的 98.31%；v0.18 并入 cpu-n16（dc018e50） |
| N-T2BE | 时序第二轮后端（用户 2026-11-06）：级数工具对卡 59/60 校准、P1 E 判定只进寄存器、P2 M 停顿网络、P3/P4 D 级预译码与提前查询、P5 ALU 环、P6/P10 扇出；最后集成 N-T2FE | Codex sol（task_1b2c7ad2a925 / ctx_65c4e1f57c5e） | N-PDS2 | 工具实测级数；B1、R01–R05；R-05 增加 ≤ 1.5% | task-cpu-n-t2be | [x] N-T2BE2 5273bd6b → cpu-n16：11 单元、B1 48/48、R01–R05 通过，R-05 1,807,726（+0.008%）。第一轮 eaf250a8：校准工具 503c2ea2；P1 禁止路径 0 条；P2–P6 等价减级，R-05 不变（1,807,583）；残余进入 PDS 复核。v0.20 放宽 4.10（用户 2026-11-07）；N-T2BE2 task_f8d9c4473201 / ctx_c9f1881ca832：P4 按 v0.20、P10 副本、集成前端 |
| N-T2FE | 时序第二轮前端：P7 I$→F1、P8 F1→RAS、P9 F1 环、P10 前端扇出 | Codex sol（task_932990e44e9b / ctx_5fe7d53b009c） | N-T2BE 第 0 步工具 | 工具实测级数；前端单元、B1 | task-cpu-n-t2fe | [x] N-T2FE2 v0.19 已集成。第一轮 b8f07fb5：等价改动，R-05 不变，381 扇出降到 14；P7 13 级、P9 11 级仍超预算。v0.19 I$ 缺失重发和 IB 寄存余量（用户 2026-11-07）；N-T2FE2 task_f719f2ce321b / ctx_891757b8fb27 |
| N-CUT | 流水线切分评估（用户 2026-11-07）：C1–C6 及组合的三负载周期、频率上限 | Codex sol（task_94c390a9105b） | — | 设计记录 | task-cpu-n-cut → cpu-n16 | [x] `docs/design/2026-11-07-cpu-pipeline-cut-eval.md`；C4 约 0%，C1 +1.4%，C2 +1.3%，C3 +2.9%，C6 行预测 +2.3%，C5 移位 +7% |
| N-PDS3 | 卡 62：v0.20 CPU+L1 独立 150 MHz 探针，分组 P1–P10 | 用户 + Windows Codex | N-T2BE2 | ≥ 135 MHz，再冲 150 MHz | win/20261107-62-cpu-v020-timing-probe | [x] 134.8 MHz（WNS −0.752，3896 个端点）；剩余为 cache tag → LRU/有效位、D$ 数据 → E、F2 纠正 → F1、F2 → IB 预译码 |
| N-T3BE | 第三轮后端（用户 2026-11-07 选择"等价修复 + 切分 C1+C3"，目标 150 MHz）：起草 v0.21（M2 级、D1/D2），D$ 内部等价修复，F 类，实现后集成 | Codex sol（task_0b43cba72d51 / ctx_8d67795d602e） | N-PDS3 | 起草稿经审定；B1、R01–R05；工具级数 | task-cpu-n-t3be | [~] v0.21 切分草稿（M2、D1/D2）已经审定，但精确模型给出 CoreMark +11.2%，用户 2026-11-07 撤回（fa8aeb8f）。本任务改为只做等价修复并负责集成 |
| N-T3FE | 第三轮前端等价修复：F2 纠正 → F1、F1 环、I$ tag → 有效位/LRU、F2 → IB | Codex sol（task_f717515b3011 / ctx_e7dd11e97e61） | N-PDS3 | 工具级数；前端单元、B1、R05 | task-cpu-n-t3fe | [~] |
| N-WAYP | D$ 路预测原型 d0（用户 2026-11-07 选择'先 e，并行试 d0'）：预测路数据直通 E，下一拍校验后冻结修复 | Codex sol（task_f3fb445e93ee / ctx_d7e2804e22e7） | — | DRM → E 的工具级数，R-05 周期和失败率 | task-cpu-n-wayp（原型，不并入） | [~] |
| N-PDS4 | 卡 64：v0.21 CPU+L1 独立 150 MHz 探针 | 用户 + Windows Codex | N-T3BE | WNS ≥ 0 | — | [ ] |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-25 | v0.1 | 初稿 |
| 2026-11-05 | v0.x | 增加第 7 节 v0.17 待办 |
