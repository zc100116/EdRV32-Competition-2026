# 20261029-07-b3-rerun 结果（先回传B3V）

B3V已完成编译、综合、映射、布局布线、STA和bitstream，用户已运行demo_vision。实际功能基本可用，但仍有setup违例和切换黑屏问题。B3R/B3F本次结果未收集。

| 项 | 内容 |
|---|---|
| 代码commit | 4ef33208996422721c342d75bb600552514a225a |
| PDS/器件 | 2022.2-SP6.1 build138931；PG2L200H-6/FBB676 |
| 实际工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3V |
| 源文件数 | 112 |
| 复用说明 | 按用户决定复用旧B3V，没有新建B3V-r2；其他工程保留 |

## 布线后时序

| 时钟对/角 | WNS ns | TNS ns | WHS ns | THS ns | setup/hold违例端点 | Fmax MHz（同域估算） |
|---|---:|---:|---:|---:|---|---:|
| clk_cam0→clk_cam0/slow | 5.495 | 0.000 | 0.145 | 0.000 | 0/0 | 221.976 |
| clk_cam1→clk_cam1/slow | 5.158 | 0.000 | 0.156 | 0.000 | 0/0 | 206.526 |
| clk_sys→clk_sys/slow | 0.182 | 0.000 | 0.129 | 0.000 | 0/0 | 101.854 |
| clk_pix→clk_pix/slow | 7.268 | 0.000 | 0.166 | 0.000 | 0/0 | 161.290 |
| clk_serial→clk_serial/slow | 1.706 | 0.000 | 0.346 | 0.000 | 0/0 | 1012.556 |
| rst_clk→rst_clk/slow | 4.643 | 0.000 | 0.257 | 0.000 | 0/0 | 297.885 |
| clk_mem→clk_mem/slow | -0.554 | -11.348 | 0.136 | 0.000 | 32/0 | 116.904 |
| phy_dq_sysclk_1→clk_mem/slow | 2.632 | 0.000 | 0.541 | 0.000 | 0/0 | — |
| phy_dq_sysclk_0→clk_mem/slow | 3.881 | 0.000 | 0.749 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_0/slow | 1.811 | 0.000 | 0.453 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_1/slow | 1.813 | 0.000 | 0.467 | 0.000 | 0/0 | — |
| clk_eth→clk_eth/slow | 0.798 | 0.000 | 0.213 | 0.000 | 0/0 | 138.850 |
| clk_cam0→clk_cam0/fast | 7.489 | 0.000 | 0.104 | 0.000 | 0/0 | 398.248 |
| clk_cam1→clk_cam1/fast | 7.331 | 0.000 | 0.107 | 0.000 | 0/0 | 374.672 |
| clk_sys→clk_sys/fast | 3.837 | 0.000 | 0.100 | 0.000 | 0/0 | 162.259 |
| clk_pix→clk_pix/fast | 9.749 | 0.000 | 0.117 | 0.000 | 0/0 | 268.889 |
| clk_serial→clk_serial/fast | 2.084 | 0.000 | 0.225 | 0.000 | 0/0 | 1640.420 |
| rst_clk→rst_clk/fast | 6.084 | 0.000 | 0.161 | 0.000 | 0/0 | 521.921 |
| clk_mem→clk_mem/fast | 2.828 | 0.000 | 0.100 | 0.000 | 0/0 | 193.349 |
| phy_dq_sysclk_1→clk_mem/fast | 4.555 | 0.000 | 0.099 | 0.000 | 0/0 | — |
| phy_dq_sysclk_0→clk_mem/fast | 5.279 | 0.000 | 0.281 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_0/fast | 4.041 | 0.000 | 0.099 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_1/fast | 4.059 | 0.000 | 0.099 | 0.000 | 0/0 | — |
| clk_eth→clk_eth/fast | 3.637 | 0.000 | 0.132 | 0.000 | 0/0 | 229.200 |

slow clk_mem WNS=-0.554 ns，TNS=-11.348 ns，32个违例端点；125MHz目标按同域setup裕量估算约116.9MHz。clk_sys裕量+0.182ns、clk_eth+0.798ns，也应关注。
hold/recovery/removal两角均无违例；完整汇总（含minimum pulse width）保留在timing_summary.txt。用户反馈违例暂未影响本次实测，不作为时序豁免或全部条件下稳定的结论。

最差路径落在mem_xbar读缓冲相关输出到PERF_MON first_err_addr_r使能端，最差路径36级逻辑；以下给出具体起终点供协调者定位。

slow clk_mem最差10条setup：

