# B-02

反复变化的 JALR 目标和故意不同于 RAS 的返回地址。

档位：`smoke`（full包含smoke）。

检查：jalr_target 至少一次目标错误 E 重定向；ras_wrong_return 的实际目标优先于 RAS 预测且年轻指令被冲刷。

B1 激励：无额外激励，I$/D$ 全命中。。

Spike：运行同一 B1 ELF，产生可供退休序列比对的提交日志；周期与 debug 检查仅 B1。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
