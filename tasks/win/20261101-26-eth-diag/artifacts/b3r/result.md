# B3R诊断：初始接收错误，PHY复位后同延迟配置连通

用户已下载卡23 R比特流并串口115200加载eth_diag.bin。启动Load result: PASS、Run: 0x10000000，PHY addr0/1的ID为0x001c/0xc916，TXDLY=1 RXDLY=1；协商后1000Mbps/full。TUN保持开启，未修改RTL或应用。

| 阶段 | 10秒probe收到广播/条 | PERF0首→末 | PERF1首→末 | PERF3首→末 | PERF5首→末 | PERF8首→末 | 最后PEER |
|---|---|---|---|---|---|---|---|
| initial | 10 | 33→53 | 0→0 | 33→53 | 0→0 | 0→0 | 0.0.0.0:0 |
| phy_reset | 7 | 53→206 | 0→10 | 53→53 | 0→142 | 0→1 | 192.168.1.2:6000 |

初始阶段ARP表无板子MAC，PERF0与PERF3同增、PERF1/PERF8为0。发送r进行PHY硬复位，仍打印TXDLY=1 RXDLY=1，但之后PERF3不再增加、PERF1及PERF8增加、PC学到02-45-44-52-56-32，PEER成为192.168.1.2:6000。初始PHY reset与r均调用程序相同的PHY复位函数，这次恢复说明存在运行状态差异；不据此宣称根因已确定或r永久解决。

本轮结果与N的r复位后仍错误不同，不能将N的四延迟组合结果推广为“RXDLY=1必然失败”。当前R复位后已恢复有效UDP，本轮未继续切换四个延迟组合。PERF计数跨PHY复位累计，阶段首→末含probe及PC命令；PC命令前后值单独保存counter_samples.json。

arp -d仍因管理员权限不足被拒绝；原生程序输出逐项保存，没有将命令退出码0误当作删除成功。ping无echo不否认ARP/UDP连通，ICMP不在ETH接收支持范围。当前无Wireshark抓包，TUN未关闭。

启动日志及工具状态在本目录，两个阶段目录保存全部可取得的当段串口、probe TX/RX和原生ping/arp输出。V对照尚待用户下载比特流并加载同一诊断程序。
