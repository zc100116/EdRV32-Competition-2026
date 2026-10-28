# ETH 独立模块级验证

依据 `docs/spec/eth-spec.md` v0.1、SoC v0.13 的 3.4、4.2、4.3、7.1、7.2、8.10
以及 `docs/testplan/eth-testplan.md` v0.1 实现 ET-01–15。没有读取 `rtl/eth/`，没有替身 RTL。
`files.f` 用 `-f ../../../rtl/filelists/eth.f` 引入真实被测模块。

`eth_ref.py` 只用 Python 标准库：网络字节序、IPv4/UDP 校验和、Ethernet CRC32、
ARP 请求/应答、应用头、按第一条失败规则分类、33 位范围比较、窗口字节内容、累计计数、
PEER 和 NOTIFY，以及描述符的 1024 B 分包和 IPv4 ID。PERF9 的时间检查由仿真完成。
参考模型不读取 RTL，也不从 DUT 输出构造预期帧或预期数据。

`cases.py` 的每个 `etNN()` 产生输入帧、描述符、RAM 初值、操作脚本、预期 RAM 和发送帧。
`run.py` 先生成向量，再构建真实 DUT，逐个运行独立进程；固定 `-j 1`，没有并行仿真。
生成物在 `build/eth/{smoke,random,perf}/`，回归入口日志在 `build/regress/`。

`edrv32_eth_tb.sv` 驱动共享 APB interface 的 slot 0，并检查 PREADY=1、PSLVERR=0；
PSTRB=0 也执行整字写。三个时钟分别是 125 MHz、125 MHz × 1.0001、125 MHz × 0.9999，
相位分别为 0、1.137 ns、2.719 ns；时钟生成使用 1 fs 精度，避免 ppm 偏差被舍入。
三路复位在各自时钟下降沿独立释放。DUT 连接仅按公开端口契约写在 `dut_connections.svh`。

`edrv32_eth_memory.sv` 是有序 AXI256 字节 RAM，未初始化位置为 0xa5；支持独立随机
AR/AW/W 握手、R 间隔和 B 延迟、固定读延迟/写响应延迟、阻塞写、挂起响应、按事务号或
读地址注入 SLVERR。响应被反压时保持不变；所有 AXI 流量通过公共 checker。
`edrv32_eth_phy.sv` 检查 Clause 22 前导、ST、OP、PHYAD、REGAD、TA、数据、MDIO OE，
维护 32 个 16 位 PHY 寄存器，并按 512 ns 的 MDC 周期检查 clk_mem / 64。

| 项目 | 实现位置 | 检查点 |
|---|---|---|
| ET-01 | `cases.py:et01`、`eth_ref.py:Reference.receive`、TB `C/R` | 四窗口，LEN 0/1/31/32/33/1464，任意偏移、乱序、重复、忽略位；所有期望字节及所有实际写地址、保护区，WIN_BYTES、PERF1/2 |
| ET-02 | `et02` | 恰好边界和超界、SIZE=0、OFFSET=0xffffffff 的 33 位比较，WIN_BYTES 写清零、PERF6 |
| ET-03 | `et03`；ERROR=1 场景在 `et11` 的 write-error | ENABLE=0 和 ERROR=1，FCS、rx_er、63/1519 B、目的 MAC、广播 IPv4；不写 RAM，PERF0/3/5 |
| ET-04 | `et04` | IPv4 版本/IHL/MF/偏移/协议/IP/长度，各种校验和、UDP 长度/端口，零和非零 UDP 校验和、短帧填充；按顺序分类，PERF4/5 |
| ET-05 | `et05`、TB `Q/N/I` | 挂起 B 后 NOTIFY/irq 均未置位；依次通知四窗口，最后 LEN=0；置位时所有此前 AW 均已 B 完成，WIN_BYTES 已更新；IRQ mask/RW1C |
| ET-06 | `et06` | 三组源 MAC/IP/端口，丢弃包不改变 PEER |
| ET-07 | `et07`、peer sink | 广播/单播 ARP，目标 IP、OPER、HTYPE/PTYPE/HLEN/PLEN 过滤；应答逐字节及 FCS/补齐；当前 UDP 完整结束后先发应答，只保留一个 pending，PERF5/8 |
| ET-08 | `et08`、`Reference.transmit`、peer sink | LEN 0/1/1023/1024/1025/3000，SRC 低 5 位、描述符保留位；头/ID/IP checksum/UDP 零 checksum/应用头/数据/补齐/FCS 全比对；NOTIFY 仅最后包，IFG ≥12 |
| ET-09 | `et09` | 三描述符顺序，ENABLE=0 仍可发送；已完成一个包后 BUSY DOORBELL 被忽略；DONE/DONE_COUNT/CUR_DESC、DESC_COUNT=0 |
| ET-10 | `et10`、TB `O/U` | 256 KiB 收发并行逐字节比对；阻塞 AXI 写时 24 个 1024 B 包，每包必须完整写入或完整丢弃，PERF7=总数−写入数，恢复后新包可写 |
| ET-11 | `et11`、TB `H/E` | 描述符和首笔数据读 SLVERR、接收写 SLVERR；分别在描述符读、数据读、线上帧期间 ABORT；ERROR/CUR_DESC/DONE_COUNT、ERROR 期间丢帧、清错恢复、在途事务排空、当前帧完整、PERF9 停止 |
| ET-12 | `et12`、`reset_registers` | 全部定义寄存器复位、RO 写忽略、未定义偏移、可写掩码、IRQ RW1C；PERF0–8 跨 DOORBELL 保留、PERF9/10 清零；UDP/ARP BUSY 时 SOFT_RST 无效、IDLE 时全恢复；未验完 RX 保持 IDLE，中途复位丢弃到帧尾且帧尾 PERF0=1；关闭 ENABLE 不影响已接受包 |
| ET-13 | `et13`、PHY 模型、TB `J/Y` | PHY_CTRL 复位和引脚、任意 PHY/REG 写读、BUSY 命令忽略、RDATA、Clause 22 位序/OE、MDC 周期 |
| ET-14 | `et14`、TB `B/G/A` | 固定 R/B 延迟 40 周期，无反压；2 MiB 连续 RX、1 MiB TX 数据逐字节及计数；速率 = 字节数 ×1000 / 仿真 ns，≥100 MB/s；发送中 ARP ≤10 µs |
| ET-15 | `et15` | 种子 0–9，每种子恰好 200 个输入帧；正确帧、各类错误、ARP、窗口/偏移/描述符、总线延迟/反压/IFG 随机；RAM、计数器、PEER/IRQ、发送序列、公共协议 checker |

