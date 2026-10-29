# 任务卡 20261029-05-b3-vision：B3 图像通路工程（不含 NPU、RND），综合实现与点亮

## 1. 目标

建 PDS 工程 **B3V 图像通路**，完成综合、布局布线、bitstream，取得时序和资源报告，并上板确认新 BIOS 能启动。
- 可以与 B2、B3R、B3F 工程同时布局布线（用户 2026-10-29）。
- 软件（S2 演示等）以后经 BIOS 加载。

| 工程 | 顶层 | 内容 |
|---|---|---|
| **B3V 图像通路** | `edrv32_fpga_board_vision_top` | CPU、系统外设、DDR、VIN（两路摄像头，含 CH2）、PIX、GEO、DISP 两层、ETH；DDR3、HDMI、两路 OV5640、千兆网口。不含 NPU、RND（用户 2026-10-29 选“加上 ETH”） |

- 板级端口和引脚与 B2 完全相同：48 组端口、137 个引脚。
- 去掉了 NPU PLL 和 clk_npu。
- NPU、RND 的 APB 槽按空槽处理，访问返回总线错误。

## 2. 输入

- **代码分支**：本卡在分支 `zc100116/b3` 上，B3 尚未合入 `main`。Windows Codex 从包含本卡的 `origin/zc100116/b3` 提交拉出 `win/20261029-05-b3-vision`，并在 `result.md` 中记录完整哈希。
- **B3V**：
  - 板级顶层 `fpga/rtl/edrv32_fpga_board_vision_top.v`；端口、引脚、接死清单见 `fpga/rtl/README.md` 的“B3 图像通路板级顶层”一节；
  - 约束 `fpga/constraints/edrv32_fpga_board_vision_top.fdc`（16 个时钟定义）；
  - 导入脚本 `fpga/scripts/import_board_vision_top.tcl`，结束时打印 `edrv32: added <N> sources`，预期 N = 112。
- 本卡 `src/`：在 Linux 端从本分支 9510c64 构建，GCC 15.2.0。

  | 文件 | 内容 |
  |---|---|
  | `ip_rom_boot.dat` | bootloader + **新 BIOS**（6708 字节；菜单 `1=Program SRAM 2=Load 3=Run 4=Baud`，SoC 规格 v0.17 7.5 3a），2048 行 × 16 HEX 字符 |
  | `ip_ram_sram.dat` | 监控程序（20392 字节 text），8192 行 × 16 HEX 字符 |

## 3. 环境

