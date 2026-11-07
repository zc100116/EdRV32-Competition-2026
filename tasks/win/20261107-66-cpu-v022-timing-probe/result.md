# 卡 66 结果

PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，ADS。资源取布线后层次表，DRM 按 DRM36K 等效计。 CPU v0.22 + L1，RTL 提交 `3aac3e03`，clk_sys 约束 150 MHz。

| 布局布线参数 | 慢角 WNS / TNS (ns) | 违例端点数 | WHS 慢角 / 快角 (ns) | 估算 Fmax (MHz) | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---:|---:|---:|---:|---:|---:|
| 默认 P&R | -0.849 / -621.056 | 2961 | +0.063 / +0.046 | 133.0495 | 23336 / 14282 / 31 / 4 / 680 | 23065 / 13562 |

布局布线完成，用时 0h:14m:18s。慢角 WNS 距 +0.300 ns 目标差 1.149 ns。最差路径为 `u_cpu/u_core/u_frontend/f2_direction_history_r[0]/opit_0_L6Q_perm/CLK` → `u_cpu/u_core/u_frontend/g_read[1].g_slice[14].response_count_copy_r[1]/opit_0_inv/D`，逻辑 / 布线 2.243 / 4.737 ns。

## 分类（起点模块 → 终点模块）

列出违例条数最多的八类，逐级延迟和扇出见 `artifacts/R1/timing_group_worst.txt`。

| 类 | 违例条数 | 最差 slack (ns) | 级数范围 | 最差路径逻辑 / 布线 (ns) | 起点 → 终点 |
|---|---:|---:|---:|---:|---|
| u_icache/u_tag1 → u_frontend/u_ib | 869 | -0.674 | 4–6 | 2.807 / 3.798 | `u_cpu/u_icache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/entries_r[3][152]/opit_0_L6Q_perm/CE` |
| u_icache/u_tag0 → u_frontend/u_ib | 609 | -0.612 | 4–6 | 2.767 / 3.799 | `u_cpu/u_icache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_icache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/entries_r[1][153]/opit_0_L6Q_perm/CE` |
| u_dcache → u_core | 276 | -0.640 | 9–11 | 1.670 / 5.025 | `u_cpu/u_dcache/addr_r[3]/opit_0_AQ_perm/CLK` → `u_cpu/u_core/e_operand_a_r[0][12]/opit_0_L6Q_perm/RS` |
| u_dcache/u_tag0 → u_core | 267 | -0.587 | 5–10 | 2.546 / 4.059 | `u_cpu/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/e_operand_a_r[0][22]/opit_0_L6Q_perm/RS` |
| u_dcache/u_tag0 → u_frontend/u_ib | 229 | -0.469 | 6–7 | 2.531 / 4.108 | `u_cpu/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/u_frontend/u_ib/g_write_entry[1].g_slice[0].write_ptr_copy1_r[1]/opit_0_inv/D` |
| u_frontend → u_frontend | 208 | -0.849 | 6–8 | 2.243 / 4.737 | `u_cpu/u_core/u_frontend/f2_direction_history_r[0]/opit_0_L6Q_perm/CLK` → `u_cpu/u_core/u_frontend/g_read[1].g_slice[14].response_count_copy_r[1]/opit_0_inv/D` |
| u_frontend → u_frontend/u_ib | 113 | -0.465 | 6–7 | 1.761 / 4.615 | `u_cpu/u_core/u_frontend/f2_direction_history_r[0]/opit_0_L6Q_perm/CLK` → `u_cpu/u_core/u_frontend/u_ib/entries_r[1][24]/opit_0_L6Q_perm/CE` |
| u_dcache/u_tag1 → u_core | 90 | -0.235 | 5–5 | 2.515 / 3.723 | `u_cpu/u_dcache/u_tag1/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_cpu/u_core/e_branch_b_r[0][14]/opit_0_L6Q_perm/I1` |

## 与卡 64 对比

慢角 WNS 下降 0.287 ns，违例端点从 1625 增至 2961。估算 Fmax 从 138.3317 MHz 降至 133.0495 MHz，减少 5.28 MHz。LUT / FF / DRM / APM / LUTRAM 的变化为 +3624 / +1405 / +4 / +0 / +0。 PDS 层次表中，I-cache 两路数据 RAM 各由 4 增至 6 个 DRM，I-cache 合计由 9 增至 13 个 DRM。

沿用卡 64 实跑的 LUTRAM 初始化配置。`ip_lutram_cpu_local_history` 和 `ip_lutram_cpu_tournament` 使用 `INIT_FILE=NONE` 并初始化为 0。卡 60 的说明要求 tournament 从文件加载 1。`ip_lutram_cpu_direction` 加载原工程的初始化文件。

## ip_ram_icache_data 端口确认

本轮编译日志确认载入重新生成的 `ip_ram_icache_data` 和新增的 `edrv32_cpu_predecode.v`。写数据端口 `wr_data[107:0]`、读数据端口 `rd_data[107:0]`，读写地址均为 11 位（深度 2048）。IDF 启用读时钟使能，关闭字节写使能和输出寄存器。完整端口、IDF 参数和编译日志摘录见 `artifacts/R1/ip_ram_icache_data.txt`。

## 导出覆盖和约束

主时钟 D18 使用 3.3 V LVCMOS33。PDS 报告扫描和复位端口缺少外部延迟，本轮按独立探针约束运行。本轮未生成 bitstream。

全局导出覆盖全部 2961 个慢角 setup 违例端点。独立导出得到 200 条 clk_sys 慢角临界正裕量路径，PDS 筛选范围为 0 到 +0.3 ns。

## 原始报告在 Windows 本地的路径

- `timing5000.rtr.gz` 压缩后 8.0 MiB，保留任务卡要求的逐级延迟、扇出和时序端点原文。
- PDS 工程和原始阶段报告位于 `G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V018`。
- 5000 路径报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards65-66/66-timing5000/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 临界正裕量报告位于 `G:/codex_project/EdRV32-Competition-2026/build/cards65-66/66-near/report_timing/edrv32_cpu_l1_timing_probe.rtr`。
- 压缩原文及可读明细见 `artifacts/R1/`。

## 未取得的项和原因

本轮工程目录未找到 IP Compiler 的选项截图。配置以生成的 IDF 和 Verilog 端口为证据。
