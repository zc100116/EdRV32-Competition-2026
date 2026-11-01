# 卡24 B3R BIOS网口加载失败

工具选择rnd_board.elf、网口、本机192.168.1.2。板端打印ETH link: up、ETH load ready 192.168.1.10:5000；随后主机ARP 192.168.1.2 -> 192.168.1.10: SendARP error 67。program.sent=0，程序镜像未开始发送，不能以此前应用5/5 PHY测试作为BIOS加载成功。

错误当时查询邻居为if5、192.168.1.10、00-00-00-00-00-00、Unreachable。错误时工具状态和串口缓冲保存在本目录json中，未重试BIOS网口加载。地址/路由/ARP/neighbor命令输出是整理报告时的现状，不冒充报错瞬间抓包；当前neighbor查询未找到对象，命令退出码及报错已保留。未修改代理、TUN、路由或IP。

未取得pcap或BIOS会话独立原始字节记录；未执行BIOS专用probe3秒诊断（此前probe为eth_diag应用5轮，不能混用）。根因未定，失败照实回传；其余上板测试通过串口继续。
