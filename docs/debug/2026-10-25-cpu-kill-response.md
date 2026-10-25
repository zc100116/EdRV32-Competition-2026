# CPU/cache 同拍 kill 与响应联调

## 1. 现象

CPU B1 从桩 core 改接真实 core 后，Verilator 报 I、D 两条 `UNOPTFLAT`。
C-R4 的真实 core+cache 联编另发现 D$ `buffer_push`、`fence_done` 与槽 1 异常路径参与组合环。
协调者确认 cpu-spec v0.8、cache-spec v0.4 的新约定：kill 不屏蔽同拍响应，取消影响后续周期；core 不提交被取消的指令；槽 1 异常按配对规则不可达。

## 2. 复现

引入分支后的基线为 `6c67c51`，来自 main `f7a0ace` 的线性 cherry-pick。
初次真实 B1 联编日志为 `build/cpu/b1/c/compile.log`（后续编译会覆盖）；仿真器 Verilator 5.020。
运行环境：`. ~/.local/opt/edrv32/env.sh`。
复现真实 B1：`python3 tools/cpu/run_b1.py verif/block/cpu/isa-rv32ui-p-add-c/case.json`。
组合检查使用 C-R4 worktree 的 `rtl/soc/edrv32_cpu_subsys.v`，加本分支 `rtl/filelists/cpu.f`、`cache.f` 展开的源文件：`verilator --lint-only -Wall +define+SIM_MODE --top-module edrv32_cpu_subsys ...`。

## 3. 观察

- B1 I$ 模型的注册响应经 `!ic_kill` 屏蔽，真实前端的 F2 边界恢复根据响应生成 `ic_kill`。
- B1 D$ 模型的注册响应经 `!dc_kill` 屏蔽，访问错误响应在 core 中生成异常和 `dc_kill`。
- C-R4 报告真实 cache 同类路径，以及 `dc_commit -> buffer_push -> fence_done -> m_ready -> m_fault1 -> m_trap` 路径。
- 修复后 core+真实 cache 的 `-Wall` 联编日志 `build/cpu/subsys-lint.log` 为空，退出码 0。

## 4. 根因

响应源与响应消费者之间通过组合取消信号形成反馈，无法实现“响应引发取消，同时取消屏蔽该响应”。
原槽 1 异常路径还把 M 级准备条件带回异常优先级；但 cpu-spec 4.2 禁止可能异常的指令进入槽 1。

## 5. 修复

B1 和真实 cache 直接输出本周期已产生的响应；kill 在时钟沿取消仍在途的事务。
D$ 写缓冲 push 只依赖 commit 和事务状态，由 core 保证 commit 与 kill 不同拍。
删除 core 中槽 1 的 exception/cause/value 状态和 `m_fault1`；槽 0 异常仍在 M 精确处理。
前端现有 redirect/recover 时序优先清空缓冲并禁止写入响应；core 的异常/中断令 `m_commit` 为零，取消指令无写回。
B1 检查器按同拍取消的事务所有权检查，不要求响应组合消失。

## 6. 防回归

B1 接入真实 RTL，持续执行 I$/D$ 请求寿命、kill/commit 互斥、设备执行和 m_enter 检查。
E-01、E-08 注入访问错误，E-03 对缺失/设备/重定向窗口注入中断；U-11 复现 F2 边界恢复。
真实 cache 的既有 smoke/full 用例继续检查 kill 后续响应消失；不把同拍已产生响应视为违规。

## 7. 同类排查

检查了前端 response_accept、halfword 缓冲写入和 valid 清除的优先级，及 core 的 M 提交门控。
检查了 I$/D$ 的 hit、fill return、device return、store buffer 和维护完成路径。
