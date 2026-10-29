# 20261029-01-media-r4 结果

| 项 | 内容 |
|---|---|
| 任务卡执行commit | 90cf049ec44e877bfe983597bcf0192d4ba1b82e |
| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |
| 完成情况 | 综合、PnR和STA完成，报告及复制寄存器核对完成；时序通过，但clk_mem未达到+1.0 ns目标 |

## 时序

| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |
|---|---:|---:|---:|---:|---|---:|
| clk_mem/slow | 0.592 | 0.000 | 0.143 | 0.000 | 0/0 | 134.9892 |
| clk_ext/slow | 1.872 | 0.000 | 0.155 | 0.000 | 0/0 | 163.1854 |
| clk_mem/fast | 3.497 | 0.000 | 0.100 | 0.000 | 0/0 | 222.0742 |
| clk_ext/fast | 4.439 | 0.000 | 0.105 | 0.000 | 0/0 | 280.8200 |

clk_mem slow由上一轮+0.388 ns提升至+0.592 ns，改善0.204 ns；无违例，距+1.0 ns目标仍差0.408 ns。
clk_ext slow为+1.872 ns，上一轮+1.898 ns。原引脚K21/D18与异步组检查保留在clock_checks.txt，未放宽专用时钟布线。
PDS violating endpoints=0; exported unique endpoints=0; coverage=complete.
危险正裕度导出采用0<slack<1 ns、max_path100000、nworst1，实际54条，未在200条截断。这里的全量是每个端点最差一条，不是枚举同一端点所有组合拓扑路径。
setup_near_positive_top200.txt沿用任务卡文件名，包含全部导出记录；setup_near_groups.txt给出寄存器对分组。
上一轮任务卡模板写146条，而上一轮提交的slow sequential筛选结果为144条；本轮按上述明示定义报告实测数量，不将模板参考数当本轮测量。

危险路径分组：

| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |
|---|---:|---:|---:|
| u_pix/discard_r → u_pix/advance_kernel11_r | 12 | 0.592 | 3 |
| u_pix/discard_r → u_pix/advance_kernel10_r | 15 | 0.693 | 3 |
| u_pix/discard_r → u_pix/advance_kernel21_r | 4 | 0.718 | 3 |
| u_pix/discard_r → u_pix/advance_kernel20_r | 8 | 0.783 | 3 |
| u_pix/discard_r → u_pix/advance_filter2_r | 2 | 0.787 | 3 |
| stim_mem_r → u_geo/u_tiles/v_o | 6 | 0.798 | 7 |
| u_pix/discard_r → u_pix/advance_filter1_r | 1 | 0.828 | 3 |
| u_eth/u_rx/header_r → u_eth/u_rx/start_r | 4 | 0.841 | 9 |
| u_vin/u_fmt1/width_r → u_vin/u_msrc/u_buffer/head_data_r | 2 | 0.952 | 8 |

最差setup路径（每域前3条；完整每域200条及前20条逐级明细见产物）：

- clk_mem: u_pix/discard_r/opit_0_inv_L6QL5_perm/CLK → u_pix/advance_kernel11_r[4]/opit_0_inv/D；0.592 ns，3级。
- clk_mem: u_pix/discard_r/opit_0_inv_L6QL5_perm/CLK → u_pix/advance_kernel10_r[17]/opit_0_inv/D；0.693 ns，3级。
- clk_mem: u_pix/discard_r/opit_0_inv_L6QL5_perm/CLK → u_pix/advance_kernel10_r[19]/opit_0_inv/D；0.693 ns，3级。
- clk_ext: u_disp/u_timing/vertical_r[5]/opit_0_inv_L6QL5Q_perm/CLK → u_disp/u_scan/perf0_r[31]/opit_0_inv_AQ_perm/CE；1.872 ns，11级。
- clk_ext: u_disp/u_timing/vertical_r[5]/opit_0_inv_L6QL5Q_perm/CLK → u_disp/u_scan/perf0_r[28]/opit_0_inv_AQ_perm/CE；2.017 ns，10级。
- clk_ext: u_disp/u_timing/vertical_r[5]/opit_0_inv_L6QL5Q_perm/CLK → u_disp/u_scan/perf0_r[24]/opit_0_inv_AQ_perm/CE；2.162 ns，9级。

## 复制寄存器

综合VM中103/103位advance寄存器均有PAP_PRESERVE=TRUE；60/60位kernel操作码寄存器也保留。路后功能网表中163位均对应独立物理FF。
逐位Q网络及驱动类型见replication_fanout.tsv。扇出按路后功能网表中连接到Q网络的原语输入引脚数统计，方向来自本机厂商VOP库；不是Device Map阶段的逻辑扇出。物理打包可能重命名网络，因此同时保留RTL名、物理FF名和Q网络名。

