# 卡 64 结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。资源取布线后层次表，DRM 按 DRM36K 等效计。 CPU v0.21 + L1，RTL 提交 `9fa3f649`，clk_sys 约束 150 MHz。

| 布局布线参数 | 慢角 WNS / TNS (ns) | 违例端点数 | WHS 慢角 / 快角 (ns) | 估算 Fmax (MHz) | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---:|---:|---:|---:|---:|---:|
| 默认 P&R | -0.562 / -224.496 | 1625 | +0.112 / +0.067 | 138.3317 | 19712 / 12877 / 27 / 4 / 680 | 19458 / 12136 |

布局布线完成，用时 0h:13m:57s。慢角 WNS 距任务目标 +0.300 ns 差 0.862 ns。本轮最差路径为 `u_cpu/u_icache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/predecode_r[2][19]/opit_0_L6Q_perm/I2`，逻辑 / 布线 3.099 / 3.617 ns。

## 分组（P1–P10、其他）

按任务卡顺序取第一个匹配组。全局导出每个端点保留最差一条慢角 clk_sys setup 路径。全局未出现的组单独筛选。逻辑级数范围取各组已导出的路径，逐级明细中的每条网络均保留 PDS 原始扇出。

逐级明细见 `artifacts/R1/timing_group_worst.txt`。

| 组 | 违例条数 | 最差 slack (ns) | 级数范围 | 最差路径逻辑 / 布线 (ns) | 起点 → 终点 |
|---|---:|---:|---:|---:|---|
| P1 | 2 | -0.052 | 9–10 | 1.742 / 4.553 | `u_cpu/u_core/e_branch_b_r[1][4]/opit_0_L6Q_perm/CLK` → `u_cpu/u_core/g_redirect_bank[16].e_redirect_copy1_r/opit_0_inv/D` |
| P2 | 292 | -0.377 | 4–11 | 2.490 / 3.918 | `u_cpu/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/g_lane[0].g_shift_bank[1].amount_copy1_r[3]/opit_0/D` |
| P3 | 51 | -0.405 | 2–12 | 1.394 / 5.047 | `u_cpu/u_core/u_frontend/u_ib/predecode_r[3][19]/opit_0_L6Q_perm/CLK` → `u_cpu/u_core/e_branch_b_r[1][27]/opit_0_L6Q_perm/I4` |
| P4 | 5 | -0.115 | 4–12 | 2.198 / 4.214 | `u_cpu/u_core/u_frontend/u_ib/entries_r[1][48]/opit_0_L6QL5Q1_perm/CLK` → `u_cpu/u_dcache/early_valid_r/opit_0_inv_L6Q_perm/I5` |
| P5 | 18 | -0.415 | 6–14 | 1.771 / 4.725 | `u_cpu/u_core/e_operand_a_r[1][10]/opit_0/CLK` → `u_cpu/u_core/e_branch_b_r[1][23]/opit_0_L6Q_perm/I3` |
| P6 | 191 | -0.424 | 2–7 | 2.489 / 3.879 | `u_cpu/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/e_branch_b_r[1][27]/opit_0_L6Q_perm/CE` |
| P7 | 0 | 未取得 | | | 单组筛选无匹配 |
| P8 | 0 | +1.030 | 4–4 | 0.960 / 4.249 | `u_cpu/u_core/u_frontend/g_query_index[1].query_valid_index_copy1_r[1]/opit_0_inv/CLK` → `u_cpu/u_core/u_frontend/u_predictor/ras_taken_r/opit_0/D` |
| P9 | 5 | -0.142 | 5–9 | 2.058 / 4.392 | `u_cpu/u_core/u_frontend/f1_pc_copy1_r[3]/opit_0_inv_L7Q_perm/CLK` → `u_cpu/u_core/u_frontend/f1_pc_copy2_r[26]/opit_0_inv/D` |
| P10 | 0 | 未取得 | | | 单组筛选无匹配 |
| 其他 | 1061 | -0.562 | 3–12 | 3.099 / 3.617 | `u_cpu/u_icache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/predecode_r[2][19]/opit_0_L6Q_perm/I2` |

### 其他组中违例最多的五类

| 起点模块 → 终点模块 | 违例条数 | 最差 slack (ns) | 违例路径级数范围 |
|---|---:|---:|---:|
| u_frontend → u_frontend/u_ib | 430 | -0.362 | 7–8 |
| u_icache/u_tag1 → u_frontend/u_ib | 318 | -0.562 | 5–7 |
| u_icache/u_tag0 → u_frontend/u_ib | 99 | -0.456 | 5–7 |
| u_frontend/u_ib → u_core | 82 | -0.301 | 9–10 |
| u_icache/u_tag0 → u_frontend | 46 | -0.220 | 5–6 |

## 与卡 62 对比

慢角 WNS 改善 0.190 ns，违例端点从 3896 减到 1625。估算 Fmax 从 134.7891 MHz 提升到 138.3317 MHz，增加 3.54 MHz（2.63%）。LUT / FF / DRM / APM / LUTRAM 的变化为 +726 / +647 / +0 / +0 / +0。

本轮复用卡 62 实跑的 IP 设置。`ip_lutram_cpu_local_history` 和 `ip_lutram_cpu_tournament` 均使用 `INIT_FILE=NONE`，生成模型把两项初始化为 0。卡 60 的 IP 说明要求 tournament 从初始化文件加载 1。`ip_lutram_cpu_direction` 仍加载原工程的初始化文件。

## 导出覆盖和约束

主时钟 D18 使用 3.3 V LVCMOS33。PDS 报告扫描和复位端口缺少外部延迟，本轮按独立探针约束运行。GUI 流程在时序报告完成后结束。

全局导出覆盖全部 1625 个慢角 setup 违例端点。独立导出得到 200 条 clk_sys 慢角临界正裕量路径，PDS 筛选范围为 0 到 +0.2 ns。

## 原始报告在 Windows 本地的路径

- `timing5000.rtr.gz` 压缩后 7.5 MiB，保留任务卡要求的逐级延迟、扇出和时序端点原文。
- PDS 工程和原始阶段报告位于 `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V018`。
- 5000 路径报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards63-64/64-timing5000/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 临界正裕量报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards63-64/64-near/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 压缩原文及可读明细见 `artifacts/R1/`。
- 单组原始导出位于 `G:/codex_project/EdRV32-Competition-2026/build/cards63-64/64-P*/report_timing/`。

## 未取得的项和原因

P7、P10 单组筛选未返回匹配的慢角 clk_sys setup 路径，最差 slack、级数和逐级明细记为未取得。对应 PDS 原文随报告保存。
