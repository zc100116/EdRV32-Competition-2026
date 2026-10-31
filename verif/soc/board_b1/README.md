# B1 启动、串口烧录与 SRAM ELF 会话

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock python3 verif/soc/board_b1/run.py menu
flock /tmp/edrv32-sim.lock python3 verif/soc/board_b1/run.py download
flock /tmp/edrv32-sim.lock python3 verif/soc/board_b1/run.py window
flock /tmp/edrv32-sim.lock python3 verif/soc/board_b1/run.py load
python3 verif/soc/board_b1/check_style.py
```

使用实际 B1 顶层、PLL/ROM/SRAM/UART 行为模型，软件由 sw/Makefile 构建。
Verilator 构建 -j 1，-Wall 0 告警，结果和日志位于 build/board_b1。

- menu：上电从 SRAM 监控程序启动，检查 logo、时钟、ISA、系统信息及菜单往返。
- window：KEY1 保持按下，实际等待 100 ms 窗口后进入 BIOS。
- download：工具 --emit 生成单段 SRAM .bin 会话（显式 --addr/--entry），等待 BIOS
  菜单后发送 1 和 Enter，收到完整 UART load ready 后发送描述块与镜像，检查自动
  运行成功；再释放 KEY1，复位两次，检查 .data 恢复、.bss 清零和 SRAM 镜像保留。
- load：先通过菜单 4 切 2 Mbaud，检查非法段范围和非法 Run 入口拒绝，再通过一次
  UART 会话发送 ELF 的两个非空 PT_LOAD（p_paddr/p_filesz），自动跳转至入口并
  检查应用 PASS 和 SIM_EXIT=0。描述块使用 uart_tool.descriptor_bytes() 生成。

当前菜单为 `BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud`，不再使用原先的
长度头/复位运行或逐段 Load 后单独 Run。协议以 sw/boot/README.md 为准。
多段 DDR UART 和 ETH 窗口 2/3、缺包重发见 verif/soc/sc_bios_eth。
B1 顶层不带 DDR/ETH，不用于网口验收。旧 B1-10 测量属于 v0.17，见 git 历史。
