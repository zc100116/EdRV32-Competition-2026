# VN ETH诊断阶段结果

115200串口加载卡43 eth_diag.bin成功（4277B），自动运行。2M切换后乱码、未完成加载，失败原文见../uart/eth_2mbaud_attempt.log。

PHY reset接收检查5/5通过，均恢复1000M全双工；PC192.168.1.2:6000每秒发一包，板端PERF1十秒增量要求>=8、PERF3不增长。

|轮次|PERF1增量|PERF3增量|结果|
|---|---:|---:|---|
|1|10|0|PASS|
|2|8|0|PASS|
|3|10|0|PASS|
|4|10|0|PASS|
|5|10|0|PASS|

eth_probe.log确认PC收到192.168.1.10:5000的EDRV32 DIAG回复，双向UDP已实测。未修改PHY delay、网卡IP、路由或Clash。探测进程已停止。完整串口见eth_diag_session.log。GUI/CLI网口加载尚未测试，不能把本次UDP收发通过写成网口烧录通过。

## GUI网口加载

115200串口控制、网口载入eth_diag.bin成功，programmedBytes4277、sent=total4325、error=null，自动Run0x10000000并输出EDRV32 ETH diagnostic。CLI独立加载正在等待用户BIOS复位，尚未给结果。

## CLI网口加载

独立uart_tool.py --eth --baud115200，COM7、本机192.168.1.2，加载本卡eth_diag.bin成功：Load bytes4277 segments1，Load result PASS，Run0x10000000，EDRV32 ETH diagnostic；随后链路1000M全双工。保留真实串口字节cli_eth_load.raw、解码文本.log和控制台.log。CLI已停止、COM7已交还GUI115200。

本次结论：PHY接收5/5；双向UDP通过；GUI网口加载1/1、CLI网口加载1/1，均自动运行；串口115200加载通过，2M加载失败（切换后乱码）。不把一次网口加载成功当成多次稳定性测试。
