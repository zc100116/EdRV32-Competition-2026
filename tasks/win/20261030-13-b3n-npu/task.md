# 任务卡 20261030-13-b3n-npu：B3N（只含 CPU + DDR + NPU）单独综合布线，上板跑 NPU 功能测试

## 1. 目标

NPU 的 MAC 阵列改成了 APM SIMD 级联累加（设计记录 `docs/design/2026-10-30-npu-apm-cascade.md`，NPU 规格 v0.5），NPU 控制路径也做了时序修复。本卡用只含 CPU、DDR 和 NPU 的工程 B3N **单独**跑一次综合和布局布线，看级联链能否合法放置、布线是否顺利；再上板运行 `board_npu`，检查 NPU 的逐字节正确性和整网帧率（设计记录 `docs/design/2026-10-30-board-npu-test.md`）。

| 口径 | 工程 | 顶层 | 内容 |
|---|---|---|---|
| NPU 单独 | **B3N** | `edrv32_fpga_board_npu_top` | CPU、系统外设（BIOS ROM、SRAM、UART、GPIO、PLIC、CLINT、SYSCTRL）、DDR、NPU。没有 VIN/PIX/GEO/RND/DISP/ETH，没有 HDMI、摄像头、网口 |

本卡**不加区域约束**；区域约束的对比在拿到本卡结果后另出卡。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261030-13-b3n-npu`，在 `result.md` 中记录完整哈希。RTL 为 `b5dc9469` 及之后。
- 板级顶层 `fpga/rtl/edrv32_fpga_board_npu_top.v`（说明见 `fpga/rtl/README.md` 的 B3N 一节）。
- 约束 `fpga/constraints/edrv32_fpga_board_npu_top.fdc`（10 个时钟定义：clk_board、clk_ddr_ref、clk_sys、clk_npu、clk_mem、rst_clk、phy_dq_clk_0/1、phy_dq_sysclk_0/1）。
- 导入脚本 `fpga/scripts/import_board_npu_top.tcl`，预期打印 `edrv32: added 87 sources`。
- 本卡 `src/`（Linux 端从 `b5dc9469` 构建）：

  | 文件 | 内容 |
  |---|---|
  | `ip_rom_boot.dat`、`ip_ram_sram.dat` | 与卡 08 相同的新 BIOS 和监控程序 |
  | `board_npu.elf` | NPU 上板测试，约 5.2 MB；39 项：A 寄存器 3 项、B 小用例 15 个、C 整网 1 项、D 连续 20 帧 |

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676，JTAG，USB 串口。
- 新建工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3N\`。
- **本工程单独运行**，不要和其他工程同时综合或布线，便于看清布线耗时和内存。

## 4. 需要的 IP

共 21 种，全部从 B3VN 工程（`G:\codex_project\EdRV32-FPGA\EdRV32-B3VN`）复制，不需要新生成：

| IP | 说明 |
|---|---|
| `ip_pll_sys`、`ip_pll_npu`、`ip_ddr3` | 板级 |
| `ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、`ip_ram_dcache_data`、`ip_mul_s33x33` | CPU |
| `ip_rom_boot`、`ip_ram_sram` | 新 BIOS；初始化文件应与本卡 `src/` 的 `.dat` 一致 |
| `ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w` | 存储子系统 |
| `ip_ram_npu_line/weight/quant/lut/residual/result/scratch`、`ip_mul_npu_quant_low/high` | NPU |

