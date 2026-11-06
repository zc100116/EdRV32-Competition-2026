# 卡57结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。Fmax按任务卡公式计算。资源取布线后层次表，DRM使用DRM36K等效口径。

R1使用53d4d36b，含PDS兼容性修复d04321f7。R2使用正式版RTL e54e471e。两轮clk_npu为200 MHz，clk_mem为125 MHz。

| 轮次 | 布线参数 | 慢角WNS/TNS(ns) | 违例端点 | WHS慢角/快角(ns) | 估算Fmax(MHz) | LUT/FF/DRM/APM/LUTRAM | 子系统LUT/FF | P&R耗时 |
|---|---|---:|---:|---:|---:|---:|---:|---|
| R1优化版 | 默认 pnr | -0.143 / -1.861 | 39 | +0.141 / +0.100 | 194.4390 | 17432/40579/123/266/1012 | 17226 / 39814 | 0h:15m:56s |
| R2正式版 | 默认 pnr | -0.976 / -300.712 | 1092 | +0.082 / +0.064 | 167.3360 | 16605/31805/123/266/1012 | 16395 / 31040 | 0h:39m:54s |

R1慢角WNS比R2改善0.833 ns，clk_npu估算Fmax提高16.20%。两轮clk_npu慢角Setup仍有违例，均未触发WNS低于−1.0 ns的补跑条件。clk_mem两轮均通过慢角Setup，快慢角各时钟域详见timing_summary.txt。

## 最差路径分类

按各轮clk_npu慢角最差200条归类。

### R1

| 起点层次 → 终点层次 | 条数 | 最差裕量(ns) | 逻辑级数 |
|---|---:|---:|---:|
| u_conv/u_datapath/u_accum → u_conv | 126 | -0.143 | 5–9 |
| u_conv/u_datapath/u_mac_array → u_conv/u_datapath/u_mac_array | 21 | 0.016 | 0–0 |
| u_conv → u_conv/u_datapath/u_weight_store | 33 | 0.046 | 0–1 |
| u_conv/u_datapath/u_weight_store → u_conv/u_datapath/u_window | 7 | 0.119 | 0–0 |
| u_conv/u_datapath/u_window → u_conv/u_datapath/u_weight_store | 1 | 0.128 | 0–0 |
| u_conv → u_regs | 1 | 0.145 | 7–7 |
| u_conv/u_datapath/u_weight_store → u_conv/u_datapath/u_weight_store | 2 | 0.152 | 0–0 |
| u_conv/u_datapath/u_window → u_conv/u_datapath/u_mac_array | 1 | 0.154 | 1–1 |
| u_conv/u_datapath/u_input_unpack → u_npu/cur_desc_r[25] | 1 | 0.167 | 4–4 |
| u_conv → u_conv | 6 | 0.170 | 4–7 |

### R2

| 起点层次 → 终点层次 | 条数 | 最差裕量(ns) | 逻辑级数 |
|---|---:|---:|---:|
| u_conv → u_conv | 94 | -0.976 | 10–10 |
| u_regs → u_conv/u_datapath/u_quant_param_store | 105 | -0.704 | 3–3 |
| u_nonconv → u_nonconv/u_plane_scratch | 1 | -0.472 | 7–7 |

## R1复制寄存器

综合网表保留了32个带PAP_PRESERVE的局部rd_en_r寄存器声明，以及64个通道/像素本地r4_valid_r寄存器声明。首次编译的Verilog-4123在修订后已消除。

## IO与流程记录

FDC对主时钟D18使用3.3 V和LVCMOS33。扫描/复位探针未固定板级引脚，PDS完成物理分配，时序分析报告这些端口没有外部延迟。

clk_mem_i由PDS分配物理引脚，8.000 ns时钟约束生效。

NPU-FMAX在时序报告完成后执行了Generate Bitstream，生成.sbit并报告SCBV未配置。

NPU-REL在时序报告完成后执行了Generate Bitstream，生成.sbit并报告SCBV未配置。

后续准备工程时，按目标板核对全部端口的引脚、Bank电压、IO标准及接口时序约束，配置对应板卡的SCBV，最后执行Generate Bitstream验证。

## 路径导出覆盖

- NPU-FMAX的慢角Setup共39个违例端点，列出39个。另导出197条0至+0.2 ns之间的Setup路径。
- NPU-REL的慢角Setup共1092个违例端点，列出1092个。另导出200条0至+0.2 ns之间的Setup路径。

## 原始报告

- NPU-FMAX原始PDS报告和阶段日志位于 G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-NPU-FMAX。5000路径报告保存在 G:/codex_project/EdRV32-Competition-2026/build/cards57-60/timing5000-NPU-FMAX/report_timing/edrv32_npu_timing_probe.rtr。
- NPU-REL原始PDS报告和阶段日志位于 G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-NPU-REL。5000路径报告保存在 G:/codex_project/EdRV32-Competition-2026/build/cards57-60/timing5000-NPU-REL/report_timing/edrv32_npu_timing_probe.rtr。

原始时序报告 timing5000.rtr.gz 约为 7–9 MB，保留任务卡要求的 5000 条路径导出，供复核时序端点、逐级延迟和扇出。