- PDS 2022.2-SP6.1，器件 PG2L200H-6 FBB676，JTAG 下载，USB 串口接 UART。
- 新建工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3V\`，与 B2 工程同级，其他工程保留不动。路径不同时写进 `result.md`。
- 使用 20261029-03 任务卡建立的 `zc100116/b3` 第二份检出（例如 `G:\codex_project\EdRV32-Competition-2026-b3\`），先 `git fetch` 更新到包含本卡的提交。
  - 如果 B3R/B3F 正在使用这份检出导入，等它们的导入步骤完成后再切换提交；
  - 或者另建第三份检出。
- 多个工程同时布局布线时，内存不够就排队，在 `result.md` 中记下实际怎么跑的。

## 4. 需要的 IP

各 IP 的选项见 `fpga/ip/<IP 名>.md`。本工程不需要新生成 IP。

| IP | 操作 |
|---|---|
| `ip_pll_sys`、`ip_pll_video`、`ip_pll_eth`、`ip_ddr3` | 从 B2 工程复制。不需要 `ip_pll_npu` |
| CPU/SYS 5 个（I$/D$ tag/data、`ip_mul_s33x33`）、`ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w` | 从 B2 工程复制 |
| `ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、`ip_ram_disp_scan`（例化两次）、`ip_ram_eth_buf`、`ip_ram_eth_fifo` | 从 B2 工程复制 |
| `ip_rom_boot`、`ip_ram_sram` | 从 B3R 或 B3F 工程复制（新 BIOS）；还没生成时，用本卡 `src/` 的 `.dat` 重新生成。不能从 B2 复制 |
| NPU、RND 的 IP | 不需要 |

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 在 b3 检出中 `git fetch origin`，`git switch -c win/20261029-05-b3-vision origin/zc100116/b3`，`git submodule update --init`。阅读本卡、`fpga/ip/README.md`、`fpga/rtl/README.md` 的 B3 一节，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 新建 B3V 工程（PG2L200H-6 / FBB676），按第 4 节复制 IP。 |
| 2 | 用户（U） | 告诉 Codex 工程的 IP 目录。 |
| 3 | Windows Codex（C） | 检查 ROM/SRAM `.idf` 的初始化文件是本卡或 B3R/B3F 的新 BIOS 版本（不是 B2 的）。不一致时停下，写进 result.md（不改生成文件，也不改 RTL）。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | `source <b3 检出>/fpga/scripts/import_board_vision_top.tcl`，把打印的 `edrv32: added <N> sources` 告诉 Codex（预期 112）。编译报错就停下，把报错原文交给 Codex。 |
| 5 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`。任何一步报错就停下，把报错原文交给 Codex。资源超出容量时（`dev_map`/`pnr` 报错）按层次导出资源分布后停下，回传。 |
| 6 | Windows Codex（C） | **确认约束生效**：应有 clk_sys 10 ns、clk_mem 8 ns、clk_pix 13.468 ns、clk_serial、cam0/1、clk_eth 和 DDR IP 内部时钟，没有 clk_npu。`create_generated_clock` 不能报找不到对象。如果 B2 工程在步骤 7 已经在本地改过 PLL 引脚名，这里做同样的修改，并写进 result.md。setup 违例照常继续，写明即可。 |
| 7 | 用户（U） | 接好 HDMI 显示器、串口、两路摄像头和网线，下载 bitstream；告诉 Codex COM 口号。 |
| 8 | Windows Codex（C） | **启动**：打开串口记录 `build/board/b3v_boot.log`，请用户按一下复位键（不按 KEY1）。日志应出现 EdRV32 logo、启动信息（`CLK_SYS_HZ 100000000`）和监控程序菜单。没有输出时，请用户报告 LED 状态；DDR 初始化未完成时串口不会有任何输出，记下这一现象。 |
| 9 | Windows Codex（C） | **监控程序**：菜单 3（系统信息）运行一次，日志 `b3v_sysinfo.log`。 |
| 10 | Windows Codex（C） | **新 BIOS**：按住 KEY1 并复位，日志 `b3v_bios.log` 应出现 `BIOS: EdRV32` 和 `BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud`。<br>再输入 `4` 回车、`2000000` 回车，应打印 `Baud result: 2000000`。之后串口改为 2000000 波特率，按回车，应看到 BIOS 菜单（输入错误提示后重新打印菜单）。<br>复位退出。软件加载留给后续任务卡。 |
| 11 | 用户（U） | 观察并告诉 Codex：HDMI 显示器是否检测到信号（监控程序下 DISP 未使能，“无信号”属正常，如实记录）。 |
| 12 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-05-b3-vision results`，推送 `win/20261029-05-b3-vision`，告诉用户完成并给出分支名。中途停下时，已完成部分照常回传，写明停在哪一步和现象。 |

## 6. 产物

放在 `tasks/win/20261029-05-b3-vision/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/*_boot.log`、`*_sysinfo.log`、`*_bios.log` | 串口原始日志（文本） |
| 2 | `ip/` | 新生成 IP 的实际端口；ROM/SRAM 的初始化选项（`.idf` 中相关行） |
| 3 | `timing_summary.txt` | 每个时钟 slow/fast 角的 WNS/TNS/WHS/THS、违例端点数、推算 Fmax |
| 4 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM 18K/36K、APM、分布式 RAM、IO、PLL）。按层次展开到 cpu/sys/mem 子系统、VIN、PIX、GEO、DISP、ETH，以及板级适配 |
| 5 | `setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | 每个时钟域最差 200 条 setup（一行一条）、最差 20 条 setup 逐级明细、最差 20 条 hold（CLAUDE.md 10.5） |
| 6 | `fdc_used.fdc` | 只有在步骤 6 本地改过约束时才提交，内容为改后的全文 |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 实现：完成综合、布局布线和 bitstream；资源在器件容量内。
- 上板：
  - 串口打印 logo 和启动信息；
  - 监控程序菜单 3 有输出；
  - 能进入新 BIOS 菜单（`1=Program SRAM 2=Load 3=Run 4=Baud`），切换到 2000000 后仍能交互。
- 报告：第 6 节产物齐全；所有数字来自 PDS 报告和串口日志原文，找不到的写“未取得”。时序是否满足不作为停止条件，但必须写明。

## 8. result.md 模板

```markdown
# 20261029-05-b3-vision 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | <完整哈希> |
| PDS 版本 | |
| 工程路径 | |
| 导入源文件数 | |
| 运行方式（与其他工程并行/排队） | |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## IP
| IP | 来源（复制自哪个工程/新生成） | 备注（初始化文件等） |
|---|---|---|

## 约束
- 各时钟周期：
- create_generated_clock 是否全部命中、有无本地修改（改后的行）：

## 时序
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM 18K/36K | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

按层次：

## 上板
| 启动信息 | 监控菜单 3 | 新 BIOS 菜单 | 2000000 波特率交互 | HDMI 显示器 |
|---|---|---|---|---|

日志摘录：

## 完整报告在 Windows 本地的路径

## 备注
```
