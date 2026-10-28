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
| 根目录（menu） | 后门加载 bootloader 和 monitor；完整五行 logo、系统字段、100 MHz、无 C ISA；收到菜单后 UART 发送 `3` 和 Enter，检查系统信息 PASS 和第二次菜单 |
| `download/` | KEY1 拉低进入 BIOS，发送 `1` CR LF 后烧录；检查字节数、PASS 和返回菜单，松开 KEY1 后复位两次；两次都打印相同 data/BSS 初值和应用 PASS |

`run.py menu` / `run.py download` 各自只运行一个场景，串行复用同一个 Verilator 构建目录。
输出位于 `build/board_b1/`：`compile.log`、`case0.log`、`case1.log`、软件构建日志、
`download.wire` 和 64 位 ROM/SRAM 镜像。模拟器使用 `-Wall -j 1 -CFLAGS "-O3 -flto=1" -LDFLAGS -flto=1`；
首次编译时间单独计入回归总耗时，单场景仿真约几十秒，不执行完整 CoreMark。

软件镜像仍由 `sw/Makefile` 构建。make 的字节镜像通过
`tools/fpga/mem_init.py` 的同一个 `pack_image()` 转为存储包装模块使用的 64 位字，
与 PDS 的打包、空洞补零及字节顺序完全相同。

串口日志由 testbench 逐行输出，Python 同时复用 `sys_cpu/uart_checks.py` 检查
boot/monitor 固定字段和实际构建元数据。菜单程序本身持续运行，菜单场景由 testbench
在第二次菜单时结束；下载场景在第二次运行软件写 `SIM_EXIT=0` 后结束。

B1-8 BIOS flow (SoC spec v0.14 7.5): `download/` holds KEY1 through reset,
checks the BIOS banner/menu, sends `1` CR LF, waits for `UART download ready`,
then sends the `uart_tool --emit` length/image stream. It checks the exact byte
count and PASS result and a returned BIOS menu before releasing KEY1 and
resetting through `rst_n_i` twice. Each execution prints `B1 data hi/lo: 7/7 bss: 0`,
uses a 32-byte-aligned 64-bit initialized global, then changes both globals and calls `cache_clean_all()` before SIM_EXIT; the
second reset therefore proves data restoration and BSS clearing in SRAM.

The shared `verif/block/sys_cpu/edrv32_boot_window.sv` helper accelerates only testbench CLINT time:
a real 100 ms window is about 10 million clk_sys cycles. After observing three
software GPIO reads, it advances mtime to just before the 100 ms deadline and
lets the remaining samples execute normally. Both board and SC benches use
this helper; software, its 100 ms constant and RTL remain identical to hardware.
The menu case starts with KEY1 held, releases it for one sample, then presses
it again; reaching the monitor proves any release suppresses BIOS entry.

`window/` is a full-tier case with this acceleration disabled. It keeps KEY1
pressed for the real 100 ms window and ends after checking the BIOS banner/menu:

```sh
python3 tools/regress.py full --path verif/soc/board_b1/window -j 1
```
