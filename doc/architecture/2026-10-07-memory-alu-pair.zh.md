# 访存 A + 独立 ALU B：开发、测量与复现

## 基线

3.115 CoreMark/MHz、100 MHz 上板验证版本已保存为提交 `0209d89`，标签 `dual-issue-board-3115-20261007`。该版本的布线 setup slack 为 +0.152 ns，三轮 CRC 正确。标签保存了完整测试结果和上板证据；用户主 PDS 工程不参与本轮独立布线实验。

本轮保留单 LSU、顺序提交、四读两写寄存器堆和原有两级访存设计，仅扩大双发射的 A 类别：ALU、Load、Store 均可携带 B。B 仍必须是独立 ALU。Branch、Jump、MDU、CSR/Fence 保持单独发射。

## 实现与正确性边界

`edrv32_decode_stage` 增加主槽允许类别；同组 RAW、非 x0 WAW、B 的旧生产者未就绪、resident 生产者依赖、取指异常、非法指令、预测跳转、非连续 PC 和不同 epoch 仍禁止配对。Store 使用在 DECODE/EX 已确定的旧源值，B 写同一源寄存器的 WAR 合法。Load 结果不能在同组旁路到 B。

`edrv32_ex_stage` 让 ALU B 的结果跟随 Load/Store A 的 capture/transfer/kill；B 没有访存请求或独立异常通道。既有 MEM1 FIFO、MEM2 owner 和提交 pipe 传递整个包。

`edrv32_commit_stage` 只有在 A 正常退休时才允许 B 退休。A 的条件已包括 Load Queue/Store Queue 完成、阻塞/MMIO 事务完成、访存错误与中断检查。因此 Load 错误、Store 权限错误和中断都压掉两条指令的写回；中断在 A 之前，mepc 指向 A。正常 Store 保持已有缓冲提交和排空规则。后续指令可使用 B 的投机旁路值，但访存异常会清除整个年轻指令流。

没有新增 RTL 文件、FPGA IP 或 IP 配置；原有导入脚本已覆盖三个修改模块。

## 固定固件 CoreMark 仿真

GCC 15.2.0，RV32IMC，固定 i10 固件；每组运行三轮。下表使用第二轮 CSR mcycle 差值，避免把 testbench 观察窗口当作硬件计数窗口。

| 配置 | 优化 | 3.115 源码基线 | 访存配对 | 节省周期 | 周期减少 |
|---|---|---:|---:|---:|---:|
| 32 位取指 + 双 ALU | O2 | 3,375,287 | 3,308,581 | 66,706 | 1.98% |
| 32 位取指 + 双 ALU | O3 | 3,349,950 | 3,289,601 | 60,349 | 1.80% |
| 64 位取指 + 双 ALU | O2 | 3,202,529 | 3,120,522 | 82,007 | 2.56% |
| 64 位取指 + 双 ALU | O3 | 3,191,155 | 3,121,790 | 69,365 | 2.17% |

O2 每轮 instret 为 2,899,049，O3 为 2,944,145。所有 CRC 与基线相同；单发射及仅双窗口配置周期逐轮不变。这些是仿真周期收益，尚无本轮上板分数，不能把 i10 的收益直接当作板上 i4000 的分数。

## 为什么收益少于候选配对数量

在旧 64 位取指 O2 基线上，每轮约 275,992 个访存＋ALU 候选，其中 232,274 个通过原有冒险、连续 PC、epoch 和预测条件。旧版只因 A 类型不为 ALU 而拒绝这些机会。

新版本第三轮实际退休 Load＋ALU 157,033 组、Store＋ALU 72,411 组。配对会改变后续分组，不能直接把这 229,444 组算作等量节省周期。

第二轮观察窗口的全部 B 退休从 291,223 增至 449,903，净增 158,680，说明新增访存配对也替代了一部分 ALU＋ALU 配对。同一窗口中零退休周期从 594,724 增至 671,396，增加 76,672；两者相减得到观察周期减少 82,008。观察窗口与 CSR 窗口有一周期边界差，CSR 实测减少 82,007。

