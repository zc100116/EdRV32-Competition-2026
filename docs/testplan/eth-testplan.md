# ETH 验证方案

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-28 |
| 对应规格 | `docs/spec/eth-spec.md` v0.1；SoC 规格 v0.13 3.4、4.2、7.1、7.2、8.10 |

## 1. 验证对象和范围

`edrv32_eth` 模块级验证，覆盖规格第 2、4、5、6、7 节。`dma2d_rd/wr` 自身的事务拆分已在 `dma2d-testplan` 验证，这里只检查 ETH 的整体结果和协议。RGMII 转换（FPGA 层）、真实 PHY、P6 与 PERF_MON 的仲裁、与 mem_xbar 和其他主设备并发时的带宽在 SoC 级或上板验证。PC 端工具和板上应用层协议（核对字节数、请求重发）由软件测试验证，不属于本方案。

## 2. 验证环境

- 层级：模块级，`verif/block/eth/`，Verilator `--timing`，自检。
- 时钟：clk_mem、eth_rx_clk、eth_tx_clk 都是 125 MHz，相位和频率互不相关（rx、tx 各有 ±100 ppm 偏差），覆盖 X7 的异步 FIFO。
- ETH 对端模型 `verif/models/eth_peer_model.sv`：在 MAC 侧 8 位接口上收发以太网帧。发送：按任务给出的字节序列加前导码、SFD、FCS，帧间隔可设（最小 12 字节）；可在指定字节处翻转一位、置 `rx_er`、截短或加长帧。接收：去掉前导码，检查 SFD、FCS 和帧间隔，把帧交给 testbench 比对。
- 帧构造：Python 脚本 `verif/block/eth/eth_ref.py`（只用标准库），按规格 2.1–2.6 生成 ARP、IPv4/UDP 帧和各类错误帧，计算期望的窗口内容、计数器值、ARP 应答帧和发送帧序列。参考模型不参照被测 RTL。
- AXI256 从设备：testbench 内存储模型（随机 `arready/awready/wready`、R 间隔、B 延迟，可设固定延迟，可对指定事务注入 SLVERR）；复用 `verif/common/edrv32_axi256_checker.sv` 检查协议。
- MDIO：testbench 内的 PHY 寄存器模型（Clause 22，32 个 16 位寄存器）。
- APB：`verif/common/edrv32_apb_if.sv`。

## 3. 测试项清单

