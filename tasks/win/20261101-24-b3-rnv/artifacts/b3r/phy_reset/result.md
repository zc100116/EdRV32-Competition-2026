# 卡24 B3R：5次PHY复位接收测试

用户停止GUI UDP6000监听后，运行tools/board/eth_probe.py --local-ip 192.168.1.2 --listen 6000，每秒发送有效窗口3 UDP包。通过工具REST串口发送r；等待link=1 speed=1000 duplex=full；发送s，约10秒后再次s。未修改PHY延迟、RTL或IP，无全局复位。5轮结束后停止本次probe子进程，GUI串口保持连接；GUI网口监听未重启。

| 轮次 | 实际串口间隔(s) | PERF1起→止 | PERF1增量 | PERF3增量 | 结果 |
|---|---:|---|---:|---:|---|
| 1 | 10.084 | 2 → 12 | 10 | 0 | PASS |
| 2 | 10.090 | 12 → 22 | 10 | 0 | PASS |
| 3 | 10.103 | 24 → 34 | 10 | 0 | PASS |
| 4 | 10.143 | 35 → 45 | 10 | 0 | PASS |
| 5 | 10.135 | 45 → 55 | 10 | 0 | PASS |

结果5/5 PASS，各轮PERF1增加10、PERF3增加0，达到PERF1增量≥8且PERF3不增加的判据。PERF5为过滤丢弃的其他帧，不能当成测试UDP丢包。原始probe收发见probe.txt，完整本轮串口与工具状态见uart/，逐轮原始计数见phy_reset_results.json。此结论仅覆盖当前bitstream的这5次PHY复位，不代替时序验收或BIOS网口下载测试。
