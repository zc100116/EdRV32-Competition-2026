# 访存配对的精确异常与中断

运行：

```sh
python3 sim/script/run_dual_issue.py --case dual-memory-precise --case dual-memory-cached-precise
```

两个 case 各执行 6 个 CASEID。直连版本检查 COMMIT 的阻塞访存事务；Cache 版本检查 Load/Store Queue 的 token、延迟响应、取消和已提交 Store 排空。Cache 响应使用可控模型；真实 Cache 与 AXI 集成另由 CoreMark 和 cached ISA/ACT 覆盖。

| CASEID | 条件 | 返回位置 |
|---|---|---|
| 0 | Load 响应延迟 12 周期后返回访问错误 | B |
| 1 | Store 响应延迟 12 周期后返回访问错误 | B |
| 2 | Load 配对进入 MEM2 时注入外部中断 | 重放 A、B |
| 3 | Store 配对进入 MEM2 时注入外部中断 | 重放 A、B |
| 4 | 未对齐 Load | B |
| 5 | 向 ROM Store，权限错误 | B |

每项要求实际捕获访存配对；晚到的错误和中断还要求 B 保留到 COMMIT。陷阱边沿两条指令不得写回，mepc 必须为 A，B 目标寄存器必须保持旧值。恢复后 B 只退休一次，后续消费者获得 B 的新值；中断 Store 只产生一次架构写请求。错误访问不得泄漏异常请求。

Cache Store 可以在已提交缓冲排空前退休，因此结束条件同时等待外部 Store 请求出现，不能仅检查尾部指令已退休。原始失败诊断和负对照日志保存在本轮 audit 包中。
