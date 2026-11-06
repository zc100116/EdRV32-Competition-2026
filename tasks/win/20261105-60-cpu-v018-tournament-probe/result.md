# 卡60结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。Fmax按任务卡公式计算。资源取布线后层次表，DRM使用DRM36K等效口径。

CPU v0.18 tournament，RTL提交1281d669，clk_sys约束150 MHz。

| 轮次 | 布线参数 | 慢角WNS/TNS(ns) | 违例端点 | WHS慢角/快角(ns) | 估算Fmax(MHz) | LUT/FF/DRM/APM/LUTRAM | 子系统LUT/FF | P&R耗时 |
|---|---|---:|---:|---:|---:|---:|---:|---|
| CPU v0.18 tournament | 默认 pnr | -2.505 / -8468.884 | 10115 | +0.148 / +0.101 | 109.0275 | 17552/10998/27/4/680 | 17296 / 10255 | 0h:24m:1s |

布局布线完成，慢角Setup未达到150 MHz。探针总DRM为27，分布式RAM为680。u_predictor使用1214 LUT和680个分布式RAM。相对卡59，估算Fmax为98.31%，达到98%对比目标。u_predictor增加437 LUT和372个分布式RAM。

## 分组最差路径

| 组 | 裕量(ns) | 级数 | 逻辑 / 布线(ns) | 起点 → 终点 |
|---|---:|---:|---|---|
| G1 | 未取得 | | | 导出范围内无名称匹配 |
| G2 | -2.505 | 11 | 3.965 / 4.803 | u_cpu/u_icache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu/u_core/u_frontend/f1_pc_r[29]_1/opit_0_inv/D |
| G3 | -0.854 | 10 | 1.859 / 5.244 | u_cpu/u_core/e_operand_b_r[1][0]/opit_0/CLK → u_cpu/u_core/e_operand_a_r[0][3]/opit_0/D |
| G4 | -2.157 | 9 | 2.961 / 5.254 | u_cpu/u_dcache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu/u_core/committed_ras_data_r[23]/opit_0_L6Q_perm/CE |
| G5 | -0.811 | 5 | 0.988 / 5.970 | u_cpu/u_core/e_redirect_r/opit_0_inv_L6Q_LUT6DL5Q_perm/CLK → u_cpu/u_core/u_frontend/u_predictor/ras_data_r[25]/opit_0_L6Q_perm/I4 |
| G6 | 未取得 | | | 导出范围内无名称匹配 |
| G7 | -2.102 | 18 | 3.569 / 4.823 | u_cpu/u_core/u_frontend/u_ib/entries_r[0][51]/opit_0_L6QL5Q_perm/CLK → u_cpu/u_dcache/early_valid_r/opit_0_inv_L6Q_perm/I4 |
| G8 | 未取得 | | | 导出范围内无名称匹配 |

## 最差路径分类

按clk_sys慢角最差200条归类。

| 起点层次 → 终点层次 | 条数 | 最差裕量(ns) | 逻辑级数 |
|---|---:|---:|---:|
| u_icache/u_tag0 → u_frontend | 59 | -2.505 | 9–14 |
| u_frontend → u_frontend/u_predictor | 50 | -2.318 | 8–8 |
| u_dcache/u_tag1 → u_cpu/u_core | 78 | -2.157 | 9–9 |
| u_frontend/u_ib → u_dcache | 4 | -2.102 | 17–19 |
| u_frontend/u_ib → u_cpu/u_core | 9 | -2.090 | 11–13 |

## IO与流程记录

FDC对主时钟D18使用3.3 V和LVCMOS33。扫描/复位探针未固定板级引脚，PDS完成物理分配，时序分析报告这些端口没有外部延迟。

V018在时序报告完成后执行了Generate Bitstream，生成.sbit并报告SCBV未配置。

后续准备工程时，按目标板核对全部端口的引脚、Bank电压、IO标准及接口时序约束，配置对应板卡的SCBV，最后执行Generate Bitstream验证。

## 路径导出覆盖

- V018的慢角Setup共10115个违例端点，列出5000个。另导出200条0至+0.2 ns之间的Setup路径。

## 原始报告

- V018原始PDS报告和阶段日志位于 G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V018。5000路径报告保存在 G:/codex_project/EdRV32-Competition-2026/build/cards57-60/timing5000-V018/report_timing/edrv32_cpu_l1_timing_probe.rtr。

原始时序报告 timing5000.rtr.gz 约为 7–9 MB，保留任务卡要求的 5000 条路径导出，供复核时序端点、逐级延迟和扇出。
