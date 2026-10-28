# 20261028-03-cpu-sys-synth-r4 结果

CPU 第四轮 Compile、Synthesize、Device Map、PnR、Report Timing 均完成。
150 MHz slow setup 仍有违例；WNS 从上一轮 −2.324 ns 改善到 −1.789 ns，推算 Fmax 118.2592 MHz。

| 项 | 内容 |
|---|---|
| 输入 commit | 6a9cd92c26926073ff297814569a7b7d7afb5a73 |
| 结果分支 | win/20261028-03-cpu-sys-synth-r4 |
| PDS | 2022.2-SP6.1 build 138931 |
| 器件 / 模式 | PG2L200H-6 FBB676 / normal |
| 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32/EdRV32.pds |
| 测量顶层 / 约束 | edrv32_fpga_cpu_sys_top / clk_sys 6.667 ns（约 150 MHz） |
| IP | 沿用原工程 7 个 IP，本轮无新增 |
| 完成情况 | 流程及任务要求的报告、G1–G8 明细整理完成；未达到 150 MHz |

## 时序

| 时钟 / 角 | WNS ns | TNS ns | WHS ns | THS ns | setup 违例端点 | hold 违例端点 | Fmax 推算 MHz |
|---|---|---|---|---|---|---|---|
| clk_sys / slow | −1.789 | −4967.383 | +0.152 | 0 | 7611/41070 | 0/41070 | 118.2592 |
| clk_sys / fast | +1.197 | 0 | +0.101 | 0 | 0/41070 | 0/41070 | 182.8154（仅 fast 角） |

Fmax 按任务卡公式 `1000 / (6.667 − WNS)` 推算；设计取 slow 限制，不能使用 fast 角数值代替。
原生报告 Performance Summary 同为 118.2592 MHz、8.456 ns；Timing Models 为 Pre-silicon。

上一轮（20261028-01 A）：slow WNS −2.324 ns、TNS −8602.632 ns、9196/39621 端点违例，
Fmax 111.2223 MHz。本轮 WNS 改善 0.535 ns，TNS 改善 3635.249 ns，违例端点少 1585 个；
Fmax 提高约 7.04 MHz（6.33%）。两轮端点总数不同，不能把违例数量变化直接解释成等量逻辑消失。
fast setup 从 +1.222 ns 变为 +1.197 ns，仍无违例；slow/fast hold 均无违例。

| 其他时序 | slow 最差 ns | fast 最差 ns | 违例端点 |
|---|---|---|---|
| Recovery | +2.649 | +4.226 | 0/2998 |
| Removal | +0.253 | +0.174 | 0/2998 |
| Minimum Pulse Width | +2.373 | +2.678 | 0/6845 |

### 最差路径与危险正裕量路径

本轮最差路径：e_jalr_expected_odd_r[4] → predictor/ras_data_r[109] CE，
slack −1.789 ns、16 级；逻辑 2.885 ns、布线 5.267 ns（64.610%），clock skew −0.016 ns。
上一轮最差起点为 e_operand_a_r，本轮最差起点已变化；具体原文见逐级明细。

| # | 起点 → 终点（省略 u_cpu_subsys/ 和 opit 打包后缀） | 裕量 ns | 级数 |
|---|---|---|---|
| 1 | `u_core/e_jalr_expected_odd_r[4]` → `u_core/u_frontend/u_predictor/ras_data_r[109]` | -1.789 | 16 |
| 2 | `u_core/e_jalr_expected_odd_r[4]` → `u_core/u_frontend/u_predictor/ras_data_r[121]` | -1.789 | 16 |
| 3 | `u_core/e_jalr_expected_odd_r[4]` → `u_core/u_frontend/u_predictor/ras_data_r[123]` | -1.789 | 16 |
| 4 | `u_core/e_jalr_expected_odd_r[4]` → `u_core/u_frontend/u_predictor/ras_data_r[127]` | -1.789 | 16 |
| 5 | `u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_core/u_frontend/u_predictor/ras_data_r[44]` | -1.753 | 11 |
| 6 | `u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_core/u_frontend/u_predictor/ras_data_r[45]` | -1.753 | 11 |
| 7 | `u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_core/u_frontend/u_predictor/ras_data_r[42]` | -1.751 | 11 |
| 8 | `u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB` → `u_core/u_frontend/u_predictor/ras_data_r[43]` | -1.751 | 11 |
| 9 | `u_core/e_jalr_expected_odd_r[4]` → `u_core/u_frontend/u_predictor/ras_data_r[17]` | -1.745 | 16 |
| 10 | `u_core/e_jalr_expected_odd_r[4]` → `u_core/u_frontend/u_predictor/ras_data_r[18]` | -1.745 | 16 |

