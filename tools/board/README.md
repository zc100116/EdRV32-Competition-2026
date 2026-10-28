# B1 UART 下载

Windows 安装依赖：`py -m pip install pyserial==3.5`（同 `tools/requirements.txt`）。
输入为 `make -C sw PROGRAM=monitor` 从 ELF 经 objcopy 生成的
`build/sw/monitor/monitor.bin`，入口在 SRAM 基址，负载最多 61440 字节，留出
bootloader 顶部 4 KiB 栈空间。下载协议见 `sw/boot/README.md`：4 字节小端长度，
随后原始镜像，无校验和或逐字节应答。

```sh
py tools/board/uart_tool.py build/sw/monitor/monitor.bin --port COM3 --log build/board/coremark.log --menu 1
```

先运行工具，再按住启动键（C23）并按复位键（C22），等下载开始后可松开启动键。
工具等待 `UART download ready` 后发送镜像，持续显示串口输出并保存原始 CRLF 日志，
Ctrl-C 停止。115200 波特、8N1，无流控。可选 `--menu 1` 在菜单出现后发送 `1` 和
Enter，CoreMark 使用默认 10 次迭代；`--menu 3` 请求系统信息。要手动操作菜单时关闭
该工具后再用串口终端打开同一端口。

仿真生成完全相同的下载字节流（不需要 pyserial）：

```sh
python3 tools/board/uart_tool.py build/board_b1/download/sc04.bin --emit build/board_b1/download.wire
python3 tools/regress.py smoke --path verif/soc/board_b1 -j 1
```

`--emit` 只包含主机发给 bootloader 的长度和镜像，菜单选择在下载之后单独发送。
