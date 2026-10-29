# B1 板级仿真

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py smoke --path verif/soc/board_b1 -j 1
python3 verif/soc/board_b1/check_style.py
```

测试直接例化 `edrv32_fpga_board_b1_top`，CPU 子系统使用默认 `RVC_EN=0`，
板钟 27 MHz，`ip_pll_sys` 模型产生 100 MHz、8 个参考周期后置 `lock`。
系统子系统已有的 reset_ctrl/reset_sync 负责复位释放。UART 初始使用真实 115200 8N1，
复用 `verif/models/uart_model.sv`，不加速 UART 或后门注入接收数据。

| smoke 项 | 覆盖与通过判据 |
|---|---|
| 根目录（menu） | 后门加载 bootloader 和 monitor；完整五行 logo、系统字段、100 MHz、无 C ISA；收到菜单后 UART 发送 `3` 和 Enter，检查系统信息 PASS 和第二次菜单 |
| `download/` | KEY1 拉低进入 BIOS，发送 `1` CR LF 后烧录；检查字节数、PASS 和返回菜单，松开 KEY1 后复位两次；两次都打印相同 data/BSS 初值和应用 PASS |
| `load/` | BIOS `4` 切换 2000000，`2` 加载两个 SRAM ELF 段；检查非法地址和越过 BIOS 栈的 FAIL range、越界及未对齐入口的 FAIL address；`3` 跳转后打印应用 PASS 并写 SIM_EXIT=0 |

`run.py menu` / `run.py download` / `run.py load` 各自只运行一个场景，串行复用同一个 Verilator 构建目录。
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

## B1-10 BIOS v0.17 加载场景

`load/` 使用真实 UART 波特率，等待旧波特率完整 `Baud result: 2000000` 后
修改 peer 的波特率，检查硬件 BAUD_DIV 等于从生成的 CLK_SYS_HZ 计算的值。
`load.c` 的 ELF 有两个文件长度非零的 PT_LOAD（代码/常量和数据初值副本），
`run.py` 复用 `uart_tool.elf_segments()`、`load_wire_bytes()` 生成地址/长度/数据。
BSP 启动恢复 data、清零 BSS 后，程序检查初值、打印一行，再写 SIM_EXIT=0。

错误用例在成功 Run 之前执行，因为应用随后结束仿真：

- Load 到系统 APB 地址，发送 8 字节长度但不发 payload，必须 FAIL range 并返回菜单。
- Load 从 BIOS 栈前 4 字节开始、长度 8，必须 FAIL range 并返回菜单。
- Run 指向系统 APB 或 SRAM 基址加 2，必须 FAIL address 并返回菜单。

B1 没有 DDR，不向 DDR 发实际写事务。`sw/boot/tests/ranges.c` 主机编译 BIOS
同一个 `boot.h`，覆盖 DDR 可缓存区完整范围、首尾字节、跨界、非缓存别名、
长度为零和溢出区间，以及 SRAM 栈边界和 Run 对齐。实际 DDR 加载需上板验证。

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=bootloader
riscv-none-elf-size build/sw/bootloader/bootloader.elf
python3 tools/regress.py smoke --path verif/soc/board_b1 -j 1
python3 -m unittest discover -s sw/boot/tests -v
python3 -m unittest discover -s tools/board/tests -v
python3 -m unittest discover -s tools/debug_tool/tests -v
python3 verif/soc/board_b1/check_style.py
```

首次工作树须先 `git submodule update --init third_party/coremark`，普通菜单场景
需要仓库指定版本的 CoreMark。软件构建使用 GCC 15.2.0，Verilator 编译带
`-Wall -j 1`；C/C11 编译带 `-Wall -Wextra -Werror`。

## B1-10 验收记录

测试实现提交：`eefa446`；后续仅有文档和 Python 代码换行，无行为改动。
工具：xPack GCC 15.2.0、Verilator 5.020、Python 3.12、PySide6 6.12.0、pyserial 3.5。
ROM `text=6708`、`data=0`、`bss=0` 字节，16 KiB ROM 余 9676 字节。

| 命令 | 结果 | 原始日志 |
|---|---|---|
| `make -C sw PROGRAM=bootloader` | PASS，C11 `-Wall -Wextra -Werror`，0 警告 | `build/board_b1/bootloader.log` |
| `python3 tools/regress.py smoke --path verif/soc/board_b1 -j 1` | 3 PASS、0 FAIL；download 114 s、load 29 s、menu 75 s（含各场景构建） | `build/b1-10-regress.log`、`build/board_b1/case{0,1,3}.log` |
| `python3 -m unittest discover -s sw/boot/tests -v` | 1 PASS，包含 20 个 Load 和 12 个 Run 边界 | 主机标准输出 |
| `python3 -m unittest discover -s tools/board/tests -v` | 7 PASS；三档波特率、ELF LMA/文件长度、CLI emit、分片 UART 捕获与原始日志、FAIL 停止，逐字节比对 | `build/b1-10-board-unittest.log` |
| 下述完整依赖环境的 debug_tool unittest | 55 PASS，0 跳过；含 GUI 图像、NPU 参考和 ELF 三档传输、REST/CLI 字节流 | `build/b1-10-debug-full-unittest.log` |
| `python3 verif/soc/board_b1/check_style.py` | 1 文件、0 警告；回归 Verilator `-Wall` 编译无 RTL/testbench 警告 | 标准输出、`build/board_b1/compile.log` |

完整运行调试工具的既有 GUI/NPU 测试需使用 `docs/guides/env-setup.md` 指定的
NPU Python 环境，并提供项目已声明的 GUI/串口依赖：

```sh
git submodule update --init third_party/ultralytics
python3 -m pip install --target build/debug-tool-deps PySide6 pyserial
QT_QPA_PLATFORM=offscreen PYTHONPATH=build/debug-tool-deps \
  ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests -v
```

系统 Python 单独运行的结果是 51 PASS、4 项按既有环境条件跳过；上表记录完整依赖
环境结果。另已通过 Qt offscreen 检查烧录页的 SRAM/ELF 切换、默认 2000000 和
115200 不切换选项，确认调用同一 `engine.start_program(path, elf, baud)`。

交互示例的主机发送顺序：`4` CR LF → `2000000` CR → 两次 `2` CR LF 和各自
地址/长度/数据 → 两次非法 `2` 请求 → 两次非法 `3` 入口 → `3` CR LF 和
`0x10000000` CR。每步均等待其对应提示；最后的应用用 BSP 初始化 data/BSS，打印
一行后写 SIM_EXIT=0。以下为 case3 的串口接收原文（线上各行以 CR LF 结束）：

```text
BIOS: EdRV32
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
Baud:
Baud result: 2000000
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
UART load ready
Load bytes: 330 at 0x10000000
Load result: PASS
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
UART load ready
Load bytes: 4 at 0x1000014c
Load result: PASS
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
UART load ready
Load result: FAIL range
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
UART load ready
Load result: FAIL range
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
Run address:
Run result: FAIL address
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
Run address:
Run result: FAIL address
BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud
Run address:
Run: 0x10000000
B1 ELF application PASS
```

B1 没有 DDR，DDR 加载范围已由同一 C 代码的主机测试覆盖；实际 DDR 数据加载
与运行留到上板，Boot ROM 内容随下一次 bitstream 生成。本任务未修改 RTL、规格、
FPGA 工程或 BSP 链接脚本，未执行完整 SoC 回归。
