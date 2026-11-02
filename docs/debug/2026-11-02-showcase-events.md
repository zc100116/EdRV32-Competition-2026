# Showcase 输入按下沿在消费前被覆盖

## 1. 现象
SoC 输入联调期间，主机调用序列确认一项输入交付缺陷：
事件等待应用处理期间，重复采样同一按键电平会清零按下沿。

## 2. 复现
环境：GCC 13.3.0、xPack GCC 15.2.0、Verilator 5.020；无随机激励。
修复前软件：`a5b1694a`；修复及回归：`9bcac9cc`；依据设计记录 showcase 4.1/4.2。
SoC 命令：`flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/soc/board_showcase -j 1`。
快速回归：`make -C sw/tests/sched test`；输入测试序列为 0 → ENTER → ENTER → 应用 dispatch。
将 input.c 的 `pending_pressed |=` 临时恢复为覆盖赋值后运行同一测试，断言失败（退出 -6）。
基线副本、失败日志在 `build/showcase/input-before.c`、`input-before.log`；不改生产代码。

## 3. 观察
旧实现每次通信服务都执行 `input_pressed = next_input & ~input_snapshot`。
第一次采样 ENTER 得到按下沿并置应用任务 INPUT 事件，第二次采样 ENTER 得到零。
通信优先级 0 可以连续运行；应用优先级 1 尚未读取时，其 INPUT 事件位仍保留。
重复采样的失败与修复证据分别在 `input-before.log`、`test-sched.log`（build/showcase/）。

## 4. 根因
事件位按 OR 保留，关联的按下沿却按采样覆盖；两者的消费时刻不一致。
主框架和应用共同读取 platform_pressed()，也不能让第一次读取就清除同一 step 的快照。

## 5. 修复
`sw/apps/showcase/input.c` 在通信采样时 OR 累积边沿；应用 dispatch 一次取出并清除待交付边沿。
主框架、NES 和图层在本次 step 内共享只读快照；按键电平保持既有完整状态协议。
纯输入交付逻辑与设备采样分开，主机直接编译实际生产实现，无寄存器或中断模拟替代实现。

## 6. 防回归
`sw/tests/sched/input.c` 验证重复采样不丢边沿、主框架/应用重复读一致、下次 dispatch 不重复交付。
还验证多个待处理按下沿和当前电平相互独立；覆盖赋值基线失败，修复实现 PASS。
SoC 用例保持按键至目标状态响应，再释放，并验证 NES 与系统状态应用往返。
最终 SoC 结果和实测时长以 `docs/reports/2026-11-02-showcase-core.md` 为准。

## 7. 同类排查
核对 main、NES、layers 的按下沿读取点：均使用同一 dispatch 快照；GUI 继续读取电平状态。
