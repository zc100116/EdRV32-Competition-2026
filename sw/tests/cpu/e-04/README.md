# E-04

MEI、MSI、MTI 同时等待时按标准优先级服务。

档位：`smoke`（full包含smoke）。

检查：软件按顺序检查三个 mcause 并返回原 mepc。

B1 激励：irq_priority_window M 入口同时置 MEIP/MSIP/MTIP；每次 trap 仅清除正在服务的中断源。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
