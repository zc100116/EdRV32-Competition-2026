# 20261028-04-media-cpu-probes 结果

| 项 | 内容 |
|---|---|
| 任务卡 commit | f757c4f3b3b303811d2c69ccc8b855f3e6eb599b |
| 结果分支 | win/20261028-04-media-cpu-probes |
| 探针版本 | src/p1、src/p2、src/p3；源自15d21f8 / 2ec4170 / 3615a7e |
| PDS / 器件 | 2022.2-SP6.1 build 138931；PG2L200H-6 FBB676；ADS综合 |
| A工程 | G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/EdRV32-MEDIA.pds |
| B工程 | build/win/20261028-04-media-cpu-probes/cpu/p1、p2、p3、p3_noregion |
| 完成情况 | A布局布线完成；B的P1/P2完成，P3区域检查失败，去区域约束的P3_noregion完成。IP选项PNG未取得，其余提取结果见artifacts |

按用户要求用三个独立后台工程并行运行CPU，复用原EdRV32工程的7个IP。没有修改RTL或IP生成文件。
原始日志、工程和数据库保留在Windows本地；本分支只回传精简日志及报告。

## A 媒体/网络模块

### IP

六个IP模块名和实际端口与包装一致。选项文本在`artifacts/media/ip/`；未操控桌面，选项PNG未取得。
DRM数来自本次PnR层次报告，不是按位数估算。

| IP | 模块名 | 端口与包装一致 | 每实例DRM | 实例数 | 总DRM36K当量 |
|---|---|---|---|---:|---:|
| ip_ram_vin_wfifo | ip_ram_vin_wfifo | 一致 | 4 × DRM36K | 3 | 12 |
| ip_ram_disp_scan | ip_ram_disp_scan | 一致 | 4 × DRM36K | 1 | 4 |
| ip_ram_pix_line | ip_ram_pix_line | 一致 | 2 × DRM36K | 4 | 8 |
| ip_ram_geo_src | ip_ram_geo_src | 一致 | 2 × DRM36K | 8 | 16 |
| ip_ram_eth_buf | ip_ram_eth_buf | 一致 | 1 × DRM36K | 2 | 2 |
| ip_ram_eth_fifo | ip_ram_eth_fifo | 一致 | 1 × DRM18K | 2 | 1 |

六个生成IP合计43 DRM36K当量；整个MEDIA还有PIX内部推导RAM，合计8 DRM18K + 42 DRM36K = 46当量。
GEO不同读写位宽配置已生成并通过综合/PnR；每实例实际使用2个DRM36K。未做IP功能仿真。

### 时序

两个时钟均约束8.000 ns（125 MHz）。

| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |
|---|---:|---:|---:|---:|---|---:|
| clk_mem/slow | -7.667 | -13627.003 | 0.146 | 0.000 | 6356/0 | 63.8284 |
| clk_ext/slow | 2.064 | 0.000 | 0.155 | 0.000 | 0/0 | 168.4636 |
| clk_mem/fast | -1.862 | -217.617 | 0.101 | 0.000 | 314/0 | 101.3993 |
| clk_ext/fast | 4.623 | 0.000 | 0.105 | 0.000 | 0/0 | 296.1208 |

PnR报告确认clk_mem_i=K21、clk_ext_i=D18，各使用一个全局时钟缓冲。
时序报告列出异步组mem_ext_async；setup/hold汇总只有同域路径，没有跨两域路径。未放宽专用时钟布线。
DISP的clk_ext域最差裕量为+2.064 ns；在125 MHz测试约束下满足setup。
这支持该域74.25 MHz目标，但不代表其他域或完整SoC的板级时序已经通过。
clk_mem最差路径位于PIX：行RAM到u_point2乘法器输入，14级，-7.667 ns。