缓冲深度是规格 5.2 的开发参数，因此 ET-10 不假定精确丢包个数；用独立数据标签判定
每个包是否完整写入，再精确比对写入数、丢弃数、字节数和恢复后的增量。未完成的部分包
不能通过检查，未定义区域的改写也不能通过。其他场景的 RAM 和计数均由参考模型预先确定。

协调者通过 ask 确认的边界：待发 ARP 优先于当前帧之后的下一个 UDP；ARP 延迟从
max(请求接收结束，收到请求时正在线上发送的帧结束) 起算；读错误之前只有已完整读入
缓冲且不含错误响应的包才能继续发送；IPv4 ID 只由实际发出的 UDP 包消耗，错误和 ABORT
丢弃的包不消耗，ARP 不消耗。错误清除后直接重启，不借 SOFT_RST 恢复。这些澄清已由
协调者写入规格（45f1072、c6fe2f6、2584a91）。另按 387619f/265bb5d 验证 STATUS 对
在发 ARP/UDP 的 BUSY 定义，以及未验完 RX 的 IDLE/SOFT_RST/帧尾 PERF0 计数。

selftest 不引用 ETH filelist 或 DUT。`selftest.py` 用固定手算样例验证 ARP 请求/应答、
最短 UDP 的 IPv4 checksum=0xb75a、线上 FCS=b4 00 3f a5、窗口边界两侧和 33 位溢出、
LEN=1025 的两包长度/数据/OFFSET/NOTIFY/ID。`eth_selftest.sv` 回环最短和最长帧，
逐字节比较，并把上述 UDP 样例的实际线端 FCS 对照固定值。
`eth_models_selftest.sv` 还在真实公共 AXI checker 下验证两拍部分写、未写字节、随机握手、
固定 40 周期延迟、R/B SLVERR，以及 PHY 的 Clause 22 写/读。

复现命令（先 `. ~/.local/opt/edrv32/env.sh`）：

```sh
python3 verif/block/eth/check_style.py
make smoke REGRESS_ARGS='-j 1 --path verif/block/eth'
make full REGRESS_ARGS='-j 1 --path verif/block/eth'
make perf REGRESS_ARGS='-j 1 --path verif/block/eth'
python3 verif/block/eth/selftest/selftest.py
```

`check_style.py` 复用 `tools/check/verilog_style.py`，仅按 9.1 排除禁止 RTL 使用 SV/initial/
延迟的规则，并排除 task/function/do/队列方法被误识别为模块例化的误报；其余机械规则保留。
runner 和 selftest 的 Verilator 构建均使用 `-Wall`，任何 lint 告警都会失败。

本次独立验证结果和准确命令见下方交付记录；正式 ET 项目的功能判定留给 V-I4 联调。

## 交付检查（2026-10-28）

工具：Linux，Python 3.12，Verilator 5.020。精确提交号随本任务 `worker_done` 回报。

- `python3 verif/block/eth/check_style.py`：8 个 SV/SVH 文件，0 告警。
- 下述 Verilator lint 命令：所有独立模型和 selftest，0 告警。
- `make smoke REGRESS_ARGS='-j 1 --path verif/block/eth'`：selftest PASS；正式目录
  FAIL，唯一编译错误为找不到 `rtl/eth/edrv32_eth.v`；汇总 1 PASS / 1 FAIL，make 退出码 2。
  selftest 包含参考模型、peer、AXI 和 PHY 四部分；首次构建约 19 秒，缓存后本次显示 0 秒。
- 三档向量生成均正常完成：smoke 22 个子场景，full 的随机部分 10 个种子，perf 3 个子场景。
  正式 ET 功能、完整 DUT lint 和正式 smoke 耗时尚未取得，留给 V-I4；full/perf 没有宣称通过。

日志：`build/eth-style.log`、`build/eth-lint.log`、`build/eth-smoke.log`，以及
`build/regress/smoke/block/eth/{selftest/verilator,verilator}/run.log`。

独立模型 lint 的准确命令：

```sh
. ~/.local/opt/edrv32/env.sh
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, 'tools')
from regress import expand_files
subprocess.run(['verilator', '--lint-only', '--timing', '-Wall',
                '--top-module', 'eth_selftest',
                *expand_files(Path('verif/block/eth/selftest/files.f'))], check=True)
print('PASS Verilator model/selftest lint: 0 warnings')
PY
```
