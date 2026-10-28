# 20261028-02-npu-pnr-r2 结果

完整 NPU 在 clk_mem_i 改为 K21 后完成 Compile、Synthesize、Device Map、PnR 和路后时序分析。
两个时钟的 slow/fast setup、hold、recovery、removal、minimum pulse width 均无违例。
clk_npu 的 slow WNS 只有 +0.214 ns，须保留对完整 SoC 集成裕量的关注。

| 项 | 内容 |
|---|---|
| 输入 commit | 6540e2c2a255cae92e2379269e299dd2cbe7af7c |
| 输入分支 | origin/main，包含 K21 修正及本任务卡 |
| 结果分支 | win/20261028-02-npu-pnr-r2 |
| PDS | 2022.2-SP6.1 build 138931 |
| 器件 / 模式 | PG2L200H-6 FBB676 / normal |
| 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32-NPU/EdRV32-NPU.pds |
| 日期 | 2026-10-28，Windows 本地时间 |
| clk_mem_i / clk_npu_i | K21 / D18 |
| 时钟缓冲 | clk_npu：clkbufg_0 / USCM_383_930；clk_mem：clkbufg_1 / USCM_383_933 |
| 完成情况 | 本轮流程与任务要求的报告收集全部完成；未使用专用时钟布线放宽 |

## 时钟与约束核对

工程 .pds 引用 `../../EdRV32-Competition-2026/fpga/constraints/edrv32_fpga_npu_top.fdc`；
impl.tcl 引用同一仓库文件。PnR run.log 明确执行并接受 `clk_mem_i LOC=K21`。
PRR 的 IO 表是 K21 / BANKL4；此前 B24 的 Place-0084 本轮未出现。
仓库 FDC 和工程实施命令没有 PAP_CLOCK_DEDICATED_ROUTE 放宽。

PRR Global Clock Info：

| 时钟 | 驱动 IO 位置 | 缓冲 | Clock Loads | Non-clock Loads |
|---|---|---|---|---|
| clk_npu_i | IOLHR_16_1386（D18） | USCM_383_930 | 34245 | 0 |
| clk_mem_i | IOLHR_16_1080（K21） | USCM_383_933 | 794 | 0 |

两时钟各经一个全局缓冲。RTR Clock Summary 的 timing graph 口径为
clk_npu 23746 clock / 10655 non-clock loads、clk_mem 794 / 0；与 PRR 口径分开保留。
clock_constraints.txt 保存约束、工程引用、PnR 应用约束原文和 PRR 缓冲表。

## 路后时序

| 时钟 / Corner | 周期 ns | WNS ns | TNS ns | WHS ns | THS ns | setup 违例端点 | hold 违例端点 | Fmax 推算 MHz |
|---|---|---|---|---|---|---|---|---|
| clk_npu / slow | 6.667 | +0.214 | 0 | +0.137 | 0 | 0/132751 | 0/132751 | 154.9667 |
| clk_npu / fast | 6.667 | +2.553 | 0 | +0.099 | 0 | 0/132751 | 0/132751 | — |
| clk_mem / slow | 8.000 | +4.448 | 0 | +0.143 | 0 | 0/1971 | 0/1971 | 281.5315 |
| clk_mem / fast | 8.000 | +5.909 | 0 | +0.100 | 0 | 0/1971 | 0/1971 | — |

Fmax 按任务卡公式 `1000 / (period − slow WNS)` 推算；原生 Performance Summary 同值。
clk_npu 请求约 150 MHz（6.667 ns），clk_mem 请求 125 MHz（8 ns）。
报告为 multi corner、Pre-silicon timing models；本轮是独立 NPU 测量工程，没有上板或生成 bitstream。

异步组已生效：RTR 明确列出 npu_mem_async 为 asynchronous，子组分别是 clk_npu、clk_mem；
setup/hold 汇总只有 clk_npu→clk_npu 和 clk_mem→clk_mem，没有跨域时钟对。
本轮扩展路径索引也按 clk_npu/clk_mem 分组；不把异步 CDC 例外当作同步时序通过。

