# NPU 数据通路：危险与接近边界的时序路径

报告器件 PG2L200H-6 FBB676，PDS 2022.2-SP6.1 build 138931，Pre-silicon、多角分析。
目标周期 6.667 ns；记录的是本轮既有 PnR 数据库，未重新运行布局布线。
低于 1 ns 的正 setup、低于 0.2 ns 的正 hold 在本报告中作为关注窗口，属于人工分析分类，不是新验收门槛。

## 全设计汇总

| 检查 | 角 | 最差裕量 ns | 总负裕量 ns | 违例端点 | 总端点 |
|---|---|---:|---:|---:|---:|
| Setup | slow | 0.341 | 0.000 | 0 | 114062 |
| Setup | fast | 2.756 | 0.000 | 0 | 114062 |
| Hold | slow | 0.139 | 0.000 | 0 | 114062 |
| Hold | fast | 0.101 | 0.000 | 0 | 114062 |
| Recovery | slow | 4.364 | 0.000 | 0 | 122 |
| Recovery | fast | 5.355 | 0.000 | 0 | 122 |
| Removal | slow | 0.488 | 0.000 | 0 | 122 |
| Removal | fast | 0.330 | 0.000 | 0 | 122 |
| Minimum Pulse Width | slow | 2.373 | 0.000 | 0 | 19982 |
| Minimum Pulse Width | fast | 2.678 | 0.000 | 0 | 19982 |

## 导出样本的分布

| 角/类型 | 样本数 | 最小 ns | 最大 ns | 负裕量 | 0≤裕量<0.5 ns | 0≤裕量<1 ns |
|---|---:|---:|---:|---:|---:|---:|
| slow setup | 200 | 0.341 | 0.952 | 0 | 4 | 200 |
| fast setup | 200 | 2.756 | 3.125 | 0 | 0 | 0 |
| slow hold | 200 | 0.139 | 0.234 | 0 | 200 | 200 |
| fast hold | 200 | 0.101 | 0.158 | 0 | 200 | 200 |

这些是 nworst=1、每类每角最多 200 条路径的统计，不是全设计的完整裕量直方图。
setup_top200.txt 和 hold_top200.txt 包含全部样本；前 20 条逐级明细包含单元、扇出、连线延迟。

## 最差慢角 setup 前 20 条

