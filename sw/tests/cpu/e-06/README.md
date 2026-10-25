# E-06

WFI 在 MIE=0 被使能中断唤醒，MIE=1 时进入处理。

档位：`smoke`（full包含smoke）。

检查：第一轮唤醒不进 handler，第二轮恰好一次 MSI；两次必须观察 debug[29]、停止发取指，唤醒后继续。

B1 激励：两处 WFI 提交后等8周期置 MSIP；第一处 wfi_wake_zero 到达M时清除，第二处 trap 入口清除。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