| 编号 | 规格条款 | 测试内容 | 激励 | 检查 | 档位 |
|---|---|---|---|---|---|
| ET-01 | 2.3、2.4 | 基本接收：单个包写入窗口 0；4 个窗口各写一块；OFFSET 和 LEN 取任意对齐（含 LEN = 0、1、31、32、33、1464）；乱序到达；同一偏移重复写 | 定向 | 窗口内容逐字节一致，窗口外 DDR 不变；WINn_BYTES；PERF1、PERF2 | smoke |
| ET-02 | 2.4 | 窗口边界：`OFFSET + LEN` 等于和超过 WINn_SIZE 各一包；`WINn_SIZE = 0`；OFFSET 接近 2^32（检查 33 位比较）；WINn_BYTES 写清零 | 定向 | 越界包不写任何 DDR、PERF6 加 1；边界内的包正常 | smoke |
| ET-03 | 2.2 第 1–3 条 | 链路层过滤：ENABLE = 0、ERROR = 1 时丢弃；FCS 错、`rx_er`、帧长 63 和 1519 字节；目的 MAC 不符、单播以外的广播 IPv4 | 定向 | 不写 DDR；PERF0、PERF3、PERF5 | smoke |
| ET-04 | 2.2 第 5–7 条 | IP/UDP 过滤：版本、IHL = 6、MF 或分片偏移非 0、协议非 17、目的 IP 不符、IP 总长度大于帧；IP 头校验和错、UDP 校验和错、UDP 校验和为 0；端口不符、UDP 长度与 IP 总长度不一致、UDP 长度 < 16；带以太网填充的短包 | 定向 | 按规格去向丢弃或写入；PERF4、PERF5 | smoke |
| ET-05 | 2.4 | NOTIFY：一块数据的最后一包置 NOTIFY，在 B 延迟较大时检查中断时刻；不同窗口交替通知；LEN = 0 的通知包 | 定向 | `RX_NOTIFYn` 在该包和此前全部包的 B 返回之后才置位；置位时 WINn_BYTES 已包含该包；irq_o | smoke |
| ET-06 | 2.4 | PEER 记录：不同源 MAC/IP/端口的包；被丢弃的包不更新 | 定向 | PEER_* 等于最近一个被写入包的源地址 | smoke |
| ET-07 | 2.5 | ARP：请求本机 IP 的广播和单播请求；目标 IP 不符、OPER = 2、HTYPE/PTYPE/HLEN/PLEN 不符；发送进行中收到请求；连续两个请求时第一个未发出 | 定向 | 应答帧逐字节与参考一致（含补齐）；插在 UDP 包之间、不打断帧；只保留 1 个待发应答，多余的计入 PERF5；PERF8 | smoke |
| ET-08 | 2.6 | 发送分包：LEN = 0、1、1023、1024、1025、3000；SRC_ADDR 低 5 位忽略；NOTIFY 只在最后一包；WIN 和 OFFSET；描述符字 4–7 和忽略位填随机值 | 定向 | 每个帧逐字节与参考一致（以太网头、IPv4 头和校验和、标识递增、UDP 头和校验和 0、应用头、数据、补齐、FCS）；帧间隔 ≥ 12 字节 | smoke |
| ET-09 | 2.6、4.1 | 多条描述符：3 条依次执行；DONE、DONE_COUNT、CUR_DESC；DESC_COUNT = 0 立即 DONE；BUSY 时 DOORBELL 被忽略 | 定向 | 寄存器；帧顺序 | smoke |
| ET-10 | 5.1、5.2、7 | 收发同时：接收线速连续包的同时执行一条 LEN = 256 KiB 的发送；接收缓冲满：AXI 写长时间阻塞时线速接收，随后恢复 | 定向 | 写入的包内容正确；溢出的整帧丢弃并计入 PERF7，不影响后续帧；发送帧正确 | smoke |
| ET-11 | 5.3、6 | 错误和 ABORT：发送描述符读 SLVERR、数据读 SLVERR；接收写 SLVERR；在发送描述符读、数据读、帧发送中各写一次 ABORT；清 ERROR 后恢复 | 定向 | ERR_CODE、IRQ_STAT、CUR_DESC；ERROR 期间接收丢弃；正在发送的帧完整发出；无未完成事务（检查器）；PERF9 计到停止 | smoke |
| ET-12 | 4 | 寄存器：复位值、只读位、未定义偏移读 0、ID、IRQ_STAT RW1C（含 RX_NOTIFY）、PERF0–8 不被 DOORBELL 清零而 PERF9–10 被清零；SOFT_RST（IDLE 时生效，BUSY 时无效，全部寄存器回到复位值）；ENABLE 清零时已通过检查的包照常写完 | 定向 | 读回值 | smoke |
| ET-13 | 2.7 | MDIO：读、写各一次，任意 PHY/REG；BUSY 期间写 MDIO_CMD 被忽略；MDC 频率；PHY_CTRL 复位值 1 和 `eth_phy_rst_n_o` | 定向 | PHY 模型收到的帧格式（前导 32 个 1、ST、OP、PHYAD、REGAD、TA、数据）；RDATA | smoke |
| ET-14 | 7 | 性能：(a) 线速连续接收 2 MiB（每包 1024 字节数据，帧间隔 12 字节）；(b) 接收空闲时发送一条 LEN = 1 MiB 的描述符；(c) 发送进行中 ARP 请求的应答延迟；存储模型按第 7 节测量条件 | 定向 | (a) 无丢包，数据写入速率 ≥ 100 MB/s；(b) 发送速率 ≥ 100 MB/s；(c) ≤ 10 µs；结果逐字节一致 | perf |
| ET-15 | 全部 | 随机回归：随机混合正确包、各类错误帧、ARP 请求，随机窗口配置和偏移，随机发送描述符，随机存储模型延迟和反压，随机帧间隔 | 随机，10 种子，各 200 帧 | 窗口内容、计数器、发送帧序列与参考一致；协议检查器 | full |

## 4. 参考模型

`eth_ref.py` 对每个输入帧按规格 2.2 的顺序判定去向（写入哪个窗口、丢弃计入哪个计数器、是否产生 ARP 应答），维护窗口内容、WINn_BYTES、PEER_* 和各计数器；对每条发送描述符生成期望的帧序列（IPv4 标识按包递增）。testbench 把输入帧、描述符和存储初值写成文件，运行前由 runner 调用参考模型生成期望文件。比对时读取存储模型中的全部窗口和寄存器，逐帧比对发送端输出；失败时打印帧序号、字节位置、期望值和实际值。

## 5. 覆盖目标

规格 2.1–2.7、4、5、6、7 的每一条至少对应一个测试项；必须命中：2.2 表中每一条的通过和不通过、窗口边界两侧、33 位范围比较、NOTIFY 时序、ARP 每个检查字段和待发已满、发送分包边界、收发同时、接收缓冲满、每种错误代码、ABORT 在途事务和发送中的帧、SOFT_RST、MDIO 读写。

## 6. 通过判据和回归档位

全部测试自检 PASS；smoke：ET-01–13；full：全部（ET-14 除外）；perf：ET-14。lint 和风格检查 0 告警。smoke 每个测试目录不超过约 60 秒（CLAUDE.md 9.1）。

## 7. 待定事项与变更记录

无待定事项。

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-28 | v0.1 | 初稿 |