| 时钟 / Corner | Recovery 最差 ns | Removal 最差 ns | Minimum Pulse Width 最差 ns |
|---|---|---|---|
| clk_npu / slow | +3.588 | +0.448 | +2.373 |
| clk_npu / fast | +4.874 | +0.303 | +2.678 |
| clk_mem / slow | +5.546 | +0.679 | +3.040 |
| clk_mem / fast | +6.536 | +0.456 | +3.430 |

以上三类均无违例。Recovery/removal 端点为 NPU 764、mem 55；min pulse width
端点为 NPU 23746、mem 794。原生汇总和每域每角的 recovery/removal 前 20 条明细已保留。

### 裕量与危险路径

- clk_npu slow 最差 +0.214 ns，约为目标周期的 3.21%，对应推算 Fmax 比 150 MHz 高约 3.31%。
  这能说明独立工程在当前约束下通过，不能保证 CPU/NPU/媒体/存储等一起集成后仍有相同裕量。
- 单独导出 `0 < setup slack < 1 ns` 的最差 200 条，均为 clk_npu slow，范围 +0.214 至 +0.752 ns；
  其中 2 条小于 0.25 ns，31 条小于 0.5 ns。计数是所保存的样本，不是设计中该范围的全量路径数。
  最差 20 条的每级延迟和扇出另存 setup_near_positive_top20_detail.txt。
- 最差路径是 channel[3]/lane[5] 乘法 APM → channel[3]/pixel[1] r1_data_r[2][16] CIN，
  2 级，逻辑 0.975 ns、布线 5.095 ns（83.937%），clock skew −0.217 ns，裕量 +0.214 ns。
  次差是 window/a5_tag_r[48] → channel[22]/lane[6] 乘法 APM X[1]，仅 +0.217 ns、1 级。
- clk_mem 最差 +4.448 ns；该路径是 AR FIFO read_bin_r[2] → memory_r_doreg[0]，
  1 级，逻辑 0.524 ns、布线 2.840 ns。最差 hold 为 NPU fast +0.099 ns、mem fast +0.100 ns，
  同样保留了 hold 明细。

对照：上一轮完整 NPU 只有综合预估，clk_npu +0.107 ns、clk_mem +4.998 ns；
本轮路后分别 +0.214 / +4.448 ns，阶段不同，不作为同条件优化差分。
更早的 NPU-DP 路后 clk_npu 为 +0.341 ns；本轮是完整 NPU，包含控制器和异步桥等逻辑，不能直接替代比较。

### clk_npu slow 最差 10 条

