# 任务 22：R/N/V 布局布线前阶段报告

本版仅整理三个工程的 Compile、Synthesize、Device Map。各阶段日志来自现有工程目录；不启动、不停止或重跑任何流程，不采集布局布线、最终 routed timing、bitstream 或上板结果。

- 分支：win/20261031-22-b3-rnv；整理时已同步软件更新 8edfca2d。
- 工具：PDS 2022.2-SP6.1；器件 PG2L200H-6 FBB676。
- 工程目录：G:/codex_project/EdRV32-FPGA/EdRV32-B3R、EdRV32-B3N、EdRV32-B3V。
- 源码目标数：R=103、N=106、V=112；配置时的添加/移除清单在各 artifacts 子目录 sources.txt。
- 用户安排三个工程并行实现、配置逐个完成，覆盖任务卡的串行安排。

## 阶段耗时和告警

W/E 为日志行数，同一类告警可能重复出现，不代表独立根因数。峰值是工具报告的 memory pool，不等同于操作系统总工作集。

| 工程 | 阶段 | 实际耗时 | CPU 时间 | Process CPU 时间 | 峰值内存池 | W: | E: |
|---|---|---|---|---|---|---|---|
| b3r | compile | 0h:2m:22s | 0h:0m:3s | 0h:0m:3s | 609 MB | 3288 | 0 |
| b3r | synthesize | 0h:9m:21s | 0h:1m:23s | 0h:1m:30s | 3,390 MB | 10467 | 0 |
| b3r | device_map | 0h:1m:13s | 0h:0m:1s | 0h:0m:1s | 1,876 MB | 20 | 0 |
| b3n | compile | 0h:2m:30s | 0h:0m:4s | 0h:0m:4s | 658 MB | 3616 | 0 |
| b3n | synthesize | 0h:7m:41s | 0h:0m:8s | 0h:0m:10s | 3,491 MB | 13578 | 0 |
| b3n | device_map | 0h:1m:15s | 0h:0m:1s | 0h:0m:1s | 1,797 MB | 268 | 0 |
| b3v | compile | 0h:2m:16s | 0h:0m:2s | 0h:0m:2s | 540 MB | 3253 | 0 |
| b3v | synthesize | 0h:7m:9s | 0h:0m:9s | 0h:0m:10s | 2,870 MB | 9365 | 0 |
| b3v | device_map | 0h:1m:6s | 0h:0m:1s | 0h:0m:2s | 1,519 MB | 56 | 0 |

## Device Map 资源

全部为布局布线前的 Device Map 原文数值。DRM 采用厂商 36K 等效口径；原始 DRM18K/DRM36K 数量在 SNR Cell Usage。综合层次资源单独保存，不与 Device Map 数字混用。

| 工程 | LUT | FF | 分布式 RAM | APM | DRM | IO | GPLL | PPLL |
|---|---|---|---|---|---|---|---|---|
| b3r | 82411 | 61760 | 741 | 170 | 117.5 | 109 | 5 | 2 |
| b3n | 64136 | 64392 | 1774 | 303 | 173 | 101 | 5 | 2 |
| b3v | 62877 | 56372 | 922 | 47 | 97 | 137 | 5 | 2 |

## 布线前时序估计

以下仅统计 SNR 中现有的 sequential timing path，已保存的路径数量受原生报告选项限制。负裕量条数是已报告路径数，不是全设计失败端点总数。setup 为 max，hold 为 min，合并 SNR 中可用的 corners 统计最差值；具体角、时钟和起终点见逐路径列表。

| 工程 | 类型 | 已报告路径数 | 最差裕量 ns | 其中负裕量路径数 |
|---|---|---|---|---|
| b3r | setup | 28 | -0.104 | 3 |
| b3r | hold | 28 | -3.198 | 9 |
| b3n | setup | 25 | 0.209 | 0 |
| b3n | hold | 25 | -1.63 | 9 |
| b3v | setup | 34 | -0.792 | 3 |
| b3v | hold | 34 | -2.889 | 9 |

最终 WNS/TNS/WHS/THS、区域内实际站点、卡21违例路径的最终改善情况，需等待布局布线完成后分析，当前不作通过结论。

## 产物和说明

每个 artifacts/b3r、b3n、b3v 下：

- native_reports/：原生 CMR、SNR、DMR。
- logs/*_excerpt.txt：全部 W:/E: 行及阶段耗时/内存等关键信息。完整原始 run.log 留在各工程的 compile/、synthesize/、device_map/。
- flow_summary.txt：各阶段告警代码计数及时间/内存原文。
- resource_summary.txt、resource_hier.txt：Device Map 汇总、综合 primitive usage、完整综合层次表，包含 CPU/cache、u_mem/u_xbar，以及各工程实际包含的 RND/NPU/图像处理/ETH 模块。
- high_fanout.txt：Device Map 的高扇出、时钟、复位、CE 表。
- regions_pre_pnr.txt：DMR 的 PAP_REGION 属性记录；表示映射阶段记录了约束，不代表最终寄存器已经落入指定区域。
- timing_pre_pnr_paths.tsv：SNR 中全部可取得的路径；timing_pre_pnr_counts.txt：按角/组/类型的数量。
- timing_pre_pnr_setup_detail.txt、timing_pre_pnr_hold_detail.txt：最差可用路径明细；timing_pre_pnr_near.tsv：裕量 <1 ns 的现有路径，包含负裕量。

大量警告已按代码归类并保留原文，包括 ConstantProbeLoop、未驱动信号、综合资源优化及约束覆盖类信息。不通过修改 RTL 消警，不将布线前估计当作实际板级故障结论。

网口和软件上板测试尚未在本卡验收。卡22使用新的 BIOS 与应用协议，上板使用卡22 src 镜像。调试工具已更新，重新启动后才生效。

## 复现整理

C:/Python314/python.exe tasks/win/20261031-22-b3-rnv/src/collect_pre_pnr.py

此脚本只读取现有工程报告并写任务产物，不调用 PDS。

## 较大产物

- artifacts\b3r\native_reports\device_map\edrv32_fpga_board_render_top.dmr (2144939 bytes)：保留原厂警告或层次数据供分析，未复制完整原始运行日志。
- artifacts\b3n\native_reports\device_map\edrv32_fpga_board_npu_top.dmr (2067890 bytes)：保留原厂警告或层次数据供分析，未复制完整原始运行日志。
- artifacts\b3v\native_reports\device_map\edrv32_fpga_board_vision_top.dmr (2151406 bytes)：保留原厂警告或层次数据供分析，未复制完整原始运行日志。
