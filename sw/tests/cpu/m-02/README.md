# M-02

设备写非推送，响应前后续指令不得退休。

档位：`full`。

检查：posted_store 写响应前 after_device_store 及年轻指令不进入W；程序检查回读和后续计数。

B1 激励：device_registers 设备写响应延迟20周期；模型提交前不写寄存器。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
