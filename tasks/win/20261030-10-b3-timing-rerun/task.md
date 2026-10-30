# 任务卡 20261030-10-b3-timing-rerun：四个工程带时序修复重新综合布线

## 1. 目标

在包含 2026-10-30 全部时序修复的 `zc100116/b3` 上，四个口径的工程重新综合、布局布线、生成 bitstream，回传时序和资源报告。

| 口径 | 工程 | 顶层 | 导入脚本 | 预期 N |
|---|---|---|---|---|
| 图像 | B3V | `edrv32_fpga_board_vision_top` | `import_board_vision_top.tcl` | 112 |
| 图像 + NPU | B3VN | `edrv32_fpga_board_vnpu_top` | `import_board_vnpu_top.tcl` | 144 |
| 渲染器 | B3R | `edrv32_fpga_board_render_top` | `import_board_render_top.tcl` | 86 |
| 全部 | B3F | `edrv32_fpga_board_b2_top`（B3 SoC） | `import_board_b2_top.tcl` | 162 |

**本次包含的修复**（依据 B3V 卡 07 的布线报告）：

| 修复 | B3V 最差路径 | 报告 |
|---|---|---|
| PERF_MON 读校验、延迟统计打拍（M-F2） | clk_mem −0.554 ns，32 个违例端点 | — |
| mem_xbar 读缓冲地址、违规检测、调度、统计（X-F1） | clk_mem −0.085 ns 及一批 0–0.4 ns 路径 | `docs/reports/2026-10-30-timing-mem-xbar.md` |
| CPU 计数器、D$ 命中扇出等（C-F1） | clk_sys +0.182 ns | `docs/reports/2026-10-30-timing-cpu-f1.md` |
| RGMII 收发各打一拍（E-F1） | clk_eth +0.798 ns | `docs/reports/2026-10-30-timing-eth-rgmii.md` |

- 卡 07、08 中还在用旧代码运行的工程可以停掉，改跑本卡。
- 软件随后按卡 09 执行（程序已含切换不黑屏，烧录工具已支持板子已在 BIOS 时直接开始）。
- 调试工具的中控台另行回传，见第 5 节步骤 6。

## 2. 输入

- 代码分支 `origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261030-10-b3-timing-rerun`，在 `result.md` 中记录完整哈希。
- 与卡 07/08 相比：
  - 没有新增或删除源文件；
  - 约束、IP、导入脚本都没有变化，只是 RTL 内容更新。

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- **工程**：
  - 卡 07/08 已建好的工程（B3V、B3R-r2、B3F-r2、B3VN）直接复用，不用重建，也不用重新导入。PDS 按路径引用仓库中的源文件，切换提交后直接重新综合即可。
  - 还没建的工程，按卡 07（B3V/B3R/B3F）或卡 08（B3VN）的第 3–4 节新建并导入。
- 内存不够时按 B3V → B3VN → B3R → B3F 排队，在 `result.md` 中记下实际怎么跑的。

## 4. 需要的 IP

无变化，沿用各工程已有的 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | 在仓库检出中 `git fetch origin`，`git switch -c win/20261030-10-b3-timing-rerun origin/zc100116/b3`，`git submodule update --init`。确认 HEAD 是包含本卡的提交。 |
| 1 | 用户（U），或 Codex 在 PDS 控制台 | 已有工程：直接进入步骤 2。新建的工程：在工程目录下执行 `source ../../EdRV32-Competition-2026/fpga/scripts/<第 1 节的脚本>`，核对 N。 |
| 2 | 用户（U），或 Codex 在 PDS 控制台 | 每个工程依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录各阶段耗时。综合日志中应能看到源文件按新时间戳重新编译。任何一步报错就停下，回传报错原文和已取得的产物。 |
| 3 | Windows Codex（C） | 按卡 07 第 6 节收集每个工程的产物（timing_summary、setup_top200_<时钟>、setup_top20_detail、hold_top20、resource_summary、resource_hier、flow_summary），并另外导出全部路径表 `timing_all_paths.tsv`，格式同卡 07 的 B3V。 |
| 4 | 用户（U） | 每个工程下载 bitstream，复位后确认串口出现启动信息，按住 KEY1 复位能进入新 BIOS 菜单。功能验收按卡 09（B3V/B3VN/B3F）和卡 04（B3R）执行，可以另行回传。 |
| 5 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/<工程>/`，提交信息 `win: 20261030-10-b3-timing-rerun results`，推送 `win/20261030-10-b3-timing-rerun`。某个工程先完成可以先回传，其余追加提交。 |
| 6 | Windows Codex（C） | **调试工具**：协调者会在 `zc100116/b3` 上另行推送 SoC 中控台。届时 `git pull` 即可使用；在那之前，继续用现有调试工具和 `tools/board/uart_tool.py`。 |

## 6. 产物

放在 `tasks/win/20261030-10-b3-timing-rerun/artifacts/<B3V|B3VN|B3R|B3F>/`，内容同卡 07 第 6 节，外加 `timing_all_paths.tsv`。不提交 PDS 工程文件、IP 生成目录、中间文件、bitstream、完整原始日志。

## 7. 通过判据

- 四个工程都完成布线和 bitstream。
- 时序：如实记录各时钟布线后的 WNS/TNS/WHS/THS，不作为停止条件。重点关注 clk_mem、clk_sys、clk_eth 与卡 07 B3V 的对比。
- 上板：能进入新 BIOS 菜单。
- 所有数字来自 PDS 报告原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261030-10-b3-timing-rerun 结果

| 项 | B3V | B3VN | B3R | B3F |
|---|---|---|---|---|
| 代码 commit | | | | |
| 工程路径（复用/新建） | | | | |
| 各阶段耗时（综合/映射/布局布线） | | | | |
| 运行方式（并行/排队） | | | | |
| 完成情况 | | | | |

## 时序（布线后，slow 角）
| 工程 | 时钟 | WNS | TNS | WHS | THS | setup 违例端点 |
|---|---|---|---|---|---|---|

与卡 07 B3V 的对比（clk_mem / clk_sys / clk_eth）：

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 资源
| 工程 | LUT | FF | DRM 18K/36K | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|---|

## 上板（BIOS 菜单）
| 工程 | 启动信息 | 新 BIOS 菜单 |
|---|---|---|

## 完整报告在 Windows 本地的路径

## 备注
```
