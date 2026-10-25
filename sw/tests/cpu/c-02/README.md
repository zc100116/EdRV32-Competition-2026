# C-02

minstret 按双退休加2，CY/IR/HPM inhibit 独立停止并支持64位写入。

档位：`smoke`（full包含smoke）。

检查：程序验证冻结前后 CY/IR/HPM 保持不变；B1 在每个 dual-retire 周期确认 minstret 加2；独立累计 IR使能时的 trace_valid 数写 expected_instret；CSR写计数器与自动增加同拍时写值优先。

B1 激励：retire_disable 生效后，在程序读取前将独立退休计数写 expected_instret；观察CY/IR/HPM各自inhibit。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