| 寄存器 | RTL位数 | 综合/路后保留位数 | 每位Q扇出（bit:输入引脚数） |
|---|---:|---|---|
| u_pix/advance_input_r | 1 | 1/1 | scalar:64 |
| u_pix/advance_point1_r | 7 | 7/7 | [3]:13, [1]:13, [2]:13, [0]:97, [5]:14, [4]:10, [6]:10 |
| u_pix/advance_point2_r | 3 | 3/3 | [2]:9, [1]:9, [0]:160 |
| u_pix/advance_filter1_r | 4 | 4/4 | [1]:165, [2]:1, [3]:58, [0]:10 |
| u_pix/advance_filter2_r | 4 | 4/4 | [2]:1, [1]:184, [3]:59, [0]:9 |
| u_pix/advance_kernel10_r | 21 | 21/21 | [8]:9, [6]:9, [7]:9, [5]:9, [2]:9, [4]:9, [3]:9, [17]:58, [18]:64, [19]:70, [0]:209, [15]:29, [20]:24, [16]:52, [1]:131, [10]:9, [11]:36, [12]:69, [13]:32, [14]:48, [9]:9 |
| u_pix/advance_kernel11_r | 21 | 21/21 | [3]:9, [1]:145, [16]:61, [0]:220, [6]:9, [11]:33, [20]:24, [12]:59, [18]:67, [19]:68, [17]:51, [2]:9, [14]:70, [10]:9, [9]:9, [8]:9, [15]:33, [5]:9, [7]:9, [4]:9, [13]:37 |
| u_pix/advance_kernel20_r | 21 | 21/21 | [4]:9, [10]:9, [3]:9, [19]:66, [8]:9, [9]:9, [17]:61, [18]:64, [2]:9, [16]:56, [15]:33, [0]:218, [20]:24, [1]:149, [14]:72, [13]:36, [6]:9, [7]:9, [5]:9, [11]:40, [12]:73 |
| u_pix/advance_kernel21_r | 21 | 21/21 | [9]:9, [12]:68, [11]:39, [8]:9, [6]:9, [0]:231, [1]:153, [3]:9, [16]:62, [20]:24, [17]:69, [10]:9, [19]:73, [18]:72, [14]:54, [13]:34, [5]:9, [4]:9, [2]:9, [7]:9, [15]:32 |
| u_pix/u_stage1/u_kernel0/op_spatial_r | 3 | 3/3 | [1]:1, [2]:1, [0]:1 |
| u_pix/u_stage1/u_kernel0/op_result_r | 3 | 3/3 | [1]:24, [2]:24, [0]:24 |
| u_pix/u_stage1/u_kernel0/g_color[0].op_color_r | 3 | 3/3 | [2]:19, [0]:19, [1]:19 |
| u_pix/u_stage1/u_kernel0/g_color[1].op_color_r | 3 | 3/3 | [1]:19, [0]:19, [2]:19 |
| u_pix/u_stage1/u_kernel0/g_color[2].op_color_r | 3 | 3/3 | [1]:19, [0]:19, [2]:19 |
| u_pix/u_stage1/u_kernel1/op_spatial_r | 3 | 3/3 | [2]:1, [0]:1, [1]:1 |
| u_pix/u_stage1/u_kernel1/op_result_r | 3 | 3/3 | [1]:24, [2]:24, [0]:24 |
| u_pix/u_stage1/u_kernel1/g_color[0].op_color_r | 3 | 3/3 | [0]:19, [2]:19, [1]:19 |
| u_pix/u_stage1/u_kernel1/g_color[1].op_color_r | 3 | 3/3 | [2]:19, [0]:19, [1]:19 |
| u_pix/u_stage1/u_kernel1/g_color[2].op_color_r | 3 | 3/3 | [1]:19, [0]:19, [2]:19 |
| u_pix/u_stage2/u_kernel0/op_spatial_r | 3 | 3/3 | [0]:1, [1]:1, [2]:1 |
| u_pix/u_stage2/u_kernel0/op_result_r | 3 | 3/3 | [0]:24, [1]:24, [2]:24 |
| u_pix/u_stage2/u_kernel0/g_color[0].op_color_r | 3 | 3/3 | [0]:19, [2]:19, [1]:19 |
| u_pix/u_stage2/u_kernel0/g_color[1].op_color_r | 3 | 3/3 | [0]:19, [1]:19, [2]:19 |
| u_pix/u_stage2/u_kernel0/g_color[2].op_color_r | 3 | 3/3 | [0]:19, [2]:19, [1]:19 |
| u_pix/u_stage2/u_kernel1/op_spatial_r | 3 | 3/3 | [2]:1, [0]:1, [1]:1 |
| u_pix/u_stage2/u_kernel1/op_result_r | 3 | 3/3 | [0]:24, [2]:24, [1]:24 |
| u_pix/u_stage2/u_kernel1/g_color[0].op_color_r | 3 | 3/3 | [1]:19, [0]:19, [2]:19 |
| u_pix/u_stage2/u_kernel1/g_color[1].op_color_r | 3 | 3/3 | [0]:19, [2]:19, [1]:19 |
| u_pix/u_stage2/u_kernel1/g_color[2].op_color_r | 3 | 3/3 | [0]:19, [1]:19, [2]:19 |

