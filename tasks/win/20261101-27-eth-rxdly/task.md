# 任务卡 20261101-27-eth-rxdly：PHY 接收延迟 RXDLY=0 在三个工程上是否稳定

## 1. 目标

卡 26 已把网口问题定位到**接收采样**：
- PHY 上电默认 RXDLY=1 时，B3N 每帧都校验出错；B3R 时好时坏；B3V 正常；
- B3N 改为 RXDLY=0 后收发正常。

本卡确认：RXDLY=0 是否在 B3N、B3R、B3V **三个**工程上都稳定。如果是，就由软件在网口初始化时统一设置 RXDLY=0。

每个工程、每种设置各做 5 次“PHY 复位 → 设置 → 测试”，统计成功次数。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交），拉出 `win/20261101-27-eth-rxdly`。
- **bitstream**：卡 23 的 B3N、B3R、B3V，不重新生成。
- **程序**：本卡 `src/eth_diag.bin`（入口 0x10000000）。比卡 26 多了直接设置延迟组合的命令：

| 串口命令 | 作用 |
|---|---|
| `r` | PHY 复位，PHY 回到上电默认 TXDLY=1、RXDLY=1 |
| `2` | 设为 TXDLY=1、RXDLY=0 |
| `3` | 设为 TXDLY=1、RXDLY=1（默认值） |
| `s` | 打印 PERF0–8、PEER、STATUS |

## 3. 环境

同卡 26：PC 有线网卡 `192.168.1.2/24`，放行 UDP 6000；Clash/TUN 保持现状即可。

## 4. 需要的 IP

无。

## 5. 操作步骤

对 **B3N、B3R、B3V** 各做一遍：

1. 下载卡 23 的 bitstream，在 BIOS 中用串口烧录本卡 `src/eth_diag.bin`：
   ```powershell
   py tools/board/uart_tool.py tasks/win/20261101-27-eth-rxdly/src/eth_diag.bin --addr 0x10000000 --entry 0x10000000 --baud 115200 --port COM3 --log build/board/c27-<工程>.log
   ```
   必须加 `--baud 115200`。加载后关闭 uart_tool，用调试工具的串口终端（115200）输入命令。
2. 另开终端，一直运行 `py tools/board/eth_probe.py --local-ip 192.168.1.2 --listen 6000`。它每秒向板子发一个 UDP 包（板子收到计入 PERF1），同时显示板子的广播。
3. **RXDLY=0，做 5 次**，每次：
   - 输入 `r`，等串口打印 `link=1 speed=1000`；
   - 输入 `2`，等打印 `Delay combination=2`；
   - 输入 `s` 记下 PERF1、PERF3；等 10 秒；再输入 `s`；
   - 判定：PERF1 增加 ≥ 8 且 PERF3 不增加 = 成功；否则 = 失败。
4. **RXDLY=1（默认），做 5 次**：同第 3 步，把命令 `2` 换成 `3`。

## 6. 产物

放在 `tasks/win/20261101-27-eth-rxdly/artifacts/<b3n|b3r|b3v>/`：每个工程的完整串口文本 `uart.log`、eth_probe 输出 `probe.txt`。

## 7. 通过判据

只采集数据。所有数字取自串口原文。

## 8. result.md 模板

```markdown
# 20261101-27-eth-rxdly 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |

| 工程 | 设置 | 第 1–5 次（成功/失败，PERF1 增量 / PERF3 增量） | 成功次数 |
|---|---|---|---|
| B3N | RXDLY=0 | | /5 |
| B3N | RXDLY=1 | | /5 |
| B3R | RXDLY=0 | | /5 |
| B3R | RXDLY=1 | | /5 |
| B3V | RXDLY=0 | | /5 |
| B3V | RXDLY=1 | | /5 |

## 问题与偏离
```
