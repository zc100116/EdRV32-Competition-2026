# B-06

冲刷路径分支不更新 BTB、gshare、GHR、RAS。

档位：`full`。

检查：记录 flushed_branch 被 kill 后不产生预测器更新；对照运行将 flushed_branch 替为等长 ALU，固定相同实际条件分支序列，probe_branch 预测和预测器状态应相同。

B1 激励：执行原始镜像和 patch 指定 PC 后的对照镜像各一次；对照仅把 flushed_branch 改为 addi x0,x0,0。

Spike：运行同一 B1 ELF，产生可供退休序列比对的提交日志；周期与 debug 检查仅 B1。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