| # | 角 | 起点 | 终点 | 裕量 ns | 级数 |
|---:|---|---|---|---:|---:|
| 1 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[25].g_lane[1].u_multiply/u_apm/gopapm/X[5]` | 0.341 | 1 |
| 2 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[26].g_lane[1].u_multiply/u_apm/gopapm/X[11]` | 0.366 | 1 |
| 3 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[25].g_lane[6].u_multiply/u_apm/gopapm/X[15]` | 0.439 | 1 |
| 4 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[16].g_lane[2].u_multiply/u_apm/gopapm/X[2]` | 0.494 | 1 |
| 5 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[24].g_lane[3].u_multiply/u_apm/gopapm/X[4]` | 0.527 | 1 |
| 6 | slow | `u_datapath/u_mac_array/g_channel[0].g_lane[7].u_multiply/u_apm/gopapm/CLK` | `u_datapath/u_mac_array/g_channel[0].g_pixel[0].r1_data_r[3][16]/opit_0_AQ_perm/CIN` | 0.532 | 4 |
| 7 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[21].g_lane[2].u_multiply/u_apm/gopapm/X[15]` | 0.544 | 1 |
| 8 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[25].g_lane[3].u_multiply/u_apm/gopapm/X[17]` | 0.577 | 1 |
| 9 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[24].g_lane[3].u_multiply/u_apm/gopapm/X[17]` | 0.579 | 1 |
| 10 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[23].g_lane[2].u_multiply/u_apm/gopapm/X[13]` | 0.589 | 1 |
| 11 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[23].g_lane[3].u_multiply/u_apm/gopapm/X[23]` | 0.589 | 1 |
| 12 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[21].g_lane[2].u_multiply/u_apm/gopapm/X[2]` | 0.594 | 1 |
| 13 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[18].g_lane[3].u_multiply/u_apm/gopapm/X[7]` | 0.596 | 1 |
| 14 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[18].g_lane[3].u_multiply/u_apm/gopapm/X[8]` | 0.596 | 1 |
| 15 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[18].g_lane[3].u_multiply/u_apm/gopapm/X[9]` | 0.596 | 1 |
| 16 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[18].g_lane[3].u_multiply/u_apm/gopapm/X[10]` | 0.596 | 1 |
| 17 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[25].g_lane[3].u_multiply/u_apm/gopapm/X[4]` | 0.603 | 1 |
| 18 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[18].g_lane[3].u_multiply/u_apm/gopapm/X[16]` | 0.605 | 1 |
| 19 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[19].g_lane[2].u_multiply/u_apm/gopapm/X[3]` | 0.607 | 1 |
| 20 | slow | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` | `u_datapath/u_mac_array/g_channel[21].g_lane[2].u_multiply/u_apm/gopapm/X[18]` | 0.612 | 1 |

## NPU 裕度与整机集成风险

当前 Design Summary 为 All Constraints Met，慢角 WNS +0.341 ns、TNS 0，工具估计 Fmax 158.0778 MHz。
0.341/6.667≈5.1%（按报告数字计算的周期余量）；最差路径中已扣除 0.050 ns clock uncertainty。
在其他项保持不变的算术条件下，额外延迟/额外时钟不确定度合计增加 0.341 ns 就会耗尽该路径现有余量。
这不是对整机额外延迟的测量或预测。

最差路径：window a5_tag_r[48] → MAC APM X[5]，只有 1 级逻辑。原始明细：
- Tco：0.213 ns；term_tag_w[48] 连线：0.956 ns，扇出 129。
- LUT6D：0.275 ns；到 APM X 输入的 activation0_w[5] 连线：4.249 ns，扇出 8。
- 两段数据连线共 5.205 ns（0.956+4.249，计算值），逻辑本身不是该路径延迟的大部分。
- Clock skew −0.114 ns，APM setup 0.469 ns，报告 clock uncertainty 0.050 ns。

慢角前 200 条中有 4 条小于 0.5 ns，全部 200 条小于 1 ns；正裕量路径均已保存，未按是否违例筛掉。
按起终模块分组（仅这 200 条）：

| 起点模块 | 终点模块 | 样本数 |
|---|---|---:|
| `u_datapath/u_window` | `u_datapath/u_mac_array` | 172 |
| `u_datapath/u_mac_array` | `u_datapath/u_mac_array` | 15 |
| `u_datapath/u_window` | `u_datapath/u_weight_store` | 11 |
| `u_datapath/u_weight_store` | `u_datapath/u_weight_store` | 2 |

### 内部 hold 裕量

快角全局最差 hold +0.101 ns 有测量壳层观测寄存器路径；数据通路内部也存在 +0.101 ns 的路径，不能仅归因于测量壳层。

| # | 角 | 起点 | 终点 | 裕量 ns | 级数 |
|---:|---|---|---|---:|---:|
| 1 | fast | `u_datapath/u_accum/g_channel[31].g_pixel[0].accum_data_r[3]/opit_0_AQ_perm/CLK` | `u_datapath/u_result_quant/hold_data_r[993]/opit_0/D` | 0.101 | 0 |
| 2 | fast | `u_datapath/u_window/a4_activation_r[20]/opit_0_L6Q_perm/CLK` | `u_datapath/u_window/g_activation_copy[3].activation_r[20]/opit_0/D` | 0.103 | 0 |
| 3 | fast | `u_datapath/u_window/a4_activation_r[148]/opit_0_L6Q_perm/CLK` | `u_datapath/u_window/g_activation_copy[3].activation_r[148]/opit_0/D` | 0.103 | 0 |
| 4 | fast | `u_datapath/u_window/a4_activation_r[22]/opit_0_L6Q_perm/CLK` | `u_datapath/u_window/g_activation_copy[3].activation_r[22]/opit_0/D` | 0.104 | 0 |
| 5 | fast | `u_datapath/u_mac_array/g_channel[20].g_pixel[0].r1_data_r[2][15]/opit_0_AQ_perm/CLK` | `u_datapath/u_mac_array/g_channel[20].g_pixel[0].r2_data_r[1][16]/opit_0_AQ_perm/CIN` | 0.105 | 1 |
| 6 | fast | `u_datapath/u_mac_array/g_channel[23].g_pixel[1].r2_data_r[0][7]/opit_0_AQ_perm/CLK` | `u_datapath/u_mac_array/g_channel[23].g_pixel[1].r3_data_r[8]/opit_0_AQ_perm/CIN` | 0.105 | 1 |
| 7 | fast | `u_datapath/u_result_quant/hold_data_r[1508]/opit_0/CLK` | `u_datapath/u_result_quant/g_lane[15].q0_acc_r[4]/opit_0_L6Q_perm/I3` | 0.105 | 0 |
| 8 | fast | `u_datapath/u_window/a4_activation_r[23]/opit_0_L6Q_perm/CLK` | `u_datapath/u_window/g_activation_copy[3].activation_r[23]/opit_0/D` | 0.107 | 0 |
| 9 | fast | `u_datapath/u_mac_array/g_channel[17].g_pixel[1].r1_data_r[2][3]/opit_0_AQ_perm/CLK` | `u_datapath/u_mac_array/g_channel[17].g_pixel[1].r2_data_r[1][4]/opit_0_AQ_perm/CIN` | 0.111 | 1 |
| 10 | fast | `u_datapath/u_writeback/chunk_tail_r[4]/opit_0_inv_L6Q_perm/CLK` | `u_datapath/u_writeback/chunk_queue_r_18_doreg[1]/opit_0_32X2DL6QL5Q/WADDR[4]` | 0.111 | 0 |

慢角内部最差 hold +0.139 ns。前 200 条快角 hold 全部低于 0.2 ns，细节保存在 hold_top20.txt。
fast removal +0.330 ns，slow removal +0.488 ns，细节见 recovery_removal_top20.txt。

### 高扇出与约束覆盖

映射报告前 100 个高扇出网络已保存：window a4_valid_r 扇出 2869、a3_valid_r 2358、
accum r4_valid_r 的 CE 扇出 2048、accum_valid_w 1584 等；完整名称及各阶段时钟负载见 high_fanout.txt。
这些是映射阶段计数，不与路后具体一条时序路径的 fanout 混用。
rst_n_i、stim_i、obs_o 没有 input/output delay，工具把它们当作组合输入/输出；
这些 IO 路径没有 slack 或通过结论，见 unconstrained_io_paths.txt。
constraint_check 的 0 error / 0 warning 只说明已给定约束的检查情况，不能替代 IO 时序覆盖。

### 本次结果的适用范围

- 这是独立数据通路测量顶层，输入由 1025 位串行激励寄存器驱动，输出经观测寄存器和 XOR 树折叠。
- 顶层采用单 clk_npu、0 个 PLL；当前 FDC 是 150 MHz 的测量约束，板载输入实际为 27 MHz，本轮不上板。
- 完整 SoC 的真实 PLL 时钟/不确定度、跨域接口和外部接口约束不在本次测量范围内。
- CPU、NPU、DDR、媒体等共用器件后的布局、布线和扇出变化没有在这两个独立工程中测量。
- 因此，本次正裕量不能保证最终整机上板不违例；需要以整机顶层真实约束下的路后多角报告确认。
- scratch 不在当前 datapath 中，当前 148 DRM 比较基准不包含它；不是完整 NPU/SoC 总资源。

## 路径及日志位置

原始完整日志与报告：`G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP`。
原始默认报告保存在 native_reports/report_timing/；扩展完整报告留在 build/win/20261027-02-cpu-npu-synth/，
本目录保存全部扩展路径索引、每角 200 条 setup/hold 列表和前 20 条逐级明细。
日志摘要与所有 W:/E: 原文分别见 flow_summary.txt、logs/warnings_detail.txt；无 RTL 或约束修改。