u_pix扇出最大的10个网络（路后物理输入引脚口径）：

| 网络 | 扇出 | 驱动类型 | 逻辑驱动单元 |
|---|---:|---|---|
| u_pix/advance_kernel21_r[0] | 231 | V_FFASYN | u_pix/advance_kernel21_r[0]/opit_0_inv/FFAPP0/FF |
| u_pix/advance_kernel11_r[0] | 220 | V_FFASYN | u_pix/advance_kernel11_r[0]/opit_0_inv/FFAPP0/FF |
| u_pix/advance_kernel20_r[0] | 218 | V_FFASYN | u_pix/advance_kernel20_r[0]/opit_0_inv/FFAPP0/FF |
| u_pix/advance_kernel10_r[0] | 209 | V_FFASYN | u_pix/advance_kernel10_r[0]/opit_0_inv/FF0/FF |
| CLMS_267_883/ntCE0 | 196 | V_LUT6CARRY | u_pix/u_stage2/N372_1/gateop_LUT6DL5_perm/FYB/LUT6CARRY |
| CLMS_231_961/ntCE1 | 193 | V_LUT6CARRY | u_pix/u_stage2/read_column_r[8]/opit_0_L6Q_LUT6DQL5_perm/FYC/LUT6CARRY |
| u_pix/advance_filter2_r[1] | 184 | V_FFASYN | u_pix/advance_filter2_r[1]/opit_0_inv/FF0/FF |
| u_pix/advance_filter1_r[1] | 165 | V_FFASYN | u_pix/advance_filter1_r[1]/opit_0_inv/FF0/FF |
| u_pix/advance_point2_r[0] | 160 | V_FFASYN | u_pix/advance_point2_r[0]/opit_0_inv/FFAPP0/FF |
| u_pix/soft_reset_w | 156 | V_FFASYN | u_pix/u_regs/soft_reset_o/opit_0_inv_L6Q_perm/FF3/FF |

syn_preserve原文提示：compile日志有12条Convert attribute name from syn_preserve to PAP_PRESERVE；综合日志本身没有同名提示。具体源文件/行号摘录在replication_check.txt。没有把没有提示等同于属性无效，实际保留数量由网表核对。
Device Map原生高扇出表也保留：例如advance_kernel11_r[0]、advance_kernel21_r[0]映射阶段均为243；PnR后分别220、231。不同阶段和打包口径不能混用。

## 资源

| 模块（PnR逻辑口径） | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| edrv32_fpga_media_top | 18223 | 25227 | 113 | 141 | 46 |
| u_disp | 1420 | 1828 | 0 | 0 | 4 |
| u_eth | 3899 | 4462 | 76 | 0 | 3 |
| u_geo | 3054 | 3306 | 0 | 9 | 16 |
| u_pix | 4947 | 7860 | 0 | 132 | 11 |
| u_reset_ext | 0 | 2 | 0 | 0 | 0 |
| u_reset_mem | 0 | 2 | 0 | 0 | 0 |
| u_vin | 3521 | 4862 | 37 | 0 | 12 |

上一轮：VIN3562、PIX4943/132 APM、DISP1468、GEO3184/9 APM、ETH3858 LUT；总18416 LUT、23199 FF。完整下一级层次、综合前后资源、DRM18K/36K拆分、器件容量和占用率见resource_hier.txt及resource_summary.txt。

## 日志与复现

flow_summary.txt保留Compile/综合/Map/PnR/STA各阶段warning分类、Real/CPU/Process CPU耗时、峰值内存，logs保存全部W/E行及阶段摘录。常量传播Loop本身不能证明RTL组合环。
复制核对另外从已完成PNR数据库导出功能网表，没有重跑综合/Map/PnR或修改RTL/IP/约束。没有生成bitstream。功能网表和原始数据库只保留本地，不入库。
功能网表导出命令（在独立build工作目录的PDS命令行工程中）：

```tcl
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
gen_netlist -input_db_file {G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/place_route/edrv32_fpga_media_top_pnr.adf} -func_sim_only -force_to_run
```

Python复现顺序：src/export_timing.py，导出上述功能网表到build/win/20261029-01-media-r4/flat_netlist，再执行src/check_replication.py和src/collect_reports.py。

## 完整报告在Windows本地的路径

- PDS工程完整报告/日志：G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/各阶段子目录。
- 补导时序：G:/codex_project/EdRV32-Competition-2026/build/win/20261029-01-media-r4/exports/。
- 路后功能网表：G:/codex_project/EdRV32-Competition-2026/build/win/20261029-01-media-r4/flat_netlist/generate_netlist/edrv32_fpga_media_top_sim.v。
