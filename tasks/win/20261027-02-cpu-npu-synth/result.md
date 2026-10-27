# 20261027-02-cpu-npu-synth 结果

CPU、NPU 的 Compile、综合、器件映射、布局布线、路后时序报告均已完成。
CPU 在 150 MHz 下仍违例；NPU 满足本轮独立顶层约束，但 setup/hold 裕度较小，不能据此保证完整 SoC 时序通过。

| 项 | 内容 |
|---|---|
| 采集时 commit | ac19178df0b10f7df19d23d6e5c7d3fea1c4cafc |
| 上游任务结论 | 8d2c16850b7592ef45ea85ff7ab71a3d8f359113，允许继续 B5–B7 |
| CPU RTL 对应版本 | 与 335bb0fddc9f3f31eb8486390ece1a584d52c9e5 一致 |
| NPU RTL 对应版本 | 与 6569f8a 的包装适配后版本一致；其后仅任务说明、报告、导入脚本变化 |
| PDS | 2022.2-SP6.1 build 138931；Pre-silicon timing models；multi corner |
| ModelSim | SE-64 2020.4 |
| 器件 | PG2L200H-6 FBB676 |
| A 工程 | G:/codex_project/EdRV32-FPGA/EdRV32/EdRV32.pds |
| B 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP/EdRV32-NPU-DP.pds |
| 约束 | 两个独立工程均为 6.667 ns、约 150 MHz |
| 完成情况 | A、B 测量及产物收集完成；未生成 bitstream、未上板、未运行多种子或 RVC=0 对照 |

PDS 原始报告不记录 Git HEAD；上表区分采集版本和源码对应版本，不把用户启动工具时的 Git HEAD 当作已由报告证明的事实。
本次只从既有 pnr.adf 导出更多路径并整理报告，没有重新运行综合/布局布线，也没有修改 RTL、IP 或约束。

## A. CPU 第二轮

### SRAM IP

实际 IP 为单口 8192×64，字地址 13 位，64 KiB；字节写使能 8 位、BYTE_SIZE=8、clk_en 开启、输出寄存器关闭、rst 接 0。
包装端口与实际 IP 一致，最终 PnR SRAM 占 16 DRM36K。端口和原始参数见 `artifacts/cpu/ip_sram_ports.md`。

### 时序

| 角 | Setup WNS ns | TNS ns | Setup 违例/总端点 | Hold WHS ns | THS ns | Hold 违例/总端点 |
|---|---:|---:|---|---:|---:|---|
| slow | -3.920 | -19583.569 | 12645/43021 | 0.143 | 0.000 | 0/43021 |
| fast | -0.069 | -0.201 | 7/43021 | 0.100 | 0.000 | 0/43021 |

工具估计频率 **94.4555 MHz**、估计周期 10.5870 ns；按任务公式 1000/(6.667−(−3.920)) 得到 94.4555 MHz。
上一轮 WNS −7.708 ns、TNS −86183.305 ns、19008/46871 个 setup 端点违例；本轮最差裕量改善 3.788 ns（计算值），但仍未达到 150 MHz。
慢角最差路径仍由 Dcache 地址寄存器到 CSR 计数器，24 级逻辑；完整起终点按 PDS 原文保留。

最差慢角 setup 前 10 条：

