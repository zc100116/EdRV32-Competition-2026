# B1 功能覆盖（C-V5）

依据协调者分支的 cpu-spec v0.15 §3.4、§7.1–7.2 和 cpu-testplan §4。
`edrv32_cpu_coverage.sv` 在每个有效时钟沿统计，正常仿真结束时由 `final`
写出 `{"counts": {"覆盖项 ID": 非负整数, ...}}`，包含所有 70 个要求项（未命中为 0）。
默认输出 `build/cpu-coverage.json`；用 `+COVERAGE_FILE=<build/ 下的路径>` 为每次运行
指定独立文件。目录由调用者事先创建；无法打开文件会明确报错。
Verilator 的 `$fatal` 会直接终止进程，不保证执行 `final`；失败运行不用于覆盖合并。

从仓库根目录运行：

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/cpu/b1/selftest.py
python3 tools/cpu/coverage_report.py \
    build/cpu-b1/stress.coverage.json build/cpu-b1/hits.coverage.json \
    > build/cpu-b1/coverage-report.md
```

selftest 为每个场景指定独立的 JSON 路径。仅将成功仿真的文件作为报告输入；
多个文件的同名计数相加。报告标准输出为 Markdown 表，逐项给出 ID、要求、
命中次数、是否覆盖，每项命中至少 1 次才算覆盖。
有任何未覆盖项时退出码为 1，全部覆盖为 0；缺少必需字段等输入错误直接报错。
桩 core 不执行真实指令流，不能证明 CPU 功能收敛；桩报告存在未覆盖项、退出码为 1
是预期行为，不影响 B1 selftest 或 smoke 的成功判定。

| 覆盖类别 | 计数来源与单位 |
|---|---|
| 配对结果 | `trace_valid_w==3` 见证成功双发射，每次双退休记 1；另从 D 实际发射两条及独立能力解码分别统计互换/不互换；`debug_o[23:21]` 原因 1–4 每拍记 1（HPM 事件 5–8 的发射限定与优先级由 core 保证） |
| 旁路源 | E0/E1/M0/M1/W0/W1 × rs1/rs2 × 消费者槽 0/1，共 24 项；从 `trace_bypass_w` 的四个三位字段按源编码 1–6 统计 |
| 异常原因 × 槽位 | `trace_trap_w` 且 mcause 中断位为 0；槽 0 的 cause 0/1/2/3/4/5/6/7/11。槽 1 的 cause 0/4/5/6/7；同步 trap 且 M 组有一条提交为槽 1 异常，否则槽 0 |
| 重定向 | D 级用 `debug_o[17]`；异常/中断用 trap/cause；MRET/FENCE.I 用已退休原始指令编码（FENCE.I 按 opcode/funct3）；E 方向/目标分别用 `trace_redirect_cause_w` 编码 1/2（编码 3 不属于这两项） |
| 停顿 | load-use=`debug[24]`、除法=`debug[25]`、I$ 缺失=`debug[15]`、D$ 缺失=`debug[14]&&debug[28]`、设备等待=`debug[26]`；计数单位为周期；乘法用 `trace_stall_cause_w==2`；CSR 包含编码 3/4 |
| 中断到达 | MEIP/MSIP/MTIP 各自上升沿为一次到达，持续高电平不重计；分别交叉除法、设备等待、D$ 缺失、E/D 重定向；普通执行需有 D/E/M/W 有效或退休，且无上述状态、异常进入及 WFI 等待。多个特殊状态同拍可分别命中 |

覆盖模块接收 `debug_o`、规格 §3.4 的 trace、中断激励及环境派生的管线分配/槽号。
实际 core 接入时保留 TB 中这些显式连接。v0.6 新增的三个 trace 由协调者经用户确认，桩 core 以零值表示没有真实管线事件。

独立验证计数器和报告合并：

```sh
python3 verif/block/cpu/b1/coverage_selftest.py
```

该测试在 `build/cpu-coverage-selftest/` 生成**人工接口观测数据**，验证全部字段解码、
IRQ 持续电平与独立上升沿、逐项合并和退出码；它不是 CPU 功能覆盖，不得并入 CPU 回归报告。

## 真实 core 联调

`core.f` 通过 `rtl/filelists/cpu.f` 接入真实 core，使用
`edrv32_cpu_b1_core_tb.sv`；原 `files.f` 和桩 core 自测继续保留。
`m_enter` 取 `u_core.e_advance_w`，退休、旁路、重定向和停顿追踪均用显式层次引用。
生成器 `tools/cpu/generate_regress.py` 和 runner `tools/cpu/run_b1.py`
负责 test.yaml、软件构建、ELF 符号解析、plusarg 激励、追踪/签名比对。
定向检查由 `edrv32_cpu_directed_checks.svh` 完成：配对原因独立解码、24项实际旁路、
结果延迟、除法冻结、CSR序列化、独立退休/HPM计数、debug逐位比对和维护/设备时序。

中断到达分类使用 `irq_arrival_debug_i`：E-03 在环境拉高 IRQ **前一刻**保存真实
`debug_o`，避免组合中断优先级立即改变 debug 后丢失原窗口。此输入只用于五个 IRQ
到达覆盖项，其余计数继续读取实时 debug/trace；此环境修正已经协调者确认。
原桩和覆盖统计自测将实时 debug 连接到该输入。

## v0.15 directed tests

P-01 retains the 17×17×3 architectural type/relation matrix. The observer independently
decodes cpu-spec 4.2 capability, RAW, dual-control and either-slot CSR/system exclusion;
HPM failure priority is RAW > structure > type > IB-single (coordinator clarification).
P-02 requires each named pair to issue and retire together, including swapped ALU/load WAW.
P-03 retains all 24 bypass bins and adds eight swapped producer/consumer cases:
E1 ALU, E0 JALR link, M0 load, W0 multiply, each using rs1/rs2 and consumer slots 0/1.
E0 ALU and E1 load/multiply in swapped groups are unreachable by pipeline capability.
B-07 checks slot-1 direction/target redirects, old-slot commit, and no D$ request from
a flushed swapped load. Its stale target is created by changing the branch displacement
with a store and FENCE.I, preserving BTB state. B-08 checks a cold slot-1 JAL;
B-09 checks three double-control pairs: two HPM7 events; cold slot-0 JAL flush
issues only slot 0 and counts no pair failure (coordinator clarification). Redirect-to-target issue separation is
three clocks: E resolves one clock after issue (penalty 3), D on issue (penalty 2).
E-02 checks slot-1 mcause 0/4/5/6/7, architectural trap tuples and old-slot commit,
then simultaneous old-load/young-branch faults with old-slot priority. Injected D$
access faults use B1 self-checks; SPIKE_SMOKE skips those injections only.

Coverage adds pair.normal/pair.swap, five exception.*.slot1 bins and E-direction/
E-target/D redirects crossed with slot. No new core-only observation names are used.
Run locally with `flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke
--path verif/block/cpu -j 1`; old RTL is expected to fail v0.15 obligations.