另用 `0 < setup slack < 1 ns` 单独导出最差 200 条 slow 正裕量路径，范围 +0.001 至 +0.019 ns；
其中 operand_b → operand_b、D$ tag → m_cause、IB read_ptr → CSR counter 等路径只有 +0.001 ns。
这些是保存样本的范围，不是设计中该区间的全量路径计数。fast setup 最差为 +1.197 ns，
该范围没有 fast 路径。危险路径索引和最差 20 条逐级明细分别保存在
setup_near_positive_top200.txt、setup_near_positive_top20_detail.txt。

8 个测量 IO（key_n_i、rst_n_i、uart_rx_i、led_o[0:3]、uart_tx_o）没有 IO 时序约束，
其路径没有 slack/pass 判定，另存 unconstrained_io_paths.txt，不能作为已通过的接口时序。

## 八类路径（G1–G8）

| 组 | 本轮 slow 最差裕量 ns | 级数 | 逻辑 / 布线延迟 ns | 上一轮裕量 / 级数 |
|---|---|---|---|---|
| G1 | -1.698 | 16 | 2.987 / 5.090 | −2.324 / 19 |
| G2 | -1.610 | 16 | 2.987 / 4.992 | −2.303 / 18 |
| G3 | -1.595 | 16 | 2.946 / 4.996 | −2.251 / 18 |
| G4 | -1.753 | 11 | 3.530 / 4.660 | −2.191 / 12 |
| G5 | -1.477 | 15 | 2.758 / 5.063 | −2.185 / 17 |
| G6 | 无此类路径 | — | — | −1.993 / 17 |
| G7 | -1.011 | 13 | 1.852 / 5.637 | — |
| G8 | -0.594 | 7 | 2.760 / 4.186 | +0.001 / 12 |

- G1–G3：e_operand_a_r 分别到 RAS、f1_cross_target_r、f1_pc_r。
- G4：两路 D$ tag RAM 到 RAS 或 f1_pc_r 的联合过滤，报告两种终点中最差的一条。
- G5：e_operand_a_r 到 I$ addr_r；G6：到 D$ dirty0_r/dirty1_r 的联合过滤。
- G7：e_operand_a_r 到 D$ 数据/tag RAM 的 CEB*、ADB*，只取读端口，不用 ADA* 写地址代替。
- G8：任意起点到 m_result_r。若无匹配路径，在明细中明确写“无此类路径”。

原报告 slow/fast setup 各 200 条，共 400 条，按寄存器主体分为 14 组；
全部另用 PDS 起终点过滤导出最差逐级路径，另加 G1–G8，共 22 组。
每组保留 slow/fast 明细、样本条数及所用命令，见 setup_group_detail.txt / setup_group_summary.txt。
去除寄存器位下标和打包后缀，保留 generate 实例；IP 内部原语按逻辑 u_ip 归组。
样本条数只来自前 200 条，不代表全设计路径总数。

## 资源

| 阶段 | LUT | FF | DRM36K 当量 | APM | 分布式 RAM | IO | GPLL / PPLL | USCM |
|---|---|---|---|---|---|---|---|---|
| PnR 最终逻辑总计 | 15204 | 8367 | 26 | 4 | 231 | 9 | 0 / 0 | 1 |
| 上一轮 PnR | 15426 | 8369 | 26 | 4 | 231 | 9 | 0 / 0 | 1 |
| 本轮相对上一轮 | −222 | −2 | 0 | 0 | 0 | 0 | 0 / 0 | 0 |

