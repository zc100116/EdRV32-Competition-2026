# 网口上板诊断

本程序只提供定位手段，不修改 RTL、FPGA IO 延迟或 PLL。SRAM 入口为
`0x10000000`，串口沿用 BIOS 当前波特率，输出为英文短行。程序先按 demo 时序
拉低 PHY 复位 10 ms、释放后等待 100 ms，再扫描 MDIO 地址 0–31 的 PHYID1/2。
非全零、非全一的 32 位 ID 视为响应，选择第一个响应地址；无响应时明确打印并使用地址 0。

打印 BMCR、两次 BMSR、ANAR、ANLPAR、1000BASE-T 状态和 RTL8211F PHYSR，
以及 page 0xD08 寄存器 0x11/0x15 的原值和 TXDLY/RXDLY 位；所有换页读写后回 page 0。
PHYSR 的 link/speed/duplex 分别取 bit2、bits5:4、bit3，依据
[RTL8211F 数据手册 8.3.18](https://dl.xkwy2018.com/downloads/RK3588/01_Official%20Release/04_Product%20Line%20Branch_NVR/02_Key%20Device%20Specifications/RTL8211F(D)(I)-CG_DataSheet_1.2.pdf)。

本机 MAC `02:45:44:52:56:32`、IP `192.168.1.10`、接收端口 5000。
WIN3 与 demo 一致：DDR 物理 `0x0a000000`，大小 64 KiB；发送描述符在
`0x0a100000`，发送数据在 `0x0a100800`，CPU 经非缓存别名写入并在提交前 fence。
每秒打印 link、speed、duplex、PERF0–8、PEER、STATUS、IRQ_STAT、ERR_CODE，
并用已有描述符路径发往 `ff:ff:ff:ff:ff:ff / 255.255.255.255:6000`。
UDP 载荷为硬件生成的 8 字节应用头，加 ASCII `EDRV32 DIAG <序号>`，序号从 0 起。
若前次发送仍忙，打印 `TX busy` 并保留其描述符与数据，状态采样继续；无重试或恢复。

## 上板步骤

1. 构建：`. ~/.local/opt/edrv32/env.sh && make -C sw PROGRAM=eth_diag -j1`。
   输出 ELF 和 `build/sw/eth_diag/eth_diag.bin`，不需要 SoC 仿真。
2. 进入 BIOS，经串口加载运行（网口尚未通，使用串口烧录）：

   ```sh
   py tools/board/uart_tool.py build/sw/eth_diag/eth_diag.bin --addr 0x10000000 --entry 0x10000000 --port COM3 --log build/board/eth-diag.log
   ```

3. 有线网卡配置 `192.168.1.2/24`，PC 运行探测脚本：

   ```sh
   python3 tools/board/eth_probe.py --local-ip 192.168.1.2 --board-ip 192.168.1.10 --port 5000 --listen 6000
   ```

   socket 只绑定指定本机地址，失败报错退出。探测包复用调试工具打包函数：
   WIN3、NOTIFY=1、OFFSET=0、1 字节零数据，允许板端学习 PC 的 IP 与端口。
   脚本每秒发送，逐包显示接收源与完整字节内容；Ctrl-C 停止。
4. PC 执行 `ping 192.168.1.10` 和 `arp -a`，同时记录串口计数器。
   ETH 只支持 ARP 和 UDP，不应答 ICMP；ping 超时本身不表示 ARP 失败，应看 ARP 表。
5. 串口依次按 `d` 试四种组合：`TXDLY/RXDLY = 0/0 → 0/1 → 1/0 → 1/1`，
   再按回到 0/0。每次只修改对应两位，然后 BMCR bit15 软复位、等自清，打印组合和
   实际读回值。等待 link 重新协商到 1000 后，比较同样时长内的计数增量、ARP 和广播。
6. `r` 重新执行硬件 PHY 复位并打印 PHY 寄存器（恢复 strap 设置，随后 `d` 从下一组合继续）；
   `s` 立即采样状态。默认不改延迟，第一次 `d` 才设置 0/0。

调试工具的所有网口入口都可填写“本机地址”，默认 `192.168.1.2`。显式绑定可避免
代理 TUN 或 WLAN 的源地址被系统路由选中；PEER 一致性检查使用此地址。
探测脚本与调试工具都占用 6000 时不能同时监听，按顺序使用。

## 判读表

计数器为累计值，切换延迟不会清零；比较固定观察时长的增量，而不是累计比例。

| 观察 | 优先排查 |
|---|---|
| MDIO 扫描无响应 | PHY 地址、复位或 MDIO 管脚；无有效响应时 link/speed 读数不能采信 |
| link=0 或 speed≠1000 | PHY、网线、PC 网卡或自动协商；本 MAC 只支持千兆 |
| PC 持续探测/ARP，但 PERF0 不增长 | RX 时钟、RXC 驱动的 PLL 或接收管脚 |
| PERF3 增量≈PERF0 增量 | 接收帧几乎全坏，优先查 RGMII 接收延迟 |
| PERF0 正常，但 PC 收不到广播或 ARP | 发送方向延迟或 TXC；结合 PERF8 与 PC 抓包区分 |
| PERF1/2 增长，PEER=192.168.1.2:6000 | 合法探测包已写入 WIN3，接收和对端建立成功 |
| PERF6 增长 | 接收窗口范围问题；核对 WIN3 地址/大小与应用头 |
| IRQ_STAT.ERROR 或 ERR_CODE 非零 | 对照 eth-spec 第 6 节检查 DDR AXI 读写错误 |
| TX busy 持续出现 | 前次发送尚未完成；结合发送时钟、TXC 和状态定位 |

固定 TXDLY，只改变 RXDLY：若 PERF3 比例明显降低、PERF1 和 PEER 开始更新，
说明接收相位更合适。固定 RXDLY，只改变 TXDLY：若 PERF1 维持正常而 PC 开始
收到广播、ARP 表开始出现板端 MAC，说明发送相位更合适。两边都要改才通时，说明
两方向相位共同影响链路。所有组合都无变化时，按 MDIO→link→PERF0→PERF3→TX
顺序缩小范围；不能仅凭这些计数判定硬件根因。软件延迟与 FPGA 固定 IO 延迟叠加，
不预设某一组合必然正确，记录四组实际读回值与观察结果再决定后续硬件调整。

## 验收记录

待本地构建、工具测试和截图检查完成后填写；实际链路与延迟组合需上板验证。
