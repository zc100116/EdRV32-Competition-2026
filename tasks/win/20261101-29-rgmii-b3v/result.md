# 卡29：B3V PLL位置、RGMII采样时序与上板结果

## 实现与约束

- 分支win/20261101-29-rgmii-b3v；约束修正输入eab69551（上游5af1c8a7）。PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 工程G:/codex_project/EdRV32-FPGA/EdRV32-B3V，用户完成实现并下载本轮新比特流。
- 初次fd21b2d7因两个gpll_inst对象找不到失败。初次原文保留在logs/synthesize_errors.txt、constraint_failure_context.txt及initial_failed_constraints.fdc；没有擅自改写约束。
- 同步协调者修正为u_gpll后，本轮各阶段均结束且错误行数为0。原厂CMR/SNR/DMR/PRR/RTR在native_reports/，工作FDC副本为edrv32_fpga_board_vision_top.fdc。
- 新增位置约束已落实，四条set_input_delay（含-clock_fall/-add_delay）被接受；这不等于时序已满足。既有层次region等警告仍按原文保存。

| 阶段 | 实际耗时 | CPU | Process CPU | 峰值内存池 | 警告行 | 错误行 |
|---|---|---|---|---|---|---|
| compile | 1m38s | 7s | 7s | 496MB | 3138 | 0 |
| synthesize | 4m48s | 16s | 18s | 2508MB | 9241 | 0 |
| device_map | 52s | 6s | 6s | 1375MB | 56 | 0 |
| place_route | 17m59s | 2m3s | 3m38s | 5032MB | 694 | 0 |
| report_timing | 1m20s | 4s | 6s | 4708MB | 161 | 0 |
| generate_bitstream | 1m25s | 12s | 12s | 3505MB | 0 | 0 |

## 实际PLL/缓冲位置

| 实例 | PRR站点 |
|---|---|
| u_rgmii/u_pll_eth/u_gpll/gpll_inst | GPLL_7_1381 |
| u_pll_sys/u_gpll/gpll_inst | GPLL_727_463 |
| u_rgmii/u_eth_clk/gopclkbufg | USCM_383_930 |

原文见clock_sites.txt，位置来自本轮PRR，不以FDC目标值代替实际站点。

## RGMII RX时序

原厂报告Some Constraints Violated。clk_rgmii_ref→clk_eth的slow setup WNS=-0.265ns/TNS=-1.252ns、fast WNS=-1.224ns/TNS=-6.047ns，两个角各5个失败端点。全部时钟域WNS/TNS/WHS/THS及其他检查原文见timing_summary.txt。

定向补导出命令（只读routed DB，不重跑PnR）：

```tcl
report_timing -input_db_file {G:/codex_project/EdRV32-FPGA/EdRV32-B3V/place_route/edrv32_fpga_board_vision_top_pnr.adf} -delay_type min_max -max_path 200 -nworst 20 -from {rgmii_rxd_i* rgmii_rx_ctl_i} -input_pins TRUE -force_to_run
```

| Corner | 捕获沿 | RX最差setup/ns | RX最差hold/ns |
|---|---|---|---|
| slow | rising | -0.183 | 0.387 |
| slow | falling | -0.265 | 0.483 |
| fast | rising | -1.216 | 2.022 |
| fast | falling | -1.224 | 2.031 |

定向报告共80条：每角setup/hold各20条，每类含10条上升沿和10条下降沿捕获，覆盖4条RXD和RX_CTL。每角最差20条逐级明细在rgmii_rx_setup_top20.txt/rgmii_rx_hold_top20.txt，包含D19输入、输入缓冲、PLL、时钟缓冲到IDDR的实际各级延迟；完整定向RTR也上传。覆盖索引见rgmii_rx_edge_coverage.json及edge_counts.txt。

例如slow最差setup在rgmii_rxd_i[2]→u_rgmii/g_rx[2].u_input/opit_1/DI，时钟链依次经过IOLHR_16_1368/DI_TO_CLK、GPLL_7_1381/CLKOUT0、USCM_383_930/CLKOUT到IOLHR_16_1404/ICLK；各级数字以原始明细为准，不手动去掉PLL/clock skew来修正裕量。

原report_timing/run.log的未约束输入警告中未见上述五个RGMII RX端口；其他未约束输入/输出警告仍存在。全局补导出-max_path200/-nworst1，共12076条各角/各类型路径，其中10条负裕量样本；该数量不是全芯片所有失败路径穷举，定向报告使用更大的nworst，勿将两份样本数直接比较。全局setup/hold索引、最差逐级明细和<1ns危险路径均保存。

各检查最差值见timing_minima.txt；DDR PHY最小脉宽低裕量也保留。完整全局扩展RTR约90MB留在build/win/20261101-29-rgmii-b3v/exports/global200/，上传原厂报告、索引及最差明细，未上传数据库。

## 上板：五次PHY复位

卡23eth_diag.bin通过COM7/115200加载成功。eth_probe独立监听192.168.1.2:6000，每秒发一个UDP；每轮r后等link=1 speed=1000 duplex=full，再发s、等待10秒、发s。未改PHY延迟或关闭TUN。

| 次 | 串口采样间隔/s | PERF1增量 | PERF3增量 | PERF1≥8且PERF3=0 |
|---|---|---|---|---|
| 1 | 10.121 | 10 | 22 | 失败 |
| 2 | 10.152 | 0 | 10 | 失败 |
| 3 | 10.144 | 4 | 41 | 失败 |
| 4 | 10.141 | 10 | 0 | 成功 |
| 5 | 10.026 | 9 | 29 | 失败 |

结果1/5成功。第1、5轮虽有≥8个有效UDP，但存在接收错误增长，仍按卡判为失败。PERF3合计FCS/帧长/RX_ER错误，可能含背景流量，不能解释为某个具体probe丢包数。原文在uart/phy_reset.log及entries、phy_reset_results.json、probe.txt。

## 上板：ETH视频60秒

加载卡24demo_vision.bin：Load result: PASS、Run: 0x10000000；两路相机均识别0x5640，设置Output mode=1（ETH）、目标视频30fps、监控100Hz。发送网口连接请求后未建立PEER。

0/10/30/60秒快照：UDP packets=0、bytes=0、视频/EDTM接收计数=0，PEER一直0.0.0.0:0。用户原话“什么都没有”，视频窗口无画面。Video skips四次为0，但实际视频未建立，不能记为视频流畅或无丢帧；GUI接收/显示fps与丢弃帧数数值未取得，未填造。

camera0和camera1在CLINT60.02413691秒内均增加1800帧，约29.98794fps；相机运行正常不等于网口视频成功。Monitor dropped records从6515增至12517，EDTM接收records=0；空CSV不作为带宽正常证据。完整状态、串口样本、用户现象、导出CSV在video_eth/。

## 结论与偏离

PLL新位置已生效，双沿RX约束被分析，但RGMII setup仍违例；PHY复位仅1/5达到判据，视频连接未成功。不能记为网口稳定性已修复。未修改RTL/FDC/IP，未增加自动重试或切换PHY延迟掩盖失败。

所有数据按原文保存；GUI无画面由用户反馈，无法通过现有API读取的GUI帧率/丢弃数写未取得。较大的原厂DMR（约2.2MB）、SNR及综合警告节选用于保留映射/警告上下文；不上传完整PDS原始run.log、IP、bitstream或实现数据库。
