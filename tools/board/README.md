# BIOS 串口 / 网口烧录（SoC v0.18）

串口依赖：`py -m pip install pyserial==3.5`。工具初始连接 115200 8N1，默认经 BIOS
菜单 4 切到 2000000，可用 `--baud 115200` 保持原波特率，或用 921600。

```sh
py tools/board/uart_tool.py build/sw/monitor/monitor.bin --addr 0x10000000 --entry 0x10000000 --port COM3
py tools/board/uart_tool.py build/sw/board_npu/board_npu.elf --elf --port COM3 --log build/board/npu.log
py tools/board/uart_tool.py build/sw/board_npu/board_npu.elf --elf --eth --local-ip 192.168.1.2 --port COM3
```

已在 BIOS 菜单时直接开始；否则按住 KEY1 并复位。每次开始先发一个 CR 获取新菜单，
然后等待 `BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud`。串口模式选择 1，等待
完整 `UART load ready` 行，发送会话描述块和所有段数据；网口模式选择 2，等待完整
`ETH load ready 192.168.1.10:5000`，菜单与结果仍经串口，数据经 UDP。

描述块为小端 u32 段数、u32 入口，以及逐段 {u32 地址, u32 长度}。
ELF 取文件长度非零的 PT_LOAD 的 p_paddr/p_filesz 和 e_entry；`.bin` 必须同时指定
`--addr` 和 `--entry`。BIOS 检查 SRAM（不含末尾 4 KiB 栈）和 DDR 可缓存区，不允许
覆盖 DDR 物理 0x0a000000 起 68 KiB 暂存区。所有段到位后自动跳转，不需另发 Run。

网口绑定 `--local-ip`（默认 192.168.1.2）的临时源端口，目标 192.168.1.10:5000。
UDP 每包最多 1472 字节，其中 8 字节应用头为网络序 `{u8 窗口,u8 NOTIFY,u16 0,
u32 偏移}`，其余最多 1464 字节为数据。DDR 段写窗口 2，偏移为地址减 0x80000000；
SRAM 段写窗口 3，偏移为 0x1000 加地址减 0x10000000。所有数据发完再写窗口 3
偏移 0 的描述块，最后一包置 NOTIFY。收到 `ETH load result: FAIL bytes ...` 后整份
重发一次，第二次仍失败则报错退出。其他 BIOS FAIL 立即报错，不额外重试。
ETH 等待期间可从串口发送任意一行取消。电脑网卡需配置指定本机 IP，并连接千兆网络。

`--log` 保存原始串口输出，运行后继续捕获，Ctrl-C 停止。省略镜像只记录串口。
`--menu 1 --iterations 5000` 可在应用监控菜单出现后启动 CoreMark，`--menu 3` 请求信息。

```sh
py tools/board/uart_tool.py --port COM3 --log build/board/coremark.log --menu 1 --iterations 5000
python3 tools/board/uart_tool.py build/sw/monitor/monitor.bin --addr 0x10000000 --entry 0x10000000 --baud 115200 --emit build/board/monitor.wire
python3 -m unittest discover -s tools/board/tests -v
```

`--emit` 输出串口操作的全部发送字节（菜单选择、波特率文本、描述块、各段数据），
不含开始探测菜单的 CR。仿真仍必须等待各 ready 提示再发送相应部分，不能整份无等待
灌入。网口模式使用 `--port`，不支持 `--emit`。

## NES 外部 ROM

```sh
py tools/board/uart_tool.py build/sw/nes/nes.elf --elf --rom D:\roms\smb.nes --port COM3
```

`--rom` 必须配合 `--elf`，从 nes_rom_slot / nes_rom_slot_end 符号及所属 PT_LOAD 的
VMA/LMA 映射得出物理槽地址；缺符号或文件超槽直接报错。ROM 作为同一会话的最后一段
发送，随后自动运行 ELF 入口；支持串口和网口。模拟器与 ROM 许可见
[NES README](../../sw/apps/nes/README.md)。

调试工具烧录页复用 `BiosTransfer`，可选串口或网口、输入本机 IP，以及 .bin 的烧录和
运行地址。脚本也可复用 `BiosTransfer.start(path, elf=False, baud=2000000, rom=None,
addr=None, entry=None, eth=False, local_ip='192.168.1.2')`。