| 起点→终点 | 裕量ns | 逻辑级数 |
|---|---:|---:|
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/first_err_addr_r[23]/opit_0_inv_L6QL5Q_perm/CE | -0.554 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/first_err_addr_r[9]/opit_0_inv_L6QL5Q_perm/CE | -0.524 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/first_err_addr_r[19]/opit_0_inv_L6QL5Q_perm/CE | -0.524 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/err_beats_r[15]/opit_0_inv_AQ_perm/CE | -0.503 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/err_beats_r[19]/opit_0_inv_AQ_perm/CE | -0.495 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/first_err_addr_r[5]/opit_0_inv_L6QL5Q_perm/CE | -0.488 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/first_err_addr_r[11]/opit_0_inv_L6QL5Q_perm/CE | -0.488 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/first_err_addr_r[13]/opit_0_inv_L6QL5Q_perm/CE | -0.488 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/first_err_addr_r[21]/opit_0_inv_L6QL5Q_perm/CE | -0.488 | 36 |
| u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_mem/u_perf_mon/err_beats_r[7]/opit_0_inv_AQ_perm/CE | -0.465 | 36 |

## 路径覆盖

从现有pnr.adf补导report_timing -max_path 200 -nworst 1 -input_pins TRUE，共12040条路径。未重跑综合、映射或布线。
每个捕获时钟分slow/fast保存最差200条setup（不足则全部），各角最差20条setup/hold和recovery/removal逐级明细另存。timing_all_paths.tsv保留全部路径；setup_near_positive_paths.tsv保留slow角0到1ns正裕量，既有默认RTR也完整保留。

## 资源

来自路后PRR逻辑层次；物理CLMA/CLMS、IO、PLL、DRM容量与综合原语拆分另见resource_summary.txt。

| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| edrv32_fpga_board_vision_top | 49938 | 49138 | 346 | 161 | 109 |
| u_cpu | 12619 | 7171 | 143 | 4 | 6 |
| u_ddr3 | 4934 | 5222 | 48 | 0 | 0 |
| u_disp | 2903 | 3886 | 0 | 7 | 8 |
| u_eth | 4059 | 4459 | 76 | 0 | 3 |
| u_geo | 3471 | 3306 | 0 | 9 | 16 |
| u_mem | 9681 | 8585 | 34 | 9 | 28 |
| u_pix | 4982 | 7860 | 0 | 132 | 11 |
| u_pll_sys | 0 | 0 | 0 | 0 | 0 |
| u_pll_video | 0 | 0 | 0 | 0 | 0 |
| u_rgmii | 0 | 0 | 0 | 0 | 0 |
| u_sys | 1898 | 1656 | 8 | 0 | 20 |
| u_tmds | 0 | 0 | 0 | 0 | 0 |
| u_vin | 5386 | 6993 | 37 | 0 | 17 |

## 各阶段日志

| 阶段 | Real | CPU | Process CPU | 峰值内存 | W/C/E行数 |
|---|---|---|---|---|---|
| compile | 0h:1m:27s | 0h:0m:14s | 0h:0m:14s | 484 MB | 2914/0/0 |
| synthesize | 0h:4m:11s | 0h:1m:0s | 0h:1m:3s | 2,517 MB | 8197/62/0 |
| device_map | 0h:0m:47s | 0h:0m:8s | 0h:0m:8s | 1,450 MB | 20/0/0 |
| place_route | 0h:17m:40s | 0h:4m:39s | 0h:7m:6s | 6,716 MB | 0/61/0 |
| report_timing | 0h:1m:7s | 0h:0m:21s | 0h:0m:25s | 4,763 MB | 166/0/0 |
| generate_bitstream | 0h:1m:19s | 0h:0m:18s | 0h:0m:18s | 3,504 MB | 0/0/0 |

日志分类及全部W/C/E行在flow_summary.txt和logs/；原生CMR/SNR/DMR/PRR/RTR/CCR在native_reports/。未提交完整原始执行日志或DB/bitstream。

## 约束和导入

clk_sys=10ns、clk_mem=8ns、clk_pix=13.468ns、clk_serial=2.6936ns、cam0/1、clk_eth及DDR内部时钟识别情况见clock_checks.txt，DDR异步组原文见原生RTR。未修改RTL/IP或FDC。
本次提交包含先前用户授权的vision导入路径修正：FPGA工程目录../../EdRV32-Competition-2026定位仓库，include为rtl/include。

## 上板及改进反馈

用户反馈基本可用；功能切换短暂黑屏，希望平滑切换；先进入BIOS再点烧录仍要再次KEY1+复位；网口及DDR未能验证；希望把场景/YOLO/视频/DDR/烧录等整合成项目专用SoC中控台。
网口/DDR：任务卡、README和当前源码声明已有相关功能；实际反馈记为交付/工具联调缺口，不写通过，也不直接断言功能未编入。
详细复现、代码线索和验收要求：tasks/win/20261029-09-b3-software/artifacts/B3V/user_feedback.md。未取得本次UART、照片、视频或CSV。

## 本地数据与复现

- 完整工程报告/日志：G:/codex_project/EdRV32-FPGA/EdRV32-B3V/各阶段目录。
- 补导：G:/codex_project/EdRV32-Competition-2026/build/win/20261029-07-b3-rerun/B3V/export/report_timing/edrv32_fpga_board_vision_top.rtr。
- 整理：C:/Python314/python.exe tasks/win/20261029-07-b3-rerun/src/collect_b3v_reports.py。
- 只收集现有结果、补导时序并只读代码，没有重跑实现、改软件/工具或操控桌面。没有核对报告时间戳或计算文件哈希。
