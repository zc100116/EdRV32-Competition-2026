# 任务卡 20261028-06-board-b1：B1 CPU 最小系统上板（100 MHz，启动信息和 CoreMark）

## 1. 目标

把 B1 板级顶层 `edrv32_fpga_board_b1_top`（CPU、I$/D$、系统子系统，clk_sys 100 MHz 由 PLL 产生）综合、布局布线、生成 bitstream 并下载到板上，取得上板串口日志（启动 logo 和启动信息、CoreMark O2 和 tuned 两种编译选项的分数与 HPM）以及资源和时序报告（`docs/plan/board-plan.md` B1-7）。

## 2. 输入

- 任务卡 commit：`main` 上包含本任务卡的提交（Windows Codex 在 `result.md` 中记录完整哈希）。
- 板级顶层 `fpga/rtl/edrv32_fpga_board_b1_top.v`：27 MHz 板钟（D18）→ `ip_pll_sys` → clk_sys 100 MHz；复位键（C22）与 PLL `lock` 共同作为复位；UART（RX B24、TX C24）、启动键（C23）、4 个 LED（A20、C18、C19、E18）。
- 约束 `fpga/constraints/edrv32_fpga_board_b1_top.fdc`：`clk_board` 37.037 ns；PLL 输出 `create_generated_clock -name clk_sys ... [get_pins {u_pll_sys/clkout0}] -multiply_by 100 -divide_by 27`（写法取自厂商 DDR3 demo，**PLL 输出引脚层次名需要在 PDS 中确认**，见步骤 6）。
- 导入脚本 `fpga/scripts/import_board_b1_top.tcl`：展开 `rtl/filelists/cpu_subsys.f`、`sys_subsys.f`，加入板级顶层和约束，定义 `FPGA_MODE`。
- 本卡 `src/`（在 Linux 端由 commit `75dff18` 构建，GCC 15.2.0，rv32im_zicsr_zifencei）：

  | 文件 | 内容 |
  |---|---|
  | `ip_rom_boot.dat` | bootloader（4584 字节），ROM 初始化文件，2048 行 × 16 HEX 字符 |
  | `ip_ram_sram.dat` | 监控程序（-O2），SRAM 初始化文件，8192 行 × 16 HEX 字符 |
  | `monitor_o2.bin` | 同一个 -O2 监控程序的二进制（UART 下载用，与 SRAM 初始化内容相同） |
  | `monitor_tuned.bin` | tuned 选项（`-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4`）的监控程序，UART 下载用 |

- 串口工具 `tools/board/uart_tool.py`（用法见 `tools/board/README.md`），需要 `py -m pip install pyserial==3.5`。

## 3. 环境

- PDS 2022.2-SP6.1（build 138931），器件 PG2L200H-6 FBB676；开发板通过 JTAG 下载，USB 串口接 UART。
- 工程：把现有的 `G:\codex_project\EdRV32-FPGA\EdRV32\` 整个目录复制为 `G:\codex_project\EdRV32-FPGA\EdRV32-B1\`（保留其中已生成的 7 个 CPU 子系统 IP），在副本中操作；原工程留给之后的布局实验，不要修改。导入脚本按 `../../EdRV32-Competition-2026` 找仓库，副本与原工程同级即可。路径不同时写进 `result.md`。

## 4. 需要的 IP

| IP | 操作 | 创建说明 |
|---|---|---|
| `ip_pll_sys` | **新生成** | `fpga/ip/ip_pll_sys.md`：输入 27 MHz，CLKOUT0 100.000 MHz，带 `lock`。IP Compiler 显示的实际频率**不是 100.000 MHz 时停下**，把实际频率和分频参数告诉 Codex 写进 result.md |
| `ip_rom_boot` | **重新生成**（加初始化文件） | `fpga/ip/ip_rom_boot.md`；初始化文件选本卡 `src/ip_rom_boot.dat`（HEX） |
| `ip_ram_sram` | **重新生成**（加初始化文件） | `fpga/ip/ip_ram_sram.md`；初始化文件选本卡 `src/ip_ram_sram.dat`（HEX） |
| 其余 5 个（I$/D$ tag/data、`ip_mul_s33x33`） | 沿用，不改 | — |

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261028-06-board-b1 origin/main`；阅读本卡，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 按第 3 节复制工程目录并打开副本；在工程中移除上一轮导入的全部设计源文件和约束文件（保留 IP）。 |
| 2 | 用户（U） | 按第 4 节生成 `ip_pll_sys`，重新生成 `ip_rom_boot`、`ip_ram_sram`（选本卡 `src/` 中的初始化文件）。告诉 Codex IP 目录。 |
| 3 | Windows Codex（C） | 核对 `ip_pll_sys` 的模块名和端口（`clkin1`、`clkout0`、`lock`）与板级顶层一致；核对 ROM/SRAM IP 的 `.idf` 中初始化选项已使能、格式 HEX、路径指向本卡文件。不一致时停下，写进 result.md（不改生成文件，也不改 RTL）。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_b1_top.tcl`，确认打印 `edrv32: added 42 sources`。编译报错就停下，把报错原文交给 Codex。 |
| 5 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。任何一步报错就停下，把报错原文交给 Codex。 |
| 6 | Windows Codex（C） | 确认约束生效：时序报告中有 `clk_board`（37.037 ns）和 `clk_sys`（10.000 ns）两个时钟，`clk_sys` 覆盖 CPU 和系统子系统的寄存器；`create_generated_clock` 有无报错或警告（PLL 输出引脚名不对时 PDS 会报找不到对象）。**引脚名不对时**：从编译后网表中找到 PLL 输出引脚的实际层次名，只在本地 `.fdc` 中改正后从步骤 4 重跑，把改后的那一行写进 result.md（协调者改仓库）。clk_sys 的 setup 违例（WNS < 0）时照常继续上板，但写明。 |
| 7 | 用户（U） | 用 PDS 下载 bitstream（JTAG）；连接 USB 串口，告诉 Codex COM 口号。 |
| 8 | Windows Codex（C） | **启动信息和 O2 CoreMark**：先运行 `py tools/board/uart_tool.py --port COMx --log build/board/b1_o2.log --menu 1 --iterations 5000`，再请用户按一下复位键（C22，不按启动键）。日志中应依次出现 EdRV32 logo、启动信息（CHIP_ID、`CLK_SYS_HZ 100000000`、ISA 不含 c 等）、监控程序菜单，随后 CoreMark 运行约 14 秒后输出分数、CoreMark/MHz、CRC、HPM。看到 CoreMark 结果和下一个菜单后按 Ctrl-C。 |
| 9 | Windows Codex（C） | **tuned CoreMark**：运行 `py tools/board/uart_tool.py tasks/win/20261028-06-board-b1/src/monitor_tuned.bin --port COMx --log build/board/b1_tuned.log --menu 1 --iterations 5000`，再请用户**按住启动键（C23）并按一下复位键（C22）**，看到 `UART download ready` 和下载开始后松开启动键。结果出来后 Ctrl-C。 |
| 10 | Windows Codex（C） | **系统信息和外设测试**：按一下复位键后分别用 `--menu 3`、`--menu 2` 各运行一次（不带镜像），日志 `b1_sysinfo.log`、`b1_periph.log`。外设测试中需要用户观察的内容（LED、按键），按串口提示请用户操作并把观察结果写进 result.md。 |
| 11 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261028-06-board-b1 results`，推送 `win/20261028-06-board-b1`，告诉用户完成并给出分支名。中途停下时，已完成部分照常回传，并写明停在哪一步、现象（例如串口无输出时 LED 状态、PLL lock 情况）。 |