| # | 起点 → 终点 | Slack ns | 逻辑级数 |
|---:|---|---:|---:|
| 1 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[2][63]/opit_0_inv_AQ_perm/CIN` | -3.920 | 24 |
| 2 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[4][63]/opit_0_inv_AQ_perm/CIN` | -3.920 | 24 |
| 3 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[3][63]/opit_0_inv_AQ_perm/CIN` | -3.837 | 24 |
| 4 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[0][63]/opit_0_inv_AQ_perm/CIN` | -3.835 | 24 |
| 5 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[2][59]/opit_0_inv_AQ_perm/CIN` | -3.829 | 23 |
| 6 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[4][59]/opit_0_inv_AQ_perm/CIN` | -3.829 | 23 |
| 7 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[6][63]/opit_0_inv_AQ_perm/CIN` | -3.796 | 24 |
| 8 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[3][59]/opit_0_inv_AQ_perm/CIN` | -3.746 | 23 |
| 9 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[0][59]/opit_0_inv_AQ_perm/CIN` | -3.744 | 23 |
| 10 | `u_cpu_subsys/u_dcache/addr_r[11]/opit_0_AQ_perm/CLK` → `u_cpu_subsys/u_core/u_csr/counter_r[2][55]/opit_0_inv_AQ_perm/CIN` | -3.738 | 22 |

### 危险但未违例的路径

- 除慢、快角各 200 条最差 setup/hold 外，另导出 slack>0 且 slack<1 ns 的 setup 路径，每角 200 条。
- 这批正裕量路径慢角 +0.001～+0.030 ns、快角 +0.008～+0.831 ns，均已保存，未只保存负裕量。
- 全局快角最差 200 条 setup 中，7 条违例、193 条正裕量。
- 最差 hold：慢角 +0.143 ns、快角 +0.100 ns；最差 removal：慢角 +0.452 ns、快角 +0.307 ns。
- 8 个 IO 没有 input/output delay；其组合路径只报告到达时间，没有可用 slack。
详见 `artifacts/cpu/dangerous_paths.md`、`setup_near_positive_top200.txt` 及逐级明细。

### 资源

最终 PRR 逻辑层次：**14879 LUT、8319 FF、231 分布式 RAM、4 APM、26 DRM36K 等效、9 IO、0 GPLL、0 PPLL、1 USCM**。
综合原语计数为 4 个 DRM18K + 24 个 DRM36K，对应 26 DRM36K 等效；不能把 28 个原语当作 28 个 DRM36K。
上一轮最终 PRR 为 24441 LUT、9121 FF、39 分布式 RAM、4 APM、74 DRM；口径均为逻辑层次统计。

| 层次 | LUT | FF | 分布式 RAM | APM | DRM36K 等效 |
|---|---:|---:|---:|---:|---:|
| `edrv32_fpga_cpu_sys_top` | 14879 | 8319 | 231 | 4 | 26 |
| `u_cpu_subsys` | 13428 | 7154 | 223 | 4 | 6 |
| `u_cpu_subsys/u_cache_ctrl` | 45 | 161 | 0 | 0 | 0 |
| `u_cpu_subsys/u_core` | 10479 | 5411 | 223 | 4 | 0 |
| `u_cpu_subsys/u_core/u_csr` | 1427 | 870 | 0 | 0 | 0 |
| `u_cpu_subsys/u_core/u_frontend` | 4027 | 2306 | 223 | 0 | 0 |
| `u_cpu_subsys/u_dcache` | 2210 | 1120 | 0 | 0 | 3 |
| `u_cpu_subsys/u_icache` | 694 | 462 | 0 | 0 | 3 |
| `u_sys_subsys` | 1450 | 1165 | 8 | 0 | 20 |
| `u_sys_subsys/u_clint` | 344 | 242 | 0 | 0 | 0 |
| `u_sys_subsys/u_gpio` | 100 | 116 | 0 | 0 | 0 |
| `u_sys_subsys/u_i2c` | 49 | 67 | 0 | 0 | 0 |
| `u_sys_subsys/u_media_apb_async` | 6 | 19 | 0 | 0 | 0 |
| `u_sys_subsys/u_media_apb_bridge` | 18 | 11 | 0 | 0 | 0 |
| `u_sys_subsys/u_plic` | 163 | 151 | 0 | 0 | 0 |
| `u_sys_subsys/u_reset_ctrl` | 9 | 19 | 0 | 0 | 0 |
| `u_sys_subsys/u_rom` | 60 | 30 | 0 | 0 | 4 |
| `u_sys_subsys/u_sram` | 138 | 37 | 0 | 0 | 16 |
| `u_sys_subsys/u_sys_apb_bridge` | 98 | 127 | 0 | 0 | 0 |
| `u_sys_subsys/u_sys_apb_decoder` | 69 | 0 | 0 | 0 | 0 |
| `u_sys_subsys/u_sys_xbar` | 188 | 137 | 0 | 0 | 0 |
| `u_sys_subsys/u_sysctrl` | 24 | 66 | 0 | 0 | 0 |
| `u_sys_subsys/u_uart` | 184 | 143 | 8 | 0 | 0 |

完整层次表及器件容量、物理利用率见 `resource_hier.txt`、`resource_summary.txt` 和原生 PRR；物理 CLMA/CLMS LUT 表与逻辑层次 LUT 口径不同，不混加。

## B. NPU 数据通路

### IP 与 ModelSim

全部 9 个 IP 为 PG2L200H-6 FBB676；weight 读写 256 位；量化 low/high 均为 XYREG=1、MREG=1、PREG/INREG/OUTREG=0。
七个 RAM 的 FPGA 分支适配仅含读使能端口名和复位接 0；RTL include 引用保留原样，头文件路径由导入脚本配置。
完整端口、参数、每 IP 资源及差异见 `artifacts/npu/ip_ports.md`。

原 `check_npu_ip.do` 在 residual 同址冲突激励中 FAIL（5166 ns），原日志保留，未改成 PASS。
任务卡第 10 节已裁定：PDS SDP 同址读出值不确定，NPU 不使用该读出值，失配记为已知差异，不再阻塞。
协调者在 Linux 的数据通路 12 个用例均通过、同址读写 0 次；这是协调者回传结论，本机未重跑 Linux 测试。
本机四路独立乘法检查全部通过，每路 4026 次，打印 `PASS npu_mul_only`；B4 详细计数见附录。

### 时序及裕度

| 角 | Setup WNS ns | TNS ns | Setup 违例/总端点 | Hold WHS ns | THS ns | Hold 违例/总端点 |
|---|---:|---:|---|---:|---:|---|
| slow | 0.341 | 0.000 | 0/114062 | 0.139 | 0.000 | 0/114062 |
| fast | 2.756 | 0.000 | 0/114062 | 0.101 | 0.000 | 0/114062 |

工具估计频率 **158.0778 MHz**、估计周期 6.3260 ns；按任务公式 1000/(6.667−0.341) 得到 158.0778 MHz。
当前 Design Summary 为 All Constraints Met；慢角 setup 只剩 **+0.341 ns**，快角 hold 只剩 **+0.101 ns**。
最差 setup 已计入 0.050 ns clock uncertainty，不能把现有的 0.050 ns 当作未计入项再重复扣减。
0.341/6.667≈5.1% 是按报告数字计算的周期余量；任何额外时序损失都从这 0.341 ns 中消耗。

最差慢角 setup 前 10 条：

| # | 起点 → 终点 | Slack ns | 逻辑级数 |
|---:|---|---:|---:|
| 1 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[25].g_lane[1].u_multiply/u_apm/gopapm/X[5]` | 0.341 | 1 |
| 2 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[26].g_lane[1].u_multiply/u_apm/gopapm/X[11]` | 0.366 | 1 |
| 3 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[25].g_lane[6].u_multiply/u_apm/gopapm/X[15]` | 0.439 | 1 |
| 4 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[16].g_lane[2].u_multiply/u_apm/gopapm/X[2]` | 0.494 | 1 |
| 5 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[24].g_lane[3].u_multiply/u_apm/gopapm/X[4]` | 0.527 | 1 |
| 6 | `u_datapath/u_mac_array/g_channel[0].g_lane[7].u_multiply/u_apm/gopapm/CLK` → `u_datapath/u_mac_array/g_channel[0].g_pixel[0].r1_data_r[3][16]/opit_0_AQ_perm/CIN` | 0.532 | 4 |
| 7 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[21].g_lane[2].u_multiply/u_apm/gopapm/X[15]` | 0.544 | 1 |
| 8 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[25].g_lane[3].u_multiply/u_apm/gopapm/X[17]` | 0.577 | 1 |
| 9 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[24].g_lane[3].u_multiply/u_apm/gopapm/X[17]` | 0.579 | 1 |
| 10 | `u_datapath/u_window/a5_tag_r[48]/opit_0/CLK` → `u_datapath/u_mac_array/g_channel[23].g_lane[2].u_multiply/u_apm/gopapm/X[13]` | 0.589 | 1 |

### 需要重点关注的路径

- 最差路径是 window 的 a5_tag_r[48] → MAC APM X[5]，仅 1 级逻辑；到 APM 的一段线延迟达 **4.249 ns**。
- 同一路径另一段 term_tag_w[48] 线延迟 0.956 ns、扇出 129；两段数据连线合计 5.205 ns（计算值）。
- 导出的慢角前 200 条 setup 全为正裕量，但 **全部小于 1 ns，4 条小于 0.5 ns**。
- 快角前 200 条 hold 全部小于 0.2 ns；内部 accum → result_quant 也有 +0.101 ns，不只是观测壳层 hold 接近边界。
- removal 最差慢角 +0.488 ns、快角 +0.330 ns，也已保存逐级明细。
- 映射阶段 window a4_valid_r 扇出 2869、a3_valid_r 2358；高扇出前 100 网络及完整 CE/复位/时钟表已保存。
详见 `artifacts/npu/dangerous_paths.md`，包括内部最差 hold、setup 分布和逐级连线。

### 为什么当前通过不能保证整机上板通过

这是单时钟、0 PLL 的独立数据通路测量顶层。输入由串行移位寄存器驱动，输出经寄存器和 XOR 树折叠；真实 SoC 边界连接不同。
当前 FDC 把 27 MHz 板载输入按 150 MHz 测量目标约束，本轮不上板。真实 PLL、外设接口和跨域约束需要由完整 SoC 工程给出。
CPU、NPU、DDR、媒体等同时放进芯片后的布线拥塞、物理距离、时钟树和负载变化，本次没有测量。
NPU 的 rst_n_i、stim_i、obs_o 未设置 input/output delay，工具报告为未约束组合 IO；这些路径没有 slack，不能计作通过。
约束检查 0 error/0 warning 不等同于 IO 时序覆盖完整。整机是否收敛须由整机顶层、真实约束下的路后多角报告确认。

### 资源

最终 PRR：**22023 LUT、31747 FF、19 分布式 RAM、288 APM、148 DRM36K、0 DRM18K、4 IO、0 GPLL、0 PPLL、1 USCM**。
器件容量为 159800 LUT、319600 FF、415 DRM36K、740 APM、400 IO；完整物理利用率由原生 PRR 给出。
本次 148 DRM 与任务卡修正后的 148 基准一致；scratch 不例化，不能把它计入本次 NPU 数据通路资源。

| 层次 | LUT | FF | 分布式 RAM | APM | DRM36K 等效 |
|---|---:|---:|---:|---:|---:|
| `edrv32_fpga_npu_dp_top` | 22023 | 31747 | 19 | 288 | 148 |
| `u_datapath` | 21813 | 30320 | 16 | 288 | 148 |
| `u_datapath/u_accum` | 2689 | 3345 | 0 | 0 | 0 |
| `u_datapath/u_activation_lut` | 1 | 20 | 0 | 0 | 16 |
| `u_datapath/u_input_unpack` | 273 | 273 | 0 | 0 | 0 |
| `u_datapath/u_line_cache` | 2 | 0 | 0 | 0 | 16 |
| `u_datapath/u_mac_array` | 8003 | 8181 | 0 | 256 | 0 |
| `u_datapath/u_quant_param_store` | 8 | 480 | 0 | 0 | 8 |
| `u_datapath/u_residual_add` | 1537 | 930 | 0 | 0 | 0 |
| `u_datapath/u_residual_buffer` | 54 | 40 | 0 | 0 | 4 |
| `u_datapath/u_result_quant` | 6371 | 8946 | 0 | 32 | 0 |
| `u_datapath/u_weight_store` | 24 | 2148 | 0 | 0 | 96 |
| `u_datapath/u_window` | 2774 | 5783 | 0 | 0 | 0 |
| `u_datapath/u_writeback` | 72 | 116 | 16 | 0 | 8 |
| `u_reset_sync` | 0 | 2 | 0 | 0 | 0 |

顶层减去 u_datapath 的差额为 210 LUT、1427 FF、3 分布式 RAM（按层次行相减的计算值，含 reset_sync 和测量壳层）。
具体每个激励/观测寄存器 bank 的优化后资源未在原始 PRR 单列；RTL 宽度为 stim_r=1025、obs_r=358、l1_r=60、l2_r=10、l3_r=2、obs_bit_r=1。
这些是源码位宽，不冒充优化后资源。

## 全流程耗时与警告

下表耗时来自各最终 stage/run.log，W/E 数为相应前缀行计数；不等同于去重后的缺陷数。

| 工程 | 阶段 | Real | CPU | Process CPU | 峰值 MB | W 行 | E 行 |
|---|---|---|---|---|---:|---:|---:|
| CPU | compile | 0h:0m:25s | 0h:0m:5s | 0h:0m:5s | 242 | 1052 | 0 |
| CPU | synthesize | 0h:1m:26s | 0h:0m:14s | 0h:0m:14s | 1,027 | 1559 | 0 |
| CPU | device_map | 0h:0m:21s | 0h:0m:3s | 0h:0m:3s | 631 | 1 | 0 |
| CPU | place_route | 0h:9m:56s | 0h:1m:53s | 0h:2m:23s | 3,326 | 0 | 0 |
| CPU | report_timing | 0h:0m:26s | 0h:0m:4s | 0h:0m:5s | 1,981 | 8 | 0 |
| NPU | compile | 0h:0m:25s | 0h:0m:1s | 0h:0m:1s | 316 | 1522 | 0 |
| NPU | synthesize | 0h:1m:37s | 0h:0m:8s | 0h:0m:9s | 2,400 | 6500 | 0 |
| NPU | device_map | 0h:0m:29s | 0h:0m:3s | 0h:0m:4s | 1,014 | 256 | 0 |
| NPU | place_route | 0h:18m:55s | 0h:2m:51s | 0h:3m:24s | 3,774 | 0 | 0 |
| NPU | report_timing | 0h:0m:43s | 0h:0m:6s | 0h:0m:6s | 2,736 | 3 | 0 |

阶段 Real 相加：CPU 12m34s，NPU 22m09s（计算值，不含人工等待，也不含本次另导出扩展时序的时间）。
上一轮 CPU Compile 11m00s，本轮 25s；上一轮 compile→timing 各 action 合计 43m24s。
所有最终 action 均完成，未发现未解析模块/黑盒错误，综合报告 Total Latches=0。

### 警告说明

- CPU Compile 1052 行 W：含 108 条 constant probe loop、两条自有 RTL Sdm-2010（regfile.v:26 与 cpu_ib.v:25，多写 RAM 推断不支持）；其余分类详见 flow_summary.txt。
- NPU Compile 1522 行 W：含 112 条 constant probe loop，主要分类涉及厂商 IP 未驱动端口、存储内容未用、仿真系统任务忽略等。
- constant probe loop 是工具常量探测提示，日志没有完整信号环路径；不能仅据此证明存在 RTL 组合环，也不能一律断言无影响。
- NPU 综合的 Public-4008 有 6489 条，映射有 256 条，为具体实例 dangling 清理；未删减这些警告的原文。
- CPU 综合另有 FSM 初态编码提示、常量寄存器移除、扇出相关提示；全部 W/E 原文保存在 logs/warnings_detail.txt。
- CPU map 的唯一 W 为已有 pcf 被覆盖；两个工程 PnR 均无 W/E 行。
- 时序报告未约束 IO：CPU 8 条、NPU 3 条，端口列表和未约束路径均保留。
- constraint_check 原生报告：CPU 56 条约束、NPU 23 条约束，均为 0 error / 0 critical warning / 0 warning；与 IO timing 未约束警告含义不同。

## 保存内容与复现

本次按任务卡保存精简日志、所有最终阶段的原生报告，以及扩展路径索引和逐级明细。没有提交完整原始 run.log、PDS 工程、IP 生成目录、数据库、网表或 bitstream。
日志节选保留全部 W:/E: 行、各阶段耗时、关键执行信息；GUI 历史导入错误单独放在 project_actions_excerpt.txt，不混进最终 stage 错误计数。
原始报告和完整日志在本地项目的 compile/、synthesize/、device_map/、place_route/、report_timing/ 下。
CPU 产物位于 `artifacts/cpu/`，NPU 产物位于 `artifacts/npu/`。两套 setup/hold 均保存慢、快各 200 条，逐级各 20 条。
CPU 额外保存两角各 200 条正裕量 setup 及各 20 条明细。
全局扩展报告 CPU 共 1640 条记录、NPU 共 1300 条；CPU 正裕量过滤另 400 条。全部索引共 3340 条记录，包含不同视图的重复路径，不称为 3340 条独立路径。
其中未约束 IO 路径 CPU 40 条、NPU 12 条，slack 标为 N/A，不伪造裕量。
扩展 .rtr 全文留在 build/win/20261027-02-cpu-npu-synth/timing_cpu_200/、timing_npu_200/、timing_cpu_near/；原始默认 .rtr 入库。
扩展导出父进程出现 W: open run.log failed.，子步骤 run.log 及 .rtr 生成正常；各导出进程退出码 0，具体信息保留在 logs/timing_export_excerpt.txt。

复现命令（PowerShell，仓库根目录）：

```powershell
& 'G:\Program\pango\PDS_2022.2-SP6.1\bin\pds_shell.exe' -file tasks/win/20261027-02-cpu-npu-synth/src/export_cpu_timing.tcl -work_dir build/win/20261027-02-cpu-npu-synth/timing_cpu_200 -project_name timing_cpu_200
& 'G:\Program\pango\PDS_2022.2-SP6.1\bin\pds_shell.exe' -file tasks/win/20261027-02-cpu-npu-synth/src/export_npu_timing.tcl -work_dir build/win/20261027-02-cpu-npu-synth/timing_npu_200 -project_name timing_npu_200
& 'G:\Program\pango\PDS_2022.2-SP6.1\bin\pds_shell.exe' -file tasks/win/20261027-02-cpu-npu-synth/src/export_cpu_near_timing.tcl -work_dir build/win/20261027-02-cpu-npu-synth/timing_cpu_near -project_name timing_cpu_near
& 'C:\Python314\python.exe' tasks/win/20261027-02-cpu-npu-synth/src/collect_reports.py
```

导出读取原始 PnR 数据库，输出写入独立目录。脚本只导出报告，不改变原工程布局布线。
本次产物未包含超过数 MB 的单文件；完整原始扩展 .rtr 留在本机。

## 导入路径与包装适配记录

七个 RAM FPGA 分支将 rd_en 改为实际 rd_clk_en，并连接 wr_rst=0、rd_rst=0；行为分支和对外端口不变。
check_npu_ip.do 与 diag_npu_ram.do 的 ip_root 已与实际目录一致，没有额外路径差异。
NPU 导入脚本从 FPGA 工程目录通过 ../../EdRV32-Competition-2026 定位源码，以 compile -include_path 传入 rtl/include 和 FPGA 工程目录。
此前对 RTL include 字符串的修改已全部撤回。最终 CMR 原文包含正确 include 路径、FPGA_MODE 与 edrv32_fpga_npu_dp_top。

## 附录：历史 B4 诊断记录（第 10 节已解除阻塞）

以下保留当时的原始诊断数据。协调者随后确认全部失配由同址读写冲突解释，IP 读出不确定，NPU 不使用该读出值。


执行版本：`8fa223700974d6fba66a421559a966b8012f15df`（已 rebase 到新增诊断任务的 origin/main）。
`diag_npu_ram.do` 的 ip_root 原本即为实际路径，无须修改。检查程序、诊断程序、行为模型、IP 均未修改。
诊断进程退出码 0，先打印 `DIAG DONE`，后打印 `PASS npu_mul_only`。该退出码表示诊断执行完成，不表示 RAM 等价性通过。

命令（仓库根目录 PowerShell）：

```powershell
& 'G:\Program\modeltech64_2020.4\win64\vsim.exe' -c `
  -l 'G:/codex_project/EdRV32-Competition-2026/tasks/win/20261027-02-cpu-npu-synth/artifacts/npu/diag_npu_ram.log' `
  -do 'do G:/codex_project/EdRV32-Competition-2026/tasks/win/20261027-02-cpu-npu-synth/src/diag_npu_ram.do'