每域最差200条setup、前20条逐级明细、fast角最差20条hold、最多30组明细、DISP clk_ext前20条均已保存。
分组样本来自每域top200，组内路径数表示导出样本数，并非设计所有路径数。
额外保存0<slack<1 ns的200条clk_mem setup路径；clk_ext没有该区间路径，最差为+2.064 ns。

最差路径前10条：clk_mem

| 起点 → 终点 | 裕量(ns) | 级数 |
|---|---:|---:|
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[3] | -7.667 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[0] | -7.619 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[6] | -7.535 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N52/gopapm/X[6] | -7.527 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[1] | -7.515 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[2] | -7.514 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N52/gopapm/X[7] | -7.485 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[7] | -7.436 | 18 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[4] | -7.386 | 14 |
| u_pix/u_stage2/u_line1/u_ip/U_ipm2l_sdpram_ip_ram_pix_line/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_pix/u_point2/N46/gopapm/X[5] | -7.381 | 14 |

最差路径前10条：clk_ext

| 起点 → 终点 | 裕量(ns) | 级数 |
|---|---:|---:|
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_blue/data_ones_r[1]/opit_0_L6Q_LUT6DQL5Q_perm/I0 | 2.064 | 4 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_blue/data_ones_r[3]/opit_0_L6Q_LUT6DQL5Q_perm/I0 | 2.091 | 4 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_blue/data_ones_r[1]/opit_0_L6Q_LUT6DQL5Q_perm/I3 | 2.245 | 4 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_blue/data_ones_r[1]/opit_0_L6Q_LUT6DQL5Q_perm/I1 | 2.253 | 4 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_blue/data_ones_r[3]/opit_0_L6Q_LUT6DQL5Q_perm/I1 | 2.254 | 4 |
| u_disp/u_timing/vertical_r[7]/opit_0_inv_L6QL5Q_perm/CLK → u_disp/u_fifo_ram/u_ip/U_ipm2l_sdpram_ip_ram_disp_scan/ADDR_LOOP[0].DATA_LOOP[3].U_GTP_DRM36K_E1/gopdrm_36k/CEB[0] | 2.311 | 4 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_blue/data_ones_r[3]/opit_0_L6Q_LUT6DQL5Q_perm/I3 | 2.326 | 4 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CE | 2.366 | 10 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_scan/debt_r[27]/opit_0_inv_AQ_perm/CE | 2.484 | 9 |
| u_disp/u_scan/debt_r[31]/opit_0_inv_AQ_perm/CLK → u_disp/u_scan/pixels_r[183]/opit_0_L6Q_perm/I1 | 2.485 | 3 |

### 资源

LUT采用逻辑层次口径；DRM总量采用36K当量。详细器件容量、占用率及18K/36K拆分见resource_summary.txt。

| 阶段 | LUT | FF | DRM18K/36K | APM | 分布式RAM | IO | PLL |
|---|---:|---:|---|---:|---:|---:|---:|
| 综合 | 19105 | 16480 | 8 / 42 | 105 | 113 | 7 | 0（PnR核实） |
| PnR逻辑层次 | 19009 | 16480 | 8 / 42（SNR拆分；PRR46当量） | 105 | 113 | 7 | 0 |

| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| u_disp | 1448 | 1729 | 0 | 0 | 4 |
| u_eth | 3863 | 3826 | 76 | 0 | 3 |
| u_geo | 3238 | 2641 | 0 | 9 | 16 |
| u_pix | 5593 | 1166 | 0 | 96 | 11 |
| u_reset_ext | 0 | 2 | 0 | 0 | 0 |
| u_reset_mem | 0 | 2 | 0 | 0 | 0 |
| u_vin | 3482 | 4205 | 37 | 0 | 12 |
| 顶层自身差额（含激励/观测逻辑） | 1385 | 2909 | 0 | 0 | 0 |

