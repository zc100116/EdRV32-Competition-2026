# 20261028-01-cpu-npu-synth 结果

CPU 第三轮综合、布局布线和路后时序分析完成；150 MHz setup 未收敛。
完整 NPU 的 Compile、Synthesize、Device Map 完成，PnR 在时钟布局时报 Place-0084，
未生成路后时序报告。已分别保存成功阶段报告、失败原文和缺失产物说明。

| 项 | 内容 |
|---|---|
| 输入 commit | 2960c57bfc2239f26cde219564357fcca3ba3741 |
| 输入分支 | zc100116/SOC系统设计 |
| 结果分支 | win/20261028-01-cpu-npu-synth |
| PDS | 2022.2-SP6.1 build 138931 |
| 器件 / 模式 | PG2L200H-6 FBB676 / normal |
| 日期 | 2026-10-28，Windows 本地时间 |
| A 工程 | G:/codex_project/EdRV32-FPGA/EdRV32/EdRV32.pds |
| B 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-NPU/EdRV32-NPU.pds |
| B 的 IP 来源 | 沿用 G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP/ipcore/ 的 9 个 IP |
| 完成情况 | A：A4/A5 产物完成；B：B4 PnR 失败，B5 保存已取得的报告，路后产物明确标为未取得 |

## A. CPU 第三轮

### 路后时序

| 时钟 / Corner | 周期 ns | WNS ns | TNS ns | WHS ns | THS ns | setup 违例端点 | hold 违例端点 | Fmax 推算 MHz |
|---|---|---|---|---|---|---|---|---|
| clk_sys / slow | 6.667 | −2.324 | −8602.632 | +0.143 | 0 | 9196/39621 | 0/39621 | 111.2223 |
| clk_sys / fast | 6.667 | +1.222 | 0 | +0.100 | 0 | 0/39621 | 0/39621 | 183.6547（仅 fast 角） |

Fmax 按任务卡公式 `1000 / (6.667 − WNS)` 推算；设计以 slow 角 111.2223 MHz 为限制，
不能按 fast 角频率使用。原生 Performance Summary 的 slow 值同为 111.2223 MHz，
Timing Models 为 Pre-silicon。上一轮 slow WNS −3.920 ns（约 94.5 MHz），
本轮改善 1.596 ns；TNS 从 −19583.569 ns 改善到 −8602.632 ns，
违例端点从 12645/43021 降到 9196/39621；fast 上一轮 −0.069 ns、7 个违例，本轮已无违例。

Recovery 最差 slow +2.527 / fast +4.156 ns；Removal +0.337 / +0.223 ns；
Minimum Pulse Width +2.373 / +2.678 ns，均无违例。它们的明细也已保存。
8 个未约束 IO 是 key_n_i、rst_n_i、uart_rx_i、led_o[0:3]、uart_tx_o；
未约束路径有 arrival time，但没有可用于合格判定的 slack，另存 unconstrained_io_paths.txt。

最差路径为 e_operand_a_r[0][2] → predictor ras_data_r[116] 的 CE：
19 级，逻辑延迟 2.770 ns、布线延迟 5.821 ns（67.757%），裕量 −2.324 ns。

