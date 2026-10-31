# BIOS v0.18 DDR / ETH 前门验收

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock python3 verif/soc/sc_bios_eth/run.py
```

复用 common SoC testbench、完整 DDR 模型和 eth_peer_model，以实际新 BIOS 启动。
构造多段 DDR ELF（含初始化 data 与 bss），再附加一个 SRAM 段。分别通过 UART、
ETH 完整会话、ETH 少发首包后整份重发三条路径加载，均自动跳转至 DDR ELF 入口。
应用检查 data、bss 和 SRAM 段，打印 BIOS application PASS 并写 SIM_EXIT=0。

PC 参考帧复用 SC-06 的 IPv4 校验计算，UDP 使用真实 uart_tool.eth_packets()，
包含 8 B 应用头；先段数据、后描述块，最后置 NOTIFY。缺包必须产生 FAIL bytes，
完整重发后必须 PASS。日志位于 build/sc_bios_eth/{uart,eth,eth_retry}.log。
场景 full 档，Verilator -j 1、-Wall，独立构建目录。

仅 CASE18 使用协调者批准的仿真加速：force BAUD_DIV=256，UART 对端 6.25 Mbaud；
每次读取 mtime 时测试端推进 10000 周期。BIOS 固件和条件判断不变，其他场景不变。
实际 115200 / 2 Mbaud 和真实 100 ms KEY1 窗口由 board_b1 原有用例覆盖。