顶层自身资源按总计减去直接子模块计算；单个stim/obs寄存器的独立资源数未取得，不按声明位宽冒充实测资源。
完整下一级子模块资源见resource_hier.txt。
Linux Yosys参考（LUT6/FF，RAM黑盒）：VIN8422/5651、DISP3179/1856、PIX32535/5234、GEO9043/3116、ETH8279/4553。
本次PDS将PIX算术映射到96个APM，GEO使用9个APM，因此不能只按LUT数与Yosys黑盒估算作等价比较。
SoC规格预算：VIN+PIX+DISP10K、GEO8K、ETH5K；本次三者逻辑LUT合计10523，GEO3238、ETH3863。

### 导入脚本修正

按此前用户要求，保留../../EdRV32-Competition-2026的相对根路径计算；include参数改为rtl/include与当前FPGA工程目录组成的Tcl列表，并用compile -force_to_run应用新配置。
已从MEDIA和CPU工程目录展开源码/include/约束路径；没有修改RTL中的include或复制头文件。MEDIA现已完成完整流程。

## B CPU时序探针

### 约束确认

- 外部FDC的syn_preserve/syn_keep在本机PDS报ConstraintEditor-0046：属性无效。
- UCE手册68页规定集成版层次分隔符为`.`，`i:`表示instance；空格分隔试验出现解析警告。
- 最小工程及实际Compile日志都显示：六个valid在读取FDC前合并为两份，仅probe_f1_redirect_valid_r和probe_f1_d_redirect_valid_r保留。
- 最终只对两份存在的FF设置PAP_DONT_TOUCH；手册93页规定它作用于Device Map，不能恢复Compile已合并的FF。本次不宣称六份复制成功。
- P3区域改为先define_global_attribute {PAP_REGION} {core_probe(423,806,600,791)}，再以define_attribute把u_cpu_subsys.u_core关联到core_probe。
- PDS报ConstraintEditor-0027（非法floorplan坐标）及UserConstraintEditor-0058，在综合约束检查阶段停止。clock_utilization.txt的block坐标范围为x=0..238、y=0..249；候选坐标误用了另一种网格尺度，未验证覆盖4个APM。
- 按B6去掉区域约束，保存P3失败日志及原约束，再运行P3_noregion；比较表使用该实测结果。
- 探针FDC仅本地适配，最终全文以artifacts内fdc_used.fdc回传；src/p2、src/p3候选FDC不随结果提交修改。

### 时序

| 版本/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |
|---|---:|---:|---:|---:|---|---:|
| 第四轮RVC=1/slow（任务卡参考） | -1.789 | -4967.383 | — | — | 7611/— | 118.3 |
| p1/slow | -1.078 | -2866.648 | 0.143 | 0.000 | 8196/0 | 129.1156 |
| p1/fast | 1.615 | 0.000 | 0.100 | 0.000 | 0/0 | 197.9414 |
| p2/slow | -0.762 | -319.292 | 0.113 | 0.000 | 1361/0 | 134.6076 |
| p2/fast | 1.792 | 0.000 | 0.100 | 0.000 | 0/0 | 205.1282 |
| p3_noregion/slow | -0.534 | -67.345 | 0.145 | 0.000 | 432/0 | 138.8696 |
| p3_noregion/fast | 2.451 | 0.000 | 0.102 | 0.000 | 0/0 | 237.1917 |

P1→P2的WNS改善0.316 ns，P2→P3_noregion再改善0.228 ns。三版均未满足6.667 ns约束。
全量违例端点导出采用max_path100000、nworst1、slack<0；去重后8196/1361/432个，与PDS汇总逐版一致。
每版另外保存最差200条setup、前20条逐级明细、fast角最差20条hold，以及0<slack<1 ns的200条危险正裕度setup及前20条明细。
三版危险正裕度样本最小均为+0.001 ns。P2/P3为功能不正确的时序探针，不能用于上板。

p1最差路径：u_cpu_subsys/u_icache/addr_r[11]/opit_0/CLK → u_cpu_subsys/u_core/u_frontend/u_ib/entries_r[2][74]/opit_0_L6Q_perm/I3，-1.078 ns，6级。

