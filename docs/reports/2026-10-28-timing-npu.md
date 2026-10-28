# 完整 NPU 时序与资源（N-W2）

| 项 | 内容 |
|---|---|
| commit | `6540e2c`（RTL 与 N-C1 合入后的 `main` 相同；`clk_mem_i` 改到 K21） |
| 任务卡 | `tasks/win/20261028-02-npu-pnr-r2/`（首次 `20261028-01` B 部分在 PnR 时钟布局报 Place-0084：B24 不能驱动全局时钟） |
| 工具 | PDS 2022.2-SP6.1（build 138931），Timing Models Pre-silicon |
| 器件 | PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_npu_top`，`edrv32_fpga_npu_top.fdc`：clk_npu 6.667 ns（150 MHz，D18），clk_mem 8.000 ns（125 MHz，K21），两者为异步组 |
| 原始数据 | `tasks/win/20261028-02-npu-pnr-r2/artifacts/`；完整报告在 Windows `G:/codex_project/EdRV32-FPGA/EdRV32-NPU/` |

## 时序（路后）

| 时钟 / 角 | WNS ns | TNS ns | WHS ns | setup 违例端点 | Fmax（`1000 / (period − WNS)`） |
|---|---|---|---|---|---|
| clk_npu / slow | +0.214 | 0 | +0.137 | 0 / 132751 | 155.0 MHz |
| clk_npu / fast | +2.553 | 0 | +0.099 | 0 / 132751 | — |
| clk_mem / slow | +4.448 | 0 | +0.143 | 0 / 1971 | 281.5 MHz |
| clk_mem / fast | +5.909 | 0 | +0.100 | 0 / 1971 | — |

Recovery、removal、最小脉宽都没有违例。异步组生效：时序汇总只有 clk_npu→clk_npu、clk_mem→clk_mem 两个时钟对。

clk_npu 最差路径：MAC 阵列乘法 APM → `g_channel[3].g_pixel[1].r1_data_r`，2 级，布线占 83.9%，+0.214 ns。其次是 `u_window/a5_tag_r` → 乘法 APM 输入（+0.217 ns，1 级）、APB 桥 `request_r` → 量化参数 RAM 地址（+0.311 ns，4 级）、`schedule_row_r` → `perf_r`（+0.360 ns，8 级）。0 到 1 ns 之间的路径样本：200 条中有 31 条小于 0.5 ns。

对比：仅数据通路（20261027-02 B）路后 clk_npu +0.341 ns；完整 NPU 综合预估（20261028-01 B）+0.107 ns。

## 资源（PnR 后）

| LUT | FF | 分布式 RAM | DRM36K | APM | IO | USCM |
|---|---|---|---|---|---|---|
| 27188 | 36481 | 412 | 157 | 290 | 6 | 2 |

`u_npu` 27108 LUT，其中 `u_conv/u_datapath` 21943（MAC 阵列 8002、结果量化 6350）、`u_nonconv` 1295、`u_regs` 582、`u_axi_bridge` 329（1 DRM）、`u_descriptor` 277（2 APM）。顶层激励/观测逻辑 80 LUT、435 FF。

与 NPU 规格第 7 节初值对比：LUT ≤ 50K（SoC 规格 9.3）、APM ≤ 300、DRM ≤ 170，均满足。

## 其他

- 映射阶段高扇出：时钟 36506，`window/a4_valid_r` 2857、`a3_valid_r` 2359、累加 `r4_valid_r` 2050。
- 集成到 SoC 后布局变化可能吃掉 +0.214 ns 的裕量，整 SoC PDS 时复查。
