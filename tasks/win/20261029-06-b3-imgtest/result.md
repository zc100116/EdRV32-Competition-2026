# 20261029-06-b3-imgtest 结果

综合、映射、布局布线、时序分析、bitstream已完成；用户反馈上板功能正常，KEY1像素处理切换时轻微卡顿。setup/hold通过，recovery有违例，不能称作所有时序检查通过。

| 项 | 内容 |
|---|---|
| 代码commit（zc100116/b3） | 56ad4a459345c6fab3d2d21a298b1d92a39b4af5 |
| PDS/器件 | 2022.2-SP6.1 build138931；PG2L200H-6/FBB676 |
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3I |
| 导入源文件数 | 67 |

## 布线后时序

| 时钟对/角 | WNS ns | TNS ns | WHS ns | THS ns | setup/hold违例端点 | Fmax MHz（同域推算） |
|---|---:|---:|---:|---:|---|---:|
| clk_cam0→clk_cam0 / slow | 5.756 | 0.000 | 0.149 | 0.000 | 0/0 | 235.627 |
| clk_cam1→clk_cam1 / slow | 5.809 | 0.000 | 0.192 | 0.000 | 0/0 | 238.607 |
| clk_pix→clk_pix / slow | 7.767 | 0.000 | 0.186 | 0.000 | 0/0 | 175.408 |
| clk_serial→clk_serial / slow | 1.706 | 0.000 | 0.346 | 0.000 | 0/0 | 1012.556 |
| clk_mem→rst_clk / slow | 4.199 | 0.000 | 0.548 | 0.000 | 0/0 | — |
| rst_clk→rst_clk / slow | 5.104 | 0.000 | 0.196 | 0.000 | 0/0 | 345.304 |
| phy_dq_sysclk_0→rst_clk / slow | 5.185 | 0.000 | 0.863 | 0.000 | 0/0 | — |
| clk_mem→clk_mem / slow | 0.244 | 0.000 | 0.102 | 0.000 | 0/0 | 128.932 |
| phy_dq_sysclk_1→clk_mem / slow | 2.737 | 0.000 | 0.611 | 0.000 | 0/0 | — |
| rst_clk→clk_mem / slow | 2.737 | 0.000 | 1.412 | 0.000 | 0/0 | — |
| phy_dq_sysclk_0→clk_mem / slow | 3.756 | 0.000 | 0.936 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_0 / slow | 1.830 | 0.000 | 0.440 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_1 / slow | 1.439 | 0.000 | 0.446 | 0.000 | 0/0 | — |
| clk_cam0→clk_cam0 / fast | 7.583 | 0.000 | 0.102 | 0.000 | 0/0 | 413.736 |
| clk_cam1→clk_cam1 / fast | 7.602 | 0.000 | 0.132 | 0.000 | 0/0 | 417.014 |
| clk_pix→clk_pix / fast | 10.082 | 0.000 | 0.120 | 0.000 | 0/0 | 295.334 |
| clk_serial→clk_serial / fast | 2.084 | 0.000 | 0.225 | 0.000 | 0/0 | 1640.420 |
| clk_mem→rst_clk / fast | 4.782 | 0.000 | 0.887 | 0.000 | 0/0 | — |
| rst_clk→rst_clk / fast | 6.323 | 0.000 | 0.133 | 0.000 | 0/0 | 596.303 |
| phy_dq_sysclk_0→rst_clk / fast | 5.524 | 0.000 | 1.078 | 0.000 | 0/0 | — |
| clk_mem→clk_mem / fast | 3.374 | 0.000 | 0.100 | 0.000 | 0/0 | 216.169 |
| phy_dq_sysclk_1→clk_mem / fast | 4.473 | 0.000 | 0.102 | 0.000 | 0/0 | — |
| rst_clk→clk_mem / fast | 5.449 | 0.000 | 0.132 | 0.000 | 0/0 | — |
| phy_dq_sysclk_0→clk_mem / fast | 5.198 | 0.000 | 0.287 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_0 / fast | 4.096 | 0.000 | 0.100 | 0.000 | 0/0 | — |
| clk_mem→phy_dq_sysclk_1 / fast | 3.744 | 0.000 | 0.100 | 0.000 | 0/0 | — |

