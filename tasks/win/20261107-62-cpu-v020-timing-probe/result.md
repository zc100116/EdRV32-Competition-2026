# 卡 62 结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。资源取布线后层次表，DRM 按 DRM36K 等效计。 CPU v0.20 + L1，RTL 提交 `23fcd74c`，clk_sys 约束 150 MHz。

| 布局布线参数 | 慢角 WNS / TNS (ns) | 违例端点数 | WHS 慢角 / 快角 (ns) | 估算 Fmax (MHz) | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---:|---:|---:|---:|---:|---:|
| 默认 P&R | -0.752 / -825.837 | 3896 | +0.144 / +0.100 | 134.7891 | 18986 / 12230 / 27 / 4 / 680 | 18727 / 11487 |

布局布线完成，用时 0h:12m:15s。慢角 setup 仍有违例，估算 Fmax 距 135 MHz 阶段目标 0.21 MHz。

## 分组（P1–P10、其他）

按任务卡顺序取第一个匹配组。P9 的违例条数来自单组慢角导出，其余各组来自全局慢角导出。全局导出对每个端点仅保留最差一条。P9 有违例路径被同端点的更差路径占位，单组计数不与全局端点数相加。级数范围按各组导出的路径统计，逐级延迟与网络扇出见 `artifacts/R1/timing_group_worst.txt`。

| 组 | 违例条数 | 最差 slack (ns) | 级数范围 | 最差路径逻辑 / 布线 (ns) | 起点 → 终点 |
|---|---:|---:|---:|---:|---|
| P1 | 0 | +0.078 | 8–8 | 1.310 / 4.875 | `u_cpu/u_core/e_branch_a_r[0][1]/opit_0_L6Q_perm/CLK` → `u_cpu/u_core/e_redirect_lane_copy1_r[9]/opit_0/D` |
| P2 | 2070 | -0.720 | 5–9 | 2.558 / 4.282 | `u_cpu/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_dcache/g_metadata[13].lru_bank_r[7]/opit_0_inv_L6Q_perm/I4` |
| P3 | 36 | -0.485 | 6–11 | 1.407 / 5.058 | `u_cpu/u_core/u_frontend/u_ib/g_operand_read[7].read_ptr_copy_r[0]/opit_0_inv/CLK` → `u_cpu/u_core/e_alu_operand_b_copy1_r[1][27]/opit_0_L6Q_perm/I2` |
| P4 | 11 | -0.382 | 5–9 | 2.158 / 4.358 | `u_cpu/u_core/u_frontend/u_ib/g_operand_read[4].read_ptr_copy_r[1]/opit_0_inv/CLK` → `u_cpu/u_dcache/early_valid_r/opit_0_inv_L6Q_perm/I0` |
| P5 | 6 | -0.184 | 7–9 | 1.708 / 4.832 | `u_cpu/u_core/e_operand_a_r[1][10]/opit_0/CLK` → `u_cpu/u_core/e_operand_a_r[1][5]/opit_0/D` |
| P6 | 215 | -0.501 | 5–11 | 2.862 / 3.672 | `u_cpu/u_dcache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/e_operand_b_r[0][24]/opit_0/D` |
| P7 | 0 | 未取得 | | | 单组筛选无匹配 |
| P8 | 0 | +0.357 | 6–6 | 1.432 / 4.467 | `u_cpu/u_core/u_frontend/f1_pc_copy1_r[5]/opit_0_inv_L6Q_perm/CLK` → `u_cpu/u_core/u_frontend/u_predictor/ras_taken_r/opit_0/D` |
| P9 | 6 | -0.177 | 7–7 | 1.545 / 4.898 | `u_cpu/u_core/u_frontend/f1_pc_copy1_r[5]/opit_0_inv_L6Q_perm/CLK` → `u_cpu/u_core/u_frontend/f1_pc_copy2_r[30]/opit_0_inv/D` |
| P10 | 0 | 未取得 | | | 单组筛选无匹配 |
| 其他 | 1558 | -0.752 | 3–14 | 2.887 / 4.073 | `u_cpu/u_icache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_icache/g_valid_bank[16].valid1_bank_r[13]/opit_0_inv_L6Q_perm/I5` |

### 其他组中违例最多的五类

| 起点模块 → 终点模块 | 违例条数 | 最差 slack (ns) | 违例路径级数范围 |
|---|---:|---:|---:|
| u_frontend → u_frontend/u_ib | 475 | -0.391 | 7–8 |
| u_icache/u_tag0 → u_icache | 377 | -0.752 | 4–5 |
| u_icache/u_tag0 → u_frontend/u_ib | 305 | -0.468 | 6–8 |
| u_frontend → u_frontend | 183 | -0.681 | 7–14 |
| u_icache/u_tag0 → u_frontend | 76 | -0.307 | 5–5 |

## 与卡 60 对比

慢角 WNS 改善 1.753 ns，违例端点从 10115 减到 3896。估算 Fmax 从 109.0275 MHz 提升到 134.7891 MHz，增加 25.76 MHz（23.63%）。LUT / FF / DRM / APM / LUTRAM 的变化为 +1434 / +1232 / +0 / +0 / +0。

本轮复用卡 60 实跑的 IP 设置。两轮的 `ip_lutram_cpu_local_history` 和 `ip_lutram_cpu_tournament` 均使用 `INIT_FILE=NONE`，生成模型把两项初始化为 0。卡 60 的 IP 说明要求 tournament 从初始化文件加载 1。本轮方向表 `ip_lutram_cpu_direction` 仍加载原工程的初始化文件。

## 导出覆盖和约束

主时钟 D18 使用 3.3 V LVCMOS33。PDS 报告扫描和复位端口缺少外部延迟，本轮按独立探针约束运行。GUI 流程在时序报告完成后结束。

全局导出覆盖全部 3896 个慢角 setup 违例端点。独立导出得到 200 条 clk_sys 慢角临界正裕量路径，PDS 筛选范围为 0 到 +0.2 ns。

## 原始报告在 Windows 本地的路径

- `timing5000.rtr.gz` 压缩后 7.0 MiB，保留任务卡要求的逐级延迟、扇出和时序端点原文。
- PDS 工程和原始阶段报告位于 `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V018`。
- 5000 路径报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards61-62/62-timing5000/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 临界正裕量报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards61-62/62-near/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 压缩原文及可读明细见 `artifacts/R1/`。
- P1、P7、P8、P9、P10 和 P9 负裕量的单组原始导出位于 `G:/codex_project/EdRV32-Competition-2026/build/cards61-62/62-P*/report_timing/`。

## 未取得的项和原因

P7、P10 单组筛选未返回匹配的慢角 clk_sys setup 路径，最差 slack、级数和逐级明细记为未取得。对应 PDS 原文随报告保存。
