# NPU 数据通路单独 PDS 测量（N-W1）

日期：2026-10-27。来源：Windows 任务 `20261027-02-cpu-npu-synth` B 部分，结果分支 `origin/win/20261027-02-cpu-npu-synth`（提交 `1c3eda6`），原始报告在该分支 `tasks/win/20261027-02-cpu-npu-synth/artifacts/npu/`，不合入 main。

## 测量条件

| 项 | 内容 |
|---|---|
| 设计输入 | `335bb0f` 的 NPU RTL，加 7 个 RAM 包装的 FPGA 分支端口适配（`6569f8a`，已并入协调者分支） |
| 顶层 | `fpga/rtl/edrv32_fpga_npu_dp_top.v`：1025 位输入由串行移位寄存器驱动，358 位输出打拍后经寄存器异或树折叠到 1 个引脚 |
| 工具 | PDS 2022.2-SP6.1（build 138931）；ModelSim SE-64 2020.4 |
| 器件 | PG2L200H-6 FBB676，Pre-silicon，多角 |
| 约束 | `fpga/constraints/edrv32_fpga_npu_dp_top.fdc`：`clk_i` 6.667 ns（clk_npu 开发初值 150 MHz）；3 个 IO 无 IO delay |

## IP 检查（ModelSim）

- 4 个乘法器（int8_pair 两路、quant_low、quant_high）各 4026 次检查通过（`PASS npu_mul_only`）；量化乘法 IP 最终配置 XYREG=1、MREG=1。
- 7 个 RAM：读延迟（2 拍，scratch 1 拍）和读使能关闭时输出保持与包装模块一致；同拍同址读写的读出值不确定（IP 无冲突模式选项）。数据通路单元测试 12 个用例实测同址读写 0 次，不受影响（见 `fpga/ip/README.md`）。

## 时序

| 角 | WNS | TNS | WHS | 违例端点 |
|---|---|---|---|---|
| slow | +0.341 ns | 0 | +0.139 ns | 0 / 114062 |
| fast | +2.756 ns | 0 | +0.101 ns | 0 / 114062 |

估计频率 **158.08 MHz**，150 MHz 约束全部满足。slow setup 前 200 条裕量 +0.341～+0.952 ns，4 条小于 0.5 ns。

最差路径：`u_window/a5_tag_r[48]` → MAC 阵列 APM 的 X 输入，1 级逻辑，主要是连线：`term_tag_w[48]` 扇出 129、0.956 ns，到 APM 的一段 4.249 ns。前 10 条中 9 条是这一类，另一条是 APM 输出 → `r1_data_r`（4 级）。

映射阶段高扇出：`u_window/a4_valid_r` 2869、`a3_valid_r` 2358、`u_accum` 的 `r4_valid_r`/`r4_first_r` 约 2050、`u_weight_store` 段选择 2048、`sum_tag_w[48]` 1248。

## 资源（布局布线后，逻辑层次）

| 层次 | LUT | FF | 分布式 RAM | APM | DRM36K |
|---|---|---|---|---|---|
| 顶层合计 | 22023 | 31747 | 19 | 288 | 148 |
| `u_datapath` | 21813 | 30320 | 16 | 288 | 148 |
| ├ `u_mac_array` | 8003 | 8181 | 0 | 256 | 0 |
| ├ `u_result_quant` | 6371 | 8946 | 0 | 32 | 0 |
| ├ `u_window` | 2774 | 5783 | 0 | 0 | 0 |
| ├ `u_accum` | 2689 | 3345 | 0 | 0 | 0 |
| ├ `u_residual_add` | 1537 | 930 | 0 | 0 | 0 |
| ├ `u_input_unpack` | 273 | 273 | 0 | 0 | 0 |
| ├ `u_weight_store` | 24 | 2148 | 0 | 0 | 96 |
| ├ `u_line_cache` | 2 | 0 | 0 | 0 | 16 |
| ├ `u_activation_lut` | 1 | 20 | 0 | 0 | 16 |
| ├ `u_quant_param_store` | 8 | 480 | 0 | 0 | 8 |
| ├ `u_writeback` | 72 | 116 | 16 | 0 | 8 |
| └ `u_residual_buffer` | 54 | 40 | 0 | 0 | 4 |

器件容量 159800 LUT、319600 FF、415 DRM36K、740 APM。APM 288、DRM 148 与设计记录估算一致（DRM 估算 156 含 N-C1 的两块 scratch，共 8）。

## 局限

单时钟、无 PLL 的独立测量顶层；输入输出由测量壳层驱动，与 SoC 中调度器、DMA 的连接不同；未与 CPU、DDR、媒体同时布局。整机时序以完整 SoC 工程为准。