resident Load 依赖等待从 212,251 增至 282,488，增加 70,237。将原本隔开的 Load 和独立 ALU 合并后，紧随其后的消费者更早遇到仍停在 DECODE-to-EX 的 Load，而该位置尚未提供 Load Queue token 给消费者。现有设计等待一个周期，待生产者成为外部 EX/访存记录，再使用已实现的 Load 旁路。额外等待基本抵消了这部分配对机会。这比盲目增加第二个 LSU 更值得优先研究。

`FE_OTHER` 是零退休周期的兜底归因。旧版第二轮 344,092 次中，EX 有包 213,392 次、仅 DECODE 有包 96,942 次、仅 ALIGN 有包 33,718 次、这三个边界都空 40 次。这是边界占用分拆，不能直接当作每个模块造成的气泡。多数记录表示气泡正在流水线内传播；下一步需要沿生产者/消费者 PC 和 Load token 追踪其生成位置。

## 回归与复现

在 Linux 虚拟机执行以下脚本，均保存 source SHA-256、命令、种子和原始日志：

```sh
python3 sim/script/run_dual_issue.py --suite all --output ../directed-final
python3 sim/script/run_dual_isa.py --mode all --memory both --jobs 8 --output ../isa
python3 sim/script/run_dual_coremark.py --mode all --opt both --jobs 8 --output ../candidate
```

新增 `dual-memory-alu` 三个随机种子，以及 `dual-memory-precise` / `dual-memory-cached-precise` 共十二种精确异常和中断组合。所有旧用例保留。另以旧基线的三个 RTL 模块运行新用例做负对照，必须因未实际访存配对而失败，防止覆盖计数空跑。

虚拟机目录：`/home/edward/File/edrv32-mem-pair-20261007/`。本机证据目录：`out/audit/2026-10-07-mem-alu-pair/`。本轮测试和布线的最终状态见 `sim/regressions/memory-alu-pair-baseline.json`。

最终通过 **104/104 模块/定向、864/864 ISA/ACT、24/24 CoreMark**。三份编译源码清单均与工作区核对；四个继承的 CRLF/LF 差异经逐字节规范化确认等价，其余源文件 SHA-256 相同。原始源码、命令、镜像哈希、测试 manifest 和日志保存在 `source-and-results.tar.gz`。`baseline-tb_soc.sv` 保存了旧 RTL 使用的精确诊断 TB，哈希与基线编译记录一致。

## 100 MHz 物理验证

沿用现有 PG2L200H、-6、FBB676、100 MHz 约束及 IP 配置，执行独立 PDS compile/synthesize/dev_map/pnr/report_timing。最终 **All Constraints Met**，slow setup WNS **+0.184 ns**、TNS **0**、失败端点 **0**；slow hold **+0.146 ns**、fast hold **+0.101 ns**。报告 SHA-256 为 `66cbc76b7e2a6530d3115ca7c463396220f880650b1f76392d83a77313826f33`，路径为 `out/audit/2026-10-07-mem-alu-pair/pds/report_timing/edrv32_pango_200h_coremark_top.rtr`。

本轮未生成新板上成绩，也未下载到板卡。复现物理流程使用 audit 目录的 `run_timing.ps1`；必须先创建 `-work_dir` 指定目录，否则 PDS 会退回当前工作目录。本轮首次流程因此在仓库根目录生成了自己的临时输出，结束后已归档到上述独立 PDS 目录；用户原 FPGA 工程不变。

## 后续方向

优先评估 resident Load 的消费者能否在 DECODE refill 时绑定正确的预分配 Load Queue token，再到 EX 捕获数据。必须保证两个同 rd Load 的年轻生产者优先、token 回收/复用、Load 错误、重定向与 IRQ 都正确。不能简单放开 `resident_blocked`，也不能以 EX 的地址计算结果充当 Load 数据。该改造独立于本轮访存配对，应单独测量、回归和检查时序。
