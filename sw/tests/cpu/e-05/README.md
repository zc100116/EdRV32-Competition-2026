# E-05

direct 入口、vectored 同步异常 BASE、外部中断 BASE+4×11。

档位：`smoke`（full包含smoke）。

检查：软件不同入口签名及 mcause 校验；B1 检查 trap 后首个取指 PC 等于 mtvec.BASE 或 BASE+44。

B1 激励：vector_irq_window M 到达时置 MEIP，trap 后清除。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
