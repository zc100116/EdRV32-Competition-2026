# 卡 61 结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。资源取布线后层次表，DRM 按 DRM36K 等效计。 RTL 提交 `573ace10`，clk_npu 200 MHz，clk_mem 125 MHz。

| 布局布线参数 | clk_npu 慢角 WNS / TNS (ns) | 违例端点数 | WHS 慢角 / 快角 (ns) | 估算 Fmax (MHz) | clk_mem 慢角 WNS (ns) | LUT / FF / DRM / APM / 分布式 RAM |
|---|---:|---:|---:|---:|---:|---:|
| 默认 P&R | -0.335 / -6.556 | 72 | +0.100 / +0.070 | 187.4414 | +2.567 | 17354 / 40526 / 123 / 266 / 1012 |

布局布线完成，用时 0h:29m:31s。clk_npu 慢角 WNS 低于 0 ns，200 MHz 目标未达到。相对卡 57 R1，WNS 从 −0.143 ns 降至 -0.335 ns，违例端点从 39 增至 72，估算 Fmax 从 194.4390 MHz 降至 187.4414 MHz。

本轮 72 条违例中，卡 57 R1 的逐像素 `accum_valid_r` 到 `u_conv/model_*` 路径特征匹配 0 条，以 `u_accum/ctrl_*` 为起点的违例有 0 条。本轮最差路径从 `u_npu/u_conv/u_datapath/u_mac_array/g_channel[7].valid_r[9]/opit_0_inv_L6QL5Q_perm/CLK` 到 `u_npu/u_conv/model_lut_addr_r[31]/opit_0_AQ_perm/CE`，逻辑和布线分别耗时 1.430 / 3.240 ns。

## 最差路径分类

按 clk_npu 慢角最差 200 条 setup 路径归类。扇出列取各类数据通路上报告的最大网络扇出。

| 起点模块 → 终点模块 | 条数 | 最差 slack (ns) | 级数范围 | 最大数据网络扇出 |
|---|---:|---:|---:|---:|
| u_conv/u_datapath/u_mac_array → u_conv | 46 | -0.335 | 4–8 | 121 |
| u_conv/u_datapath/u_mac_array → u_npu | 41 | -0.295 | 4–5 | 44 |
| u_conv/u_datapath/u_mac_array → u_conv/u_datapath/u_mac_array | 60 | -0.086 | 0–0 | 20 |
| u_conv → u_conv | 9 | -0.058 | 7–7 | 74 |
| u_conv/u_datapath/u_line_cache → u_conv/u_datapath/u_window | 2 | -0.053 | 1–1 | 2 |
| u_npu → u_conv/u_datapath/u_quant_param_store | 33 | -0.019 | 2–2 | 185 |
| u_conv/u_datapath/u_weight_store → u_conv/u_datapath/u_weight_store | 3 | +0.027 | 0–0 | 96 |
| u_conv/u_datapath/u_window → u_conv/u_datapath/u_mac_array | 4 | +0.038 | 0–0 | 1 |
| u_nonconv/u_plane_scratch → u_nonconv | 2 | +0.070 | 0–0 | 1 |

## 控制有效位寄存器

ADS 综合网表中，`ctrl_r4_valid_r`、`ctrl_r5_valid_r`、`ctrl_accum_valid_r` 均以独立的 `GTP_DFF_C` 实例保留，三个实例均带 `PAP_PRESERVE="TRUE"`。网表中另有逐像素 `r4_valid_r` 64 个、`r5_valid_r` 64 个、`accum_valid_r` 0 个 DFF 声明。实例证据见 `artifacts/R3/preserve_registers.txt`。

## 导出覆盖和约束

主时钟 D18 使用 3.3 V LVCMOS33。PDS 报告扫描和复位端口缺少外部延迟，本轮按独立探针约束运行。GUI 流程在时序报告完成后结束。

全局导出覆盖全部 72 个慢角 setup 违例端点。独立导出得到 200 条 clk_npu 慢角临界正裕量路径，PDS 筛选范围为 0 到 +0.2 ns。

## 原始报告在 Windows 本地的路径

- `timing5000.rtr.gz` 压缩后 6.8 MiB，保留任务卡要求的逐级延迟、扇出和时序端点原文。
- PDS 工程和原始阶段报告位于 `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-NPU-FMAX`。
- 5000 路径报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards61-62/61-timing5000/report_timing/edrv32_npu_timing_probe.rtr`。
- 临界正裕量报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards61-62/61-near/report_timing/edrv32_npu_timing_probe.rtr`。
- 压缩原文及可读明细见 `artifacts/R3/`。

## 未取得的项和原因

无。
