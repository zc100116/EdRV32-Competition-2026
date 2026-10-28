外部器件模型（DDR、OV5640、HDMI 接收、UART、QSPI flash、ETH 对端）


`ddr3_axi256_model.sv` is the mem-subsystem MB DDR timing model (testplan 2.3).
It exposes the SoC 3.2 scalar slave pins, with no BREADY/RREADY. Commands share an
ordered depth-8 queue; AW precedes AR on simultaneous arrival. Address mapping:
row `[29:15]`, bank `[14:12]`, byte column `[11:0]`. Data storage is sparse by byte;
unwritten test locations read as zero, and `poke`/`peek` provide explicit preloads
and byte error injection. Reset clears control/queues and open-row validity;
stored bytes survive reset.

Timing plusargs, in clk_mem cycles: `+T_HIT=8 +T_MISS=4 +T_TURN=3 +T_REFI=975
+T_RFC=38 +T_B=2`. Read-command latency overlaps earlier data transfers; the
shared data bus transfers at most one read or write beat per cycle. Refresh stops
data transfers, closes rows, and preserves queued transactions. B follows the
last executed write beat by T_B cycles. Backpressure applies only to AW/AR/W.
`read_response` and `write_response` are test controls for response-error routing.

Model, driver and protocol-checker self-tests and the case mapping live in
`verif/block/mem_subsys/README.md`. Run `. ~/.local/opt/edrv32/env.sh` first.
## DDR3 IP 用户端口模型

`pango_ddr3_ip_model.sv` 对应存储子系统规格附录 A 和 AD-01，用于
`fpga/rtl/edrv32_fpga_ddr_adapter.v` 的单元验证。模型只模拟 IP 用户端口，
不模拟物理引脚、PLL、APB 或校准调试端口。`core_clk_i` 由测试环境提供，
`resetn_i` 为低有效复位，`ddr_init_done_o` 为初始化完成状态。

IP 用户端口清单如下（下表使用 PDS 模板原名，模型加 `_i`/`_o` 方向后缀，
适配器的方向与模型相反）：

| 方向（相对 IP） | 模板端口 | 位宽 |
|---|---|---|
| 输入 | `axi_awaddr`、`axi_araddr` | 各 28 |
| 输入 | `axi_awuser_ap`、`axi_aruser_ap` | 各 1，适配器固定 0 |
| 输入 | `axi_awuser_id`、`axi_aruser_id` | 各 4 |
| 输入 | `axi_awlen`、`axi_arlen` | 各 4 |
| 输入 | `axi_awvalid`、`axi_arvalid` | 各 1 |
| 输出 | `axi_awready`、`axi_arready` | 各 1 |
| 输入 | `axi_wdata`、`axi_wstrb` | 256、32 |
| 输出 | `axi_wready`、`axi_wusero_id`、`axi_wusero_last` | 1、4、1 |
| 输出 | `axi_rdata`、`axi_rid`、`axi_rlast`、`axi_rvalid` | 256、4、1、1 |

没有 WVALID/WLAST、BREADY、RREADY 或原生 B/RRESP 端口。适配器用
`axi_wusero_last` 和 `axi_wusero_id` 直接合成 B，BRESP/RRESP 固定 OKAY。
IP 的 `ddr_init_done` 接适配器 `ddr_init_done_i`，输出 `mem_ready_o` 给 SoC；
实际 IP 的 `core_clk` 同时驱动 SoC 的 clk_mem，适配器为纯组合逻辑。

地址单位为 4 B：SoC 物理字节地址 `[29:2]` 接 IP `[27:0]`，每个 256 位拍
递增 8 个 IP 地址单位。依据是旧适配器
`legacy/rtl/soc/ddr/edrv32_pango_ddr_axi_adapter.v:156,257` 的切片，及旧模型
`legacy/sim/models/pango_ddr_ui_model.sv:7,185,210` 的单位说明和步进。
控制器按序执行是模型和当前适配器契约的假设，仍需真实 IP/上板确认。

模型参数：`MEMORY_BYTES`（默认 65536，连续字节存储窗口，从地址 0 开始）、
`INIT_CYCLES`（8）、`COMMAND_LATENCY`（3）、`WUSER_DELAY`（0）。
非零 `WUSER_DELAY` 将完成脉冲推迟到最后一个 W 拍之后、WREADY 为低时输出。
命令按序执行，一次执行一笔，AW/AR 同时有效时先接受 AW；固定 LFSR 提供
命令、写数据和读数据的等待周期。内存不复位，测试必须先写后读，并在配置的
存储窗口内访问；模型不代表 DDR 实际带宽或校准行为。

`eth_peer_model.sv` 提供 ETH MAC 侧 8 位帧收发、前导码/SFD/FCS/IFG 检查和位翻转、rx_er、截短、加长注入；独立 selftest 与 ET-01–15 见 `verif/block/eth/README.md`。
