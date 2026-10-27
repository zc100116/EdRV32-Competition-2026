# CPU 第二轮：危险与接近边界的时序路径

报告器件 PG2L200H-6 FBB676，PDS 2022.2-SP6.1 build 138931，Pre-silicon、多角分析。
目标周期 6.667 ns；记录的是本轮既有 PnR 数据库，未重新运行布局布线。
低于 1 ns 的正 setup、低于 0.2 ns 的正 hold 在本报告中作为关注窗口，属于人工分析分类，不是新验收门槛。

## 全设计汇总

| 检查 | 角 | 最差裕量 ns | 总负裕量 ns | 违例端点 | 总端点 |
|---|---|---:|---:|---:|---:|
| Setup | slow | -3.920 | -19583.569 | 12645 | 43021 |
| Setup | fast | -0.069 | -0.201 | 7 | 43021 |
| Hold | slow | 0.143 | 0.000 | 0 | 43021 |
| Hold | fast | 0.100 | 0.000 | 0 | 43021 |
| Recovery | slow | 1.876 | 0.000 | 0 | 2858 |
| Recovery | fast | 3.716 | 0.000 | 0 | 2858 |
| Removal | slow | 0.452 | 0.000 | 0 | 2858 |
| Removal | fast | 0.307 | 0.000 | 0 | 2858 |
| Minimum Pulse Width | slow | 2.373 | 0.000 | 0 | 6716 |
| Minimum Pulse Width | fast | 2.678 | 0.000 | 0 | 6716 |

## 导出样本的分布

| 角/类型 | 样本数 | 最小 ns | 最大 ns | 负裕量 | 0≤裕量<0.5 ns | 0≤裕量<1 ns |
|---|---:|---:|---:|---:|---:|---:|
| slow setup | 200 | -3.920 | -2.888 | 200 | 0 | 0 |
| fast setup | 200 | -0.069 | 0.820 | 7 | 61 | 193 |
| slow hold | 200 | 0.143 | 0.305 | 0 | 200 | 200 |
| fast hold | 200 | 0.100 | 0.199 | 0 | 200 | 200 |

这些是 nworst=1、每类每角最多 200 条路径的统计，不是全设计的完整裕量直方图。
setup_top200.txt 和 hold_top200.txt 包含全部样本；前 20 条逐级明细包含单元、扇出、连线延迟。

## 最差慢角 setup 前 20 条

| # | 角 | 起点 | 终点 | 裕量 ns | 级数 |
|---:|---|---|---|---:|---:|
| 1 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[2][63]/opit_0_inv_AQ_perm/CIN` | -3.920 | 24 |
| 2 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[4][63]/opit_0_inv_AQ_perm/CIN` | -3.920 | 24 |
| 3 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[3][63]/opit_0_inv_AQ_perm/CIN` | -3.837 | 24 |
| 4 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[0][63]/opit_0_inv_AQ_perm/CIN` | -3.835 | 24 |
| 5 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[2][59]/opit_0_inv_AQ_perm/CIN` | -3.829 | 23 |
| 6 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[4][59]/opit_0_inv_AQ_perm/CIN` | -3.829 | 23 |
| 7 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[6][63]/opit_0_inv_AQ_perm/CIN` | -3.796 | 24 |
| 8 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[3][59]/opit_0_inv_AQ_perm/CIN` | -3.746 | 23 |
| 9 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[0][59]/opit_0_inv_AQ_perm/CIN` | -3.744 | 23 |
| 10 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[2][55]/opit_0_inv_AQ_perm/CIN` | -3.738 | 22 |
| 11 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[4][55]/opit_0_inv_AQ_perm/CIN` | -3.738 | 22 |
| 12 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[1][63]/opit_0_inv_AQ_perm/CIN` | -3.713 | 25 |
| 13 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[6][59]/opit_0_inv_AQ_perm/CIN` | -3.705 | 23 |
| 14 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[5][63]/opit_0_inv_AQ_perm/CIN` | -3.691 | 25 |
| 15 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[3][55]/opit_0_inv_AQ_perm/CIN` | -3.654 | 22 |
| 16 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[0][55]/opit_0_inv_AQ_perm/CIN` | -3.653 | 22 |
| 17 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[7][63]/opit_0_inv_AQ_perm/CIN` | -3.648 | 24 |
| 18 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[2][51]/opit_0_inv_AQ_perm/CIN` | -3.647 | 21 |
| 19 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[4][51]/opit_0_inv_AQ_perm/CIN` | -3.647 | 21 |
| 20 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/u_csr/counter_r[1][59]/opit_0_inv_AQ_perm/CIN` | -3.622 | 24 |

CPU 150 MHz 未收敛，慢角 WNS −3.920 ns、12645/43021 端点违例；快角仍有 7 个端点违例。
最差慢角路径从 Dcache 地址寄存器到 CSR counter_r[2][63]，24 级逻辑；此为工具的起终点标注，不等同于已经确认 RTL 根因。
全局慢角前 200 条都违例，因此另外执行 slack>0 且 slack<1 的正裕量导出，保留快、慢角各 200 条。

