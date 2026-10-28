# B1 板级仿真

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py smoke --path verif/soc/board_b1 -j 1
python3 verif/soc/board_b1/check_style.py
```

测试直接例化 `edrv32_fpga_board_b1_top`，CPU 子系统使用默认 `RVC_EN=0`，
板钟 27 MHz，`ip_pll_sys` 模型产生 100 MHz、8 个参考周期后置 `lock`。
系统子系统已有的 reset_ctrl/reset_sync 负责复位释放。UART 保持真实 115200 8N1，
复用 `verif/models/uart_model.sv`，不加速 UART 或后门注入接收数据。

| smoke 项 | 覆盖与通过判据 |
|---|---|
| 根目录（menu） | 后门加载 bootloader 和 monitor；完整五行 logo、系统字段、100 MHz、无 C ISA；收到菜单后 UART 发送 `3`，检查系统信息 PASS 和第二次菜单 |
| `download/` | 启动键拉低，只预加载 ROM；`uart_tool.py --emit` 生成下载流，UART 模型逐字节发送；小程序打印 `B1 UART application PASS`，并写 `SIM_EXIT=0` |

`run.py menu` / `run.py download` 各自只运行一个场景，串行复用同一个 Verilator 构建目录。
输出位于 `build/board_b1/`：`compile.log`、`case0.log`、`case1.log`、软件构建日志、
`download.wire` 和 64 位 ROM/SRAM 镜像。模拟器使用 `-Wall -j 1 -CFLAGS -O3`；
首次编译时间单独计入回归总耗时，单场景仿真约几十秒，不执行完整 CoreMark。

软件镜像仍由 `sw/Makefile` 构建。make 的字节镜像通过
`tools/fpga/mem_init.py` 的同一个 `pack_image()` 转为存储包装模块使用的 64 位字，
与 PDS 的打包、空洞补零及字节顺序完全相同。

串口日志由 testbench 逐行输出，Python 同时复用 `sys_cpu/uart_checks.py` 检查
boot/monitor 固定字段和实际构建元数据。菜单程序本身持续运行，菜单场景由 testbench
在第二次菜单时结束；下载场景由软件 `SIM_EXIT` 结束。