| # | 起点 → 终点（省略 u_npu/ 和 opit 打包后缀） | 裕量 ns | 级数 |
|---|---|---|---|
| 1 | `u_conv/u_datapath/u_mac_array/g_channel[3].g_lane[5].u_multiply/u_apm/gopapm/CLK` → `u_conv/u_datapath/u_mac_array/g_channel[3].g_pixel[1].r1_data_r[2][16]` | 0.214 | 2 |
| 2 | `u_conv/u_datapath/u_window/a5_tag_r[48]` → `u_conv/u_datapath/u_mac_array/g_channel[22].g_lane[6].u_multiply/u_apm/gopapm/X[1]` | 0.217 | 1 |
| 3 | `u_apb_bridge/request_r[47]` → `u_conv/u_datapath/u_quant_param_store/g_bank[1].u_ram/u_ip/U_ipm2l_sdpram_ip_ram_npu_quant/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/ADB0[9]` | 0.311 | 4 |
| 4 | `u_conv/u_datapath/u_mac_array/g_channel[3].g_lane[5].u_multiply/u_apm/gopapm/CLK` → `u_conv/u_datapath/u_mac_array/g_channel[3].g_pixel[1].r1_data_r[2][12]` | 0.317 | 1 |
| 5 | `u_conv/u_datapath/u_window/a5_tag_r[48]` → `u_conv/u_datapath/u_mac_array/g_channel[23].g_lane[6].u_multiply/u_apm/gopapm/X[1]` | 0.326 | 1 |
| 6 | `u_conv/schedule_row_r[3]` → `u_regs/perf_r[4][5]` | 0.360 | 8 |
| 7 | `u_apb_bridge/request_r[47]` → `u_conv/u_datapath/u_quant_param_store/g_bank[7].u_ram/u_ip/U_ipm2l_sdpram_ip_ram_npu_quant/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/ADB0[5]` | 0.371 | 4 |
| 8 | `u_apb_bridge/request_r[47]` → `u_conv/u_datapath/u_quant_param_store/g_bank[7].u_ram/u_ip/U_ipm2l_sdpram_ip_ram_npu_quant/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM36K_E1/gopdrm_36k/ADB0[9]` | 0.374 | 4 |
| 9 | `u_conv/u_datapath/u_mac_array/g_channel[2].g_lane[5].u_multiply/u_apm/gopapm/CLK` → `u_conv/u_datapath/u_mac_array/g_channel[2].g_pixel[0].r1_data_r[2][16]` | 0.384 | 3 |
| 10 | `u_conv/u_datapath/u_window/g_activation_copy[0].activation_r[187]` → `u_conv/u_datapath/u_mac_array/g_channel[4].g_lane[7].u_multiply/u_apm/gopapm/X[15]` | 0.409 | 0 |

### clk_mem slow 最差 10 条

| # | 起点 → 终点（省略 u_npu/ 和 opit 打包后缀） | 裕量 ns | 级数 |
|---|---|---|---|
| 1 | `u_axi_bridge/u_ar_fifo/read_bin_r[2]` → `u_axi_bridge/u_ar_fifo/memory_r_doreg[0]` | 4.448 | 1 |
| 2 | `u_axi_bridge/u_r_fifo/read_meta_r[3]` → `u_axi_bridge/u_r_fifo/full_r` | 4.448 | 2 |
| 3 | `u_axi_bridge/u_ar_fifo/read_bin_r[2]` → `u_axi_bridge/u_ar_fifo/memory_r_doreg[3]` | 4.505 | 1 |
| 4 | `u_axi_bridge/u_aw_fifo/read_gray_r[1]` → `u_axi_bridge/u_aw_fifo/memory_r_doreg[4]` | 4.546 | 1 |
| 5 | `u_axi_bridge/u_w_fifo/memory_r_0/gopdrm_36k/CLKB[0]` → `l1_r[13]` | 4.661 | 0 |
| 6 | `u_axi_bridge/u_w_fifo/memory_r_0/gopdrm_36k/CLKB[0]` → `l1_r[19]` | 4.675 | 0 |
| 7 | `u_axi_bridge/u_w_fifo/memory_r_0/gopdrm_36k/CLKB[0]` → `l1_r[12]` | 4.704 | 0 |
| 8 | `u_axi_bridge/u_w_fifo/memory_r_0/gopdrm_36k/CLKB[0]` → `l1_r[20]` | 4.715 | 0 |
| 9 | `u_axi_bridge/u_w_fifo/memory_r_0/gopdrm_36k/CLKB[0]` → `l1_r[22]` | 4.753 | 0 |
| 10 | `u_axi_bridge/u_w_fifo/memory_r_0/gopdrm_36k/CLKB[0]` → `l1_r[23]` | 4.768 | 0 |

## 分组路径明细

