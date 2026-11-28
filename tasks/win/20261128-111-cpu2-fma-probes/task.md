# 卡 111：CPU v2 FPU 乘加探针（FP32 新版 + FP64）布局布线

## 1. 目标

FPU 的单精度乘加单元（加入了加法/乘法旁路、尾端预约和输出缓冲）和新的双精度乘加单元（12 颗 APM 级联）各做一个独立小工程，在 165 MHz 约束下综合、布局布线，量出真实裕量、资源和高扇出。只做时序和资源分析，不生成比特流，不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 用 `git log -1 --format=%H origin/zc100116/gpu-dev -- tasks/win/20261128-111-cpu2-fma-probes` 找到本卡的提交，从它拉出 `win/20261128-111-cpu2-fma-probes`，记录 HEAD |
| 工程 B（FP32，沿用卡 110 工程） | 顶层 `edrv32_fpga_probe_cpu2_fma_top`；约束 `fpga/constraints/edrv32_fpga_probe_cpu2_fma_top.fdc`；导入脚本 `fpga/scripts/import_probe_cpu2_fma_top.tcl`；文件列表 `rtl/filelists/cpu2_probe_fma.f` |
| 工程 C（FP64，新建） | 顶层 `edrv32_fpga_probe_cpu2_fma64_top`；约束 `fpga/constraints/edrv32_fpga_probe_cpu2_fma64_top.fdc`；导入脚本 `fpga/scripts/import_probe_cpu2_fma64_top.tcl`；文件列表 `rtl/filelists/cpu2_probe_fma64.f` |
| 流水与路径说明 | `verif/unit/cpu2_fpu_fma32/README.md`、`verif/unit/cpu2_fpu_fma64/README.md` |

两个工程都是单时钟 `clk_i`，约束 6.061 ns（165 MHz），没有 PLL。

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 110 相同。

## 4. 需要的 IP

无。乘法直接例化 `GTP_APM_E2` 原语，说明见 `fpga/ip/apm_cpu2_fpu.md`（已加 D 一节）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | 按第 2 节拉分支，记录 HEAD |
| 1 | U | 打开卡 110 的工程 `EdRV32-FPGA/cpu2_probe_fma`，移除旧源文件，在工程目录的 PDS Tcl 控制台执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_probe_cpu2_fma_top.tcl` |
| 2 | U | 默认参数跑综合、Device Map、布局布线；关闭 Generate Bitstream 的 Auto Run |
| 3 | U | 新建工程 `EdRV32-FPGA/cpu2_probe_fma64`（PG2L200H-6 FBB676），执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_probe_cpu2_fma64_top.tcl`，同样跑到布局布线 |
| 4 | C | 两个工程各自导出报告（导出命令同卡 110 第 5 节），按第 6 节整理 |
| 5 | C | 填写 result.md，提交推送 |

两个工程互不依赖，可以同时跑。某一步报错，把报错原文写进 result.md 后停下，不要改 RTL 或约束。特别留意 APM 相关告警（级联、CPI/CPO、内部寄存器），原文照录。

## 6. 产物

放在 `artifacts/fma32/` 和 `artifacts/fma64/` 下，两边各一套：
- `timing_summary.txt`：WNS/TNS/WHS/THS 和估算 Fmax；
- `setup_top200.txt`：最差 200 条 setup 路径，一行一条（起点、终点、裕量、逻辑级数、逻辑延迟/布线延迟）；
- `setup_top20_detail.txt`：最差 20 条逐级明细；`hold_top20.txt`；
- `segments.txt`：按终点寄存器所在流水级分组（寄存器名前缀以两份 README 中的流水级命名为准；对不上时按终点寄存器名的前缀自行分组并在文件开头说明），每组最差 3 条；另列 APM 内部/级联上的最差路径；
- `resource_summary.txt`：LUT、FF、DRM、APM、分布式 RAM、IO，以及 **CLM 用量（Use of CLMA、Use of CLMS）和控制组合（control set）数量**；`resource_hier.txt`：按模块层次的资源；
- `high_fanout.txt`：扇出最大的 50 个网络（网名、扇出）。本卡重点之一：`keep`/`syn_preserve` 的控制副本是否保留（按副本网名列出各自扇出），以及有无扇出超过 16 的流水使能网络；
- `settings.txt`：实际 P&R 参数。

## 7. 通过判据

两个工程都完成布局布线并交齐第 6 节产物（时序不满足也要完整回传，不判失败）。所有数字取自报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 111 结果

| 项 | 内容 |
|---|---|
| 分支 HEAD | |
| PDS 版本 | |

## 工程 B（FP32）
| 项 | 值 |
|---|---|
| WNS / TNS / WHS / THS | |
| 估算 Fmax | |
| LUT / FF / APM / 分布式 RAM | |
| Use of CLMA / CLMS | |
| control set 数 | |
| 最差路径（起点 → 终点、级数、逻辑/布线延迟） | |
| 控制副本是否保留、最大流水使能扇出 | |

## 工程 C（FP64）
（同上）

## 问题与偏离
```
