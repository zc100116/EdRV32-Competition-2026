# Boot ROM BIOS

Source `. ~/.local/opt/edrv32/env.sh`, then run `make -C sw PROGRAM=bootloader`
(or `make -C sw sys` for the bootloader and SC programs). Outputs are under
`build/sw/bootloader/`: ELF, disassembly, map, raw `.bin`, and byte-oriented
`rom.hex`/`sram.hex`/`ddr.hex`. Code and constants occupy the 16 KiB ROM.
The bootloader has no mutable static data; its private startup only sets GP/SP,
leaving the SRAM application intact. Its stack uses the final 4 KiB of SRAM.

On reset, bootloader enables UART TX/RX, sets 115200 8N1 from SYSCTRL
`CLK_SYS_HZ`, configures GPIO as inputs, prints the ASCII logo, waits for
`STATUS.MEM_READY` and prints system information. Fixed `Key: Value` fields are
`CHIP_ID`, `CLK_SYS_HZ`, `ROM bytes`, `SRAM bytes`, `I-cache bytes`,
`D-cache bytes`, `MEM_READY`, `Build commit`, `Compiler version`.
Memory sizes come from generated `soc_map.h`; cache sizes are cache-spec 2.1
constants. Build information comes from Makefile macros.

After this information, bootloader repeatedly samples KEY1 (GPIO bit0, active
low) for `BOOT_BUTTON_WINDOW_MS=100` ms, measured by CLINT `mtime` using
SYSCTRL `CLK_SYS_HZ`. KEY1 must stay pressed throughout this window to enter
BIOS. Alternatively, `SCRATCH0=BOOT_DOWNLOAD_MAGIC=0x55415254` requests BIOS;
SCRATCH0 is cleared after reading. Applications can set this request then write
`SYSCTRL_RESET_SOC`; scratch survives soft reset. Otherwise bootloader prints
`Boot SRAM`, drains UART, executes FENCE/FENCE.I and enters SRAM base.
There is no SCRATCH1 boot-mode handoff.

## BIOS v0.18 会话协议

菜单为 `BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud`，所有输出行以 CR LF
结束，菜单输入支持 CR、LF、CR LF。选择 1 或 2 的描述块相同：小端 u32 段数
N（1–16）、u32 入口，随后 N 组 {u32 目标地址, u32 字节长度}。
ELF 使用非空 PT_LOAD 的 p_paddr/p_filesz 和 e_entry；裸 .bin 必须指定地址和入口。

每段长度至少 1，整段必须在一个可加载区域内：SRAM（不含末尾 4 KiB 栈），或
DDR 可缓存区（不含物理 0x0a000000 起 68 KiB ETH 暂存区）。入口必须 4 字节对齐
并在可加载区域内，不要求入口位于某段中，不检查段重叠。检查失败输出
`Load result: FAIL range`，不接收段数据，回菜单。

选择 1：等待完整 `UART load ready` 行，再发描述块和按描述顺序排列的各段数据。
选择 2：BIOS 写回并作废 D$，按现有 eth_monitor 时序复位 PHY 10 ms，释放后等
100 ms，配置 MAC 02:45:44:52:56:32、IP 192.168.1.10、UDP 5000；用 PHYAD 0
连续两次读 BMSR，取第二次 bit2，直到链路建立。打印 `ETH link: up`、
`ETH load ready 192.168.1.10:5000` 后 PC 才发数据。

ETH 窗口 2 覆盖整个物理 DDR，DDR 段偏移为目标地址减 DDR 可缓存基址；窗口 3
位于物理 0x0a000000，描述块偏移 0，SRAM 段偏移 0x1000 加目标地址减 SRAM
基址。先发所有段数据，最后发描述块，最后一包置 NOTIFY。收到窗口 3 通知后，
BIOS 检查描述块并比对 WIN2_BYTES（DDR 段字节和）、WIN3_BYTES（描述块加 SRAM
段字节和）。不一致时清零计数并打印
`ETH load result: FAIL bytes win2=<n> expect=<n> win3=<n> expect=<n>`，等待整份重发。
一致后拷贝 SRAM 暂存段。ETH 等待期间收到任意一行即禁用 ETH、返回菜单。

两种模式均自动运行：BSP 写回 D$，作废外部写入 DDR 区域，打印：

```text
Load bytes: <总字节数> segments: <N>
Load result: PASS
Run: 0x<8位小写十六进制入口>
```

等 UART 发完后执行 fence.i、关中断并跳转，应用自己初始化运行环境。
SRAM 镜像在复位后仍可从 SRAM 启动；DDR 程序每次复位后必须重新烧录。
协议没有校验和、逐包确认或额外重试；PC 仅在 FAIL bytes 后整份重发一次。

