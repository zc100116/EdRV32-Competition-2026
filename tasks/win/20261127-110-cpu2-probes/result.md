# 卡 110 结果

第 3 轮使用源码 aafe7b7e（本地提交 92cbf02d）。器件 PG2L200H-6 FBB676，PDS 2022.2-SP6.1 build 138931，默认 P&R 参数。两份工程的请求周期均实测为 6.061 ns，PDS 显示请求频率 164.9893 MHz。

| 工程与轮次 | 约束 (ns) | 慢角 WNS / TNS (ns) | 慢角 WHS / THS (ns) | 估算 Fmax (MHz) | LUT / FF / DRM36K 等效 / APM / LUTRAM / IO | P&R 用时 |
|---|---:|---|---|---:|---|---|
| A 整数，上一轮 | 6.667 | +0.151 / 0.000 | +0.142 / 0.000 | 153.4684 | 4194 / 2676 / 26.5 / 0 / 502 / 4 | 1 分 48 秒 |
| B FMA，上一轮 | 6.667 | +0.356 / 0.000 | +0.212 / 0.000 | 158.4535 | 1836 / 1070 / 0 / 2 / 0 / 9 | 1 分 4 秒 |
| A 整数，第 3 轮 | 6.061 | +0.121 / 0.000 | +0.142 / 0.000 | 168.3502 | 4265 / 3115 / 26.5 / 0 / 534 / 4 | 1 分 40 秒 |
| B FMA，第 3 轮 | 6.061 | +0.480 / 0.000 | +0.195 / 0.000 | 179.1794 | 3111 / 1097 / 0 / 2 / 0 / 9 | 1 分 23 秒 |

LUT 取 PDS 模块层次表的顶层计数。器件表的 LUT 槽位计数见各组资源汇总。

## 165 MHz 对比

- A 组通过各阶段，布通 6703/6703 条网络。估算 Fmax 提升 14.88 MHz，LUT 增加 71，FF 增加 439，分布式 RAM LUT 增加 32。9 个 IP 沿用原配置，实装 DRM36K 16 个、DRM18K 21 个。
- B 组通过各阶段，布通 3795/3795 条网络。估算 Fmax 提升 20.73 MHz，LUT 增加 1275（69.4%），FF 增加 27，仍用 2 个 APM。
- 两组慢角 TNS、THS 均为 0。快角 WNS / WHS 分别为 A 2.517 / 0.100 ns、B 2.744 / 0.131 ns。
- A 的全局最差建立路径从 I$ tag DRM 到 <code>u_fetch/g_ib[5].ib_instr_r[3]/opit_0_L6Q_perm/CE</code>。按照任务卡的终点规则，该路径归入 Other。B 的最差建立路径仍收在 E8 结果寄存器。

## 每段最差建立路径（慢角）