**不要**复制 `ip_pll_video`、`ip_pll_eth` 和媒体、网口的 IP。MAC 阵列直接例化 `GTP_APM_E2` 原语（`rtl/tech/edrv32_mac_npu_int8_chain.v`），不需要 IP（见 `fpga/ip/ip_mac_npu_int8_chain.md`）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261030-13-b3n-npu origin/zc100116/b3`。阅读本卡、`fpga/rtl/README.md` 的 B3N 一节和 `sw/tests/board_npu/README.md`，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 新建 B3N 工程（PG2L200H-6 / FBB676），按第 4 节复制 21 个 IP，告诉 Codex IP 目录。 |
| 2 | Windows Codex（C） | 检查 ROM/SRAM 的初始化文件与本卡 `src/` 的 `.dat` 一致，不一致就停下写进 `result.md`。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 当前目录为工程目录，执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_npu_top.tcl`，把打印的源文件数告诉 Codex（预期 87）。编译报错就停下，把报错原文交给 Codex。 |
| 4 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录每一步的耗时和峰值内存；布线过程中记下每一轮的未布通网络数（与卡 10 的 `route_progress.tsv` 同格式）。任何一步报错就停下，回传报错原文和已经取得的产物。**`dev_map` 或 `pnr` 报 APM 级联（CPO/CPI）放置或连接相关的错误时，原文全部抄下**，这是本卡最关心的问题。 |
| 5 | Windows Codex（C） | 确认约束生效：clk_sys 10 ns、clk_mem 8 ns、clk_npu 6.667 ns、DDR IP 内部时钟；`create_generated_clock` 不能报找不到对象。setup 违例照常继续，写明即可。 |
| 6 | 用户（U） | 接好串口，下载 bitstream，告诉 Codex COM 口号。 |
| 7 | Windows Codex（C） | **启动**：打开串口记录 `build/board/b3n_boot.log`，请用户按一下复位键（不按 KEY1），应出现 EdRV32 logo、启动信息和监控程序菜单。 |
| 8 | 用户（U） + Codex（C） | **NPU 测试**：<br>1. 用户按住 KEY1 并复位进入 BIOS；<br>2. Codex 执行 `py tools/board/uart_tool.py tasks/win/20261030-13-b3n-npu/src/board_npu.elf --elf --baud 2000000 --port COMx --log build/board/b3n_board_npu.log`（加载约 26 秒）；<br>3. 程序跑完最后一行为 `NPU board: PASS 39/39` 或 `NPU board: FAIL ...`；LED4 亮表示通过，LED5 亮表示失败。请用户报告 LED 状态。<br>失败时日志里有失败项、描述符号、首个不一致的地址、期望值和实际值，原样保留。 |
| 9 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261030-13-b3n-npu results`，推送 `win/20261030-13-b3n-npu`，告诉用户完成并给出分支名。中途停下时，已完成部分照常回传，写明停在哪一步和现象。 |

## 6. 产物

放在 `tasks/win/20261030-13-b3n-npu/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/b3n_boot.log`、`uart/b3n_board_npu.log` | 串口原始日志 |
| 2 | `timing_summary.txt` | 布线后每个时钟 slow/fast 角的 WNS/TNS/WHS/THS、违例端点数、推算 Fmax |
| 3 | `setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | CLAUDE.md 10.5 |
| 4 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM、APM、分布式 RAM、IO、PLL）；按层次展开到 cpu/sys/mem 子系统和 NPU（NPU 再展开到 datapath、mac_array、conv、DMA） |
| 5 | `flow_summary.txt`、`route_progress.tsv` | 各阶段耗时、峰值内存、W/C/E 行数；布线每轮未布通网络数；失败时附失败网络摘要 |
| 6 | `apm_placement.pcf` | 布线完成后在工程目录执行 `generate_constraint -file {apm_placement.pcf} -device {APM}` 得到的 APM 布局（用于检查 8 级链是否落在同一列的连续站点） |

不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 实现：完成布线和 bitstream；没有 APM 级联相关的错误。
- 上板：`NPU board: PASS 39/39`，日志中有整网 `ms/frame` 和 `fps`。
- 时序：如实记录，不作为停止条件。
- 所有数字来自 PDS 报告和串口日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261030-13-b3n-npu 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | |
| PDS 版本 | |
| 工程路径 | |
| 导入源文件数 | |
| 各阶段耗时 / 峰值内存（综合/映射/布局布线） | |
| 布线轮数、最后一轮未布通数 | |
| APM 级联相关的警告或错误 | 无 / 原文 |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## 时序（布线后）
| 时钟 / 角 | WNS | TNS | WHS | THS | setup 违例端点 | Fmax（推算） |
|---|---|---|---|---|---|---|

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

按层次（cpu/sys/mem、NPU 及其子模块）：

## 上板
| 启动信息 | board_npu 结果 | LED | 整网 ms/frame | fps |
|---|---|---|---|---|

失败项（如有）：

日志摘录（每项一行的 `NPU ... PASS/FAIL` 全部列出）：

## 完整报告在 Windows 本地的路径

## 备注
```