主时钟最紧的是clk_mem：slow setup +0.244 ns，hold最小约+0.100 ns。正裕量路径也已保留供后续集成评估，不仅保存违例。

## Recovery / removal

Recovery违例集中在DDR PHY复位相关路径。以下是报告原文汇总，未自行添加false_path或修改IP/RTL/约束。

| 时钟对/角 | recovery WNS ns | recovery TNS ns | 违例端点 |
|---|---:|---:|---:|
| rst_clk→phy_dq_clk_0 / slow | -5.076 | -154.511 | 34 |
| clk_mem→phy_dq_clk_0 / slow | -3.933 | -11.013 | 3 |
| rst_clk→phy_dq_sysclk_0 / slow | -3.904 | -114.733 | 35 |
| rst_clk→phy_dq_clk_1 / slow | -4.143 | -283.851 | 84 |
| clk_mem→phy_dq_clk_1 / slow | -4.045 | -14.390 | 4 |
| rst_clk→phy_dq_sysclk_1 / slow | -2.860 | -188.839 | 84 |
| rst_clk→phy_dq_clk_0 / fast | -3.072 | -86.503 | 34 |
| clk_mem→phy_dq_clk_0 / fast | -2.870 | -8.070 | 3 |
| rst_clk→phy_dq_sysclk_0 / fast | -1.695 | -48.281 | 35 |
| rst_clk→phy_dq_clk_1 / fast | -2.561 | -152.935 | 84 |
| clk_mem→phy_dq_clk_1 / fast | -2.894 | -10.549 | 4 |
| rst_clk→phy_dq_sysclk_1 / fast | -1.098 | -61.779 | 84 |

最差recovery路径（expanded report）：

| 角 | 起点→终点 | 裕量ns |
|---|---|---:|
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_dqs_rst/opit_0_inv/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/i_ca_group[2].u_ddc_ca/ddc_inst/RST | -5.076 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_dqs_rst/opit_0_inv/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/u_outbuft_wen/opit_1/OSR_IOLHR | -5.026 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_iol_rst/opit_0_inv_L6QL5Q_perm/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/i_ca_group[2].u_tserdes_ca1/oserdes_inst/TSR | -4.995 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_dqs_rst/opit_0_inv/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/u_outbuft_casn/opit_1/OSR_IOLHR | -4.909 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_iol_rst/opit_0_inv_L6QL5Q_perm/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/i_ca_group[2].u_tserdes_ca0/oserdes_inst/TSR | -4.892 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_dqs_rst/opit_0_inv/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/i_ca_group[1].u_ddc_ca/ddc_inst/RST | -4.891 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_iol_rst/opit_0_inv_L6QL5Q_perm/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/i_ca_group[1].u_tserdes_ca1/oserdes_inst/TSR | -4.821 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_dqs_rst/opit_0_inv/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/i_mem_addr_0[10].u_outbuft_addr0/opit_1/OSR_IOLHR | -4.728 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_dqs_rst/opit_0_inv/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/u_outbuftco_ck/opit_3/OSR_IOLHR | -4.707 |
| slow | u_ddr3/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_dqs_rst/opit_0_inv/CLK → u_ddr3/u_ddrphy_top/ddrphy_slice_top/k_mem_ba[2].u_outbuft_ba/opit_1/OSR_IOLHR | -4.692 |

Recovery各角最差20条逐级明细见recovery_top20_detail.txt；removal同样保留。setup/hold为0违例并不消除recovery问题，上板正常也未用于豁免违例。

## 路径覆盖

从既有pnr.adf补导report_timing -max_path 200 -nworst 1 -input_pins TRUE，不重跑综合、映射或布线。各捕获时钟按slow/fast分别选最差200条setup；不足200时保留全部。setup和hold最差20条明细分别按角保留。补导全部路径索引、接近零的正setup裕量路径、recovery/removal另存。
补导记录数：10424；原生默认报告也完整保留。

