# B1 BIOS UART 烧录

Windows 安装依赖：`py -m pip install pyserial==3.5`（同 `tools/requirements.txt`）。
输入为 `make -C sw PROGRAM=monitor` 从 ELF 经 objcopy 生成的
`build/sw/monitor/monitor.bin`，入口在 SRAM 基址，负载最多 61440 字节，留出
bootloader 顶部 4 KiB 栈空间。下载协议见 `sw/boot/README.md`：4 字节小端长度，
随后原始镜像，无校验和或逐字节应答。

```sh
py tools/board/uart_tool.py build/sw/monitor/monitor.bin --port COM3 --log build/board/coremark.log --menu 1
```

先运行工具，再按住启动键（C23）并按复位键（C22），等下载开始后可松开启动键。
工具等待 `BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud`，发送 `1` 和 CR，再等到完整的
`UART download ready` 行后发送长度和镜像。收到 `Program SRAM result:` 后显示结果；
PASS 后松开 KEY1 并再按复位键运行程序。工具持续显示串口输出并保存原始 CRLF 日志，
Ctrl-C 停止。115200 波特、8N1，无流控。可选 `--menu 1` 在菜单出现后发送 `1` 和
Enter，CoreMark 使用默认 10 次迭代；加 `--iterations 5000` 时只发送 `1`，在
`Iterations input` 提示出现后输入迭代次数和 Enter（CoreMark 要求运行至少 10 秒，
100 MHz 下约需 4000 次以上）；`--menu 3` 请求系统信息。省略镜像参数时不下载，
只记录 SRAM 初始化程序的输出并按 `--menu` 操作菜单：

```sh
py tools/board/uart_tool.py --port COM3 --log build/board/coremark_o2.log --menu 1 --iterations 5000
```

tuned 编译选项的监控程序：`make -C sw PROGRAM=monitor OUT=$PWD/build/sw/monitor_tuned
MONITOR_OPT_FLAGS="-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4
-falign-jumps=4 -falign-loops=4"`。要手动操作菜单时关闭
该工具后再用串口终端打开同一端口。

仿真生成完全相同的下载字节流（不需要 pyserial）：

```sh
python3 tools/board/uart_tool.py build/board_b1/download/sc04.bin --emit build/board_b1/download.wire
python3 tools/regress.py smoke --path verif/soc/board_b1 -j 1
```

`--emit` 仍只包含长度和镜像，不含 BIOS 菜单选择；仿真在看到 BIOS 菜单后单独发送
`1` 和 Enter，等 ready 后才发送这个字节流。烧录后不会自动运行，必须松开 KEY1 并复位。

## 加载 ELF 并立即运行

```sh
py tools/board/uart_tool.py build/sw/<程序>/<程序>.elf --elf --port COM3 --log build/board/elf.log
py tools/board/uart_tool.py build/sw/<程序>/<程序>.elf --elf --baud 921600 --port COM3
py tools/board/uart_tool.py build/sw/<程序>/<程序>.elf --elf --baud 115200 --port COM3
```

串口初始仍为 115200 8N1。先启动工具，然后按住 KEY1 按复位。默认先执行 BIOS
`4` 切换到 2000000；可选 921600，或选 115200 跳过切换。工具收到旧波特率的完整
`Baud result: <值>` 行后才切换主机串口，并等新波特率菜单。每个文件长度非零的
PT_LOAD 段依次执行一次 `2`，以 `p_paddr` 为目标地址，只传 `p_filesz` 字节；
空 BSS 段与非 PT_LOAD 段跳过。各段收到 `Load result: PASS` 后才继续，最后执行
`3` 并输入 ELF `e_entry`，无需复位。任一 BIOS FAIL 直接报错停止，无重试或校验和。
程序启动代码负责恢复 `.data`、清零 `.bss` 和设置栈；ELF 的 LMA/VMA 布局由软件链接脚本决定。

目标可为 SRAM（不含末尾 BIOS 栈）或 DDR 可缓存区。DDR 程序必须加载后直接运行，
不得复位；复位仍从 SRAM 启动。下载后持续记录应用串口输出，保持所选波特率。
原 `.bin` 烧录命令与 115200 行为不变。

`--elf --emit` 输出完整会话的发送字节（菜单选择、波特率文本、每段地址/长度/数据、
入口文本），供测试逐字节比对；执行时仍须按协议等待各提示，不能把文件无等待地直接写入串口。
原 `.bin --emit` 仍只输出长度和镜像。

```sh
python3 -m unittest discover -s tools/board/tests -v
```
