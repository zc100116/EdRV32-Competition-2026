# 卡 110 结果

源码 HEAD 为 8a507b0f8430c0d434742a0f545d83d826631452。PDS 为 2022.2-SP6.1 build 138931，器件为 PG2L200H-6 FBB676。

| 工程 | 慢角 WNS / TNS (ns) | 慢角 WHS / THS (ns) | 估算 Fmax (MHz) | LUT / FF / DRM / APM / 分布式 RAM / IO | P&R 用时 |
|---|---|---|---|---|---|
| A int | 未取得 | 未取得 | 未取得 | 未取得 | Compile 失败 |
| B fma | +0.356 / 0.000 | +0.212 / 0.000 | 158.4535 | 1836 / 1070 / 0 / 2 / 0 / 9 | 1 分 4 秒 |

B 组布通 2515/2515 条网络。PDS 报告显示 6.667 ns 约束满足，快角 WNS / TNS 为 +3.043 / 0.000 ns，WHS / THS 为 +0.148 / 0.000 ns。
表中的 LUT 是 PDS 模块层次表口径，器件使用表的 CLMA 与 CLMS LUT 槽位合计 1895。FMA 头、尾各使用 1 个 APM。

## 关键段（每组最差一条）

| 工程 | 组 | 裕量 (ns) | 级数 | 逻辑 / 布线 (ns) | 起点 → 终点 |
|---|---|---:|---:|---:|---|
| B fma | E1 | +1.253 | 8 | 1.413 / 3.675 | <code>a_r[26]/opit_0_srl/CLK</code> → <code>u_fma/e1_special_r/opit_0_L5Q_perm/I2</code> |
| B fma | E2 | +1.314 | 8 | 1.413 / 3.675 | <code>a_r[26]/opit_0_srl/CLK</code> → <code>u_fma/e2_special_result_r[31]/opit_0_L6QQ_perm/I3</code> |
| B fma | E3 | +1.879 | 6 | 1.570 / 2.950 | <code>u_fma/e1_a_exp_r[3]/opit_0_AQ_perm/CLK</code> → <code>u_fma/e3_base_exp_r[8]/opit_0_AQQ_perm/CIN</code> |
| B fma | E4 | +3.463 | 2 | 0.684 / 2.121 | <code>u_fma/e3_shift_r[0]/opit_0_L5Q_perm/CLK</code> → <code>u_fma/e4_c_r[22]/opit_0_L6QL5Q_perm/I1</code> |
| B fma | E5 | +3.709 | 2 | 0.785 / 1.876 | <code>u_fma/e4_c_r[11]/opit_0_L6Q_perm/CLK</code> → <code>u_fma/e5_c_r[59]/opit_0/D</code> |
| B fma | E6 | +2.085 | 4 | 1.091 / 3.258 | <code>u_fma/u_product/u_tail/u_apm/gopapm/CLK</code> → <code>u_fma/e6_forward_count1_r[1]/opit_0_L8Q_perm/M2</code> |
| B fma | E7 | +0.850 | 5 | 1.208 / 4.312 | <code>u_fma/e6_forward_hit0_r/opit_0_L6Q_perm/CLK</code> → <code>u_fma/e7_magnitude_r[0]/opit_0_L6Q_perm/I5</code> |
| B fma | E8 | +0.356 | 9 | 2.063 / 3.981 | <code>u_fma/e7_shift_r[2]/opit_0_L5Q_perm/CLK</code> → <code>u_fma/result_o[31]/opit_0_L6Q_perm/I5</code> |
| B fma | APM 边界 | +2.085 | 4 | 1.091 / 3.258 | <code>u_fma/u_product/u_tail/u_apm/gopapm/CLK</code> → <code>u_fma/e6_forward_count1_r[1]/opit_0_L8Q_perm/M2</code> |
| B fma | APM CPO → CPI | +4.860 | 0 | 0.581 / 0.000 | <code>u_fma/u_product/u_head/u_apm/gopapm/CLK</code> → <code>u_fma/u_product/u_tail/u_apm/gopapm/PI[0]</code> |

