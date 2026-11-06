# 卡59结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。Fmax按任务卡公式计算。资源取布线后层次表，DRM使用DRM36K等效口径。

CPU v0.17，RTL提交b1e9d08b，clk_sys约束150 MHz。

| 轮次 | 布线参数 | 慢角WNS/TNS(ns) | 违例端点 | WHS慢角/快角(ns) | 估算Fmax(MHz) | LUT/FF/DRM/APM/LUTRAM | 子系统LUT/FF | P&R耗时 |
|---|---|---:|---:|---:|---:|---:|---:|---|
| CPU v0.17 | 默认 pnr | -2.350 / -6509.970 | 7890 | +0.149 / +0.102 | 110.9016 | 17125/10800/27/4/308 | 16866 / 10057 | 0h:12m:25s |

布局布线完成，慢角Setup未达到150 MHz。探针总DRM为27，分布式RAM为308。u_predictor使用777 LUT和308个分布式RAM。

## 分组最差路径

| 组 | 裕量(ns) | 级数 | 逻辑 / 布线(ns) | 起点 → 终点 |
|---|---:|---:|---|---|
| G1 | -0.914 | 7 | 1.407 / 5.768 | u_cpu/u_core/u_frontend/f1_pc_r[5]_1/opit_0_inv/CLK → u_cpu/u_core/u_frontend/f1_pc_r_1_copy[6]_6/opit_0_inv/D |
| G2 | 未取得 | | | 导出范围内无名称匹配 |
| G3 | -1.611 | 11 | 2.044 / 5.821 | u_cpu/u_core/e_operand_a_r[0][24]/opit_0/CLK → u_cpu/u_core/e_operand_a_r[1][21]/opit_0/D |
| G4 | -1.971 | 10 | 3.039 / 4.998 | u_cpu/u_dcache/u_data1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_data/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/CLKB[0] → u_cpu/u_core/e_operand_b_r[0][30]/opit_0/D |
| G5 | 未取得 | | | 导出范围内无名称匹配 |
| G6 | 未取得 | | | 导出范围内无名称匹配 |
| G7 | -1.829 | 11 | 2.345 / 5.755 | u_cpu/u_core/u_frontend/u_ib/entries_r[1][56]/opit_0_L6QL5Q_perm/CLK → u_cpu/u_core/e_operand_b_r[1][7]/opit_0/D |

## 最差路径分类

按clk_sys慢角最差200条归类。

| 起点层次 → 终点层次 | 条数 | 最差裕量(ns) | 逻辑级数 |
|---|---:|---:|---:|
| u_dcache/u_tag0 → u_dcache | 7 | -2.350 | 7–14 |
| u_cpu/u_core → u_dcache | 175 | -2.132 | 13–13 |
| u_dcache/u_data1 → u_cpu/u_core | 2 | -1.971 | 10–10 |
| u_cpu/u_core → u_cpu/u_core | 7 | -1.912 | 13–13 |
| u_dcache → u_cpu/u_core | 7 | -1.857 | 11–11 |
| u_frontend/u_ib → u_cpu/u_core | 1 | -1.829 | 11–11 |
| u_dcache/u_tag0 → u_dcache/u_data0 | 1 | -1.807 | 7–7 |

## IO与流程记录

FDC对主时钟D18使用3.3 V和LVCMOS33。扫描/复位探针未固定板级引脚，PDS完成物理分配，时序分析报告这些端口没有外部延迟。

V017在时序报告完成后执行了Generate Bitstream，生成.sbit并报告SCBV未配置。

后续准备工程时，按目标板核对全部端口的引脚、Bank电压、IO标准及接口时序约束，配置对应板卡的SCBV，最后执行Generate Bitstream验证。

## 路径导出覆盖

- V017的慢角Setup共7890个违例端点，列出5000个。另导出200条0至+0.2 ns之间的Setup路径。

## 原始报告

- V017原始PDS报告和阶段日志位于 G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V017。5000路径报告保存在 G:/codex_project/EdRV32-Competition-2026/build/cards57-60/timing5000-V017/report_timing/edrv32_cpu_l1_timing_probe.rtr。

原始时序报告 timing5000.rtr.gz 约为 7–9 MB，保留任务卡要求的 5000 条路径导出，供复核时序端点、逐级延迟和扇出。
