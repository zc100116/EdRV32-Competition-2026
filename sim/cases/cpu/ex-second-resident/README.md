# B 槽跨组寄存旁路与保留

运行：`python3 sim/script/run_dual_issue.py --case ex-second-resident`。

测试先通过真实 EX 输出 pipe 建立上一组 A=101、B=205 的结果；下一组 B 的数据输入使用毒化值，只能从指定的上一组寄存结果取数。

五个场景分别覆盖 lhs/rhs 来源 {A,B}、{B,B}、{A,A}、kill 后的恢复，以及上一组 A 为尚无 Load 数据的访存指令而 B 已产生 ALU 结果。每项先给出错误的父 PC，必须不捕获；再恢复正确 PC，在输出反压和本组 A 的 MDU 操作数等待期间捕获 B 的两个源。随后让上一组离开、毒化反馈数据，B 必须仍保留正确结果。MDU 数据到达后整组执行；kill 必须清除保留状态。

共 35 项检查。将 B 的保留寄存器写入值改为 `32'hdeadbeef`，本用例必须失败；本轮保留了该负对照的源码和日志。

整核 `dual-alu` 和 `dual-memory-alu` 另含确定性的 C.ADDI/C.ADD 序列，要求每个随机种子实际覆盖 B 的 lhs/rhs 来自上一组 A/B 的全部四个选择器，并逐条核对退休写回值。