每组最差三条和 APM 专线明细见 [segments.txt](artifacts/fma/segments.txt)。全局最差路径位于 E8。

## A 组报错

01:33:05 的首次 Compile 启动时 IP 尚未生成齐全，出现以下错误。

> E: Verilog-4072: [G:/codex_project/edrv32-card110/rtl/tech/edrv32_ram_cpu2_rf.v(line number: 17)] ip_lutram_cpu2_rf is referenced to undefined module

生成齐全后，01:33:35 和 01:34:06 两次 Compile 都通过 rtl-elaborate 和 rtl-prep，并在进入 DFF inference 后以 signal 11 退出。两次 GUI 提示相同。

> Start rtl-infer.
> Start DFF-inference.
> pds_shell received signal 11.
> E: Flow-0189: Internal error occurred.

尚未定位触发崩溃的 RTL 语句或生成 IP 内部逻辑。按任务卡在 Compile 失败处停止。

## A 组生成 IP 核对

9 个 Generate 日志均为 0 error、0 warning。以下位宽按生成后的 Verilog 声明核对，5 个初始化文件的绝对路径保存在 IDF 和生成的 Verilog 中。

| 模块 | 深度×数据位宽 | 地址位宽 | 实际端口数与包装连接 | 初始化 |
|---|---:|---:|---|---|
| ip_lutram_cpu2_rf | 32×32 | 5 | 8，全部匹配 | 关闭 |
| ip_lutram_cpu2_btb | 64×59 | 6 | 8，全部匹配 | 关闭 |
| ip_lutram_cpu2_fast | 1024×2 | 10 | 8，全部匹配 | HEX，1024 行 1 |
| ip_ram_cpu2_cache_data | 2048×32 | 11 | 10，全部匹配 | 关闭 |
| ip_ram_cpu2_cache_tag | 512×19 | 9 | 10，全部匹配 | 关闭 |
| ip_ram_cpu2_tage | 256×16 | 8 | 10，全部匹配 | HEX，256 行 0000 |
| ip_ram_cpu2_tage_train | 512×16 | 9 | 10，全部匹配 | HEX，512 行 0000 |
| ip_ram_cpu2_base | 2048×2 | 11 | 10，全部匹配 | HEX，2048 行 1 |
| ip_ram_cpu2_base_train | 4096×2 | 12 | 10，全部匹配 | HEX，4096 行 1 |

[A 组 Compile 报错与调用栈节选](artifacts/int/compile_failure.log)

## 原始报告在 Windows 本地的路径

- A 组 GUI 日志 G:/codex_project/EdRV32-FPGA/cpu2_probe_int/pds.log，最终 Compile 和堆栈 G:/codex_project/EdRV32-FPGA/cpu2_probe_int/run.log。
- B 组最终布线数据库 G:/codex_project/EdRV32-FPGA/cpu2_probe_fma/place_route/edrv32_fpga_probe_cpu2_fma_top_pnr.adf。
- B 组原始时序报告 G:/codex_project/EdRV32-FPGA/cpu2_probe_fma/report_timing/edrv32_fpga_probe_cpu2_fma_top.rtr，扩展报告 G:/codex_project/edrv32-card110/build/card110-report/report_timing/edrv32_fpga_probe_cpu2_fma_top.rtr。
- B 组布线资源报告 G:/codex_project/EdRV32-FPGA/cpu2_probe_fma/place_route/edrv32_fpga_probe_cpu2_fma_top.prr。

## 未取得的项和原因

- A 组停在 Compile，无法导出布局布线时序、资源、RAM 实际映射及高扇出报告。
- B 组时序结论覆盖 FDC 中的 clk_sys。PDS 对 seed_i 和 observe_o 给出 I/O 未加时序约束的提示。
- B 组高扇出表使用时序路径中可见的网络，另外保留 PDS 原生全局时钟扇出。
- 卡 110 的整体验收要求两份工程都完成布局布线，本轮完成 B 组。
