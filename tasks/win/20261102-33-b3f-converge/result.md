# 卡33 B3F A/B：截至Device Map阶段结果

代码输入：`f2028ed003ba54a0cdd5d4aa626bf4a43dd1b057`。PDS 2022.2-SP6.1，PG2L200H-6 FBB676。用户已分别启动A/B布局布线，本次只上传Compile、Synthesize ADS、Device Map结果，未停止或启动流程；不宣称本卡最终收敛或上板通过。

| 项 | A | B |
|---|---|---|
| 工程目录 | G:/codex_project/EdRV32-FPGA/EdRV32-B3F | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-B |
| 工程文件 | EdRV32-B3F-card31.pds | EdRV32-B3F-card33-B.pds |
| 约束 | fpga/constraints/edrv32_fpga_board_full_top.fdc | 本卡src/edrv32_fpga_board_full_top_left.fdc |
| 源文件 | 164 | 同A |
| Compile / Synthesize / Map | 完成，E=0 | 完成，E=0 |
| ILA | 已插入 | 已插入 |
| 区域 | 默认RGMII/DDR区域 | 新增fp_left(0,121,0,219)用于RND/VIN/PIX/GEO/DISP/ETH |

## 各阶段耗时、CPU和峰值内存

|版本|阶段|墙钟|CPU / Process CPU|峰值内存池|W / C / E消息行|
|---|---|---|---|---|---|
|A|Compile|2m31s|12s / 12s|836MB|5396 / 0 / 0|
|A|Synthesize|9m30s|48s / 54s|4992MB|19819 / 61 / 0|
|A|Device Map|2m17s|6s / 7s|2823MB|367 / 0 / 0|
|B|Compile|2m50s|13s / 13s|839MB|5396 / 0 / 0|
|B|Synthesize|10m24s|38s / 44s|3662MB|19825 / 61 / 0|
|B|Device Map|3m4s|19s / 19s|2901MB|367 / 0 / 0|

分阶段按代码计数见各版本warning_counts.txt。logs/保留去除完全重复行后的W/C/E原文，次数仍以原始日志逐行计数，不能当作独立缺陷数。Map的Public-4010为覆盖已有PCF提示。完整原始run.log仍在本机工程相应阶段目录。

## Device Map资源（含ILA，两版本相同）

|LUT|FF|DRM|APM|Distributed RAM|IO|GPLL / PPLL|
|---:|---:|---:|---:|---:|---:|---|
|106184（67%）|118708（38%）|301.5（73%）|448（61%）|2252（6%）|137（35%）|6 / 2|

各版本resource_summary.txt为Map资源原文，resource_hier.txt为SNR完整模块层次资源表。SNR在Inserter之前，不含插入的ILA，不能与Map混为同阶段；层次表父项包含子项，不能相加。与旧卡31的差额同时包含扇出优化和ILA影响，不标为独立ILA实测资源。

## ILA与高扇出

两版本日志确认Core Insertion Complete，存在u_CORES/u_debug_core_0，采样时钟clk_sys_w。数据400位：mcycle、minstret、hpm3–10各低40位；两个触发端口各40位：minstret、mcycle。深度1024；FIC全部480个位连接对照实际综合网表正确。HPM网络counter_r[0..7]对应寄存器实例g_counter[2..9].g_hpm.count_r。FIC及已有GUI参数截图在ila/，B FIC指向B自身ADF。

Device Map设置fanout_number=1000。high_fanout.txt保存Clock/Reset/CE/Other原文，controlsets.txt保存综合控制集。不宣称每一张表必有1000条实际条目。

## A/B配置与并行依据

机器物理内存34001649664字节，i9-12900H，14核20逻辑线程。卡24 B3R的PnR峰值5119MB，满足两倍峰值并留余量，因此准备A+B；此依据不保证B3F未来峰值相同。用户手动启动两个PDS实例运行，实施期间不运行仿真虚拟机。

两个版本统一：Placement Decongestion Mode=2（默认1），dump_router_congestion_plot开启，路由线程5，其余保持截图参数。B工程参数由Codex写入，A由用户GUI保存；依据本机手册正文111、117页及pnr -help。模式2是本次试验选择，不保证收敛改善。截图、默认值及设置记录见pnr_settings/。

任一变体第40轮unrouted>18000即停止该变体，按任务卡回传。当前最终PnR时序、危险路径、模块放置范围、最终拥塞和bitstream均未取得，待完成或止损后补。

## B约束加载问题与纠正

B由A复制IP、综合及Map目录，未复制旧place_route、日志历史或锁文件。源码及include仍用../../EdRV32-Competition-2026相对路径，FIC使用B本地ADF。

首次仅修改工程FDC并重跑Map（2m27s、2108MB）后，DMR/PCF均没有fp_left，不能认定B区域变体生效。先前“无需重跑综合”的指导错误。随后用户在B重新Compile、Synthesize ADS、Device Map，最终DMR/PCF均确认fp_left及六个目标模块的属性；本报告表格和原生报告仅对应这次有效重建。区域条目计数（不是资源/唯一实例计数）见B/map_region_check.txt。

## 产物和边界

A的产物位于artifacts/，B位于artifacts/B/。各自保存原生CMR、SNR、DMR，资源汇总/模块层次、高扇出、控制集、阶段耗时和诊断原文。原生SNR保留综合估算时序全文；尚无布线后时序，未为导出报告额外运行实现。

B DMR原始约29.2MB，主要增加逐实例fp_left属性，使用标准gzip完整保留为native_reports/edrv32_fpga_board_full_top.dmr.gz（约0.42MB，可用gzip解压），没有删减原文。A DMR约2.7MB，保留完整约束、资源和高扇出信息供比较。

卡31旧PnR快照已在a4fd6d83上传，不重复采集。未提交PDS工程、IP生成目录、数据库、网表、bitstream或完整PDS运行日志。本卡处于实现中，尚未开展上板冒烟。
