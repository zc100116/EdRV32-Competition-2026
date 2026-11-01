# 厂商UDP基线准备

执行更新：用户要求把工作副本DEST_IP改为192.168.1.2，已完成。本轮后续监听192.168.1.2:8080；下文.105描述的是厂商原始配置，差异见user_requested_pc_ip_change.md。

原件：G:/claude code/EdRV32-Competition-2026/docs/board/pago_200/2_Demo/2_11_ethernet_test/2_11_ethernet_test。
工作副本：G:/codex_project/EdRV32-FPGA/EdRV32-ETH-VENDOR；完整复制129个文件约50MB至仓库外，未修改原件或副本RTL/FDC，未运行实现。

从顶层source/ethernet_test.v:24–28查得实际参数（顶层覆盖子模块默认）：
- 板端IP192.168.1.11，MAC a0:b1:c2:d3:e1:e1。
- 板端UDP端口0x1f90=8080，PC目的IP192.168.1.105，目的UDP端口8080。
- 注意子模块默认16'h8080并非本例程顶层实际端口；教程PDF176给出的e1:e1:e1:e1:e1:e1与当前顶层源码不同，以当前源码为准并记录差异。

PC有线网卡需要192.168.1.105/24，监听UDP8080；不要将SoC的192.168.1.10:5000/PC6000参数用于此例程。准备阶段没有修改当前PC地址；到测试A时再配置，保留TUN既有要求。

支持ARP和ICMP echo（教程PDF174及icmp.v），可ping192.168.1.11。eth_udp_test.v的发送状态机周期发送固定20字节：b'www.meyesemi.com   \n'，UDP_DEPTH=5、length=4*5。主机接收时记录包数、每包长度与内容是否吻合。

源码未找到把收到UDP负载回送到发送端的回环连接；接收信号仅输出至顶层的观察信号。不能将接收固定板端消息视为PC发包逐包回环，也不能据60秒收到约60条无序号固定数据精确计算每个网络丢包。PC→板侧可用ARP/ICMP做方向确认；UDP发包数与板端固定消息数分开记录。

教程2 PDF175–176/印刷168–169要求PC192.168.1.105、板端192.168.1.11，观察LED及Wireshark。教程为配套说明，MAC及模块描述与本地源码有差异，原文已保存tutorial_test_method.txt。

当前工作副本ethernet_test.pds已经标为PG2L200H-6/FBB676；ref_clock.idf仍标PG2L100H/FBG676，需要用户在目标工程按任务重新生成ref_clock，参数保持原件：125MHz输入、CLKOUT0 125MHz、请求30度、50%、内部CLKOUTF反馈、No Buffer。其余本例程模块保留，RTL和FDC不改。

尚未跑A实现或上板；站点、时序和60秒通信结果未取得。
