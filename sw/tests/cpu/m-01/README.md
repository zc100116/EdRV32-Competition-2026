# M-01

较老异常冲刷设备访问，禁止任何设备副作用。

档位：`smoke`（full包含smoke）。

检查：设备模型不得执行 forbidden_device_load/store/forbidden_immediate_store 的事务；handler 检查异常元组，年轻寄存器值不改变。

B1 激励：device_registers 为设备区域，记录读写次数均为0。

Spike：运行同一 B1 ELF，产生可供退休序列比对的提交日志；周期与 debug 检查仅 B1。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
