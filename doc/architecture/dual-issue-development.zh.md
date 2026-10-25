# EdRV32 双发射开发记录

最新阶段已允许 B 槽使用上一组 A/B 的寄存 ALU 结果，并在反压或 A 等待时保留操作数；同组 A→B RAW 仍拒绝。64 位取指 i10 O2/O3 周期在访存配对基础上再降 1.88% / 2.04%，累计相对 3.115 源码降 4.39% / 4.17%。105 次定向/模块、864 次 ISA/ACT、24 轮 CoreMark 通过；100 MHz WNS +0.212 ns、TNS 0。本轮未上板，具体结构、负对照及复现证据见 [B 槽跨组旁路记录](2026-10-07-b-resident-forward.zh.md)。

最新阶段已加入 Load/Store A＋独立 ALU B 配对，保留单 LSU 和顺序提交。固定 i10 固件的 64 位取指 O2/O3 周期再降低 2.56% / 2.17%；104 次模块/定向、864 次 ISA/ACT、24 轮 CoreMark 通过，100 MHz PDS WNS +0.184 ns、TNS 0。本轮尚未上板；已上板 3.115 基线保存为 `0209d89` / `dual-issue-board-3115-20261007`。实现、精确异常覆盖及复现证据见 [访存配对记录](2026-10-07-memory-alu-pair.zh.md)。以下按阶段保留历史记录。

已完成宽取指与 resident B 旁路阶段，接口、复现及 PDS 参数说明见 [宽取指记录](2026-10-07-wide-fetch.zh.md)。此前双 ALU 检查点为 `2e09af0`。本批已通过 89 次模块/定向、864 次 ISA/ACT、24 轮 CoreMark；O2/O3 周期比单发射降低 8.16% / 9.44%。

随后完成 100 MHz 物理时序修复：ALU/重定向选择、IF2 固定入队、ALIGN 循环队列及 MUL 寄存输入连接。最终 PDS WNS +0.152 ns、TNS 0，完整回归通过且所有 CoreMark 周期保持不变。当前板顶层默认打开双发射和宽取指，IP 配置不变；板上复测尚待确认。详细路径、各轮报告和新边界用例见上述宽取指记录的时序修复章节。以下默认参数与未布线状态属于各历史检查点。

14:56 上板复测已完成：100 MHz、GCC 15.2.0 O2、4000 次迭代，三轮 CRC 均通过，实测 3.115 CoreMark/MHz。热态周期 1284000785、instret 1159743496、CPI 1.107142044；相对单发射周期下降 9.95%、成绩提升 11.05%。原始串口输出、精确计算和整数显示差异见宽取指记录末尾。

2026-10-07 已实现第一版独立 ALU+ALU 双发射及双退休。`DUAL_ISSUE=1` 自动选择双窗口前端，启用 4R2W 寄存器堆、第二 ALU、两槽结果传递、年龄优先旁路、双写回和每周期 0/1/2 条退休计数。分支、访存、MDU、CSR 和系统指令仍单独发射。

开发分支为 `codex/dual-issue`；已上板单发射基线仍在 `single-issue-board-20261006`（`429b271`）。所有新配置默认关闭。每个阶段的源码和测试一起保存，当前阶段详见 [独立双 ALU 实现及验证](2026-10-07-dual-alu.zh.md)。

```sh
python3 sim/script/run_dual_issue.py --suite all
python3 sim/script/run_dual_issue.py --case dual-alu --seed 7 --wave
python3 sim/script/run_dual_isa.py --mode both --memory both --jobs 8
python3 sim/script/run_dual_coremark.py --mode all --opt both
```

本阶段已通过 82 次模块/定向、576 次 ISA/ACT 和 18 轮 CoreMark。O2/O3 热态周期分别降低 2.66% / 4.29%，修复了完整架构回归发现的 IF2 缺失 B 判断问题。

这四个入口分别覆盖定向/模块回归、逐条随机对照、冻结指令与架构测试、固定镜像 CoreMark。生成文件位于 `sim/build/`，源码和测试输入与 Git 版本关联。没有本阶段的 FPGA 布线或上板结果。

## 2026-10-06 前端阶段记录（b50bee8）

当前完成双指令前端阶段：IF2 可捕获两条完整的相邻指令，ALIGN 可同时解压并输出两条指令，两个边界各有四项本地寄存容量。整核 DECODE、EX、MEM1/MEM2 和 COMMIT 仍使用单发射接口，尚未完成双执行或双提交。

