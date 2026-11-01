# 任务卡 20261101-26-eth-diag：B3N/B3R 网口不通的板上诊断

## 1. 目标

用卡 23 的 bitstream 和 `eth_diag.bin`，查清 B3N、B3R 上网口为什么时好时坏，B3V 作为对照。

已知现象：
- 卡 23 中，B3N 的应用网口曾经通过（YOLO 有回传），但 BIOS 网口烧录卡在 ARP，B3R 也没有建立 PEER；
- 卡 25 中，同一个 B3N bitstream 加上同样的软件，网口完全不通。PC 侧有线网卡显示 1 Gbps Up，但对 192.168.1.10 的 ARP 一直是 Incomplete / Unreachable，`SendARP error 67`；
- B3V 一直能通。

三者的软件网口初始化相同，ETH PLL 位置相同（GPLL_727_463），RGMII 收发都在 IO 内的 IDDR/ODDR 里完成。问题更像运行时状态（PHY 协商或复位、ETH PLL 重新锁定）或 PC 侧，而不是布局。本卡用计数器把问题分到下面三类之一：

| 现象 | 说明 |
|---|---|
| PERF0（收到的帧）不增加 | 板子收不到任何帧：PHY/RX 时钟/PLL |
| PERF0 增加，但 PERF3（FCS 等错误）同步增加 | 能收但采样错：RX 时序或 PHY 延迟设置 |
| PERF8（发出的 ARP 应答）增加，但 PC 仍 Incomplete | 板子已回应答，PC 没收到：TX 路径或 PC 侧 |

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交），拉出 `win/20261101-26-eth-diag`。
- **bitstream**：卡 23 的 B3N、B3R、B3V，不重新生成；记录路径和修改时间。
- **程序**：`tasks/win/20261031-23-b3-converged/src/eth_diag.bin`（入口 0x10000000）。它的功能：
  - 启动时复位 PHY，扫描 MDIO，打印 PHY ID、BMCR/BMSR、协商结果、`link/speed/duplex`、PHY 的 `TXDLY/RXDLY`；
  - 配置本机为 `02:45:44:52:56:32 192.168.1.10:5000`，打开接收和 ARP 应答；
  - 每秒向 192.168.1.255:6000 广播 `EDRV32 DIAG <n>`；
  - 串口命令：`s` 打印 PERF0–8、PEER、STATUS；`r` 复位 PHY 并重新打印；`d` 切换下一种 PHY 延迟组合（共 4 种）并打印。
- **工具**：`tools/board/eth_probe.py`（监听 6000）、`tools/board/uart_tool.py`。

## 3. 环境

- JTAG、USB 串口；PC 有线网卡 `192.168.1.2/24`，放行 UDP 6000。
- **Clash/Mihomo TUN**：先保持开启做 5.1–5.3；最后在 5.4 关闭一次做对照，做完可以恢复。
- 不需要 PDS 综合。

## 4. 需要的 IP

无。

## 5. 操作步骤

每一步都保存串口原文。PowerShell 命令从仓库根目录运行，COM3 换成实际端口。

### 5.1 B3N：失败现场采集

1. 下载卡 23 的 B3N bitstream，在 BIOS 中用串口烧录 `eth_diag.bin`：
   ```powershell
   py tools/board/uart_tool.py tasks/win/20261031-23-b3-converged/src/eth_diag.bin --addr 0x10000000 --entry 0x10000000 --baud 115200 --port COM3 --log build/board/c26-n-diag.log
   ```
   必须加 `--baud 115200`：卡 23 的旧 ROM 在默认的 2 Mbaud 下会乱码。加载完成后关闭 uart_tool，用调试工具的串口终端（115200）查看输出、输入 `s`/`r`/`d` 命令。
2. 记录启动时打印的 PHY 信息（PHY ID、link/speed/duplex、TXDLY/RXDLY）。
3. 另开终端：`py tools/board/eth_probe.py --local-ip 192.168.1.2 --listen 6000`。观察 10 秒，记录是否收到 `EDRV32 DIAG n`（能收到说明板→PC 方向通）。
4. 在串口输入 `s`，记录 PERF0–8。
5. PC 执行：
   ```powershell
   arp -d 192.168.1.10
   ping -S 192.168.1.2 -n 5 192.168.1.10
   arp -a -N 192.168.1.2
   ```
   再在串口输入 `s`，记录 PERF0–8 的变化。
6. 如果 ARP 仍不通：
   - 输入 `r`（PHY 复位），重复第 3–5 步；
   - 依次输入 `d` 四次，每切换一种延迟组合都重复第 3–5 步，记录每种组合下 ARP 是否通、DIAG 广播能否收到，以及 PERF 的变化。

### 5.2 B3N：复位方式对照

1. 按 KEY1 复位，重新用串口烧录 `eth_diag.bin`，做 5.1 第 2–5 步。
2. 断电重新上电，重新下载 bitstream，再做一遍。
3. 记录三种情况下网口是否通：刚下载 bitstream、KEY1 复位后、断电重启后。

### 5.3 B3R、B3V

分别下载卡 23 的 B3R、B3V bitstream，做 5.1 第 1–5 步（不通时也做第 6 步）。B3V 作为对照。

### 5.4 TUN 对照（一次）

关闭 Clash/Mihomo TUN，在 B3N 上重复 5.1 第 3–5 步一次，然后恢复 TUN。

### 5.5 抓包（如果可以）

在 5.1 第 5 步期间，用 Wireshark 在有线网卡上抓 `arp or udp.port == 6000`，保存为 pcapng，只保留这段时间的包。

## 6. 产物

放在 `tasks/win/20261101-26-eth-diag/artifacts/`：

| 产物 | 内容 |
|---|---|
| `bitstream.txt` | 三个 bitstream 的路径和修改时间 |
| `<b3n|b3r|b3v>/uart_*.log` | 每次运行的完整串口文本 |
| `<b3n|b3r|b3v>/pc_*.txt` | ping、arp、eth_probe 的输出原文 |
| `capture.pcapng` | 5.5 的抓包（如有） |

## 7. 通过判据

本卡只采集数据，不判定通过与否。每一步都要有串口和 PC 侧的原文；做不了的步骤写明原因。所有数字取自原文。

## 8. result.md 模板

```markdown
# 20261101-26-eth-diag 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| bitstream | B3N / B3R / B3V 路径与修改时间 |

## 汇总
| 工程 | 情况 | PHY link/speed/duplex | TXDLY/RXDLY | DIAG 广播 PC 能否收到 | ARP 是否通 | ping 前后 PERF0 / PERF3 / PERF5 / PERF8 |
|---|---|---|---|---|---|---|
| B3N | 刚下载 | | | | | |
| B3N | r 之后 | | | | | |
| B3N | d 组合 0–3 | | | | | |
| B3N | KEY1 复位后 | | | | | |
| B3N | 断电重启后 | | | | | |
| B3N | TUN 关闭 | | | | | |
| B3R | 刚下载 | | | | | |
| B3V | 刚下载 | | | | | |

## 抓包要点（如有）

## 问题与偏离
```