```

各 m0–m3 列为失配次数，0 才表示对应候选模型完整匹配。

| RAM | CAS_MODE | RD_OCE_EN | 冲突模式选项 | checks | collisions | m0_spec | m1_write_first | m2_oce_gated | m3_both |
|---|---|---|---|---|---|---|---|---|---|
| line | 36K | false | 无可选项 | 6002 | 525 | 428 | 310 | 2047 | 1971 |
| weight | 36K | false | 无可选项 | 6002 | 507 | 418 | 292 | 2035 | 1960 |
| quant | 36K | false | 无可选项 | 6001 | 530 | 478 | 283 | 2083 | 1948 |
| lut | 36K | false | 无可选项 | 6002 | 501 | 407 | 333 | 2063 | 1992 |
| residual | 36K | false | 无可选项 | 6001 | 519 | 443 | 313 | 2052 | 1957 |
| result | 36K | false | 无可选项 | 6002 | 552 | 460 | 315 | 2090 | 1988 |
| scratch | 36K | false | 无可选项 | 6003 | 545 | 437 | 318 | 437 | 318 |

七个 RAM 的 CAS_MODE、RD_OCE_EN 来自各 IP 的 PDS `.idf` 保存参数。另只读打开 residual 的 IP Compiler 配置界面，
确认 DRM36K、Enable rd_oce 未勾选、输出寄存器勾选、读时钟使能勾选；未保存或重新生成。
同版本 1.10 的界面定义 ui.tcl 无 Write Mode / Read First / Write First / No Change 选项，七个 `.idf` 亦无冲突模式参数。
具体路径和界面核对结果见 `artifacts/npu/ip_ports.md`。

每个 RAM 第一次 m0 失配原文（包含 edge-0..3 和 actual matches）：

```text
# diag residual first m0 mismatch time=5166000 expected=19861f335c63fbb807c42b0f56592bacd4e63ca968758dd0285d9750a8227850 actual=524ee3a4cb789e96ac53b658f3565ae6988bd0310fce171f342ce768f499a8e9
# diag residual   edge-0 we=1 wa=106 re=1 ra=180
# diag residual   edge-1 we=1 wa=387 re=1 ra=387
# diag residual   edge-2 we=1 wa=377 re=1 ra=377
# diag residual   edge-3 we=1 wa=455 re=1 ra=288
# diag residual   actual matches m1=1 m2=0 m3=1

