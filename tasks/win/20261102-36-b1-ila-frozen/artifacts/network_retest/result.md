# 卡36同批工具修复：GUI网口加载复测

代码0177990f，沿用卡24B3R比特流及eth_diag.bin，不重新构建。用户重启工具、进入BIOS菜单后，通过GUI同一REST入口选网口、115200、本机192.168.1.2、地址/入口0x10000000。

工具日志：ETH load ready → 等待网卡以太网就绪0.4s → Load bytes4157 segments1 → Load result PASS → Run0x10000000 → EDRV32 ETH diagnostic。program_status：sent=total=4205，programmedBytes4157，error=null。此为GUI网口加载1/1成功，不冒充新版CLI独立复测或多次稳定性回归。

本轮Npcap原始抓包bios_gui_fixed.pcap及packet_index.json保存ARP请求/应答、发往192.168.1.10:5000的镜像UDP。未关闭代理或修改网络配置，没有自行加入等待/重试；等待逻辑来自Claude下发的工具修复。旧卡35证据为ready后SendARP error67、没有请求出线；本轮等待后已真正发送并取得板端PASS，支持链路恢复时机修复有效。
