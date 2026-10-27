# CPU + 系统子系统测量顶层时序与资源（C-W2，第一轮）

日期：2026-10-26（测量）；整理：2026-10-27。来源：Windows 任务 `20261025-01-cpu-sys-synth`，结果分支 `origin/win/20261025-01-cpu-sys-synth`（提交 `4517fe7`），原始报告在该分支 `tasks/win/20261025-01-cpu-sys-synth/artifacts/`，未合入 main（含超大原始日志）。

## 测量条件

| 项 | 内容 |
|---|---|
| 设计输入 commit | `157afa245359199cfa6bf7c18e2e21d165ae8203`（SRAM 256 KiB，C-R5 之前的 CPU） |
| 顶层 | `edrv32_fpga_cpu_sys_top`，`RVC_EN` = 1 |
| 工具 | PDS 2022.2-SP6.1（build 138931），Fabric Compiler |
| 器件 | PG2L200H-6 FBB676，时序模型 Pre-silicon，多角分析 |
| 约束 | `fpga/constraints/edrv32_fpga_cpu_sys_top.fdc`：`clk_i` 6.667 ns（150 MHz）；8 个 IO 没有 input/output delay 约束（Timing-4086/4087） |
| 流程 | compile → synthesize -ads → dev_map → pnr → report_timing（扩展报告 max_path=200、nworst=1） |

## 时序

| 时钟 | 目标 | 估计频率 | WNS（slow） | TNS（slow） | 违例端点 | WHS | THS |
|---|---|---|---|---|---|---|---|
| clk_sys | 149.99 MHz | **69.57 MHz** | −7.708 ns | −86183.305 ns | 19008 / 46871 | +0.153 ns（slow），+0.107 ns（fast） | 0 |

- Fast corner setup：10320 / 46871 个端点违例，前 200 条为 −1.911 至 −1.528 ns。
- Recovery/Removal 两角均无违例。
- 最差路径（30 级）：`u_dcache/addr_r[11]` → 命中判断 → core 的 M 级提交/停顿 → 前端（`ic_miss_start_w`）→ `u_csr/counter_r[2][62]`（HPM 事件选择 + 64 位计数）。
- slow setup 前 200 条的终点：`u_csr` 131 条（最差 −7.708 ns），`u_frontend` 69 条（最差 −7.360 ns）。

## 资源（布局布线后，逻辑层次）

| 层次 | LUT | FF | 分布式 RAM | APM | DRM |
|---|---|---|---|---|---|
| 顶层合计 | 24441 | 9121 | 39 | 4 | 74 |
| `u_cpu_subsys` | 22746 | 7951 | 31 | 4 | 6 |
| ├ `u_core` | 19628 | 6209 | 31 | 4 | 0 |
| │ ├ `u_frontend` | 12776 | 3161 | 31 | 0 | 0 |
| │ │ ├ `u_ib` | 1150 | 723 | 0 | 0 | 0 |
| │ │ └ `u_predictor` | 1454 | 1198 | 29 | 0 | 0 |
| │ ├ `u_regfile` | 2155 | 992 | 0 | 0 | 0 |
| │ ├ `u_csr` | 1902 | 853 | 0 | 0 | 0 |
| │ ├ `u_div` | 224 | 139 | 0 | 0 | 0 |
| │ └ `u_mul`（乘法 IP） | 2 | 68 | 0 | 4 | 0 |
| ├ `u_dcache` | 2389 | 1119 | 0 | 0 | 3 |
| └ `u_icache` | 682 | 462 | 0 | 0 | 3 |
| `u_sys_subsys` | 1694 | 1170 | 8 | 0 | 68（SRAM 64） |

Device Map 汇总：LUT 24347/159800、FF 9099/319600、DRM 74/415、APM 4/740、IO 9。

## 编译耗时

Compile 11 分 0 秒（CPU 1 分 44 秒），峰值内存 2394 MB，编译数据库 147,420,498 B；PnR 26 分 3 秒。

## 与旧工程 CoreMark 顶层对比

旧工程数据来自同一结果分支 `artifacts/old_coremark/`（2026-10-07 报告，未记录 commit；架构、存储配置和目标频率都不同，只作参考）。

| 项 | 旧 CoreMark 顶层 | 本轮 |
|---|---|---|
| 目标频率 | 100 MHz | 150 MHz |
| 估计频率 | 102.17 MHz | 69.57 MHz |
| WNS（slow） | +0.212 ns | −7.708 ns |
| LUT / FF | 29245 / 15755 | 24347 / 9099 |
| APM / DRM | 7 / 22 | 4 / 74 |
| Compile 耗时 / 数据库 | 1 分 42 秒 / 6,210,072 B | 11 分 0 秒 / 147,420,498 B |

## 后续

据此完成的优化：C-R5（HPM 事件寄存一拍、取指缓冲重构、系统指令提交解耦）和 C-R6（切断 D$ 命中到前端的重定向路径），见 `2026-10-26-perf-cpu-timing.md`。第二轮综合为 Windows 任务 `20261027-01-cpu-sys-synth-r2`。
