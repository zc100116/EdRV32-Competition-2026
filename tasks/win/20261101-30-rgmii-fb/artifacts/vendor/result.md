# A厂商UDP例程：PC目的IP改为.2后的测试结果

工作副本G:/codex_project/EdRV32-FPGA/EdRV32-ETH-VENDOR；目标PG2L200H-6 FBB676，ref_clock已按目标重新生成，保持125MHz输入/输出、请求30度、内部CLKOUTF反馈、外部反馈禁用。资料包原件未改。

用户明确要求修改工作副本DEST_IP，从192.168.1.105改为192.168.1.2，之后用户重新实现并下载。本次仅改PC目的IP，没有修改厂商RGMII/PLL/FDC。修改原文见user_requested_pc_ip_change.md及pc_destination_change.patch，实际顶层及FDC/config保存在source_used/。因此不能记为完全不改源码的厂商基线。

## 通信测试

- 本机192.168.1.2:8080，板端192.168.1.11:8080，MAC a0:b1:c2:d3:e1:e1。
- 源地址绑定ARP成功，ARP表学到上述MAC。
- 源地址绑定ping：5发5收，0丢包，均<1ms。
- UDP采集60.075920秒，PC发60包，收到板端60包，其中60包全部匹配固定20字节内容，异常包0。
- 内容hex：7777772e6d65796573656d692e636f6d2020200a，即www.meyesemi.com加3个空格和换行。
- 板端固定消息不含递增序号，源码也没有把PC收到的UDP负载回环。因此“发60收60”不是逐包echo验证，不据此声称PC的60条UDP全部被板端应用消费，也不能精确计算端到端UDP丢包率。ARP/ICMP双向及板端固定UDP在本次窗口内正常。

原始收发每包方向、相对时间、peer、长度、hex保存在pc_ip_2_test/packets.json和udp.log；ping、ARP原文及机器可读汇总在同目录。未取得pcap（本地未发现Wireshark/dumpcap）。Clash/TUN保持既有状态，无修改路由/网卡。

## 实现报告

所有阶段结束、原厂时序汇总All Constraints Met，原文见timing_summary.txt。厂商FDC没有RGMII输入/输出延迟约束，所以此汇总不等同于已证明RX采样裕量充分。PLL/全局缓冲的实际站点原文在clock_sites.txt；各阶段原厂报告、警告/错误/耗时节选在native_reports/、logs/和flow_summary.txt，已经更新为用户改PC目的IP后这一轮工作工程的结果。

当前A完成；B外部反馈IP、实现和上板尚未执行。没有把本次短时成功推广为全部工艺角或长期稳定性已验证。
