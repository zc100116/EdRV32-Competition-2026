# 卡25 N网口连接失败

## 结论

新版demo_npu.bin通过串口加载成功并运行，但本轮两次建立网口连接均未取得板端PEER确认。用户按建议重新下载卡23 N比特流并重新通过串口加载程序后，现象不变。失败仍处于ARP/对端建立阶段，未进入可验证的模型加载和图片推理；不能记为图片检测失败、也不能记为卡25批量修复已验证。

## 程序与现场

- 分支win/20261101-25-b3-sw，输入提交78e5a3de；沿用卡23比特流，无重新综合或生成IP。
- 程序tasks/win/20261101-24-b3-rnv/src/demo_npu.bin；串口COM7、115200。
- 最新串口seq8598–8616：Load bytes: 22468 segments: 1；Load result: PASS；Run: 0x10000000；Demo: demo_npu network image inference；Build commit: d5d16c34；NPU ID: 0x00060001；ETH ID: 0x00070001；Network: 02:45:44:52:56:32 192.168.1.10:5000; peer from PC UDP source；随后工具记录已发送连接请求。
- 日志中先前虽有模型3247136 B发送完成，但无EDNM: loaded或PEER确认。发送完成不是板端收到的证据。

## 网络观测

- PC有线网卡if5，Realtek Gaming 2.5GbE，Up、1Gbps，192.168.1.2/24。
- 选择的到192.168.1.10路由为if5、192.168.1.10/32、on-link、metric1。
- 两次检查邻居均为MAC 00-00-00-00-00-00、Unreachable。
- 首轮调用新版tools.board.uart_tool.resolve_arp('192.168.1.2')，得到ARP 192.168.1.2 -> 192.168.1.10: SendARP error 67。一次源地址绑定ping超时，ping仅辅助观察，不以无ICMP应答独立判定故障。
- 工具UDP监听192.168.1.2:6000，rx active=true、error=null，但PEER未建立，未出现新N数据。显示的10690包与最后接收时间来自此前会话，不能作为当前N网口连通证据。
- Clash/Mihomo TUN保持开启，未按卡中环境建议关闭（用户要求保留代理）。保留当时地址、路由和ARP原文，未擅自修改网络设置；不能仅凭TUN存在认定其为根因。

## 保存文件

首次状态及完整可取得工具缓冲保存在本目录根部；重新下载/加载后的状态、完整可取得缓冲、带时间/方向/hex的entries.json、网络配置/路由/ARP原文在retest/。

本轮没有替换为诊断程序，未在BIOS菜单2执行正式ETH加载或eth_probe，未取得抓包。卡25要求的BIOS诊断仍未完成；这是应用网口建立失败记录，不混写成一次新的BIOS网口烧录失败。没有确认板端未响应ARP的具体原因，保留现场供Claude进一步分析。
