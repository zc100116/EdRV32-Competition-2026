# 任务卡 20261102-35-eth-isolate：网口问题定位（硬件还是软件），不重新构建

## 1. 目标

用现成的卡 24 B3R bitstream（含卡 30 的 RGMII 修复和卡 24 的 BIOS），**不综合、不布局布线**，通过一组对照实验，确定网口剩下的问题出在哪一层。

剩下的问题：
1. BIOS 网口烧录失败：BIOS 打印 link up / ready 后，PC 端 `SendARP error 67`、sent=0，邻居 Unreachable；
2. S3 的网口遥测（EDTM）records=0。

已经确认正常的部分：
- 板子的 PHY 和网线：厂商 UDP 例程 ping 5/5、UDP 60/60（卡 30 A）；
- 我们 RTL 的 RGMII 收发：卡 30 B3V 网口视频 30.5 fps、PHY 复位 10/10；卡 24 B3R `eth_diag` 5/5；
- 应用层收包：demo_npu 网口上传模型成功（卡 23）。

判断方法：硬件 ARP 应答在 BIOS 和应用中是同一套 RTL（`edrv32_eth_rx.v`/`edrv32_eth_tx.v`，ENABLE 后由硬件自动应答）。所以先在应用中 ping 板子，再在 BIOS 中 ping 板子，对照结果：

| 应用中 ping | BIOS 中 ping | 结论 |
|---|---|---|
| 通 | 通 | 硬件正常。BIOS 烧录失败出在 PC 工具的发送时机或 PC 网络配置上（软件/主机） |
| 通 | 不通 | 硬件 ARP 正常，BIOS 的初始化顺序有问题（软件） |
| 不通 | 不通 | 我们 RTL 的 ARP 应答有问题（硬件/RTL），用抓包确认板子有没有回 ARP |

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261102-35-eth-isolate`，在 result.md 中记录完整哈希。
- **bitstream**：卡 24 B3R 工程生成的 bitstream（Windows 本地，路径写进 result.md）。没有保留就停下告诉用户。
- **程序**：`tasks/win/20261101-24-b3-rnv/src/eth_diag.bin`、`s3.elf`。
- **工具**：`tools/board/uart_tool.py`、`tools/board/eth_probe.py`、调试工具（S3 遥测页）。

## 3. 环境

- PC 有线网卡固定为 192.168.1.2/24，板子为 192.168.1.10。
- **关闭 Clash/TUN 等代理和 VPN 的虚拟网卡**，或者确认 192.168.1.0/24 不经过它们。第 0 步要记录关闭前后的路由表。
- 能装 Wireshark 就用它抓有线网卡；不能装就用 Windows 自带的 `pktmon`（`pktmon start --capture --comp nics`，`pktmon stop`，`pktmon etl2pcap`）。
- 本卡不综合，可以和卡 34 同时进行。

## 4. 需要的 IP

无。

## 5. 操作步骤

所有 PowerShell 命令从仓库根目录运行，`COM3` 换成实际端口。每一步的命令输出、串口原文、抓包都保存（见第 6 节）。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-35-eth-isolate origin/zc100116/b3`。记录 `Get-NetAdapter`、`Get-NetIPAddress -AddressFamily IPv4`、`route print -4`、`arp -a`，以及 Clash/TUN/VPN 是否开着。开着就请用户关掉，再记录一次。 |
| 1 | 用户（U） | 下载卡 24 B3R bitstream。开始抓包（全程抓，直到第 4 步结束）。 |
| 2 | U + C | **应用中 ping**：KEY1 复位进 BIOS，串口 115200 烧录 `eth_diag.bin`（`--addr 0x10000000 --entry 0x10000000`）。在 eth_diag 中输入 `r`，等到 `link=1 speed=1000`。然后在 PC 上：`arp -d 192.168.1.10`；`ping -S 192.168.1.2 192.168.1.10 -n 10`；`arp -a -N 192.168.1.2`；`Get-NetNeighbor -IPAddress 192.168.1.10`。记录 ping 通几次、ARP 表里板子的 MAC（应为 02-45-44-52-56-32）。 |
| 3 | U + C | **BIOS 中 ping**：KEY1 复位进 BIOS，选 `2=ETH load`，等串口打印 ready。记录从 BIOS 开始复位 PHY 到 PC 网卡重新 link up 的时间（`Get-NetAdapter` 每秒查一次状态，或看 Windows 事件日志中的网卡断开/连接事件）。ready 之后：立即做一次 `arp -d 192.168.1.10` 和 `ping -S 192.168.1.2 192.168.1.10 -n 10`，记录结果；等 10 秒再做一次。 |
| 4 | U + C | **BIOS 烧录**：KEY1 复位，停在 BIOS 菜单（不手动选 2，工具会经串口自己选 ETH load），运行 `py tools/board/uart_tool.py tasks/win/20261101-24-b3-rnv/src/eth_diag.bin --addr 0x10000000 --entry 0x10000000 --eth --baud 115200 --local-ip 192.168.1.2 --port COM3 --log build/board/bios-eth-35.raw`，记录结果和报错原文。失败后不复位，等 10 秒，再 `ping -S 192.168.1.2 192.168.1.10 -n 10`、`arp -a -N 192.168.1.2`，记录板子此时是否已能应答。停止抓包。 |
| 5 | U + C | **S3 遥测**：串口烧录 `s3.elf`，打开调试工具的 S3 遥测页，运行 1 分钟。同时抓包，记录板子有没有发 UDP 包给 PC（源 192.168.1.10）、发往哪个 IP 和端口，以及调试工具监听的 IP 和端口。 |
| 6 | C | 从抓包中逐步整理：每一步中 PC 有没有发 ARP 请求、板子有没有回 ARP 应答（时间戳）、PC 网卡 link 断开和恢复的时间、BIOS 烧录时 PC 有没有发出 UDP 数据包。按第 1 节的对照表写出结论。 |

