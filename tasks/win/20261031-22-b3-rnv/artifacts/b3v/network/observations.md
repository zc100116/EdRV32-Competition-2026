# V 网口测试：未通过，原因尚未闭环

## 串口/工具观测

- demo_vision 已运行，Scene=2；串口能接受 status，返回 Demo command: OK。
- 最初电脑 UDP6000 被 NI Citadel 4 Service (LkCitadelServer/lkcitdl.exe) 占用，工具报 WinError10048。按用户授权临时停止服务，启动类型未改。
- 电脑有线 Realtek 网卡配置为 192.168.1.2/24，不设网关，链路 Up、1Gbps。
- 监听 UDP6000 和发送 WIN3 完成，但板端 ETH peer IP=0x00000000、port=0；PEER 不一致，视频和 EDTM 都为0。发送成功只表示 socket 发送调用成功，不能证明报文到达板子。
- 20:12:55 的串口：ETH STATUS=0x00000002；VIN camera0/camera1/CH0 帧计数增长，CH0/CH2 overflow=0；Monitor sequence=18130，dropped records=18130。
- 后续记录 peer 仍为0，Monitor sequence/dropped records 同步增长。具体原文见 uart/serial_console_session.log；没有把该现象直接判为 DDR 故障。
- 最后保留的 status 显示 Output mode=0。不能仅以视频计数0判断输出设置有误，EDTM 同样未收到才是本轮网络现象的一部分。

## 代理排除调整（用户要求 Clash 保持运行）

- 初始自动选路曾选中 Mihomo 198.18.0.1。
- 在当前订阅规则前插入 IP-CIDR,192.168.1.10/32,DIRECT,no-resolve。
- 应用 config.yaml 的 tun.route-exclude-address 增加 192.168.1.10/32；运行配置同样更新。
- 使用 Mihomo 配置检查通过，经本地控制 API 热加载成功（HTTP204）；回读确认 rule 模式、TUN 仍启用、板子直连规则位于首条、TUN 排除包含板子地址。代理与TUN未关闭。
- 为板子添加了临时活动路由：192.168.1.10/32、以太网 ifIndex5、on-link、metric1；重启不保留。
- 配置后自动 UDP 源地址仍选为 WLAN 192.168.5.31，工具 expectedPeer 也变为该地址；显式 socket.bind(192.168.1.2) 可建立本地绑定。这不证明网口包已到板端。
- 板子邻居 MAC 未解析成功（曾出现 Unreachable/Incomplete）。有线配置、排除规则完成后仍没有成功的 PEER/EDTM 证据，不能将问题完全归因于代理或宣称修复完成。
- 规则、路由、工具源地址选择与板端 ARP/RX 链路需要后续联合定位。未进一步改 RTL、固定 ARP 或关闭代理。
- 不上传代理完整配置，避免包含订阅、节点与凭据；本报告只记录相关非敏感设置。

## GUI 烧录地址问题

截图中的 .bin 烧录/运行地址只有 placeholder，实际为空，导致 int('',0) 异常。
用户可手动在两栏填0x10000000；本地修复为两个实际默认值。
已加入 ProgramPanel 的回归测试，验证默认地址经烧录调用传给引擎，测试通过。实际程序加载功能与网口建立问题分别记录。

## 缺失证据

本轮未取得非空 EDTM CSV、网口视频或目标地址PEER成功确认。未取得逐项图像处理模式的完整主观结论，不宣称整个V验收通过。