开发分支为 `codex/dual-issue`。已上板的单发射源码保持在标签 `single-issue-board-20261006`，提交 `429b271`。默认新参数为 0，固定镜像下默认配置的周期与单发射基线一致。

## 配置和模块

`edrv32_core` 和 `edrv32_cached_core` 增加 `FRONTEND_DUAL_WINDOW` 参数；SoC 顶层对应 `CPU_FRONTEND_DUAL_WINDOW`。参数值 1 选择新前端，并将输出按顺序交给现有单发射后端。

IF2 的 32 位返回接口保留。已有标量模式使用原来的两项 window 寄存器；新模式使用四项完整 instruction-window 寄存器，并允许在空间足够时捕获两条完整指令。压缩双指令可直接从一个返回块捕获，较长指令可从半字 FIFO 形成。

`edrv32_align_pair_stage` 独立解压两个 window，保留各自 PC、原始指令、错误、epoch 和预测信息。输入和输出的较年轻槽都不能越过较老槽推进。寄存容量判断不组合复用下游当周期释放的空间；pipe 模块只保存 valid 和 payload，队列控制在 stage 内。

新配置在预测已跳转、较老指令错误/非法、第二条未收全或顺序路径不连续时按单条接收。原 IF2 预测 redirect 和跨块 continuation 处理保留。64 位取指返回、双译码和资源配对判断尚待后续实现。

## 本阶段验证

| 验证 | 结果 |
| --- | --- |
| 原有回归 | 38 项通过 |
| 新配置回归 | 七种用例，随机用例各三种固定种子，合计 11 次通过 |
| 合计 | 49 次测试运行全部通过 |
| 连续双输出 | 压缩指令流连续 47 至 48 周期，每周期输出两条 |
| 边界 | 混合长度、跨块、不完整 B、背压、单条消费、错误、illegal、kill、reset、旧 epoch 和回绕均通过 |
| 整核边界 | CSR/trap、IRQ/fence.i、缓存 MDU RAW/IRQ 均通过 |
| CoreMark | O2/O3 × 两种前端配置 × 三轮，12 轮 CRC 和退休指令数全部正确 |
| RTL 风格 | 无新增检查问题；保留基线 core 中已有七项格式诊断 |

固定 10 次迭代镜像的第二轮结果：

| 镜像 | 原前端 | 双指令前端加标量后端 | 周期变化 |
| --- | ---: | ---: | ---: |
| O2 | 3,487,221 | 3,489,802 | 增加 2,581 |
| O3 | 3,523,737 | 3,506,524 | 减少 17,213 |

前端缓冲改变了发射时机和分支/背压交互，尚不能保证所有程序更快。这些数字是前端阶段的兼容性观察，不是完整双发射的收益，也没有新的物理时序或板上评分结果。

新 IF2 提供三位 `hpm_consume_halfwords_o` 观察单次 1 至 4 半字捕获，集成用例核对 3/4 半字事件。旧前端 HPM 的 1/2 半字事件尚未扩展为完整双指令计数，不能在新配置中沿用旧公式计算总消费半字；本阶段性能对照使用 mcycle/minstret。双发射后端阶段再统一维护发射、退休及供给计数。

## 复现和复盘

源码、用例、依赖模型、运行脚本和固定镜像一起纳入 Git。构建输出仍放在忽略的 `sim/build/`。参考结果保存在 `sim/regressions/dual-frontend-baseline.json`，包含源码 SHA256、通过项、随机覆盖计数和三轮 CoreMark 结果。

```sh
python3 sim/script/run_dual_issue.py --suite all
python3 sim/script/run_dual_issue.py --case dual-frontend --seed 7 --wave
python3 sim/script/run_dual_coremark.py
```

详见 [前端用例说明](../../sim/cases/cpu/dual-frontend/README.md) 和 [CoreMark 对照说明](../../sim/soc/dual-frontend-coremark/README.md)。每次回归生成独立 manifest 和日志，不覆盖前次记录。新源码修改后重新运行，不把旧二进制或旧日志作为新版本结果。

## 下一阶段

定义有序 A/B 两槽的 DECODE 到 EX 契约，实现 4R2W 寄存器堆和独立 ALU 配对，再打通双结果保存与双提交。原流水级保留对 LSU/MDU token 和唯一 COMMIT 副作用所有者的管理。

先覆盖 RAW/WAW 拆分、合法 WAR、x0、写回到四个读口、B 保持后变成 A、双槽异常抑制和单/双提交。随后扩展 B 分支和任一槽选择共享 LSU，再评估晚消费者。按阶段增加用例，持续保留单发射配置的对照入口。