## 6. 产物

放在 `tasks/win/20261102-35-eth-isolate/artifacts/`：

| 产物 | 内容 |
|---|---|
| `net_state_<步骤>.txt` | 第 0、2、3、4 步的网卡/路由/ARP/邻居输出 |
| `uart/*.log`、`uart/*.raw` | 各步串口原文 |
| `ping_<步骤>.txt` | 各次 ping 原文 |
| `link_events.txt` | 第 3 步网卡断开/恢复的时间 |
| `capture/*.pcapng` | 抓包，只保留与 192.168.1.10 相关的包（过滤 `host 192.168.1.10 or arp`） |
| `capture_summary.txt` | 第 6 步整理出的时间线 |

## 7. 通过判据

本卡只定位问题，不设通过门槛。必须给出：第 1 节对照表落在哪一行，以及支撑这个结论的抓包时间线。所有数字取自命令输出、串口和抓包原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-35-eth-isolate 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| bitstream 路径 | |
| Clash/TUN/VPN | 开/关；关闭前后路由表是否变化 |

## 对照结果
| 场景 | ping 结果 | ARP 表中板子 MAC | 抓包：PC ARP 请求 / 板子 ARP 应答 |
|---|---|---|---|
| eth_diag 中 | | | |
| BIOS ready 后立即 | | | |
| BIOS ready 后 10 s | | | |

## PHY 复位导致的网卡断开
BIOS 选 2 之后网卡断开时刻、恢复时刻、ready 打印时刻。

## BIOS 烧录
| 项 | 结果 |
|---|---|
| 工具烧录结果、报错原文 | |
| 失败后 10 s 的 ping / ARP | |

## S3 遥测
板子是否发包、目的 IP/端口；工具监听 IP/端口。

## 结论（对照表哪一行）

## 问题与偏离
```
