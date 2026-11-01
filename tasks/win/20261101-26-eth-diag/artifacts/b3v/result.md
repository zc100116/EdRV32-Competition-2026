# B3V诊断对照

用户下载卡23 V比特流、串口115200加载同一eth_diag.bin，Load result: PASS，Run: 0x10000000。PHY addr0/1读到0x001c/0xc916，默认TXDLY=1 RXDLY=1，1000Mbps/full。

未执行额外PHY复位或修改延迟，10秒probe收到10条DIAG广播，PC学到02-45-44-52-56-32，PEER=192.168.1.2:6000。本采集阶段PERF0 150→191、PERF1 1→10、PERF3 0→0、PERF5 148→180、PERF8 1→1。计数首次样本已经在probe开始后，不把首值中的ARP应答从本轮中排除。

原始启动/加载日志、工具状态、probe收发、ping/arp原文及PC命令前后样本均保存。五次ping无echo不否认ARP/UDP连通；ICMP不在本ETH接收支持范围。arp -d被权限拒绝，不能凭退出码0认定删除成功。TUN保持开启，未取得抓包。