## 6. 产物

放在 `tasks/win/20261028-06-board-b1/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/b1_o2.log`、`b1_tuned.log`、`b1_sysinfo.log`、`b1_periph.log` | 串口原始日志（文本） |
| 2 | `ip/` | `ip_pll_sys` 实际端口、实际输出频率和分频参数、选项截图；ROM/SRAM 的初始化选项（`.idf` 中相关行） |
| 3 | `timing_summary.txt` | 各时钟 slow/fast 角 WNS/TNS/WHS/THS、违例端点数；clk_sys 推算 Fmax（`1000 / (10.000 − WNS)` MHz）；两个时钟的周期 |
| 4 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM 18K/36K、APM、分布式 RAM、IO、PLL）；按层次：`u_cpu_subsys`（及 `u_core`、`u_icache`、`u_dcache`）、`u_sys_subsys` 的下一级 |
| 5 | `setup_top200.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | clk_sys 最差 200 条 setup（一行一条）、最差 20 条逐级明细、最差 20 条 hold |
| 6 | `fdc_used.fdc` | 仅在步骤 6 本地改过约束时提交改后的全文 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 上板：串口打印 logo 和启动信息，`CLK_SYS_HZ` 为 100000000；O2 和 tuned 两次 CoreMark 的 CRC 校验正确并输出分数；系统信息和外设测试有输出。
- 报告：第 6 节产物齐全；所有数字来自 PDS 报告和串口日志原文，找不到的写"未取得"。时序是否满足 100 MHz 不作为停止条件，但必须写明。

## 8. result.md 模板

```markdown
# 20261028-06-board-b1 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | <完整哈希> |
| PDS 版本 | |
| 工程路径 | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## IP
| IP | 模块名 | 端口与顶层一致 | 备注（PLL 实际频率、N/M/O；初始化文件） |
|---|---|---|---|

## 约束
- clk_board / clk_sys 周期：
- create_generated_clock 是否生效、有无本地修改（改后的行）：

## 时序
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

clk_sys 最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| | LUT | FF | DRM 18K/36K | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|

按层次（u_core、u_icache、u_dcache、u_sys_subsys 各子模块）：

## 上板
- 启动信息（日志摘录）：
- CoreMark：

| 编译选项 | 迭代次数 | 计时周期 | CoreMark | CoreMark/MHz | CRC | IPC |
|---|---|---|---|---|---|---|
| O2 | | | | | | |
| tuned | | | | | | |

仿真参考（RTL 仿真，同一配置 RV32IM、SRAM、8 KiB I$/D$）：O2 3.592456，tuned 4.290770 CoreMark/MHz。

- 系统信息、外设测试（含用户观察）：

## 完整报告在 Windows 本地的路径

## 备注
```
