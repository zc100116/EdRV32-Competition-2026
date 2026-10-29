# 任务卡 20261029-03-b3-render-full：B3 渲染验证工程和 B3 完整系统工程，综合实现与点亮

## 1. 目标

建两个 PDS 工程，各自完成综合、布局布线、生成 bitstream，取得时序和资源报告，并上板确认新 BIOS 能启动。
- 两个工程可以与正在运行的 B2 工程同时布局布线（用户 2026-10-29）。
- 软件程序（RND 自检、S3 LVGL 与游戏、NES）以后经 BIOS 下载到 DDR 运行，不需要重新生成 bitstream，由后续任务卡执行。

| 工程 | 顶层 | 内容 |
|---|---|---|
| **B3R 渲染验证** | `edrv32_fpga_board_render_top` | CPU、系统外设、DDR、RND、DISP 两层、HDMI。不含摄像头、PIX、GEO、NPU、ETH |
| **B3F 完整系统** | `edrv32_fpga_board_b2_top`（板级顶层与 B2 相同，SoC 换成 B3 版本） | CPU、系统、存储、VIN + PIX + CH2、GEO、**RND**、**DISP 两层**、NPU、ETH；DDR3、HDMI、两路 OV5640、千兆网口 |

B3F 与正在运行的 B2 工程的区别：SoC 中加入了 RND（P4、媒体 APB 槽 4、PLIC 源 11），DISP 升级为两层（v0.3，多一个 L1 扫描 FIFO）；Boot ROM 为新 BIOS。板级顶层、引脚、约束都相同。

## 2. 输入

- **代码分支**：本卡在分支 `zc100116/b3` 上，B3 尚未合入 `main`。Windows Codex 从包含本卡的 `origin/zc100116/b3` 提交拉出 `win/20261029-03-b3-render-full`，并在 `result.md` 中记录完整哈希。
- **B3R**：
  - 板级顶层 `fpga/rtl/edrv32_fpga_board_render_top.v`；端口、引脚、接死清单见 `fpga/rtl/README.md` 的“B3 渲染验证板级顶层”一节；
  - 约束 `fpga/constraints/edrv32_fpga_board_render_top.fdc`；
  - 导入脚本 `fpga/scripts/import_board_render_top.tcl`，结束时打印 `edrv32: added <N> sources`，预期 N = 86。
- **B3F**：
  - 板级顶层 `fpga/rtl/edrv32_fpga_board_b2_top.v`；
  - 约束 `fpga/constraints/edrv32_fpga_board_b2_top.fdc`；
  - 导入脚本 `fpga/scripts/import_board_b2_top.tcl`（展开 `rtl/filelists/soc.f`，B3 中已含 `rnd.f`），预期 N = 173（SoC 169 + 板级 4）。
  - 三个文件都与 B2 相同，只是从本分支导入。
- 本卡 `src/`：在 Linux 端从本分支 9510c64 构建，GCC 15.2.0。两个工程共用：

  | 文件 | 内容 |
  |---|---|
  | `ip_rom_boot.dat` | bootloader + **新 BIOS**（6708 字节；菜单 `1=Program SRAM 2=Load 3=Run 4=Baud`，SoC 规格 v0.17 7.5 3a），2048 行 × 16 HEX 字符 |
  | `ip_ram_sram.dat` | 监控程序（20392 字节 text），8192 行 × 16 HEX 字符 |

## 3. 环境

