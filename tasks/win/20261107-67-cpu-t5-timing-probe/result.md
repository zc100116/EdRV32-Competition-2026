# 卡 67 结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。资源取布线后层次表，DRM 按 DRM36K 等效计。 CPU v0.22 + T5 + L1，检出 `54e2049d`，T5 候选 `f1e0d42f`，clk_sys 约束 150 MHz。

| 布局布线参数 | 慢角 WNS / TNS (ns) | 违例端点数 | WHS 慢角 / 快角 (ns) | 估算 Fmax (MHz) | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---:|---:|---:|---:|---:|---:|
| 默认 P&R | -0.834 / -782.109 | 2849 | +0.152 / +0.102 | 133.3156 | 22929 / 15194 / 31 / 4 / 680 | 22660 / 14473 |

布局布线完成，用时 0h:15m:29s。150 MHz 约束下慢角 setup 有违例。最差路径为 `u_cpu/u_icache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/predecode_r[3][31]/opit_0_L6Q_perm/I2`，逻辑 / 布线 2.790 / 3.995 ns。

## 分类（起点模块 → 终点模块）

列出违例条数最多的八类，逐级延迟和扇出见 `artifacts/R1/timing_group_worst.txt`。

| 类 | 违例条数 | 最差 slack (ns) | 级数范围 | 最差路径逻辑 / 布线 (ns) | 起点 → 终点 |
|---|---:|---:|---:|---:|---|
| u_icache/u_tag1 → u_frontend/u_ib | 931 | -0.832 | 4–7 | 2.339 / 4.548 | `u_cpu/u_icache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/entries_r[0][91]/opit_0_L6Q_perm/I3` |
| u_dcache/u_tag1 → u_core | 497 | -0.688 | 5–8 | 2.672 / 4.123 | `u_cpu/u_dcache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/g_registered_forward[0].g_slice[2].map_copy_r[4]/opit_0_inv/CE` |
| u_dcache/u_tag1 → u_frontend/u_ib | 397 | -0.426 | 6–7 | 2.902 / 3.774 | `u_cpu/u_dcache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/g_write_entry[3].g_slice[16].pointer_candidate_r[1][1]/opit_0_inv/D` |
| u_icache/u_tag0 → u_frontend/u_ib | 267 | -0.834 | 4–5 | 2.790 / 3.995 | `u_cpu/u_icache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/predecode_r[3][31]/opit_0_L6Q_perm/I2` |
| u_dcache → u_core | 166 | -0.784 | 8–12 | 2.269 / 4.589 | `u_cpu/u_dcache/addr_r[3]/opit_0_AQ_perm/CLK` → `u_cpu/u_core/e_branch_a_r[1][10]/opit_0_L6Q_perm/RS` |
| u_dcache/u_tag0 → u_dcache | 115 | -0.522 | 7–7 | 3.049 / 3.548 | `u_cpu/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_dcache/wb_addr_r[28]/opit_0_L6Q_perm/I4` |
| u_frontend/u_ib → u_core | 111 | -0.422 | 6–10 | 1.196 / 5.334 | `u_cpu/u_core/u_frontend/u_ib/entries_r[2][54]/opit_0_L6Q_perm/CLK` → `u_cpu/u_core/e_branch_b_r[0][26]/opit_0_L6Q_perm/RS` |
| u_core → u_dcache | 69 | -0.638 | 7–8 | 2.133 / 4.572 | `u_cpu/u_core/g_forward[2].g_select_copy[0].select_copy_r[1]/opit_0_L6QL5_perm/CLK` → `u_cpu/u_dcache/lookup_lru_bank_r[12]/opit_0_L6Q_perm/I1` |

## 与卡 64、卡 66 对比

| 任务 | 版本 | 慢角 WNS / TNS (ns) | 违例端点 | 估算 Fmax (MHz) | LUT / FF / DRM / APM / LUTRAM |
|---|---|---:|---:|---:|---:|
| 卡 64 | v0.21 | -0.562 / -224.496 | 1625 | 138.3317 | 19712 / 12877 / 27 / 4 / 680 |
| 卡 66 | v0.22 | -0.849 / -621.056 | 2961 | 133.0495 | 23336 / 14282 / 31 / 4 / 680 |
| 卡 67 | v0.22 + T5 | -0.834 / -782.109 | 2849 | 133.3156 | 22929 / 15194 / 31 / 4 / 680 |

卡 67 较卡 66 提升 0.27 MHz，违例端点减少 112 个，但 TNS 下降 161.053 ns。卡 64 比卡 67 高 5.02 MHz。按任务卡的频率判据，整片集成的冻结候选为卡 64 的 v0.21（`9fa3f649`）。

卡 67 复用卡 66 的 108 位 × 2048 I-cache 数据 IP。`ip_lutram_cpu_local_history` 和 `ip_lutram_cpu_tournament` 沿用实跑的 `INIT_FILE=NONE` 并初始化为 0。卡 60 的 IP 说明要求 tournament 从文件加载 1。`ip_lutram_cpu_direction` 加载原工程的初始化文件。

## 布线拥塞

| 轮次 | 首条通用布线迭代（编号，未布线，overused） | 通用网络收敛迭代 | 全部网络收敛迭代 | 成功 / 总网络 | 路由耗时 (s) |
|---|---|---:|---:|---:|---:|
| 64 | 2, 24289, 236992 | 241 | 242 | 26528 / 26528 | 561.08 |
| 66 | 2, 28656, 278990 | 141 | 142 | 31314 / 31314 | 533.53 |
| 67 | 2, 29119, 274400 | 288 | 289 | 31730 / 31730 | 612.16 |

卡 67 通用网络在第 288 轮达到 0 条未布线、0 项 overused，全部 31730 个网络完成布线。数据取 PDS 路由迭代日志，见 `artifacts/R1/routing_congestion.txt`。

## 导出覆盖和约束

主时钟 D18 使用 3.3 V LVCMOS33。PDS 报告扫描和复位端口缺少外部延迟，本轮按独立探针约束运行。本轮未生成 bitstream。

全局导出覆盖全部 2849 个慢角 setup 违例端点。独立导出得到 200 条 clk_sys 慢角临界正裕量路径，PDS 筛选范围为 0 到 +0.3 ns。

## 原始报告在 Windows 本地的路径

- `timing5000.rtr.gz` 压缩后 8.1 MiB，保留任务卡要求的逐级延迟、扇出和时序端点原文。
- PDS 工程和原始阶段报告位于 `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V018`。
- 5000 路径报告位于 `G:/codex_project/EdRV32-Competition-2026/build/card67/67-timing5000/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 临界正裕量报告位于 `G:/codex_project/EdRV32-Competition-2026/build/card67/67-near/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 压缩原文及可读明细见 `artifacts/R1/`。

## 未取得的项和原因

布线拥塞汇总取路由迭代日志，现有 P&R 产物中未取得空间拥塞图。
