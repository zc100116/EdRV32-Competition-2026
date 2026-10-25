# C-01

全部列举 CSR 的复位、读写、WARL、只读别名与非法访问。

档位：`smoke`（full包含smoke）。

检查：程序逐 CSR 比较复位值与写回掩码，计数器冻结后检查64位和别名；mcycle/minstret 在首条软件读取前已前进，其复位零由B1在复位释放时检查；time/timeh由C-04覆盖；只读 CSR 写入和未实现0x7ff必须报mcause2且mtval为原指令。

B1 激励：初始 irq/mtime 为0；复位释放采样所有CSR reset包括 mcycle/minstret。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
