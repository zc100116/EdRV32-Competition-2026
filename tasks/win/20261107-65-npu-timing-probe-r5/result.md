# 卡 65 结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。资源取布线后层次表，DRM 按 DRM36K 等效计。 任务提交 `32a3efd2`，实跑提交 `953268f0`，clk_npu 200 MHz，clk_mem 125 MHz。

| 布局布线参数 | clk_npu 慢角 WNS / TNS (ns) | 违例端点数 | WHS 慢角 / 快角 (ns) | 估算 Fmax (MHz) | clk_mem 慢角 WNS (ns) | LUT / FF / DRM / APM / 分布式 RAM |
|---|---:|---:|---:|---:|---:|---:|
| 默认 P&R | +0.053 / 0.000 | 0 | +0.108 / +0.100 | 202.1427 | +3.245 | 17198 / 46144 / 123 / 266 / 1012 |

## 与卡 63 对比

布局布线完成，用时 0h:22m:31s。200 MHz 约束通过，慢角 WNS 距 +0.300 ns 的余量目标差 0.247 ns。相对卡 63，WNS 改善 0.080 ns，违例端点从 2 降为 0，估算 Fmax 从 198.9258 MHz 提升到 202.1427 MHz。LUT / FF / DRM / APM / LUTRAM 的变化为 +129 / +6119 / +0 / +0 / +0。

最差路径从 `u_npu/u_conv/u_datapath/u_window/a3_in_c4_r/opit_0/CLK` 到 `u_npu/u_conv/u_datapath/u_window/a4_activation_r[114]/opit_0_L6Q_perm/RS`，1 级，逻辑 / 布线 0.545 / 3.814 ns。

## 最差路径分类

按慢角 clk_npu 的全部违例和 0 至 +0.3 ns 窗口内最差 151 条路径分类，表中列出最差 slack 最低的 10 类。扇出列取各类数据通路上报告的最大网络扇出。

| 起点模块 → 终点模块 | 条数 | 最差 slack (ns) | 级数范围 | 最大数据网络扇出 |
|---|---:|---:|---:|---:|
| u_conv/u_datapath/u_window → u_conv/u_datapath/u_window | 28 | +0.053 | 0–1 | 129 |
| u_conv/u_datapath/u_line_cache → u_conv/u_datapath/u_window | 6 | +0.061 | 1–1 | 2 |
| u_conv/u_datapath/u_window → u_conv/u_datapath/u_mac_array | 23 | +0.086 | 0–1 | 256 |
| u_conv/u_datapath/u_mac_array → u_conv/u_datapath/u_mac_array | 53 | +0.087 | 0–0 | 5 |
| u_conv/u_datapath/u_weight_store → u_conv/u_datapath/u_weight_store | 9 | +0.118 | 0–0 | 32 |
| u_conv/u_datapath/u_weight_store → u_conv/u_datapath/u_window | 5 | +0.118 | 0–0 | 1 |
| u_conv → u_conv/u_datapath/u_weight_store | 3 | +0.126 | 0–0 | 24 |
| u_conv/u_datapath/u_mac_array → u_conv/u_datapath/u_accum | 1 | +0.138 | 0–0 | 63 |
| u_conv/u_datapath/u_writeback → u_conv/u_datapath/u_window | 5 | +0.146 | 5–7 | 195 |
| u_nonconv → u_nonconv/u_plane_scratch | 2 | +0.201 | 5–6 | 6 |

## 副本保留情况

- `u_weight_store`：24 组 bank/segment，`wr_addr_r` 216 个 DFF，`wr_bank_addr_r` 264 个 DFF，`wr_valid_r` 24 个 DFF。
- `u_mac_array`：链输入 `activation_r` 256 组，4096 个 DFF。
- `u_window`：`a3_pixel_r` 8 个独立 DFF，对应每个像素四个选择副本。

上述实例均带 `PAP_PRESERVE="TRUE"`。按位实例名和综合网表摘录见 `artifacts/R5/preserve_registers.txt`。

## 布线拥塞

| 轮次 | 首条通用布线迭代（编号，未布线，overused） | 通用网络收敛迭代 | 全部网络收敛迭代 | 成功 / 总网络 | 路由耗时 (s) |
|---|---|---:|---:|---:|---:|
| 63 | 3, 42475, 240408 | 244 | 247 | 50245 / 50245 | 766.26 |
| 65 | 3, 47819, 256636 | 473 | 474 | 56542 / 56542 | 1053.59 |

卡 65 通用网络在第 473 轮达到 0 条未布线、0 项 overused。统计取 PDS 路由迭代日志，见 `artifacts/R5/routing_congestion.txt`。

## 流程记录

首轮在 `32a3efd2` 遇到 Verilog-4123 / Verilog-4039。在 `953268f0` 完成编译、综合、Map 和布局布线。报错摘录和本轮各阶段统计见 `artifacts/R5/flow_summary.txt`。

主时钟 D18 使用 3.3 V LVCMOS33。PDS 报告扫描和复位端口缺少外部延迟，本轮按独立探针约束运行。本轮未生成 bitstream。

## 原始报告在 Windows 本地的路径

- `timing5000.rtr.gz` 压缩后 6.9 MiB，保留任务卡要求的逐级延迟、扇出和时序端点原文。
- PDS 工程和原始阶段报告位于 `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-NPU-FMAX`。
- 5000 路径报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards65-66/65-timing5000/report_timing/edrv32_npu_timing_probe.rtr`。
- 临界正裕量报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards65-66/65-near/report_timing/edrv32_npu_timing_probe.rtr`。
- 压缩原文及可读明细见 `artifacts/R5/`。

## 未取得的项和原因

PDS 在 0 至 +0.3 ns 的窗口内返回 151 条慢角 setup 路径，已全部列出。原始报告还包含 2 条异步时序路径。

布线拥塞汇总使用 PDS 迭代日志。现有 P&R 产物中未取得单独的空间拥塞图。
