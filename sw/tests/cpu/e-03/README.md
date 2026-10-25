# E-03

五种到达窗口的外部中断，处理程序记录 mepc 并检查无重复/遗漏。

档位：`full`。

检查：每个窗口恰好一次 MEI，mepc 指向未提交指令，程序总计数为5；除法及设备事务完成后才允许进入中断；miss/redirect 的中断优先级按4.4/4.5；B1 独立记录每个中断边界，核对 irq_record 中5组 mepc/mcause。

B1 激励：分别在 irq_ordinary M、irq_division 的 debug[25]、irq_device debug[26]、irq_dc_miss debug[28]、irq_redirect E 重定向同拍拉高 MEIP；每次 trap 入口清除 MEIP；设备/load 响应分别延迟20周期；device_registers 映射为设备寄存器。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
