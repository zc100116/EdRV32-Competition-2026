# 卡 63 结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。资源取布线后层次表，DRM 按 DRM36K 等效计。 RTL 提交 `b5be940c`，clk_npu 200 MHz，clk_mem 125 MHz。

| 布局布线参数 | clk_npu 慢角 WNS / TNS (ns) | 违例端点数 | WHS 慢角 / 快角 (ns) | 估算 Fmax (MHz) | clk_mem 慢角 WNS (ns) | LUT / FF / DRM / APM / 分布式 RAM |
|---|---:|---:|---:|---:|---:|---:|
| 默认 P&R | -0.027 / -0.050 | 2 | +0.103 / +0.100 | 198.9258 | +3.647 | 17069 / 40025 / 123 / 266 / 1012 |

布局布线完成，用时 0h:17m:29s。clk_npu 尚未达到 200 MHz 目标。相对卡 61，慢角 WNS 改善 0.308 ns，违例端点从 72 减至 2，估算 Fmax 从 187.4414 MHz 提升到 198.9258 MHz。

本轮违例中，卡 61 的逐通道 MAC `valid_r` 到 `u_conv/model_*` 路径特征匹配 0 条，以 MAC 控制链或 `busy_r` 为起点的违例有 0 条。

## 剩余 setup 违例

- -0.027 ns，0 级，逻辑 / 布线 0.194 / 4.474 ns。`u_npu/u_conv/u_datapath/u_weight_store/g_bank[0].wr_addr_r[5]/opit_0/CLK` → `u_npu/u_conv/u_datapath/u_weight_store/g_bank[6].g_segment[2].u_ram/u_ip/U_ipm2l_sdpram_ip_ram_npu_weight/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/ADA0[10]`。
- -0.023 ns，0 级，逻辑 / 布线 0.194 / 4.505 ns。`u_npu/u_conv/u_datapath/u_weight_store/g_bank[0].wr_addr_r[5]/opit_0/CLK` → `u_npu/u_conv/u_datapath/u_weight_store/g_bank[6].g_segment[1].u_ram/u_ip/U_ipm2l_sdpram_ip_ram_npu_weight/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/ADA0[10]`。

## 最差路径分类

按 clk_npu 慢角最差 200 条 setup 路径归类。扇出列取各类数据通路上报告的最大网络扇出。

| 起点模块 → 终点模块 | 条数 | 最差 slack (ns) | 级数范围 | 最大数据网络扇出 |
|---|---:|---:|---:|---:|
| u_conv/u_datapath/u_weight_store → u_conv/u_datapath/u_weight_store | 19 | -0.027 | 0–1 | 96 |
| u_conv/u_datapath/u_mac_array → u_conv/u_datapath/u_mac_array | 35 | +0.013 | 0–0 | 20 |
| u_conv → u_conv/u_datapath/u_weight_store | 49 | +0.025 | 0–1 | 256 |
| u_conv/u_datapath/u_weight_store → u_conv/u_datapath/u_window | 55 | +0.059 | 0–0 | 256 |
| u_conv/u_datapath/u_window → u_conv/u_datapath/u_window | 21 | +0.085 | 1–1 | 128 |
| u_conv → u_conv | 17 | +0.114 | 6–7 | 74 |
| u_conv/u_datapath/u_accum → u_conv/u_datapath/u_accum | 2 | +0.117 | 0–0 | 32 |
| u_npu → u_conv | 2 | +0.194 | 2–2 | 262 |

## busy_r 和 ctrl_valid_r 保留情况

ADS 在 `edrv32_npu_mac_array` 中保留 1 个 `busy_r` 实例和 `ctrl_valid_r` 的 11 位（位号 0–10），均为独立的 `GTP_DFF_C`，带 `PAP_PRESERVE="TRUE"`。同模块另有 12 个以 `g_channel[0].valid_r` 命名的 DFF 声明。实例和连接见 `artifacts/R4/preserve_registers.txt`。

## 导出覆盖和约束

主时钟 D18 使用 3.3 V LVCMOS33。PDS 报告扫描和复位端口缺少外部延迟，本轮按独立探针约束运行。GUI 流程在时序报告完成后结束。

全局导出覆盖全部 2 个慢角 setup 违例端点。独立导出得到 154 条 clk_npu 慢角临界正裕量路径，PDS 筛选范围为 0 到 +0.2 ns。

## 原始报告在 Windows 本地的路径

- `timing5000.rtr.gz` 压缩后 6.5 MiB，保留任务卡要求的逐级延迟、扇出和时序端点原文。
- PDS 工程和原始阶段报告位于 `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-NPU-FMAX`。
- 5000 路径报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards63-64/63-timing5000/report_timing/edrv32_npu_timing_probe.rtr`。
- 临界正裕量报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards63-64/63-near/report_timing/edrv32_npu_timing_probe.rtr`。
- 压缩原文及可读明细见 `artifacts/R4/`。

## 未取得的项和原因

临界正裕量导出的上限为 200 条，PDS 在 0 到 +0.2 ns 的指定窗口内返回 154 条，已全部列出。