## 单独保存的正裕量危险路径

| 角 | 数量 | 最小 ns | 最大 ns |
|---|---:|---:|---:|
| slow | 200 | 0.001 | 0.030 |
| fast | 200 | 0.008 | 0.831 |

正裕量列表：setup_near_positive_top200.txt；逐级细节：setup_near_positive_top20_detail.txt。
慢角最接近零的正裕量只有 +0.001 ns；处理最坏违例后，这批路径仍需一并复查。

### 慢角最接近零的正裕量前 20 条

| # | 角 | 起点 | 终点 | 裕量 ns | 级数 |
|---:|---|---|---|---:|---:|
| 1 | slow | `u_cpu_subsys/u_core/u_frontend/u_ib/read_ptr_r[1]/opit_0_inv_L6Q_perm/CLK` | `u_cpu_subsys/u_core/e_record_r[0][105]/opit_0_L6QL5Q_perm/I4` | 0.001 | 5 |
| 2 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/m_record_r[0][24]/opit_0/CE` | 0.001 | 5 |
| 3 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/m_result_r[0][11]/opit_0_L6Q_perm/CE` | 0.001 | 5 |
| 4 | slow | `u_cpu_subsys/u_core/w_record_r[0][86]/opit_0/CLK` | `u_cpu_subsys/u_core/u_csr/instret_r[14]/opit_0_inv_L6Q_perm/I5` | 0.001 | 7 |
| 5 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[0][65]/opit_0_L6Q_perm/I5` | 0.001 | 7 |
| 6 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[0][107]/opit_0_L6Q_perm/I3` | 0.001 | 7 |
| 7 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[1][78]/opit_0_L6Q_perm/I4` | 0.001 | 7 |
| 8 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[3][131]/opit_0_L6Q_perm/I2` | 0.001 | 7 |
| 9 | slow | `u_cpu_subsys/u_core/e_operand_a_r[0][0]/opit_0_L6Q_perm/CLK` | `u_cpu_subsys/u_core/e_resolved_r/opit_0_inv_L6Q_perm/I4` | 0.002 | 11 |
| 10 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[0][142]/opit_0_L6Q_perm/I3` | 0.002 | 7 |
| 11 | slow | `u_cpu_subsys/u_core/e_operand_a_r[0][0]/opit_0_L6Q_perm/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[1][23]/opit_0_L6Q_perm/CE` | 0.002 | 10 |
| 12 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[2][64]/opit_0_L6Q_perm/I5` | 0.002 | 7 |
| 13 | slow | `u_sys_subsys/u_sram/u_memory/u_ip/U_ipml_spram_ip_ram_sram/ADDR_LOOP[1].DATA_LOOP[3].U_GTP_DRM36K_E1/gopdrm_36k/CLKA[0]` | `u_cpu_subsys/u_dcache/u_data1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_data/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/DB1[7]` | 0.002 | 4 |
| 14 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/committed_ras_data_r[15]/opit_0_L6Q_perm/CE` | 0.003 | 6 |
| 15 | slow | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` | `u_cpu_subsys/u_core/committed_ras_data_r[47]/opit_0_L6Q_perm/CE` | 0.003 | 6 |
| 16 | slow | `u_cpu_subsys/u_core/u_frontend/u_ib/read_ptr_r[1]/opit_0_inv_L6Q_perm/CLK` | `u_cpu_subsys/u_core/u_csr/instret_r[1]/opit_0_inv_L6Q_perm/I1` | 0.003 | 6 |
| 17 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[0][80]/opit_0_L6Q_perm/I5` | 0.003 | 8 |
| 18 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[2][106]/opit_0_L6Q_perm/I2` | 0.003 | 7 |
| 19 | slow | `u_cpu_subsys/u_core/e_operand_a_r[0][0]/opit_0_L6Q_perm/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[2][134]/opit_0_L6Q_perm/CE` | 0.003 | 10 |
| 20 | slow | `u_cpu_subsys/u_core/u_frontend/f2_pc_r[9]/opit_0/CLK` | `u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[3][78]/opit_0_L6Q_perm/I2` | 0.003 | 7 |

快角最差 hold +0.100 ns，见 hold_top20.txt；slow removal +0.452 ns、fast removal +0.307 ns 也保留了逐级路径。
时序未约束 IO 有 8 个：key_n_i、rst_n_i、uart_rx_i、led_o[0..3]、uart_tx_o。

## 路径及日志位置

原始完整日志与报告：`G:/codex_project/EdRV32-FPGA/EdRV32`。
原始默认报告保存在 native_reports/report_timing/；扩展完整报告留在 build/win/20261027-02-cpu-npu-synth/，
本目录保存全部扩展路径索引、每角 200 条 setup/hold 列表和前 20 条逐级明细。
日志摘要与所有 W:/E: 原文分别见 flow_summary.txt、logs/warnings_detail.txt；无 RTL 或约束修改。