前10组（去除寄存器位下标及打包后缀，保留generate实例下标；IP内部归并到u_ip）：

| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |
|---|---:|---:|---:|
| u_cpu_subsys/u_icache/addr_r → u_cpu_subsys/u_core/u_frontend/u_ib/entries_r | 485 | -1.078 | 6 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_core/N791_17 | 30 | -1.036 | 8 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_core/N630_15 | 30 | -1.034 | 8 |
| u_cpu_subsys/u_core/e_operand_a_r → u_cpu_subsys/u_core/u_frontend/f1_pc_r | 19 | -1.032 | 11 |
| u_cpu_subsys/u_core/u_frontend/f1_pc_r → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r | 128 | -0.999 | 9 |
| u_cpu_subsys/u_core/e_operand_a_r → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r | 333 | -0.993 | 11 |
| u_cpu_subsys/u_core/u_frontend/f1_pc_r → u_cpu_subsys/u_core/u_frontend/f1_pc_r | 35 | -0.947 | 15 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_dcache/dirty0_r | 502 | -0.847 | 7 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_dcache/dirty1_r | 480 | -0.841 | 7 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_dcache/buffer_addr_r | 17 | -0.840 | 7 |

p2最差路径：u_cpu_subsys/u_dcache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu_subsys/u_dcache/dirty0_r[106]/opit_0_inv_L6Q_perm/I2，-0.762 ns，9级。

前10组（去除寄存器位下标及打包后缀，保留generate实例下标；IP内部归并到u_ip）：

| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |
|---|---:|---:|---:|
| u_cpu_subsys/u_dcache/u_tag1/u_ip → u_cpu_subsys/u_dcache/dirty0_r | 603 | -0.762 | 9 |
| u_cpu_subsys/u_dcache/u_tag1/u_ip → u_cpu_subsys/u_dcache/dirty1_r | 309 | -0.648 | 9 |
| u_cpu_subsys/u_core/u_mul/u_product/u_ip → u_cpu_subsys/u_core/N791_17 | 7 | -0.515 | 5 |
| u_cpu_subsys/u_core/u_mul/u_product/u_ip → u_cpu_subsys/u_core/N469_15 | 6 | -0.429 | 5 |
| u_cpu_subsys/u_core/u_mul/u_product/u_ip → u_cpu_subsys/u_core/N308_15 | 6 | -0.371 | 5 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_core/e_record_r | 129 | -0.321 | 7 |
| u_cpu_subsys/u_core/u_mul/u_product/u_ip → u_cpu_subsys/u_core/N630_15 | 7 | -0.313 | 5 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_core/N630_15 | 15 | -0.296 | 7 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_core/e_imm_r | 15 | -0.286 | 7 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip → u_cpu_subsys/u_core/N308_15 | 14 | -0.285 | 7 |

p3_noregion最差路径：u_cpu_subsys/u_core/u_frontend/u_predictor/history_r[6]/opit_0_inv_srl/CLK → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r[19]/opit_0_L6Q_perm/CE，-0.534 ns，8级。

前10组（去除寄存器位下标及打包后缀，保留generate实例下标；IP内部归并到u_ip）：

| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |
|---|---:|---:|---:|
| u_cpu_subsys/u_core/u_frontend/u_predictor/history_r → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r | 109 | -0.534 | 8 |
| u_cpu_subsys/u_dcache/addr_r → u_cpu_subsys/u_core/w_result_r | 15 | -0.405 | 8 |
| u_cpu_subsys/u_core/u_frontend/u_predictor/history_r → u_cpu_subsys/u_core/u_frontend/f1_pc_r | 20 | -0.354 | 8 |
| u_cpu_subsys/u_dcache/u_tag1/u_ip → u_cpu_subsys/u_dcache/dirty1_r | 132 | -0.314 | 9 |
| u_cpu_subsys/u_dcache/u_tag1/u_ip → u_cpu_subsys/u_dcache/dirty0_r | 58 | -0.281 | 9 |
| u_cpu_subsys/u_core/u_frontend/u_ib/read_ptr_r → u_cpu_subsys/u_core/e_record_r | 16 | -0.214 | 7 |
| u_cpu_subsys/u_core/u_frontend/u_predictor/history_r → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_count_r | 5 | -0.205 | 8 |
| u_cpu_subsys/u_dcache/u_tag1/u_ip → u_cpu_subsys/u_dcache/valid0_r | 54 | -0.146 | 9 |
| u_cpu_subsys/u_core/u_frontend/u_ib/read_ptr_r → u_cpu_subsys/u_core/u_csr/instret_r | 10 | -0.143 | 9 |
| u_cpu_subsys/u_core/u_frontend/u_predictor/history_r → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_ptr_r | 2 | -0.098 | 8 |

### 资源

| 版本 | LUT | FF | DRM36K当量 | APM | 分布式RAM | u_core LUT/FF |
|---|---:|---:|---:|---:|---:|---|
| p1 | 14750 | 8362 | 26 | 4 | 151 | 10140/5412 |
| p2 | 15567 | 8657 | 26 | 4 | 151 | 10237/5703 |
| p3_noregion | 15232 | 8714 | 26 | 4 | 151 | 10244/5771 |

CPU均为4 DRM18K + 24 DRM36K，IO9、PLL0。u_core和下一级模块的LUT/FF全文见各版resource_hier.txt。

## 日志、耗时和产物范围

| 工程 | Compile | 综合 | Device Map | PnR | 最终阶段Error数 |
|---|---|---|---|---|---:|
| p1 | 0h:0m:29s | 0h:1m:27s | 0h:0m:19s | 0h:7m:40s | 0 |
| p2 | 0h:0m:34s | 0h:1m:35s | 0h:0m:21s | 0h:6m:14s | 0 |
| p3_noregion | 0h:0m:30s | 0h:1m:32s | 0h:0m:22s | 0h:5m:9s | 0 |
| media | 0h:0m:18s | 0h:1m:13s | 0h:0m:22s | 0h:5m:54s | 0 |

flow_summary.txt保留各阶段warning分类/条数、Real/CPU/Process CPU时间、峰值内存；logs保留全部W/E行及阶段摘要。
主要warning包括常量传播Loop、位宽截断/扩展、常量寄存器移除、未约束IO。ConstantProbeLoop本身不能据此判为RTL组合环。具体原文及位置均在warnings_detail.txt。
MEDIA内存域在fast角仍有-1.862 ns/314个setup违例；CPU和MEDIA的hold汇总均无违例，但最小裕量约0.100 ns，已保留hold明细。
时序汇总也保留recovery/removal和pulse-width检查，不能只看setup。
P1初始批处理在PDS执行队列前复制尚未产生的报告，出现Flow-0163；实际Compile/PnR/STA均成功，脚本已移除这些提前复制命令，详细导出另起只读STA任务完成。
P3原区域失败日志与前次FDC试验已精简保留；未用成功重跑覆盖失败事实。

### Windows本地完整报告

- MEDIA：G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/{compile,synthesize,device_map,place_route,report_timing}/。
- CPU：G:/codex_project/EdRV32-Competition-2026/build/win/20261028-04-media-cpu-probes/cpu/{p1,p2,p3,p3_noregion}/。
- 补导时序：G:/codex_project/EdRV32-Competition-2026/build/win/20261028-04-media-cpu-probes/exports/。

### 复现命令

```powershell
C:/Python314/python.exe tasks/win/20261028-04-media-cpu-probes/src/export_timing.py
C:/Python314/python.exe tasks/win/20261028-04-media-cpu-probes/src/collect_reports.py
C:/Python314/python.exe tasks/win/20261028-04-media-cpu-probes/src/write_result.py
```

本次只整理报告及此前授权的导入脚本修复，不改RTL，不跑Verilator或功能仿真。