| # | 起点 → 终点（省略 u_cpu_subsys/ 和打包后缀） | 裕量 ns | 级数 |
|---|---|---|---|
| 1 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[116]` | -2.324 | 19 |
| 2 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[117]` | -2.321 | 19 |
| 3 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[118]` | -2.321 | 19 |
| 4 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[43]` | -2.319 | 19 |
| 5 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[48]` | -2.319 | 19 |
| 6 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[36]` | -2.314 | 19 |
| 7 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[45]` | -2.314 | 19 |
| 8 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[46]` | -2.314 | 19 |
| 9 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[59]` | -2.314 | 19 |
| 10 | `u_core/e_operand_a_r[0][2]` → `u_core/u_frontend/u_predictor/ras_data_r[86]` | -2.312 | 19 |

### 六类路径 G1–G6 与分组明细

| 组 | 本轮 slow 最差裕量 ns | 级数 | 逻辑 / 布线延迟 ns | 上一轮裕量 / 级数 |
|---|---|---|---|---|
| G1 | 无此类路径（对象已匹配） | — | — | −3.920 / 24 |
| G2 | -2.324 | 19 | 2.770 / 5.821 | −3.233 / 17 |
| G3 | 无此类路径（对象已匹配） | — | — | −3.102 / 9 |
| G4 | -2.251 | 18 | 2.750 / 5.757 | −3.085 / 17 |
| G5 | +3.865 | 2 | 0.584 / 1.672 | −2.892 / 10 |
| G6 | -1.567 | 17 | 2.562 / 5.494 | — |

G1、G3 的起终点对象均匹配成功，但没有这类直接 setup 路径；
这不等同于对应模块全部通过。G6 在 packed DRM 中读地址对应 ADB*、读使能对应 CEB*，
以实际读端口查询，没有用写地址 ADA* 代替。实际过滤字符串和命令写在 setup_group_detail.txt。

slow / fast 各导出 200 条 setup，共 400 行，合并后得到 17 组（slow 10 组、fast 7 组）；
每组均另用 PDS `-from/-to` 导出最差路径，保留 slow/fast 逐级明细；此外 G1–G6 各单列。
分组条数指这 400 条样本中的数量，不代表全设计的路径总数。
打包单元名含数组下标时，按实际可匹配的实例模式导出；IP 使用对应 u_ip 子层次过滤。
初次无效过滤曾触发 STA-3016，已修正后重导，不能把 PDS 忽略过滤后返回的全局路径当作该组明细。

**正裕量危险路径单独保留**：查询 `0 < slack < 1 ns`，slow 角最差 200 条为
+0.001 至 +0.021 ns；其中 e_operand_a_r[0][2] → m_result_r[0][6] CE 仅 +0.001 ns、12 级。
这些只是极小正裕量，集成后不能按已充足收敛处理。fast 角最差 setup 为 +1.222 ns，
该范围无 fast 路径。见 setup_near_positive_top200.txt 和前 20 条逐级明细。
hold 最差 20 条逐级明细按 slow/fast 分别保留；另外附各角前 200 条索引。

### CPU 资源

| 阶段 | LUT | FF | 分布式 RAM | DRM18K / DRM36K | DRM36K 当量 | APM | IO | GPLL / PPLL |
|---|---|---|---|---|---|---|---|---|
| Synthesize | 15413 | 8355 | 231 | 4 / 24 | 26 | 4 | 9 | 0 / 0 |
| PnR 最终逻辑层次总计 | 15426 | 8369 | 231 | 原生 PRR 不再分 18K/36K | 26 | 4 | 9 | 0 / 0 |

最终逻辑 LUT 占 159800 的 9.65%，FF 占 319600 的 2.62%；DRM 占 415 的 6.27%，
APM 占 740 的 0.54%。上一轮最终为 14879 LUT、8319 FF、26 DRM 当量；
本轮 LUT +547、FF +50，DRM/APM 不变。
PRR 物理 CLMA/CLMS LUT 行描述打包物理资源，不与逻辑 LUT 总计混用。
CPU 映射高扇出：时钟 8646、u_cache_ctrl/N44 为 3807、predictor/N5893 为 1024；
最终 PRR 时钟 Clock Loads=7192，和映射阶段统计口径不同。

| 实例（父子行不能相加） | LUT | FF | 分布式 RAM | APM | DRM36K 当量 |
|---|---|---|---|---|---|
| u_cpu_subsys | 13985 | 7205 | 223 | 4 | 6 |
| u_cpu_subsys/u_cache_ctrl | 46 | 161 | 0 | 0 | 0 |
| u_cpu_subsys/u_core | 10683 | 5426 | 223 | 4 | 0 |
| u_cpu_subsys/u_core/u_csr | 1811 | 869 | 0 | 0 | 0 |
| u_cpu_subsys/u_core/u_frontend | 3933 | 2298 | 223 | 0 | 0 |
| u_cpu_subsys/u_core/u_frontend/u_ib | 1181 | 724 | 0 | 0 | 0 |
| u_cpu_subsys/u_core/u_frontend/u_predictor | 1294 | 1199 | 30 | 0 | 0 |
| u_cpu_subsys/u_dcache | 2535 | 1122 | 0 | 0 | 3 |
| u_cpu_subsys/u_icache | 721 | 496 | 0 | 0 | 3 |
| u_sys_subsys | 1440 | 1164 | 8 | 0 | 20 |
| u_sys_subsys/u_clint | 345 | 242 | 0 | 0 | 0 |
| u_sys_subsys/u_gpio | 99 | 116 | 0 | 0 | 0 |
| u_sys_subsys/u_i2c | 49 | 67 | 0 | 0 | 0 |
| u_sys_subsys/u_media_apb_async | 6 | 19 | 0 | 0 | 0 |
| u_sys_subsys/u_media_apb_bridge | 18 | 11 | 0 | 0 | 0 |
| u_sys_subsys/u_plic | 159 | 150 | 0 | 0 | 0 |
| u_sys_subsys/u_reset_ctrl | 10 | 19 | 0 | 0 | 0 |
| u_sys_subsys/u_rom | 59 | 30 | 0 | 0 | 4 |
| u_sys_subsys/u_sram | 138 | 37 | 0 | 0 | 16 |
| u_sys_subsys/u_sys_apb_bridge | 99 | 127 | 0 | 0 | 0 |
| u_sys_subsys/u_sys_apb_decoder | 69 | 0 | 0 | 0 | 0 |
| u_sys_subsys/u_sys_xbar | 183 | 137 | 0 | 0 | 0 |
| u_sys_subsys/u_sysctrl | 24 | 66 | 0 | 0 | 0 |
| u_sys_subsys/u_uart | 182 | 143 | 8 | 0 | 0 |

## B. 完整 NPU

### PnR 失败

2026-10-28 12:39:06，`Phase 1.2 Clock placement` 停止：

```text
E: Place-0084: GLOBAL_CLOCK: the driver clk_mem_i_ibuf/opit_1 fixed at IOLHR_16_1242 is unreasonable. Sub-optimal placement for a clock source and a clock buffer.
```

现有约束把 clk_mem_i 放在 B24、clk_npu_i 放在 D18；PnR 日志显示六个引脚约束均已接受，
之后 clk_mem_i 的固定 IO 驱动位置与全局时钟缓冲布局规则冲突。
Compile、Synthesize、Device Map 已完成，这次失败点是时钟物理布局；
不是前面 include 或 IP 未加入导致的语法失败，也没有资源超容量错误。
日志提到可用 PAP_CLOCK_DEDICATED_ROUTE=FALSE 降级为警告，**本轮没有应用此放宽**，
没有改 RTL、引脚、时钟约束或重新跑 PnR。

完整上下文和厂商提示见 artifacts/npu/logs/pnr_failure_excerpt.txt；
原生 .prr 只有失败前的部分信息，不作为完成布局布线后的资源或时序报告。
下一步需由协调者结合器件/板卡引脚资料确认 clk_mem 的合法时钟输入位置或时钟接入方式，
修改对应约束后重跑 PnR、report_timing，再补齐两个域的路后路径和分组。

### 路后时序与综合预估的区别

| 路后时钟 | WNS/TNS/WHS/THS | 违例端点 | Fmax |
|---|---|---|---|
| clk_npu 150 MHz | 未取得 | 未取得 | 未取得 |
| clk_mem 125 MHz | 未取得 | 未取得 | 未取得 |

未完成布线，没有 routed pnr.adf，不能判定完整 NPU 的路后裕度。
本轮 **SNR 单角综合预估**另存 timing_synthesis_estimate.txt：

| 时钟 | 周期 ns | WNS ns | TNS ns | WHS ns | THS ns | setup / hold 违例端点 | 预估 Fmax MHz |
|---|---|---|---|---|---|---|---|
| clk_npu | 6.667 | +0.107 | 0 | +0.324 | 0 | 0/81298；0/81298 | 152.4390 |
| clk_mem | 8.000 | +4.998 | 0 | +0.376 | 0 | 0/1671；0/1671 | 333.1113 |

clk_npu 综合估算只余 0.107 ns（周期的约 1.6%），距离足够的集成裕量没有实测依据；
不能把综合的 All Constraints Met 当作上板或路后通过。
上一轮仅 NPU-DP 的路后 +0.341 ns / 约 158 MHz 也不能代替本轮完整 NPU。
SNR 明确列出 npu_mem_async 为 asynchronous，两个子组分别 clk_npu / clk_mem，
setup/hold 表只列同域时钟对，综合阶段异步组已生效；路后确认尚未取得。

### NPU 资源与 IP

| 阶段 | LUT | FF | 分布式 RAM | DRM18K | DRM36K | APM | IO | GPLL / PPLL | USCM |
|---|---|---|---|---|---|---|---|---|---|
| Synthesize | 27372 | 36737 | 412 | 0 | 157 | 290 | 6 | 0 / 0 | 0（尚未插入） |
| Device Map | 27372 | 36481 | 412 | 0 | 157 | 290 | 6 | 0 / 0 | 2 |
| PnR 完成后 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |

综合占用 LUT 17.13%（27372/159800），FF 11.49%（36737/319600），
分布式 RAM 1.04%（412/39500），DRM 37.83%（157/415），APM 39.19%（290/740），
IO 1.50%（6/400）。LUT 低于规格 50K 预算；资源未超器件容量。
仅 NPU-DP 上轮为 22023 LUT、31747 FF、148 DRM、288 APM；对象和测量阶段不同，不能视为严格路后差分。
完整 NPU 新增的 9 个 DRM 在层次表中为 nonconv 的两块 scratch 共 8 个和 AXI bridge 写 FIFO 1 个；
多出的 2 APM 在 descriptor，卷积子树仍为 288 APM / 148 DRM。

9 个 IP 的模块名和包装端口集合一致，实际位宽、输出寄存器、读使能、reset 端口及
实例资源汇总见 artifacts/npu/ip_ports.md；乘法器生成 .v 的 XYREG=1、MREG=1、PREG=0。
Compile 的 include_relation.txt 已解析 10 个包装的 edrv32_build_mode.vh，CMR 列出全部 9 个 .idf。

以下层次取 **SNR**；完整层次（含 datapath 各子模块、桥下 FIFO）见 resource_hier.txt：

| 实例（父子行不能相加） | LUT | FF | 分布式 RAM | APM | DRM36K 当量 |
|---|---|---|---|---|---|
| u_npu | 27297 | 36298 | 412 | 290 | 157 |
| u_npu/u_apb_bridge | 10 | 205 | 0 | 0 | 0 |
| u_npu/u_axi_bridge | 338 | 417 | 260 | 0 | 1 |
| u_npu/u_conv | 24236 | 32445 | 143 | 288 | 148 |
| u_npu/u_conv/u_conv_write | 402 | 455 | 128 | 0 | 0 |
| u_npu/u_conv/u_datapath | 22090 | 30229 | 13 | 288 | 148 |
| u_npu/u_descriptor | 277 | 511 | 0 | 2 | 0 |
| u_npu/u_nonconv | 1300 | 1235 | 0 | 0 | 8 |
| u_npu/u_read_dma | 28 | 328 | 9 | 0 | 0 |
| u_npu/u_regs | 614 | 518 | 0 | 0 | 0 |
| u_npu/u_write_dma | 282 | 563 | 0 | 0 | 0 |
| u_reset_mem | 0 | 2 | 0 | 0 | 0 |
| u_reset_npu | 0 | 2 | 0 | 0 | 0 |

顶层本地开销（总计减 u_npu 和两个 reset_sync）为 75 LUT、435 FF，
包括串行激励和观测逻辑；工具未单独给出各 stim/obs 寄存器组的优化后资源，不能用 RTL 位宽冒充实测 FF。
映射阶段高扇出：时钟 36506，window/a4_valid_r 为 2857、a3_valid_r 为 2359；
high_fanout.txt 保存前 100 个网络和时钟/复位/CE 表，均明确为映射阶段。

## 各阶段耗时与 warning/error

计数是最终各阶段 run.log 中的 W:/E: 行数，不是独立缺陷数量；全部原文已保存在各自 logs/warnings_detail.txt。
历史导入重试的 pds.log 摘录单独标明，未混入最终流程状态。

| 对象 | 阶段 | Real | CPU | Process CPU | 峰值内存 | W 行 | E 行 |
|---|---|---|---|---|---|---|---|
| CPU | compile | 0h:0m:25s | 0h:0m:4s | 0h:0m:4s | 244 MB | 1053 | 0 |
| CPU | synthesize | 0h:1m:25s | 0h:0m:12s | 0h:0m:12s | 1,011 MB | 1551 | 0 |
| CPU | device_map | 0h:0m:17s | 0h:0m:3s | 0h:0m:3s | 629 MB | 1 | 0 |
| CPU | place_route | 0h:6m:24s | 0h:1m:29s | 0h:1m:52s | 3,303 MB | 0 | 0 |
| CPU | report_timing | 0h:0m:24s | 0h:0m:7s | 0h:0m:8s | 1,949 MB | 8 | 0 |
| NPU | compile | 0h:0m:30s | 0h:0m:4s | 0h:0m:4s | 339 MB | 1706 | 0 |
| NPU | synthesize | 0h:2m:2s | 0h:0m:29s | 0h:0m:30s | 2,432 MB | 7480 | 0 |
| NPU | device_map | 0h:0m:33s | 0h:0m:6s | 0h:0m:7s | 1,108 MB | 256 | 0 |
| NPU | place_route | 0h:0m:38s | 0h:0m:7s | 0h:0m:7s | 2,798 MB | 0 | 1 |

CPU 五阶段 Real 合计 8m55s；PnR 6m24s 中，工具子阶段为 placement 18.02s、routing 221.50s，
其中 detailed routing 172.35s、hold violation fix 26.79s。总 Real 还包含数据库/模型处理等阶段外开销，
不把 Real 减 CPU 的差值直接认定为卡死或 RTL 问题。全部 18572 个网络布线成功。
NPU 最终四阶段 Real 合计 3m43s，最后 38s 以 Place-0084 结束；不包含用户在两阶段之间的空闲时间。

主要 warning：

- Compile：CPU constant probe loop 109 行，NPU 197 行；提示来自常量传播探测，
  原文没有给出足以定位每个环路的单元链，不能只凭这句话认定业务 RTL 存在组合反馈环或证明其无害。
  IP 模板还大量出现无驱动位补 0、参数分支不可达、忽略 $display/$finish；全部保留供协调者分类。
- CPU regfile 有 2 行 Sdm-2010（Not support multi-write simultaneously for RAM registers_r），应随资源实现一并审查。
- Synthesize：CPU Public-4008 悬空实例清理 985 行，NPU 7396 行；NPU Device Map 再清理 256 行。
  不将这些数量直接等同缺失业务逻辑；零锁存器见原生 SNR。
- 两工程综合都各有 4 行 Unable to honor max fanout constraint，相关大扇出网络见各自 high_fanout.txt。
- CPU 路后 8 行未约束 IO warning；NPU 综合 4 行未约束 IO warning。测量顶层没有 IO 时序合格判定。
- CPU Device Map 的 Public-4010 是旧 .pcf 被覆盖；NPU 本轮最终错误为上述 Place-0084。

## 产物位置与复现

仓库精简产物：本任务 artifacts/cpu/ 与 artifacts/npu/。
两侧均保留 native_reports 中的 Compile .cmr/include 关系、SNR、DMR、约束检查；
CPU 另有完成后的 PRR/RTR，NPU 保存失败 PRR 和时钟布局错误摘录。
CPU 附 slow/fast 前 200 setup/hold 索引、前 20 逐级路径、17 组加 G1–G6、
正裕量危险路径、recovery/removal、高扇出。NPU 缺失的路后产物文件写明未取得和原因；
已有综合路径另以 synthesis 命名保存，避免与路后路径混淆。

完整原始日志和数据库留在：

- G:/codex_project/EdRV32-FPGA/EdRV32/{compile,synthesize,device_map,place_route,report_timing}/
- G:/codex_project/EdRV32-FPGA/EdRV32-NPU/{compile,synthesize,device_map,place_route}/
- 各工程 pds.log 为历史控制台操作记录。NPU 没有本轮 report_timing/ 路后报告。
- 独立 CPU 扩展查询：build/win/20261028-01-cpu-npu-synth/timing_cpu_200/、timing_cpu_near/、groups/。
  只读原 routed 数据库，原 FPGA 工程未被报告导出修改，没有重新布局布线。

```powershell
$pds = 'G:/Program/pango/PDS_2022.2-SP6.1/bin/pds_shell.exe'
& $pds -file "$PWD/tasks/win/20261028-01-cpu-npu-synth/src/export_cpu_timing.tcl" -work_dir "$PWD/build/win/20261028-01-cpu-npu-synth/timing_cpu_200" -project_name cpu_timing_export
& $pds -file "$PWD/tasks/win/20261028-01-cpu-npu-synth/src/export_cpu_near.tcl" -work_dir "$PWD/build/win/20261028-01-cpu-npu-synth/timing_cpu_near" -project_name cpu_near_export
C:/Python314/python.exe tasks/win/20261028-01-cpu-npu-synth/src/collect_reports.py
C:/Python314/python.exe tasks/win/20261028-01-cpu-npu-synth/src/collect_npu_failure.py
C:/Python314/python.exe tasks/win/20261028-01-cpu-npu-synth/src/export_cpu_groups.py
C:/Python314/python.exe tasks/win/20261028-01-cpu-npu-synth/src/write_result.py
```

各过滤 report_timing 命令原文位于 setup_group_detail.txt 段首。
不提交 PDS 工程、IP 生成文件、数据库、网表、bitstream 或完整 run.log。
所有单个产物均小于 2 MB；最大的 NPU warning 摘录约 1.47 MB，是保留各阶段全部 W:/E: 行所需。

## 既有导入脚本修正记录

本次结果一并回传之前按用户要求完成、尚未提交的两处脚本改动：

- CPU 根路径沿用 `file normalize ../../EdRV32-Competition-2026`，从实际 FPGA 工程目录计算，
  include 为 rtl/include 和当前工程目录。
- 完整 NPU 同样沿用上述相对根路径，`compile -include_path` 传单一 rtl/include 目录；
  原工程 12:31:46 Compile 完成，10 个包装头文件与 9 个 IP 均已解析，随后综合和映射成功。

没有修改 RTL、包装、IP 选项或约束。本轮整理只使用文件、日志和 PDS 命令行，没有操控桌面，
没有运行 Verilator/RTL 回归；Windows 测量结果由协调者在 Linux 端审查。
任务状态：CPU 测量完成（150 MHz 有违例）；NPU 本轮未通过“布局布线完成”的验收，失败证据已回传。