- PDS 2022.2-SP6.1，器件 PG2L200H-6 FBB676，JTAG 下载，USB 串口接 UART。
- 新建两个工程：
  - `G:\codex_project\EdRV32-FPGA\EdRV32-B3R\`
  - `G:\codex_project\EdRV32-FPGA\EdRV32-B3F\`
- 与 B2 工程同级，B1、MEDIA、NPU、B2 工程保留不动。路径不同时写进 `result.md`。
- 本地需要第二份仓库检出：B2 工程从 `main` 导入，这两个工程从 `zc100116/b3` 导入，不能共用一份工作区。
  - 例如 `G:\codex_project\EdRV32-Competition-2026-b3\`；
  - 两个工程的导入脚本从这份检出 `source`。
- 三个工程同时布局布线时，内存不够就按 B3R → B3F 的顺序排队，在 `result.md` 中记下实际怎么跑的。

## 4. 需要的 IP

各 IP 的选项见 `fpga/ip/<IP 名>.md`，总表见 `fpga/ip/README.md`。

| IP | B3R | B3F | 操作 |
|---|---|---|---|
| `ip_pll_sys`、`ip_pll_video`、`ip_ddr3` | ✓ | ✓ | 从 B2 工程复制 |
| `ip_pll_npu`、`ip_pll_eth` | | ✓ | 从 B2 工程复制 |
| CPU/SYS 5 个（I$/D$ tag/data、`ip_mul_s33x33`）、`ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w` | ✓ | ✓ | 从 B2 工程复制 |
| `ip_ram_disp_scan` | ✓ | ✓ | 从 B2 工程复制。DISP v0.3 例化两次（L0、L1），用同一个 IP，不需要另外生成 |
| VIN/PIX/GEO/ETH 的 5 个（`ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、`ip_ram_eth_buf`、`ip_ram_eth_fifo`）、NPU 的 9 个 | | ✓ | 从 B2 工程复制 |
| `ip_ram_rnd_line`、`ip_ram_rnd_palette` | ✓ | ✓ | **新生成**（`ip_ram_rnd_line.md`、`ip_ram_rnd_palette.md`）。在一个工程生成后复制到另一个 |
| `ip_rom_boot`、`ip_ram_sram` | ✓ | ✓ | **重新生成**，初始化文件选本卡 `src/` 中的两个 `.dat`（HEX）。不能从 B2 复制：B2 的 ROM 是旧 BIOS |

## 5. 操作步骤