| 工程 | 组 | 裕量 (ns) | 级数 | 逻辑 / 布线 (ns) | 起点 → 终点 |
|---|---|---:|---:|---:|---|
| A | RF read | +2.249 | 2 | 0.690 / 2.734 | <code>rf_id_rs_r[6]/opit_0/CLK</code> → <code>rf_id_data_r[36]/opit_0_L6Q_perm/I0</code> |
| A | ID → AGU | +4.584 | 0 | 0.213 / 0.980 | <code>id_agu_id_addr_r[14]/opit_0_AQ_perm/CLK</code> → <code>id_agu_ex_addr_r[13]/opit_0/D</code> |
| A | Fetch IB candidates | +0.211 | 6 | 2.496 / 3.032 | <code>u_fetch/g_bank[1].g_way[0].u_tag/u_ip/U_ipm2l_sdpram_ip_ram_cpu2_cache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB</code> → <code>u_fetch/g_ib[10].ib_candidates_r[4:0]_1[1]/opit_0_L6Q_perm/RS</code> |
| A | TAGE direction | +0.208 | 5 | 2.498 / 2.770 | <code>u_tage/g_table[0].g_bank[0].u_predict/u_ip/U_ipm2l_sdpram_ip_ram_cpu2_tage/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB</code> → <code>tage_f2_alternate_r[0]/opit_0_L6Q_perm/I0</code> |
| A | TAGE shadow | +0.393 | 9 | 2.193 / 3.231 | <code>u_tage/last_mask_r[1]/opit_0_L6Q_perm/CLK</code> → <code>u_tage/g_query[0].g_key[1].f2_shadow_tag_r/opit_0_L6Q_perm/I5</code> |
| A | DRM load | +1.409 | 2 | 2.119 / 2.139 | <code>u_id_agu/g_way[1].u_tag/u_ip/U_ipm2l_sdpram_ip_ram_cpu2_cache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB</code> → <code>u_id_agu/operand_data_r[21]/opit_0_L6Q_perm/I1</code> |
| A | Other | +0.121 | 6 | 2.536 / 2.926 | <code>u_fetch/g_bank[1].g_way[0].u_tag/u_ip/U_ipm2l_sdpram_ip_ram_cpu2_cache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB</code> → <code>u_fetch/g_ib[5].ib_instr_r[3]/opit_0_L6Q_perm/CE</code> |
| B | E1 | +1.653 | 5 | 1.120 / 3.036 | <code>a_r[1]/opit_0_srl/CLK</code> → <code>u_fma/e1_special_result_r[22]/opit_0_L6QL5_perm/I5</code> |
| B | E2 | +1.617 | 5 | 1.120 / 3.036 | <code>a_r[1]/opit_0_srl/CLK</code> → <code>u_fma/e2_special_r/opit_0_L6QQ_perm/I3</code> |
| B | E3 | +2.271 | 7 | 1.567 / 1.983 | <code>u_fma/e1_b_exp_r[3]/opit_0_AQ_perm/CLK</code> → <code>u_fma/e3_base_exp_r[8]/opit_0_AQQ_perm/CIN</code> |
| B | E4 | +2.902 | 2 | 0.689 / 2.073 | <code>u_fma/e3_c_r[20]/opit_0_L6QQ_perm/CLK</code> → <code>u_fma/e4_c_r[21]/opit_0_L6QL5Q1_perm/I1</code> |
| B | E5 | +3.194 | 2 | 0.724 / 1.885 | <code>u_fma/e4_right_r/opit_0_L6QQ_perm/CLK</code> → <code>u_fma/e5_c_r[57]/opit_0/D</code> |
| B | E6 | +0.503 | 21 | 2.317 / 2.962 | <code>u_fma/u_product/residue_r[0]/opit_0/CLK</code> → <code>u_fma/e6_reverse_segment_r[3]/opit_0/D</code> |
| B | E7 | +0.929 | 5 | 1.633 / 3.219 | <code>u_fma/e6_reverse_hit1_r/opit_0_L6Q_perm/CLK</code> → <code>u_fma/e7_magnitude_r[51]/opit_0_L6Q_perm/I5</code> |
| B | E8 result | +0.480 | 4 | 0.828 / 4.310 | <code>u_fma/e7_overflow_inf_r/opit_0_L6Q_LUT6DQL5_perm/CLK</code> → <code>u_fma/result_o[8]/opit_0_AL5Q_perm/I1</code> |
| B | APM boundary | +1.377 | 4 | 1.062 / 3.239 | <code>u_fma/u_product/u_tail/u_apm/gopapm/CLK</code> → <code>u_fma/e6_reverse_hit1_r/opit_0_L6Q_perm/I1</code> |
| B | APM CPO → CPI | +4.249 | 0 | 0.581 / 0.000 | <code>u_fma/u_product/u_head/u_apm/gopapm/CLK</code> → <code>u_fma/u_product/u_tail/u_apm/gopapm/PI[0]</code> |

## 详细报告及原始日志

- A 组 [时序汇总](artifacts/int/timing_summary.txt) · [建立前 200 条](artifacts/int/setup_top200.txt) · [建立前 20 条明细](artifacts/int/setup_top20_detail.txt) · [保持明细](artifacts/int/hold_top20.txt) · [分段报告](artifacts/int/segments.txt) · [资源汇总](artifacts/int/resource_summary.txt) · [资源层次](artifacts/int/resource_hier.txt) · [RAM 映射](artifacts/int/ram_mapping.txt) · [高扇出](artifacts/int/high_fanout.txt) · [实际参数](artifacts/int/settings.txt) · [阶段日志](artifacts/int/flow-excerpts.log)
- B 组 [时序汇总](artifacts/fma/timing_summary.txt) · [建立前 200 条](artifacts/fma/setup_top200.txt) · [建立前 20 条明细](artifacts/fma/setup_top20_detail.txt) · [保持明细](artifacts/fma/hold_top20.txt) · [分段报告](artifacts/fma/segments.txt) · [资源汇总](artifacts/fma/resource_summary.txt) · [资源层次](artifacts/fma/resource_hier.txt) · [高扇出](artifacts/fma/high_fanout.txt) · [实际参数](artifacts/fma/settings.txt) · [阶段日志](artifacts/fma/flow-excerpts.log)
- 原 GUI 日志、PRR、RTR 在 G:/codex_project/EdRV32-FPGA/cpu2_probe_int 和 G:/codex_project/EdRV32-FPGA/cpu2_probe_fma。按各段需求从同一 PNR 数据库将 max_path 扩到 16000。扩展报告在 G:/codex_project/edrv32-card110/build/card110-report-r3，与 GUI 汇总逐项一致。
- 保持明细包含快角和慢角各前 20 条。高扇出来自时序路径可见网络，同时附原生全局时钟扇出。报告中的 165 MHz 验证限于已约束的内部时钟。GUI 日志保留未加 I/O 时序约束的提示。
- [前两轮结果、端口核对和 Compile 崩溃记录](https://github.com/zc100116/EdRV32-Competition-2026/blob/82296504/tasks/win/20261127-110-cpu2-probes/result.md)。第 1 轮 [编译报错节选](artifacts/int/compile_failure.log) 也保留在本轮文件中。
