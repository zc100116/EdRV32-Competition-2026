# 卡26：B3N/B3R网口诊断与B3V对照

- 分支：win/20261101-26-eth-diag；任务输入942ed9da。
- 沿用卡23三个本地比特流，不重新综合、不生成IP；路径与修改时间见artifacts/bitstream.txt。
- 三个工程均用卡23src/eth_diag.bin，串口COM7/115200，加载/入口0x10000000。
- Clash/Mihomo TUN全程保持开启；没有修改路由、网卡、RTL、应用或调试工具。

## 关键结果

1. N默认1/1下板→PC广播可达，但PERF0与PERF3同步增长，无有效UDP及ARP应答；r复位、KEY1复位重载、断电重启重载后仍复现。
2. N四组延迟中RXDLY=0的0/0、1/0组均产生有效UDP及ARP应答，PERF3不再增长；RXDLY=1的0/1、1/1组均接收错误增长。最后恢复0/0再次确认。此设置不是持久修复，重载程序时会PHY reset并恢复默认1/1。
3. R默认1/1初始同样接收错误；r复位后延迟仍为1/1，却恢复有效UDP、ARP与PEER。这是重要反例，不能将RXDLY=1写成所有工程必然失败的原因。
4. V默认1/1即正常：DIAG广播、有效UDP、ARP和PEER成立，PERF3=0。
5. 已将现象收敛到“接收帧校验/采样与PHY运行状态有关”的排查方向，但没有证明具体FCS错误、帧长错误、RX_ER、PHY复位时序或PLL锁定中的某一个为根因。TUN未关闭，因此也不能宣称已经完全排除PC侧影响。

## 汇总：阶段首样本→末样本

三个PHY均读到addr0/1、PHYID1=0x001c、PHYID2=0xc916；稳定后均为link=1、1000Mbps/full。表中PERF按阶段累计，不是ping独占流量。

| 工程/阶段 | TXDLY/RXDLY | 10秒probe RX/条 | PERF0 | PERF1 | PERF3 | PERF5 | PERF8 |
|---|---|---|---|---|---|---|---|
| b3n/initial | 1/1 | 10 | 37→37 | 0→0 | 37→37 | 0→0 | 0→0 |
| b3n/phy_reset | 1/1 | 8 | 37→70 | 0→0 | 37→70 | 0→0 | 0→0 |
| b3n/delay0 | 0/0 | 7 | 70→250 | 0→9 | 70→70 | 0→170 | 0→1 |
| b3n/delay1 | 0/1 | 8 | 252→284 | 9→9 | 70→102 | 172→172 | 1→1 |
| b3n/delay2 | 1/0 | 8 | 284→454 | 9→18 | 102→102 | 172→332 | 1→2 |
| b3n/delay3 | 1/1 | 8 | 457→475 | 18→18 | 102→120 | 335→335 | 2→2 |
| b3n/restored_delay0 | 0/0 | 7 | 489→663 | 18→27 | 134→134 | 335→499 | 2→3 |
| b3n/key_reset | 1/1 | 10 | 21→35 | 0→0 | 21→35 | 0→0 | 0→0 |
| b3n/power_cycle | 1/1 | 10 | 26→37 | 0→0 | 26→37 | 0→0 | 0→0 |
| b3r/initial | 1/1 | 10 | 33→53 | 0→0 | 33→53 | 0→0 | 0→0 |
| b3r/phy_reset | 1/1 | 7 | 53→206 | 0→10 | 53→53 | 0→142 | 0→1 |
| b3v/initial | 1/1 | 10 | 150→191 | 1→10 | 0→0 | 148→180 | 1→1 |

N组合0首次PC ARP从无有效MAC变为02-45-44-52-56-32、Reachable，PEER成为192.168.1.2:6000。后续延迟切换保留旧PEER及ARP缓存，所以是否恢复有效接收以PERF1和PERF8的新增长等证据判断，不仅看PEER。R复位后PC学到同一MAC，PERF1 0→10、PERF8 0→1；V初始PERF1及ARP应答也成立。

PERF3为FCS错/帧长非法/RX_ER的合计，不能单独称为“全部CRC错”；PERF5包括非本机帧、协议/端口不支持等过滤，ICMP不在支持范围。ping无echo不等于UDP/ARP不通；来自本机的Destination host unreachable也不是板子回复。

## 原始数据

每工程startup_entries.json/tool_initial.json/program_initial.json保存启动与状态；每阶段目录含uart.log、带序号/时间/hex的entries.json、pc_probe.txt、pc_ping_arp.txt、phase.txt及counter_samples.json。key_reset和power_cycle另保存重载日志。counter_samples.json中保存PC命令前后样本，便于与ping/ARP对齐。

- [N原始数据](artifacts/b3n/)
- [R结果及原文](artifacts/b3r/result.md)
- [V结果及原文](artifacts/b3v/result.md)
- PC接口、地址、路由、ARP及TUN状态：artifacts/pc_network_tun_on.txt。

## 采集限制与未执行项

- arp -d因需要管理员权限被拒绝，本轮没有提权；某些arp.exe仍返回exit0，原文已保留。后续ARP缓存不能证明每组新学习。
- N组合1/2/3的子PowerShell没有返回PC命令文本，组合2记录exit4294967295。这三组保留有效的probe和串口计数，但ping/arp原文未取得；后续改直接运行原生ping.exe/arp.exe，未补造缺失输出。
- RX计数按阶段采集，PHY重新协商会占掉部分10秒窗口，收到7–8条广播不用于推算稳态丢包率。
- R在r后已恢复，因此本轮未继续四组延迟扫描，明确记录这一偏离；V默认已通，未做额外复位/延迟修改。
- 按用户既有要求没有关闭Clash/TUN，卡26第5.4关闭TUN对照未执行。
- PATH及标准Wireshark目录未发现tshark/dumpcap，未取得第5.5抓包。
- 断电/下载操作由用户执行，报告按用户完成反馈归属。

本卡只回传观测数据，不判定整体验收通过，不把诊断中临时可通信写成原应用已修复。