# diag result first m0 mismatch time=5256000 expected=775bf9ee382dcb7018dcdb31f94b54f2c6fd5a8d8fb66c1fc435da88b448aa68b6bef86dffd7a8ff7a42edf4381ef7707785edef6e74e9dc4a9d8b954a028594 actual=1e401d3c9690e42dd0efdaa15652cdac20836d4120db1f418bebf817fd7528fa1138d92283ae4e0799f90633f72fdaee39137b722ae3e555ceae849de11d30c2
# diag result   edge-0 we=0 wa=144 re=0 ra=422
# diag result   edge-1 we=1 wa=270 re=1 ra=270
# diag result   edge-2 we=1 wa=41 re=0 ra=24
# diag result   edge-3 we=1 wa=180 re=1 ra=267
# diag result   actual matches m1=1 m2=0 m3=0

# diag scratch first m0 mismatch time=5286000 expected=15932f2bec9b08d95e6543bcfd6ba4fa0942c91295c0a02b51f051a321019942 actual=3ab58d75c733568e756c2deab05fd460ee35f2dc6e893fddb8660870dffee6bf
# diag scratch   edge-0 we=1 wa=340 re=1 ra=340
# diag scratch   edge-1 we=1 wa=384 re=0 ra=384
# diag scratch   edge-2 we=0 wa=128 re=1 ra=212
# diag scratch   edge-3 we=0 wa=354 re=1 ra=250
# diag scratch   actual matches m1=1 m2=0 m3=1

