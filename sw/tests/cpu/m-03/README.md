# M-03

FENCE 等待写缓冲排空后提交。

档位：`full`。

检查：dc_fence_o 有效且完成前 fence_wait 不提交；after_fence 退休前写缓冲为空。

B1 激励：fence_store 写缓冲保留8周期再排空，dc_fence_done_i 等待排空。

Spike：运行同一 B1 ELF，产生可供退休序列比对的提交日志；周期与 debug 检查仅 B1。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