两个工程各做一遍步骤 1–7，可以交错进行。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 在第二份检出中 `git fetch origin`，`git switch -c win/20261029-03-b3-render-full origin/zc100116/b3`，`git submodule update --init`。阅读本卡、`fpga/ip/README.md`、`fpga/rtl/README.md` 的 B3 一节，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 新建 B3R、B3F 工程（PG2L200H-6 / FBB676），按第 4 节从 B2 工程复制 IP。 |
| 2 | 用户（U） | 生成 `ip_ram_rnd_line`、`ip_ram_rnd_palette`；重新生成 `ip_rom_boot`、`ip_ram_sram`（选本卡 `src/` 的 `.dat`）。告诉 Codex 两个工程的 IP 目录。 |
| 3 | Windows Codex（C） | 核对新生成 IP 的模块名和端口与 `rtl/tech/edrv32_ram_rnd_line.v`、`edrv32_ram_rnd_palette.v` 包装模块一致（`fpga/ip/*.md` 末尾的期望端口），检查 ROM/SRAM `.idf` 的初始化选项。不一致时停下，写进 result.md（不改生成文件，也不改 RTL）。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | 在 B3R 中 `source <第二份检出>/fpga/scripts/import_board_render_top.tcl`，在 B3F 中 `source <第二份检出>/fpga/scripts/import_board_b2_top.tcl`，把打印的 `edrv32: added <N> sources` 告诉 Codex（预期 86 / 173）。编译报错就停下，把报错原文交给 Codex。 |
| 5 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。任何一步报错就停下，把报错原文交给 Codex。资源超出容量时（`dev_map`/`pnr` 报错）按层次导出资源分布后停下，回传。 |
| 6 | Windows Codex（C） | **确认约束生效**：<br>• B3R 应有 clk_sys 10 ns、clk_mem 8 ns、clk_pix 13.468 ns、clk_serial 和 DDR IP 内部时钟；<br>• B3F 与 B2 相同（另有 clk_npu 6.667 ns、clk_eth）。<br>`create_generated_clock` 不能报找不到对象。如果 B2 工程在步骤 7 已经在本地改过 PLL 引脚名，这里做同样的修改，并写进 result.md。setup 违例照常继续，写明即可。 |
| 7 | 用户（U） | 接好 HDMI 显示器、串口（B3F 另接两路摄像头和网线），下载 bitstream；告诉 Codex COM 口号。 |
| 8 | Windows Codex（C） | **启动**：打开串口记录 `build/board/<工程>_boot.log`，请用户按一下复位键（不按 KEY1）。日志应出现 EdRV32 logo、启动信息（`CLK_SYS_HZ 100000000`）和监控程序菜单。没有输出时，请用户报告 LED 状态；DDR 初始化未完成时串口不会有任何输出，记下这一现象。 |
| 9 | Windows Codex（C） | **监控程序**：菜单 3（系统信息）运行一次，日志 `<工程>_sysinfo.log`。 |
| 10 | Windows Codex（C） | **新 BIOS**：按住 KEY1 并复位，日志 `<工程>_bios.log` 应出现 `BIOS: EdRV32` 和 `BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud`。<br>再输入 `4` 回车、`2000000` 回车，应打印 `Baud result: 2000000`。之后串口改为 2000000 波特率，按回车，应看到 BIOS 菜单（输入错误提示后重新打印菜单）。<br>复位退出。软件加载留给后续任务卡。 |
| 11 | 用户（U） | 观察并告诉 Codex：HDMI 显示器是否检测到信号（监控程序下 DISP 未使能，“无信号”属正常，如实记录）。 |
| 12 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-03-b3-render-full results`，推送 `win/20261029-03-b3-render-full`，告诉用户完成并给出分支名。一个工程先完成时可以先回传，另一个完成后追加提交。中途停下时，已完成部分照常回传，写明停在哪一步和现象。 |

## 6. 产物

放在 `tasks/win/20261029-03-b3-render-full/artifacts/<B3R 或 B3F>/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/*_boot.log`、`*_sysinfo.log`、`*_bios.log` | 串口原始日志（文本） |
| 2 | `ip/` | 新生成 IP 的实际端口；ROM/SRAM 的初始化选项（`.idf` 中相关行） |
| 3 | `timing_summary.txt` | 每个时钟 slow/fast 角的 WNS/TNS/WHS/THS、违例端点数、推算 Fmax |
| 4 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM 18K/36K、APM、分布式 RAM、IO、PLL）。按层次展开到子系统和各引擎（B3R：cpu/sys/mem 子系统、RND、DISP；B3F：`u_soc` 下一级），以及板级适配 |
| 5 | `setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | 每个时钟域最差 200 条 setup（一行一条）、最差 20 条 setup 逐级明细、最差 20 条 hold（CLAUDE.md 10.5） |
| 6 | `fdc_used.fdc` | 只有在步骤 6 本地改过约束时才提交，内容为改后的全文 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 实现：两个工程都完成综合、布局布线和 bitstream；资源在器件容量内。
- 上板：
  - 串口打印 logo 和启动信息；
  - 监控程序菜单 3 有输出；
  - 能进入新 BIOS 菜单（`1=Program SRAM 2=Load 3=Run 4=Baud`），切换到 2000000 后仍能交互。
- 报告：第 6 节产物齐全；所有数字来自 PDS 报告和串口日志原文，找不到的写“未取得”。时序是否满足不作为停止条件，但必须写明。

## 8. result.md 模板

```markdown
# 20261029-03-b3-render-full 结果

| 项 | B3R | B3F |
|---|---|---|
| 代码 commit（origin/zc100116/b3） | <完整哈希> | <完整哈希> |
| PDS 版本 | | |
| 工程路径 | | |
| 导入源文件数 | | |
| 运行方式（与 B2 并行/排队） | | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） | |

## IP
| 工程 | IP | 模块名 | 端口与包装一致 | 备注（初始化文件等） |
|---|---|---|---|---|

## 约束
- 各时钟周期：
- create_generated_clock 是否全部命中、有无本地修改（改后的行）：

## 时序
| 工程 | 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|---|

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| 工程 | LUT | FF | DRM 18K/36K | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|

按层次：

## 上板
| 工程 | 启动信息 | 监控菜单 3 | 新 BIOS 菜单 | 2000000 波特率交互 | HDMI 显示器 |
|---|---|---|---|---|---|

日志摘录：

## 完整报告在 Windows 本地的路径

## 备注
```
