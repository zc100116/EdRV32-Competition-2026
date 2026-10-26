# 当前设计危险时序路径

来源：`report_timing_expanded/report_timing/edrv32_fpga_cpu_sys_top.rtr`。
本报告从已完成的 PnR 数据库重新分析，使用 max_path=200、nworst=1，未重跑编译、综合或布局布线，原工程报告未修改。
完整报告约 13.25 MB，按用户要求保留原文。

## 总体结果

- 目标 clk_sys 周期 6.667 ns；最差 setup WNS 为 -7.708 ns，TNS 为 -86183.305 ns。
- Slow corner setup 违例端点 19008 / 46871；Fast corner 为 10320 / 46871。
- Estimated Frequency 为 69.5652 MHz，目标约150MHz，时序未收敛。
- Slow setup 前200条均违例，范围 -7.708 至 -7.143 ns；Fast setup 前200条均违例，范围 -1.911 至 -1.528 ns。
- Hold 前200条无负裕量；全局报告 THS=0，最小 WHS 为 Fast corner 的 +0.107 ns。
- Recovery/Removal 两角均无负总裕量；扩展报告保留各200条，最差 Recovery slow 为 +0.875 ns，Removal fast 为 +0.217 ns。

## Slow setup 最差路径

以下逐项来自工具输出。路径中的逻辑连接只表示当前网表，不直接作为 RTL 修复结论。

| 排名 | 起点 | 终点 | 裕量 ns | 逻辑级数 |
|---:|---|---|---:|---:|
| 1 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][62]/opit_0_inv_L6Q_perm/I5 | -7.708 | 30 |
| 2 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][61]/opit_0_inv_L6Q_perm/I1 | -7.677 | 30 |
| 3 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][62]/opit_0_inv_L6Q_perm/I5 | -7.649 | 30 |
| 4 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][60]/opit_0_inv_L6Q_perm/I5 | -7.632 | 30 |
| 5 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][61]/opit_0_inv_L6Q_perm/I1 | -7.620 | 30 |
| 6 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][58]/opit_0_inv_L6Q_perm/I5 | -7.617 | 29 |
| 7 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][59]/opit_0_inv_L6Q_perm/I4 | -7.603 | 30 |
| 8 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][57]/opit_0_inv_L6Q_perm/I1 | -7.586 | 29 |
| 9 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[5][62]/opit_0_inv_L6Q_perm/I5 | -7.576 | 30 |
| 10 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][60]/opit_0_inv_L6Q_perm/I5 | -7.575 | 30 |
| 11 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][58]/opit_0_inv_L6Q_perm/I5 | -7.560 | 29 |
| 12 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][54]/opit_0_inv_L6Q_perm/I1 | -7.557 | 28 |
| 13 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[5][61]/opit_0_inv_L6Q_perm/I1 | -7.546 | 30 |
| 14 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[6][62]/opit_0_inv_L6Q_perm/I5 | -7.543 | 30 |
| 15 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[2][56]/opit_0_inv_L6Q_perm/I5 | -7.541 | 29 |
| 16 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][59]/opit_0_inv_L6Q_perm/I1 | -7.536 | 30 |
| 17 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[1][57]/opit_0_inv_L6Q_perm/I1 | -7.529 | 29 |
| 18 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[7][58]/opit_0_inv_L6Q_perm/I2 | -7.528 | 29 |
| 19 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[6][61]/opit_0_inv_L6Q_perm/I1 | -7.512 | 30 |
| 20 | u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK | u_cpu_subsys/u_core/u_csr/counter_r[5][60]/opit_0_inv_L6Q_perm/I5 | -7.504 | 30 |

最差路径从 D-cache 的 addr_r[11] 出发，经缓存命中判断、core 控制、frontend 和 ic_miss_start_w，
进入 CSR counter_r[2] 的计数逻辑；逐级单元、连线延迟、fanout 和时钟偏斜均保留在 setup_top20_detail.txt。
这段描述仅依据第一条路径中的实际资源名，不把具体根因或修复方案预先定为某个模块。

## 前200条 Slow setup 的终点分组

| 终点分组 | 条数 | 最差裕量 ns |
|---|---:|---:|
| u_csr | 131 | -7.708 |
| u_frontend | 69 | -7.360 |

## 必须同时关注的未约束端口

工具在默认报告和扩展报告中均给出 Timing-4086/4087：

- 输入：key_n_i、rst_n_i、uart_rx_i。
- 输出：led_o[0]、led_o[1]、led_o[2]、led_o[3]、uart_tx_o。

这些端口没有 input/output delay 时序约束，被当作 combinational input/output。
扩展报告保留两角的组合路径，各类最多10条，但这些路径没有可判定的 setup/hold Slack。
不能因内部寄存器 hold 通过，就认定这些板级 IO 的外部时序也已验证。
本次未自行补充约束或例外。

## 高扇出信息与完整路径

- high_fanout.txt：Device Map 的高扇出、复位和CE表，以及 PnR 的时钟负载表。时钟、复位和控制信号需结合功能分析，不能只凭扇出数认定缺陷。
- setup_top200.txt：慢、快两角各200条顺序电路 setup 路径，包含起终点、裕量、级数。
- setup_top20_detail.txt：慢、快两角各20条 setup 逐级明细。
- hold_top20.txt：慢、快两角各20条 hold 逐级明细。
- report_timing_expanded/all_paths.tsv：全部1640条导出路径的索引，包括 setup、hold、recovery、removal、未约束组合路径。
- 完整 `.rtr` 保留所有工具明细；原默认报告仍在 report_timing/。
