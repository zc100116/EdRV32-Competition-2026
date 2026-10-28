# 20261028-05-media-r2 结果

| 项 | 内容 |
|---|---|
| 任务卡执行commit | 8b3d5df60843d90eaa881e386caecf48c4a8d03c |
| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |
| 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/EdRV32-MEDIA.pds |
| 完成情况 | 布局布线完成，要求产物已收集；125 MHz内存域仍有setup违例 |

## 时序

| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |
|---|---:|---:|---:|---:|---|---:|
| clk_mem/slow | -1.270 | -250.561 | 0.136 | 0.000 | 542/0 | 107.8749 |
| clk_ext/slow | 1.475 | 0.000 | 0.153 | 0.000 | 0/0 | 153.2567 |
| clk_mem/fast | 2.486 | 0.000 | 0.100 | 0.000 | 0/0 | 181.3565 |
| clk_ext/fast | 4.025 | 0.000 | 0.101 | 0.000 | 0/0 | 251.5723 |

Fmax按1000/(8.000−WNS)计算。上一轮clk_mem slow为-7.667 ns、63.8284 MHz、6356个违例端点；本轮WNS改善6.397 ns，剩余542个端点。
clk_ext从+2.064 ns变为+1.475 ns，仍满足本次8.000 ns setup约束。
PnR报告IO表确认clk_mem_i=K21、clk_ext_i=D18，各经一个全局时钟缓冲；异步组mem_ext_async生效，setup/hold汇总仅同域路径。
未增加PAP_CLOCK_DEDICATED_ROUTE FALSE。

clk_mem违例端点按模块：

| 终点模块 | 端点数 | 最差裕量(ns) |
|---|---:|---:|
| u_vin | 172 | -0.348 |
| u_pix | 0 | 无违例 |
| u_geo | 174 | -0.995 |
| u_disp | 0 | 无违例 |
| u_eth | 196 | -1.270 |
| top | 0 | 无违例 |

PDS clk_mem slow setup failing endpoints=542; exported unique endpoints=542; coverage=complete.

本次全量端点表显示：PIX、DISP和顶层自身无clk_mem slow setup违例；剩余违例在ETH、GEO、VIN。

全部违例按每端点最差一条去重；端点是PDS原生时序端点，可能为打包单元输入/CE/APM/DRM引脚。模块统计按终点归属，跨模块起点保留在TSV。

寄存器对分组前15组（全表见endpoint_groups.txt）：

| 起点寄存器 → 终点寄存器 | 端点数 | 最差裕量(ns) | 最差路径级数 |
|---|---:|---:|---:|
| u_eth/u_rx/header_r → u_eth/arp_ip_r | 32 | -1.270 | 20 |
| u_eth/u_rx/header_r → u_eth/arp_mac_r | 48 | -1.203 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_write/metadata_r | 55 | -1.165 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx/start_r | 19 | -1.135 | 22 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/count_r | 4 | -1.101 | 21 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/write_ptr_r | 1 | -1.065 | 20 |
| u_geo/desc_r → u_geo/u_regs/perf_r | 62 | -0.995 | 22 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_63/ram32x2d | 1 | -0.854 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_60/ram32x2d | 1 | -0.835 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_62/ram32x2d | 1 | -0.835 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_61/ram32x2d | 1 | -0.830 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_64/ram32x2d | 1 | -0.830 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_58/ram32x2d | 1 | -0.813 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_59/ram32x2d | 1 | -0.813 | 20 |
| u_eth/u_rx/header_r → u_eth/u_rx_packets/memory_r_56/ram32x2d | 1 | -0.812 | 20 |

### 违例及危险路径

- clk_mem: u_eth/u_rx/header_r[144]/opit_0/CLK → u_eth/arp_ip_r[19]/opit_0/CE；-1.270 ns，20级。
- clk_mem: u_eth/u_rx/header_r[144]/opit_0/CLK → u_eth/arp_ip_r[20]/opit_0/CE；-1.203 ns，20级。
- clk_mem: u_eth/u_rx/header_r[144]/opit_0/CLK → u_eth/arp_ip_r[21]/opit_0/CE；-1.203 ns，20级。
- clk_ext: u_eth/u_tx_front/state_r_reg[2]/opit_0_inv_L6Q_perm/CLK → u_eth/u_tx_fifo/u_fifo/head_data_r[7]/opit_0/CE；1.475 ns，1级。
- clk_ext: u_disp/u_fifo_ram/u_ip/U_ipm2l_sdpram_ip_ram_disp_scan/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_disp/u_red/data_ones_r[1]/opit_0_L6Q_LUT6DQL5Q_perm/I4；1.506 ns，1级。
- clk_ext: u_disp/u_fifo_ram/u_ip/U_ipm2l_sdpram_ip_ram_disp_scan/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_disp/u_red/data_ones_r[3]/opit_0_L6Q_LUT6DQL5Q_perm/I2；1.557 ns，1级。