SNR 原语计数：4 个 DRM18K + 24 个 DRM36K = 26 DRM36K 当量。
本轮最终逻辑 LUT 占 159800 的约 9.51%，FF 占 319600 的约 2.62%；
DRM 26/415（6.27%），APM 4/740（0.54%），分布式 RAM 231/39500（0.58%），IO 9/400（2.25%）。
物理 CLMA/CLMS 表与逻辑 LUT 总计使用不同打包口径，按原文分别保留。
综合阶段的 Cell Usage/Mapping Summary 另存在 resource_summary.txt 和原生 SNR。

| 实例（父子行不能相加） | LUT | FF | 分布式 RAM | APM | DRM36K 当量 |
|---|---|---|---|---|---|
| edrv32_fpga_cpu_sys_top | 15204 | 8367 | 231 | 4 | 26 |
| u_cpu_subsys | 13758 | 7204 | 223 | 4 | 6 |
| u_cpu_subsys/u_cache_ctrl | 46 | 161 | 0 | 0 | 0 |
| u_cpu_subsys/u_core | 10625 | 5429 | 223 | 4 | 0 |
| u_cpu_subsys/u_core/u_csr | 1816 | 869 | 0 | 0 | 0 |
| u_cpu_subsys/u_core/u_frontend | 3869 | 2296 | 223 | 0 | 0 |
| u_cpu_subsys/u_core/u_frontend/u_ib | 1146 | 724 | 0 | 0 | 0 |
| u_cpu_subsys/u_core/u_frontend/u_predictor | 1293 | 1198 | 30 | 0 | 0 |
| u_cpu_subsys/u_dcache | 2404 | 1121 | 0 | 0 | 3 |
| u_cpu_subsys/u_icache | 683 | 493 | 0 | 0 | 3 |
| u_sys_subsys | 1445 | 1163 | 8 | 0 | 20 |
| u_sys_subsys/u_clint | 352 | 242 | 0 | 0 | 0 |
| u_sys_subsys/u_gpio | 99 | 116 | 0 | 0 | 0 |
| u_sys_subsys/u_i2c | 49 | 67 | 0 | 0 | 0 |
| u_sys_subsys/u_media_apb_async | 6 | 19 | 0 | 0 | 0 |
| u_sys_subsys/u_media_apb_bridge | 18 | 11 | 0 | 0 | 0 |
| u_sys_subsys/u_plic | 147 | 149 | 0 | 0 | 0 |
| u_sys_subsys/u_reset_ctrl | 9 | 19 | 0 | 0 | 0 |
| u_sys_subsys/u_rom | 61 | 30 | 0 | 0 | 4 |
| u_sys_subsys/u_sram | 138 | 37 | 0 | 0 | 16 |
| u_sys_subsys/u_sys_apb_bridge | 97 | 127 | 0 | 0 | 0 |
| u_sys_subsys/u_sys_apb_decoder | 69 | 0 | 0 | 0 | 0 |
| u_sys_subsys/u_sys_xbar | 192 | 137 | 0 | 0 | 0 |
| u_sys_subsys/u_sysctrl | 24 | 66 | 0 | 0 | 0 |
| u_sys_subsys/u_uart | 184 | 143 | 8 | 0 | 0 |

高扇出表保存映射前 100 个网络及 clock/reset/CE 表；映射时钟扇出 8647，
u_cache_ctrl/N44 为 3809、predictor/N5893 为 1024、frontend/N21 为 733、push_count_w[1] 为 706。
这些是 Device Map 口径，最终时钟分配表单独保留在 high_fanout.txt 中。

## 日志与耗时

