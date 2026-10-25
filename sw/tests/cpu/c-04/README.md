# C-04

time/timeh 只读返回外部64位 mtime_i。

档位：`smoke`（full包含smoke）。

检查：固定外部mtime_i检查两个半部，连续读取保持同值。

B1 激励：整个测试固定mtime_i=0x0123456789abcdef。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