每域最差200条slow setup及前20条逐级明细、每域fast角最差20条hold均已保存。
另外导出0<slack<1 ns的危险正裕度setup（每域上限200条）及前20条逐级明细；具体数量和最小裕量：

- clk_mem: 200条，0.001 ns。
- clk_ext: 0条，该范围无路径。

## 资源

PnR逻辑层次口径；DRM按36K当量。物理CLMA/CLMS LUT占用不冒充逻辑LUT总数。

| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| edrv32_fpga_media_top | 18506 | 22422 | 113 | 141 | 46 |
| u_disp | 1452 | 1729 | 0 | 0 | 4 |
| u_eth | 3841 | 3826 | 76 | 0 | 3 |
| u_geo | 3357 | 2641 | 0 | 9 | 16 |
| u_pix | 4935 | 7107 | 0 | 132 | 11 |
| u_reset_ext | 0 | 2 | 0 | 0 | 0 |
| u_reset_mem | 0 | 2 | 0 | 0 | 0 |
| u_vin | 3532 | 4205 | 37 | 0 | 12 |

各模块下一级和完整层次见resource_hier.txt；SNR原语数、综合后/路后资源、器件容量和利用率见resource_summary.txt。
上一轮：u_vin3482、u_pix5593 LUT/96 APM、u_disp1448、u_geo3238、u_eth3863 LUT；整个工程19009 LUT/16480 FF/105 APM。
PIX本轮4935 LUT/7107 FF/132 APM，上一轮5593 LUT/1166 FF/96 APM；流水化后FF增加5941、APM增加36。
本轮综合Cell Usage为8 DRM18K + 42 DRM36K，46 DRM36K当量；IO7、PLL0（PnR）。

## 日志与阶段耗时

```text
STAGE compile: Errors=0 Warnings=937
Verilog-2008	316
ConstantProbeLoop	238
Verilog-2038	167
Sdm-2000	96
Verilog-2020	72
Verilog-2023	26
Verilog-2039	14
Public-4030	5
Sdm-2014	2
Uncoded warning	1
Action compile: Real time elapsed is 0h:0m:21s
Action compile: CPU time elapsed is 0h:0m:2s
Action compile: Process CPU time elapsed is 0h:0m:2s
Current time: Wed Oct 28 22:16:40 2026
Action compile: Peak memory pool usage is 233 MB

STAGE synthesize: Errors=0 Warnings=2893
Public-4008	1753
Uncoded warning	1132
Timing-4087	3
Uncoded fanout warning	2
Timing-4086	2
Adm-4019	1
Action synthesize: Real time elapsed is 0h:1m:19s
Action synthesize: CPU time elapsed is 0h:0m:11s
Action synthesize: Process CPU time elapsed is 0h:0m:12s
Current time: Wed Oct 28 22:18:06 2026
Action synthesize: Peak memory pool usage is 1,231 MB

STAGE device_map: Errors=0 Warnings=1
Public-4010	1
Action dev_map: Real time elapsed is 0h:0m:24s
Action dev_map: CPU time elapsed is 0h:0m:1s
Action dev_map: Process CPU time elapsed is 0h:0m:2s
Current time: Wed Oct 28 22:18:29 2026
Action dev_map: Peak memory pool usage is 879 MB

STAGE place_route: Errors=0 Warnings=0
Action pnr: Real time elapsed is 0h:5m:45s
Action pnr: CPU time elapsed is 0h:0m:39s
Action pnr: Process CPU time elapsed is 0h:0m:54s
Current time: Wed Oct 28 22:24:13 2026
Action pnr: Peak memory pool usage is 3,734 MB

STAGE report_timing: Errors=0 Warnings=5
Timing-4087	3
Timing-4086	2
Action report_timing: Real time elapsed is 0h:0m:37s
Action report_timing: CPU time elapsed is 0h:0m:1s
Action report_timing: Process CPU time elapsed is 0h:0m:1s
Current time: Wed Oct 28 22:24:51 2026
Action report_timing: Peak memory pool usage is 2,553 MB

```

各阶段W/E原文及耗时/峰值内存摘录位于logs/。Loop was found during constant probe是常量传播诊断，单独此条不能证明RTL组合环。
未约束IO警告保持原文；测量顶层的时序结论不等于完整板级IO时序已通过。
仅补导STA并整理报告，没有重跑Compile/综合/PnR，没有修改RTL、IP、导入脚本或约束，不生成bitstream。

## 完整报告在Windows本地的路径

- 完整日志和报告：G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/{compile,synthesize,device_map,place_route,report_timing}/。
- 补导时序及命令：G:/codex_project/EdRV32-Competition-2026/build/win/20261028-05-media-r2/exports/。

## 复现整理命令

```powershell
C:/Python314/python.exe tasks/win/20261028-05-media-r2/src/collect_reports.py
```

脚本复用上一轮已提交的报告提取函数；不上传PDS工程、IP目录、中间数据库、bitstream或完整原始日志。