## 资源

下表来自路后PRR逻辑层次，物理容量、IO、GPLL/PPLL以及DRM原语拆分见resource_summary.txt。

| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| edrv32_fpga_board_imgtest_top | 20472 | 24914 | 85 | 148 | 77 |
| g_key[0].u_sync | 0 | 2 | 0 | 0 | 0 |
| g_key[1].u_sync | 0 | 2 | 0 | 0 | 0 |
| g_key[2].u_sync | 0 | 2 | 0 | 0 | 0 |
| u_cam_init | 82 | 58 | 0 | 0 | 1 |
| u_ctrl | 220 | 59 | 0 | 0 | 0 |
| u_ddr3 | 4927 | 5204 | 48 | 0 | 0 |
| u_disp | 2001 | 2857 | 0 | 7 | 8 |
| u_geo | 3078 | 3041 | 0 | 9 | 16 |
| u_keys | 80 | 66 | 0 | 0 | 0 |
| u_mem | 1917 | 1110 | 0 | 0 | 28 |
| u_pix | 4768 | 7760 | 0 | 132 | 11 |
| u_pll_video | 0 | 0 | 0 | 0 | 0 |
| u_reset_ctrl | 0 | 10 | 0 | 0 | 0 |
| u_tmds | 0 | 0 | 0 | 0 | 0 |
| u_vin | 3395 | 4743 | 37 | 0 | 13 |

## 各阶段

| 阶段 | Real | CPU | Process CPU | 峰值内存 | W/C/E行数 |
|---|---|---|---|---|---|
| compile | 0h:1m:2s | 0h:0m:11s | 0h:0m:11s | 359 MB | 1686/0/0 |
| synthesize | 0h:2m:5s | 0h:0m:1s | 0h:0m:2s | 1,486 MB | 11991/56/0 |
| device_map | 0h:0m:27s | 0h:0m:1s | 0h:0m:1s | 951 MB | 19/0/0 |
| place_route | 0h:5m:39s | 0h:0m:16s | 0h:0m:24s | 4,210 MB | 0/57/0 |
| report_timing | 0h:0m:40s | 0h:0m:3s | 0h:0m:4s | 2,790 MB | 148/0/0 |
| generate_bitstream | 0h:0m:47s | 0h:0m:6s | 0h:0m:6s | 2,837 MB | 0/1/0 |

W/C/E为行数而非独立缺陷数，完整分类及所有warning/error在flow_summary.txt和logs/。原生CMR/SNR/DMR/PRR/RTR/CCR保存于native_reports。

## 上板

用户确认：上板功能均正常；KEY1切换像素处理时有很小的卡顿，未测量时长，不推断根因。逐项记录见checklist.md。LED状态及各档照片未单独取得，不补写为已验证。

## 导入与约束

保留本机此前授权的导入脚本路径修正：工程目录../../EdRV32-Competition-2026定位仓库，include_path传rtl/include，FPGA_MODE。GUI初次导入曾报Flow-0245和头文件错误，最终工程已完成全流程；不把之前的路径展开检查当作实际编译通过证据。未修改RTL/IP或FDC。时钟约束识别情况见clock_checks.txt。

## 本地原始数据与复现

- 完整工程日志、原生报告：G:/codex_project/EdRV32-FPGA/EdRV32-B3I/各阶段目录。
- 补导报告：G:/codex_project/EdRV32-Competition-2026/build/win/20261029-06-b3-imgtest/export/report_timing/edrv32_fpga_board_imgtest_top.rtr。
- 整理命令：C:/Python314/python.exe tasks/win/20261029-06-b3-imgtest/src/collect_reports.py。
- 只收集已有实现结果并补导时序；没有重跑综合/布局布线，没有核对时间戳或做文件哈希，也没有提交数据库、bitstream、完整原始执行日志。