| 阶段 | Real | CPU | Process CPU | 峰值内存 | W 行 | E 行 |
|---|---|---|---|---|---|---|
| compile | 0h:0m:24s | 0h:0m:2s | 0h:0m:2s | 242 MB | 1053 | 0 |
| synthesize | 0h:1m:18s | 0h:0m:20s | 0h:0m:21s | 1,016 MB | 1543 | 0 |
| device_map | 0h:0m:16s | 0h:0m:4s | 0h:0m:4s | 630 MB | 1 | 0 |
| place_route | 0h:5m:55s | 0h:1m:28s | 0h:1m:47s | 3,314 MB | 0 | 0 |
| report_timing | 0h:0m:25s | 0h:0m:6s | 0h:0m:6s | 1,981 MB | 8 | 0 |

五阶段 Real 合计 8m18s，比上一轮 8m55s 少 37s；不计用户在各阶段之间的空闲时间。
PnR 为 5m55s（上一轮 6m24s），峰值内存 3314 MB；内部各 placement/routing 子阶段耗时
保存在 logs/execution_excerpt.txt。日志所有 W:/E: 行均保存在 logs/warnings_detail.txt，
分类计数见 flow_summary.txt。上述计数是日志行数，不是独立缺陷数量。

- 最终各阶段 E: 行为 0，PnR 没有 W:/E:。
- Compile 1053 行警告，包含 109 行 constant probe loop、2 行 regfile 的 Sdm-2010
  （Not support multi-write simultaneously for RAM registers_r），其余多为生成 IP 的常量分支、
  未驱动位补零和忽略仿真 system task；完整原文保留。
- Synthesize 1543 行，其中 985 行 Public-4008 悬空实例清理、4 行 max fanout 约束无法满足；
  SNR 报告零锁存器。loop 提示本身没有给出明确反馈链，不能单独用于断言业务 RTL 组合环存在或已排除。
- Device Map 1 行 Public-4010 是旧 .pcf 被覆盖；Report Timing 8 行是上述未约束 IO。
- 历史 pds.log 的导入/重跑记录另存 project_actions_excerpt.txt，不混入本轮最终阶段状态。

## 产物与本地原始数据

精简产物位于本任务 artifacts/：时序汇总、每角前 200 setup/hold 索引、前 20 逐级路径、
14 组加 G1–G8、危险正裕量路径、recovery/removal、高扇出、资源层次、原生阶段报告和日志摘录。
你在 PDS 中已设 `-max_path 200 -input_pins true`，直接复用现有 RTR，不重跑全局时序导出。
原 RTR 约 10.95 MB，完整文件留在工程本地；回传所需索引、汇总及逐级明细，不重复提交完整大文件。

原工程：G:/codex_project/EdRV32-FPGA/EdRV32/。
完整原始日志仍位于 compile/、synthesize/、device_map/、place_route/、report_timing/ 下的 run.log；
原生 .cmr/.snr/.dmr/.prr/.rtr 也在各自目录。完整 routed 数据库和网表不入库。
补充查询在 build/win/20261028-03-cpu-sys-synth-r4/timing_cpu_near/ 与 groups/，只读取原 routed DB。

复现补充查询/汇总（仓库根目录）：

```powershell
$pds = 'G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe'
New-Item -ItemType Directory -Force "$PWD/build/win/20261028-03-cpu-sys-synth-r4/timing_cpu_near" | Out-Null
& $pds -file "$PWD/tasks/win/20261028-03-cpu-sys-synth-r4/src/export_cpu_near.tcl" -work_dir "$PWD/build/win/20261028-03-cpu-sys-synth-r4/timing_cpu_near" -project_name cpu_near
C:/Python314/python.exe tasks/win/20261028-03-cpu-sys-synth-r4/src/collect_reports.py
C:/Python314/python.exe tasks/win/20261028-03-cpu-sys-synth-r4/src/export_groups.py
C:/Python314/python.exe tasks/win/20261028-03-cpu-sys-synth-r4/src/write_result.py
```

本次 32 个精简产物合计 4.31 MB；
最大单文件 project_actions_excerpt.txt 约 0.83 MB。
没有修改 RTL、IP、约束或导入脚本，没有重新综合/布局布线，没有操控桌面或运行 RTL 仿真。
本轮测量报告采集完成；150 MHz 的 setup 收敛工作仍需继续。
