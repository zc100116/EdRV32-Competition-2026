# M-04

执行旧代码后改写为返回42，FENCE.I 后必须执行新字节。

档位：`smoke`（full包含smoke）。

检查：程序检查旧值1、新值42；dc_clean_all_o 完成后才 ic_inv_o，I$无效完成后 FENCE.I 提交并从下一PC重取。

B1 激励：D$ clean 和 I$ invalidate 各延迟8周期。

Spike：运行同一 B1 ELF，产生可供退休序列比对的提交日志；周期与 debug 检查仅 B1。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