每个时钟每角的前 200 条 setup，共 800 条索引。
按起终点寄存器主体分组，去掉寄存器位下标与 opit/gop/gateop 打包后缀，保留 generate 实例下标；
IP 内部 DRM 原语归到其逻辑 u_ip 实例。
clk_npu 观测到 65 组，取样本最差裕量排序前 30 组；clk_mem 19 组全部导出，共 49 组。
每组均实际执行 `report_timing -from ... -to ... -max_path 1 -nworst 1`，分别保留 slow/fast 最差逐级明细。
段首包含命令原文、分组名、样本条数、裕量；概要在 setup_group_summary.txt，
全部 84 个观测组的样本计数和最差裕量另存 setup_group_index.txt。

| 组 | slow 最差裕量 ns | 级数 | top200 样本条数 | 起点主体 → 终点主体 |
|---|---|---|---|---|
| clk_npu_01 | 0.214 | 2 | 6 | `u_npu/u_conv/u_datapath/u_mac_array/g_channel[3].g_lane[5].u_multiply/u_apm` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[3].g_pixel[1].r1_data_r` |
| clk_npu_02 | 0.217 | 1 | 34 | `u_npu/u_conv/u_datapath/u_window/a5_tag_r` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[22].g_lane[6].u_multiply/u_apm` |
| clk_npu_03 | 0.311 | 4 | 8 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_conv/u_datapath/u_quant_param_store/g_bank[1].u_ram/u_ip` |
| clk_npu_04 | 0.326 | 1 | 17 | `u_npu/u_conv/u_datapath/u_window/a5_tag_r` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[23].g_lane[6].u_multiply/u_apm` |
| clk_npu_05 | 0.360 | 8 | 21 | `u_npu/u_conv/schedule_row_r` → `u_npu/u_regs/perf_r` |
| clk_npu_06 | 0.371 | 4 | 6 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_conv/u_datapath/u_quant_param_store/g_bank[7].u_ram/u_ip` |
| clk_npu_07 | 0.384 | 3 | 11 | `u_npu/u_conv/u_datapath/u_mac_array/g_channel[2].g_lane[5].u_multiply/u_apm` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[2].g_pixel[0].r1_data_r` |
| clk_npu_08 | 0.409 | 0 | 6 | `u_npu/u_conv/u_datapath/u_window/g_activation_copy[0].activation_r` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[4].g_lane[7].u_multiply/u_apm` |
| clk_npu_09 | 0.410 | 1 | 8 | `u_npu/u_conv/u_datapath/u_mac_array/g_channel[2].g_lane[5].u_multiply/u_apm` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[2].g_pixel[1].r1_data_r` |
| clk_npu_10 | 0.425 | 7 | 12 | `u_npu/u_conv/residual_pair_r` → `u_npu/u_conv/residual_row_r` |
| clk_npu_11 | 0.427 | 2 | 8 | `u_npu/u_conv/u_datapath/u_mac_array/g_channel[4].g_lane[5].u_multiply/u_apm` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[4].g_pixel[1].r1_data_r` |
| clk_npu_12 | 0.429 | 3 | 9 | `u_npu/u_conv/u_datapath/u_mac_array/g_channel[4].g_lane[5].u_multiply/u_apm` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[4].g_pixel[0].r1_data_r` |
| clk_npu_13 | 0.450 | 2 | 36 | `u_npu/u_conv/u_datapath/u_input_unpack/remaining_r` → `u_npu/u_conv/u_datapath/u_line_cache/u_bank1/u_ip` |
| clk_npu_14 | 0.463 | 11 | 19 | `u_npu/u_descriptor/desc_r` → `u_npu/u_conv/load_addr_r` |
| clk_npu_15 | 0.479 | 11 | 18 | `u_npu/u_descriptor/desc_r` → `u_npu/u_conv/load_row_addr_r` |
| clk_npu_16 | 0.509 | 5 | 9 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_read_dma/data_r` |
| clk_npu_17 | 0.517 | 4 | 7 | `u_npu/u_conv/u_datapath/u_mac_array/g_channel[1].g_lane[5].u_multiply/u_apm` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[1].g_pixel[0].r1_data_r` |
| clk_npu_18 | 0.548 | 5 | 2 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_nonconv/u_row_scratch/u_ip` |
| clk_npu_19 | 0.557 | 0 | 2 | `u_npu/u_conv/u_datapath/u_window/g_activation_copy[0].activation_r` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[2].g_lane[1].u_multiply/u_apm` |
| clk_npu_20 | 0.558 | 5 | 4 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_conv/weight_data_r` |
| clk_npu_21 | 0.581 | 0 | 7 | `u_npu/u_conv/u_datapath/u_window/g_activation_copy[0].activation_r` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[3].g_lane[7].u_multiply/u_apm` |
| clk_npu_22 | 0.590 | 13 | 5 | `u_npu/u_conv/residual_pairs_r` → `u_npu/u_conv/residual_addr_r` |
| clk_npu_23 | 0.591 | 6 | 21 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_conv/line_data_r` |
| clk_npu_24 | 0.593 | 1 | 6 | `u_npu/u_conv/u_datapath/u_mac_array/g_channel[1].g_lane[5].u_multiply/u_apm` → `u_npu/u_conv/u_datapath/u_mac_array/g_channel[1].g_pixel[1].r1_data_r` |
| clk_npu_25 | 0.599 | 5 | 13 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_regs/done_count_r` |
| clk_npu_26 | 0.602 | 5 | 9 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_descriptor/desc_r` |
| clk_npu_27 | 0.609 | 5 | 8 | `u_npu/u_apb_bridge/request_r` → `u_npu/u_conv/u_datapath/u_input_unpack/data_r` |
| clk_npu_28 | 0.620 | 11 | 2 | `u_npu/u_descriptor/desc_r` → `u_npu/u_conv/load_row_r` |
| clk_npu_29 | 0.621 | 11 | 3 | `u_npu/u_descriptor/desc_r` → `u_npu/u_conv/load_plane_base_r` |
| clk_npu_30 | 0.632 | 9 | 2 | `u_npu/u_conv/model_addr_r` → `u_npu/u_conv/model_addr_r` |
| clk_mem_01 | 4.448 | 1 | 12 | `u_npu/u_axi_bridge/u_ar_fifo/read_bin_r` → `u_npu/u_axi_bridge/u_ar_fifo/memory_r_doreg` |
| clk_mem_02 | 4.448 | 2 | 2 | `u_npu/u_axi_bridge/u_r_fifo/read_meta_r` → `u_npu/u_axi_bridge/u_r_fifo/full_r` |
| clk_mem_03 | 4.546 | 1 | 13 | `u_npu/u_axi_bridge/u_aw_fifo/read_gray_r` → `u_npu/u_axi_bridge/u_aw_fifo/memory_r_doreg` |
| clk_mem_04 | 4.661 | 0 | 139 | `u_npu/u_axi_bridge/u_w_fifo/memory_r_0` → `l1_r` |
| clk_mem_05 | 4.805 | 1 | 2 | `u_npu/u_axi_bridge/u_ar_fifo/empty_r` → `u_npu/u_axi_bridge/u_ar_fifo/empty_r` |
| clk_mem_06 | 4.814 | 1 | 2 | `u_npu/u_axi_bridge/u_aw_fifo/read_gray_r` → `u_npu/u_axi_bridge/u_aw_fifo/empty_r` |
| clk_mem_07 | 4.894 | 2 | 2 | `u_npu/u_axi_bridge/u_b_fifo/full_r` → `u_npu/u_axi_bridge/u_b_fifo/full_r` |
| clk_mem_08 | 4.897 | 1 | 41 | `u_npu/u_axi_bridge/u_w_fifo/read_gray_r` → `u_npu/u_axi_bridge/u_w_fifo/memory_r_1_1_1_doreg` |
| clk_mem_09 | 4.963 | 1 | 60 | `u_npu/u_axi_bridge/u_w_fifo/read_gray_r` → `u_npu/u_axi_bridge/u_w_fifo/memory_r_1_1_0_doreg` |
| clk_mem_10 | 4.986 | 1 | 58 | `u_npu/u_axi_bridge/u_w_fifo/read_gray_r` → `u_npu/u_axi_bridge/u_w_fifo/memory_r_1_0_doreg` |
| clk_mem_11 | 5.020 | 1 | 8 | `u_npu/u_axi_bridge/u_w_fifo/read_bin_r` → `u_npu/u_axi_bridge/u_w_fifo/memory_r_1_1_1_doreg` |
| clk_mem_12 | 5.050 | 1 | 4 | `u_npu/u_axi_bridge/u_w_fifo/read_bin_r` → `u_npu/u_axi_bridge/u_w_fifo/memory_r_1_0_doreg` |
| clk_mem_13 | 5.061 | 1 | 28 | `u_npu/u_apb_bridge/u_response/ack_r` → `u_npu/u_apb_bridge/source_response_r` |
| clk_mem_14 | 4.884 | 2 | 2 | `stim_r` → `u_npu/u_axi_bridge/u_r_fifo/full_r` |
| clk_mem_15 | 4.572 | 1 | 6 | `u_npu/u_axi_bridge/u_ar_fifo/read_gray_r` → `u_npu/u_axi_bridge/u_ar_fifo/memory_r_doreg` |
| clk_mem_16 | 5.222 | 1 | 6 | `u_npu/u_axi_bridge/u_w_fifo/read_bin_r` → `u_npu/u_axi_bridge/u_w_fifo/memory_r_1_1_0_doreg` |
| clk_mem_17 | 5.254 | 1 | 6 | `stim_r` → `u_npu/u_apb_bridge/u_request/data_r` |
| clk_mem_18 | 4.745 | 1 | 7 | `u_npu/u_axi_bridge/u_aw_fifo/read_bin_r` → `u_npu/u_axi_bridge/u_aw_fifo/memory_r_doreg` |
| clk_mem_19 | 5.198 | 2 | 2 | `u_npu/u_axi_bridge/u_b_fifo/write_gray_r` → `u_npu/u_axi_bridge/u_b_fifo/full_r` |

## 资源

| 阶段 | LUT | FF | 分布式 RAM | DRM18K | DRM36K | APM | IO | GPLL / PPLL | USCM |
|---|---|---|---|---|---|---|---|---|---|
| Synthesize | 27372 | 36737 | 412 | 0 | 157 | 290 | 6 | 0 / 0 | 0（尚未插入） |
| PnR 最终逻辑层次总计 | 27188 | 36481 | 412 | 0 | 157 | 290 | 6 | 0 / 0 | 2 |

最终占用：LUT 17.01%（27188/159800）、FF 11.41%（36481/319600）、分布式 RAM 1.04%（412/39500）、
DRM36K 37.83%（157/415）、APM 39.19%（290/740）、IO 1.50%（6/400）、USCM 6.25%（2/32）。
DRM18K/36K 分项来自 SNR primitive counts，PRR 的 DRM 总数也为 157。
PRR 物理 CLMA/CLMS 行与逻辑 LUT 总计采用不同的打包口径，不混用；最终层次数字按 PRR 原文保留。
完整 NPU 的 LUT 低于规格 50K 预算，DRM/APM 未超过本器件容量；整 SoC 资源仍需集成测量。
与本轮综合相比，最终逻辑 LUT −184、FF −256，DRM/APM/分布式 RAM 总数不变。

| 实例（父子行不能相加） | LUT | FF | 分布式 RAM | APM | DRM36K |
|---|---|---|---|---|---|
| edrv32_fpga_npu_top | 27188 | 36481 | 412 | 290 | 157 |
| u_npu | 27108 | 36042 | 412 | 290 | 157 |
| u_npu/u_apb_bridge | 39 | 205 | 0 | 0 | 0 |
| u_npu/u_axi_bridge | 329 | 417 | 260 | 0 | 1 |
| u_npu/u_conv | 24071 | 32188 | 143 | 288 | 148 |
| u_npu/u_conv/u_conv_write | 417 | 455 | 141 | 0 | 0 |
| u_npu/u_conv/u_datapath | 21943 | 29975 | 0 | 288 | 148 |
| u_npu/u_conv/u_datapath/u_line_cache | 2 | 0 | 0 | 0 | 16 |
| u_npu/u_conv/u_datapath/u_mac_array | 8002 | 8109 | 0 | 256 | 0 |
| u_npu/u_conv/u_datapath/u_quant_param_store | 8 | 480 | 0 | 0 | 8 |
| u_npu/u_conv/u_datapath/u_result_quant | 6350 | 8777 | 0 | 32 | 0 |
| u_npu/u_conv/u_datapath/u_weight_store | 24 | 2148 | 0 | 0 | 96 |
| u_npu/u_descriptor | 277 | 511 | 0 | 2 | 0 |
| u_npu/u_nonconv | 1295 | 1235 | 0 | 0 | 8 |
| u_npu/u_read_dma | 60 | 328 | 9 | 0 | 0 |
| u_npu/u_regs | 582 | 519 | 0 | 0 | 0 |
| u_npu/u_write_dma | 297 | 563 | 0 | 0 | 0 |
| u_reset_mem | 0 | 2 | 0 | 0 | 0 |
| u_reset_npu | 0 | 2 | 0 | 0 | 0 |

顶层本地开销：总计减去 u_npu 和两个 reset_sync 后为 80 LUT、435 FF，
包括串行激励/观测及异或树逻辑。PRR 未单独给各 stim/obs 寄存器组的优化后资源；
本报告没有用 RTL 声明位宽代替最终 FF 数。resource_hier.txt 保留完整子层次。

映射前 100 个高扇出网络、时钟/复位/CE 表和最终时钟缓冲表均已保存。
主要映射扇出：时钟 36506，window/a4_valid_r 2857、a3_valid_r 2359、accum r4_valid_r 2050，
weight rd_segment_output_r 和 r4_first_r 各有 2048；这些是 Device Map 口径，不能与 PRR 时钟负载混用。

## 日志、耗时与警告

| 阶段 | Real | CPU | Process CPU | 峰值内存 | W 行 | E 行 | 结束时间 |
|---|---|---|---|---|---|---|---|
| compile | 0h:0m:29s | 0h:0m:4s | 0h:0m:4s | 339 MB | 1706 | 0 | Wed Oct 28 13:14:12 2026 |
| synthesize | 0h:2m:1s | 0h:0m:31s | 0h:0m:33s | 2,432 MB | 7480 | 0 | Wed Oct 28 13:16:12 2026 |
| device_map | 0h:0m:32s | 0h:0m:8s | 0h:0m:8s | 1,109 MB | 257 | 0 | Wed Oct 28 13:16:45 2026 |
| place_route | 0h:11m:57s | 0h:3m:13s | 0h:4m:15s | 4,216 MB | 0 | 0 | Wed Oct 28 13:28:43 2026 |
| report_timing | 0h:0m:46s | 0h:0m:12s | 0h:0m:14s | 3,100 MB | 4 | 0 | Wed Oct 28 13:29:31 2026 |

五阶段 Real 合计 15m45s；各阶段 CPU 时间、Process CPU 时间和结束时间按 run.log 原文记录，
不把阶段间用户空闲时间加进流程耗时。
PnR 用时 11m57s，内部 placement 30.00s、routing 502.72s；其中 detailed routing 439.15s、
hold violation fix 21.92s。全部 61395 个网络布线成功；其他耗时包含模型、数据库和阶段外开销，
不能只凭 Real 大于 CPU 时间判定卡死。

所有最终阶段 E: 行为 0。W: 行数是日志出现次数，不是独立缺陷数；全部原文和阶段分类均已保留：

- Compile 1706 行，含 constant probe loop 197 行；大量来自生成 IP 模板的常量分支、未驱动位补零、
  忽略仿真 system task。Loop 提示没有提供可直接定位的反馈单元链，不据此单独断言 RTL 组合环已存在或已排除。
- Synthesize 7480 行，Public-4008 悬空实例清理 7396 行；Device Map 清理 256 行，
  另有 1 行 Public-4010（已有 .pcf 被覆盖）。这些信息与最终资源报告一起保留；SNR 报告零锁存器。
- 综合有 4 行 Unable to honor max fanout constraint，映射高扇出表已保存，供集成时评估。
- 路后仅 4 行未约束 IO 提示：rst_n_i、stim_i、obs_o、irq_obs_o。
  这些测量 IO 的组合路径没有 slack/pass 判定，单独保存在 unconstrained_io_paths.txt。
  本轮 All Constraints Met 指已声明的时序约束，不能据此认定这些外部 IO 已完成接口时序签核。
- 本轮 PnR 无 warning/error；旧 B24 Place-0084 只存在历史 pds.log 操作摘录，未混入本轮失败计数。

## 完整报告在 Windows 本地的路径

原工程：`G:/codex_project/EdRV32-FPGA/EdRV32-NPU/`，各阶段完整原始日志仍是
`compile/run.log`、`synthesize/run.log`、`device_map/run.log`、`place_route/run.log`、`report_timing/run.log`。
原生报告是各目录下的 .cmr、.snr、.dmr、.prr、.rtr；历史控制台记录是工程根目录 pds.log。

回传产物位于本任务 artifacts/：资源、约束证据、每域每角前 200 setup/hold 索引、
前 20 条逐级明细、49 组明细、危险正裕量路径、recovery/removal、IO 未约束路径、
高扇出、原生报告和保留全部 W:/E: 行的精简日志。
完整扩展 RTR 和独立查询日志留在 `build/win/20261028-02-npu-pnr-r2/` 的 timing_200/、timing_near/、groups/。
查询只读已有 routed 数据库，没有重新布局布线，没有修改原工程。

复现报告导出的命令（从仓库根目录执行）：

```powershell
$pds = 'G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe'
New-Item -ItemType Directory -Force -Path "$PWD/build/win/20261028-02-npu-pnr-r2/timing_200", "$PWD/build/win/20261028-02-npu-pnr-r2/timing_near" | Out-Null
& $pds -file "$PWD/tasks/win/20261028-02-npu-pnr-r2/src/export_timing.tcl" -work_dir "$PWD/build/win/20261028-02-npu-pnr-r2/timing_200" -project_name npu_report
& $pds -file "$PWD/tasks/win/20261028-02-npu-pnr-r2/src/export_near.tcl" -work_dir "$PWD/build/win/20261028-02-npu-pnr-r2/timing_near" -project_name npu_report
C:/Python314/python.exe tasks/win/20261028-02-npu-pnr-r2/src/collect_reports.py
C:/Python314/python.exe tasks/win/20261028-02-npu-pnr-r2/src/export_groups.py
C:/Python314/python.exe tasks/win/20261028-02-npu-pnr-r2/src/write_result.py
```

## 备注

本轮没有修改 RTL、IP、约束或导入脚本；CPU 没有重跑。
按任务卡仅回传结果、精简产物及查询脚本，PDS 工程、IP 生成文件、中间数据库、网表、bitstream 和完整原始日志不入库。
34 个精简产物合计约 6.43 MB，单个最大约 1.47 MB（保留各阶段全部 W:/E: 行的警告摘录）。
未操控桌面，未运行 Verilator/RTL 仿真。本轮任务的布局布线及报告采集验收满足；
后续整 SoC 的布局和布线变化仍需重新检查 +0.214 ns 的核心时序裕量。
