# 卡 70 结果

| 项 | 内容 |
|---|---|
| 实现源码提交 | `ce2b4fd42edc526fa702fd08071e14b4c2a0353a`，基于卡 70 修订提交 `520ba3cb` |
| 工程 | `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST/EdRV32-B3F-POST.pds` |
| 工具与器件 | PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676 |
| Slack Weight | 40 |
| 时钟约束 | CPU 125 MHz，NPU 180 MHz，MEM 125 MHz |
| Compile / ADS 综合 / Device Map | 原工程均完成，分别耗时 2m42s / 8m06s / 1m34s |
| Place & Route | 2026-11-13 21:28（北京时间）快照，布局完成，布线尚未收敛 |
| 布线后时序、资源和上板 | 未取得 |

## 三个后处理 RAM

| IP | PDS 生成配置 | 与 FPGA 包装匹配的端口 |
|---|---|---:|
| `ip_ram_npu_post_best` | DRM 简单双口，11 位地址，16 位数据 | 10 |
| `ip_ram_npu_post_queue` | DRM 简单双口，12 位地址，32 位数据 | 10 |
| `ip_ram_npu_post_table` | DRM 真双口，A/B 均为 10 位地址、32 位数据 | 14（修复后） |

三个 IP 的 `generate.log` 均报告 0 错误、0 警告。生成文件和日志位于 PDS 工程的 `ipcore/`。

## 资源

Device Map 汇总与卡 68 R2 使用同一统计口径。

| 资源 | 卡 68 R2 | 卡 70 |
|---|---:|---:|
| LUT | 91,208 / 159,800 | 93,252 / 159,800 |
| FF | 107,042 / 319,600 | 110,423 / 319,600 |
| 分布式 RAM | 2,743 / 39,500 | 2,781 / 39,500 |
| DRM | 286 / 415 | 298 / 415 |
| APM | 372 / 740 | 373 / 740 |
| IO | 137 / 400 | 137 / 400 |
| GPLL / PPLL | 6 / 10，2 / 10 | 6 / 10，2 / 10 |

| ADS 综合层次 | LUT | FF | 分布式 RAM | DRM | APM |
|---|---:|---:|---:|---:|---:|
| 整片 | 93,263 | 110,939 | 2,781 | 298 | 373 |
| `u_npu` | 19,004 | 42,630 | 1,086 | 134 | 267 |
| `u_npu/u_post` | 1,602 | 2,787 | 32 | 12 | 1 |

后处理的 12 个 DRM 来自 2 个 best bank（各 1 个）、2 个 queue bank（各 4 个）、exp 和 probability 表（各 1 个）。来源为 ADS 层次报告。

## 布线进度

PDS 日志记录 20:54:59 启动 PnR，布局耗时 320.69 秒。时钟网络第 5 轮归零，通用网络从第 7 轮开始，路由线程数为 5。下表每格依次为单轮秒数、未布通网络数、过用数。

| 通用布线轮次 | 卡 68 R2 | 卡 70 |
|---:|---:|---:|
| 7（第 1 轮） | 16.048 / 147,564 / 1,103,823 | 18.085 / 153,088 / 1,171,255 |
| 8（第 2 轮） | 15.952 / 131,854 / 888,753 | 32.616 / 138,219 / 975,236 |
| 9（第 3 轮） | 18.770 / 117,783 / 687,856 | 172.984 / 125,561 / 784,086 |

阶段快照最后一条完整轮次写于 21:20:40。21:29 抽样时路由进程仍在，工作集 8.90 GiB，系统可用物理内存 9.47 GiB。日志写入间隔与 PDS 报告的单轮耗时分开记录。已完成轮次中没有超过 600 秒的记录，也未出现 `Route-0039` 或 `Route-0008`。第 40 轮止损条件尚无法评估。前三轮同轮对照显示卡 70 残余和过用更多，最终收敛结果未取得。

### 产物

- `artifacts/implementation_stages.txt`、`ip_generation.txt` 保留阶段与 IP 生成日志摘录。
- `artifacts/resource_summary.txt`、`resource_hier.txt`、`high_fanout.txt` 分别来自 Device Map 和 ADS 报告。
- `artifacts/routing_congestion.txt` 保留截至快照的时钟网络和通用网络逐轮记录。第 7–9 轮 PDS 原始网格及共用色标 PNG 一并保存，网格索引、尺寸和坐标方向见 `congestion_grids.txt`。
- 完整阶段日志快照位于本工作区 `build/card70/progress/`。PDS 原始 SNR、DMR 和拥塞网格位于上述工程的 `synthesize/`、`device_map/` 和 `place_route/CongestionPlot/`。

## 问题与偏离

PDS 重新解析层次时报告 `Verilog-4119`，提示 `ip_ram_npu_post_table` 中不存在 `clk_a`。生成的真双口 RAM 使用 `a_clk`、`a_rst`、`a_clk_en`、`a_wr_en`、`a_addr`、`a_wr_data`、`a_rd_data`，B 端口使用对应的 `b_` 前缀。本次按用户确认在 Windows 结果分支修正 [`edrv32_ram_npu_post_table.v`](../../../rtl/tech/edrv32_ram_npu_post_table.v) FPGA 实例的全部 14 个端口名。三份生成模块与各自包装的端口集合逐项核对一致。

原始错误位于 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST/pds.log`。使用原工程和已生成 IP 的副本执行 `pds_shell -project check.pds -work_dir <验证目录> -run compile`，PDS 分析了三个 IP 的生成文件，日志记录 `Process "Compile" done.`，未再出现 `Verilog-4119`。验证工程与 `compile-console.log` 位于本工作区 `build/card70/compile-post-table/`。包装文件的 Verilog 风格检查为 0 警告。
