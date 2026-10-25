# Load/Store A + ALU B 的顺序参考模型

运行：`python3 sim/script/run_dual_issue.py --case dual-memory-alu`。
默认种子为 1、7、20261006；可用 `--seed` 固定复现。

复用 `dual-alu` 的逐指令退休参考模型，每条 A/B 分别检查 PC、指令、目的寄存器和写回值。
新增参考存储数组在 Store **退休**时更新，Load 从该数组取得预期值，最后核对实际存储器。
因此预期值不依赖 DUT 写入的存储器内容。

覆盖独立 Load/Store 配对、Load 后立即使用、同组 RAW/WAW 拒绝、Store 读取旧值而 B 覆写同一寄存器的 WAR、混合压缩指令、带符号/无符号字节和半字、随机取指和数据反压，以及 B 的后续消费者。每个种子必须实际退休 Load 和 Store 配对。

将三个改动的 RTL 文件恢复为 `dual-issue-board-3115-20261007` 时，本用例必须因缺少访存配对覆盖而失败。