# diag quant first m0 mismatch time=5376000 expected=b2c7de652cc46759 actual=ce318c9c2d946b5b
# diag quant   edge-0 we=0 wa=32 re=1 ra=217
# diag quant   edge-1 we=1 wa=202 re=1 ra=202
# diag quant   edge-2 we=0 wa=341 re=1 ra=404
# diag quant   edge-3 we=0 wa=355 re=1 ra=355
# diag quant   actual matches m1=1 m2=0 m3=1

# diag weight first m0 mismatch time=5506000 expected=238f0147bc33f6784dfd719bc26ad684f0e788e132977b65ad4d105ac049be80 actual=aff4845fd54494aad6f76ead21289b423706496ea8931a518fe5f81fdf3bc2be
# diag weight   edge-0 we=0 wa=214 re=1 ra=411
# diag weight   edge-1 we=1 wa=381 re=1 ra=381
# diag weight   edge-2 we=0 wa=502 re=1 ra=502
# diag weight   edge-3 we=0 wa=511 re=1 ra=0
# diag weight   actual matches m1=1 m2=0 m3=1

# diag line first m0 mismatch time=10356000 expected=499d279312a6c7252bb29b57a7fd104f6f1805de32278b64b532506af63514ec actual=23c2c7474b38f396121c9b248e5c941c47291b8e2bedd7571600112caed02c5d
# diag line   edge-0 we=0 wa=28 re=1 ra=1023
# diag line   edge-1 we=1 wa=812 re=1 ra=812
# diag line   edge-2 we=0 wa=72 re=1 ra=532
# diag line   edge-3 we=0 wa=644 re=1 ra=234
# diag line   actual matches m1=1 m2=0 m3=1

# diag lut first m0 mismatch time=41576000 expected=4f actual=25
# diag lut   edge-0 we=0 wa=4015 re=0 ra=4015
# diag lut   edge-1 we=1 wa=2670 re=1 ra=2670
# diag lut   edge-2 we=0 wa=4095 re=1 ra=0
# diag lut   edge-3 we=1 wa=4095 re=1 ra=0
# diag lut   actual matches m1=1 m2=0 m3=0

```

乘法器独立检查：两路 INT8 各 4026 次，quant_low 4026 次，quant_high 4026 次；`PASS npu_mul_only`。

诊断结论：七个 RAM 均不完全匹配任何一个候选模型。七个首次 m0 失配均匹配 m1（写优先），
但整段激励的 m1 仍有 283–333 次失配；因此不能将实际行为定为单一写优先，也不能归因为输出寄存器门控。
以上为当时诊断观察；最终以任务卡第 10 节的协调者结论为准，已解除阻塞。

补充测量范围：scratch 不由当前 datapath 例化；本轮资源比较基准按新任务卡改为 148 DRM。
