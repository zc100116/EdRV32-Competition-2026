# E-08

设备 store 响应错误的精确异常与年轻副作用取消。

档位：`full`。

检查：handler 比较 mcause=7/mepc/mtval；设备模型仅收到 fault store 一次且不产生成功写入，后续寄存器无访问。

B1 激励：device_error_store 的设备写响应延迟20周期后返回错误；device_registers+4 必须无写入。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