选择 3 仍提示 `Run address:`，接收 `0x` 开头的入口；非法时输出
`Run result: FAIL address`，合法时打印 Run 行并跳转。
选择 4 仍提示 `Baud:`，支持 115200、921600、2000000，合法时用旧波特率打印
`Baud result: <值>`，等发送完成再切换；切换后等 100 ms 再发送新速率菜单
（SoC v0.22 7.5(3a)），供主机重配 USB 串口；非法时打印 `Baud result: FAIL`。
其他输入打印 `Input error: type 1-4 then Enter`。未跳转的操作结束后重新打印菜单。

PC 使用说明见 [tools/board/README.md](../../tools/board/README.md)。
ROM 生成按 [ip_rom_boot.md](../../fpga/ip/ip_rom_boot.md) 的同一打包方式执行。

## v0.18 验收记录

- 基线：ddd39075；前置ETH v0.2修复：3689bd7b/3f128270/8732764b；
  实现：包含本节的提交（`git log -1 --format=%h -- sw/boot`）。
- 环境：本机；用户提供的仿真主机（环境不记录）。
- `make -C sw PROGRAM=bootloader -j 1`：0 warning，text=8884 B，data/bss=0。
- ROM：8884 B ≤ 16384 B；`build/fpga/ip_rom_boot.dat` 为 2048×64 bit，空位补零。
  生成：`python3 tools/fpga/mem_init.py build/sw/bootloader/rom.hex build/sw/monitor/sram.hex`。
- `python3 -m unittest discover -s sw/boot/tests -v`：通过；实际 C 解析器覆盖
  N=0/1/16/17、SRAM/DDR/暂存区边界、长度0/回绕、入口对齐和窗口字节计数。
- `python3 -m unittest discover -s tools/board/tests -v`：10 项通过；ELF物理地址、bin
  地址必填、描述块、UDP≤1472 B/偏移/NOTIFY、整份只重发一次和自动Run。
- `QT_QPA_PLATFORM=offscreen PYTHONPATH=third_party/ultralytics
  ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests -v`：
  67 项通过，包括串口、网口复用、REST/CLI和1366×768/1920×1080布局。
- 本机仿真命令均加 `flock /tmp/edrv32-sim.lock`，构建 `-j 1`：
  `python3 verif/soc/board_b1/run.py {menu,download,window,load}`：全部PASS。
  download：SRAM烧录后自动运行，再复位两次仍恢复data/bss；load：双段ELF、
  非法段/入口及2 Mbaud；window：真实100 ms。日志 `build/board_b1/case{0,1,2,3}.log`。
- `python3 verif/block/sys_cpu/run.py sc04`：KEY1与SCRATCH请求两场景PASS；
  日志 `build/sys_cpu/{sc04,sc04_scratch}/run.log`。
- `python3 verif/soc/{board_render,board_vision,board_vnpu,board_npu}/run.py`：全部PASS。
- `python3 verif/soc/sc_06_eth_rx/run.py`：原ETH接收/ARP场景PASS（共享环境回归通过）。
- `python3 verif/soc/board_npu/program/run.py --mac sim`：原始卡13 ELF经新BIOS Run，
  首个B-OP-01 PASS；该旧场景补齐当前ETH顶层端口/文件列表，行为MAC lint 0告警。
- `python3 verif/soc/sc_bios_eth/run.py`：UART/ETH三段384 B均自动进入DDR并检查PASS；
  ETH缺首包精确报告win2=4 expect=380、win3=36 expect=36，整份重发后自动运行PASS。
  仅CASE18按批准加速UART/mtime，B1覆盖实际波特率/100 ms；固件不变。
- `python3 verif/{soc/common,soc/board_b1,block/sys_cpu}/check_style.py`：全部0告警；
  上述板级及新增SoC场景 Verilator `--lint-only --timing -Wall`：0告警。
- 旧协议搜索：`rg -n 'Program SRAM|UART download ready|2=Load|load_wire_bytes' sw tools verif docs tasks`。
  已同步 sw/boot、tools/board、tools/debug_tool；sw/apps/{demo,nes}/README.md；
  sw/tests/{sys,rnd_board,board_npu}/README.md；verif/block/sys_cpu 与 verif/soc/board_b1；
  verif/soc/{board_render,board_vision,board_vnpu,board_npu} 及 board_npu/program。
- 历史命中按协调者确认保留原样，由v0.18取代：docs/debug/2026-10-28-{boot-bios,board-b1}.md；
  docs/design/2026-10-30-board-npu-test.md；tasks/win/20261028-{06-board-b1,07-media-r3-b1}；
  tasks/win/20261029-{03-b3-render-full,04-b3r-software,05-b3-vision,07-b3-rerun,
  08-b3-vnpu,09-b3-software}。历史日志/测量未改，卡22使用新ROM。
