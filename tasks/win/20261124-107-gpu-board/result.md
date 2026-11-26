# 卡 107 结果

## 第 10 轮 Device Map 结果

| 项 | 内容 |
|---|---|
| 实测版本 | 本地 `74c53048`，RTL 与任务卡 `bfaa8a41` 一致 |
| 环境 | Windows PDS 2022.2-SP6.1 build 138931，ADS 综合，Logos2 PG2L200H-6 FBB676 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 阶段用时 | Compile 通过（2 分 25 秒），Synthesize 通过（9 分 57 秒），Device Map 通过（2 分 02 秒） |
| 布线门槛 | `clk_gpu` 综合估算 **166.0689 MHz**，WNS **−0.466 ns**，满足本轮 150 MHz 门槛 |
| 范围 | 北京时间 2026-11-26 22:43:14 采集。本次回传截至 Device Map。 |

三个阶段的日志均无 `E:` 行。[阶段日志](artifacts/round10/flow-excerpts.log)

### Device Map 资源

| 资源 | 第 9 轮用量 | 第 10 轮用量 | 容量 | 第 10 轮 PDS 占用 |
|---|---:|---:|---:|---:|
| LUT | 116,167 | 103,239 | 159,800 | 65% |
| FF | 174,211 | 157,260 | 319,600 | 50% |
| DRM（36K 等效） | 254 | 250 | 415 | 61% |
| APM | 243 | 236 | 740 | 32% |
| 分布式 RAM | 11,974 | 12,145 | 39,500 | 31% |
| I/O | 115 | 115 | 400 | 29% |
| GPLL | 7 | 7 | 10 | 70% |
| PPLL | 2 | 2 | 10 | 20% |

相较第 9 轮，LUT 少 **12,928**、FF 少 **16,951**、DRM 少 **4**、APM 少 **7**。综合层次中，GPU 使用 66,944 LUT、126,731 FF，`u_mem` 使用 3,559 LUT、4,034 FF，`u_disp` 使用 1,671 LUT、2,168 FF。GPU、mem、DISP 的子模块在层次表中单列。[Device Map 资源原文](artifacts/round10/resource_summary.txt) · [完整综合层次表](artifacts/round10/resource_hier.txt)

### 综合预估时序

| 时钟域 | 估算 MHz | WNS（ns） | TNS（ns） | WHS（ns） | THS（ns） |
|---|---:|---:|---:|---:|---:|
| `clk_gpu` | 166.0689 | −0.466 | −121.927 | 0.324 | 0.000 |
| `clk_sys` | 115.3659 | −0.668 | −79.536 | 0.324 | 0.000 |
| `clk_mem` | 102.7644 | −1.731 | −85.775 | −0.006 | −0.942 |
| `clk_aud` | 276.6247 | 77.765 | 0.000 | 0.619 | 0.000 |

GPU 综合估算从 **153.6182 MHz** 提升至 **166.0689 MHz**。全设计汇总 WNS **−1.731 ns** 对应 `clk_mem`。综合报告包含 200 个不同端点的 GPU setup 路径，slack 从 −0.466 ns 到 −0.141 ns。最差路径为 `u_write_dma/alloc_ptr_r/CLK` 到 `u_write_dma/g_keep[1].first_keep_r[24]/D`，5 逻辑级。[所有时钟域时序](artifacts/round10/timing_summary.txt) · [GPU 最差 200 条 setup 路径](artifacts/round10/setup_top200_clk_gpu.txt) · [前 20 条逐级明细](artifacts/round10/setup_top20_detail.txt)

### 高扇出

综合报告记录 1,880 组控制集，`maximum fanout` 为 36,097，对应控制集表的单独时钟项 `CLK(clk_gpu_w)`。Device Map 中 `ntclkbufg_0` 为 GPU 全局时钟网，扇出 137,957。Other 表中的 GPU 非时钟网包括 `u_setup/control_enable_w[0]`（1,750）、`u_geometry/u_project/pipeline_enable_w[5]`（1,585）和 `u_texture/address_slot_0_r_d5_r[1]`（1,573）。[Clock、Reset、CE、Other 原表](artifacts/round10/high_fanout.txt)

原始阶段报告和日志快照存于 `G:/codex_project/edrv32-card107/build/card107-pds-check/logbackup/round10-device-map-20261126-224314`。

### 第 10 轮布局与布线进度

截至 **2026-11-26 23:06:38（北京时间）**，布局已完成，通用布线最新完成到 **第 11 轮**。PDS 日志最近写入时间为 23:05:20。本次覆盖全部已经写入日志的轮次，尚无本轮 P&R 结束记录或布线后时序。[布局阶段日志](artifacts/round10/placement-excerpts.log) · [布线日志](artifacts/round10/route-progress.log)

PDS 报告布局用时 **92.39 秒**，预布线用时 **86.124 秒**，时钟网在第 **5** 轮全部布通。布局结束的全设计 `Worst slack` 为 `-2394`，`TNS` 为 `-9124844`（PDS 日志原值）。[布局时钟资源](artifacts/round10/placement-clock-utilization.txt)

| 通用布线迭代 | PDS `MT total route time`（秒） | 未布网 | `overused` |
|---:|---:|---:|---:|
| 7 | 23.130 | 171,514 | 1,181,958 |
| 8 | 29.039 | 155,564 | 984,069 |
| 9 | 51.248 | 141,765 | 807,525 |
| 10 | 122.441 | 130,645 | 687,674 |
| 11 | 224.394 | 122,209 | 603,127 |

同为通用布线第 11 轮，第 9 轮用时 2,016.117 秒、未布网 161,152、`overused` 965,636，第 10 轮对应为 224.394 秒、122,209 条和 603,127。本轮最终收敛结果仍待布线结束。

PDS 布线日志已报告迭代的计数原值随附件上传。当前 P&R 日志未见 `E:` 行。[拥塞与轮次摘要](artifacts/round10/route-congestion.txt)

原始快照保存在 `G:/codex_project/edrv32-card107/build/card107-pds-check/logbackup/round10-pnr-20261126-230638`。

## 第 9 轮资源、时序与布局快照

| 项 | 内容 |
|---|---|
| 实测版本 | 本地 `1f540308`，RTL 与任务卡 `4426bf9e` 一致 |
| 环境 | Windows PDS 2022.2-SP6.1 build 138931，ADS 综合，Logos2 PG2L200H-6 FBB676 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 阶段用时 | Compile 通过（2 分 33 秒），Synthesize 通过（10 分 27 秒），Device Map 通过（2 分 19 秒） |
| 布线门槛 | `clk_gpu` 综合估算 **153.6182 MHz**，WNS **−0.954 ns**，满足本轮 150 MHz 门槛（WNS ≥ −1.11 ns） |
| 截取状态 | 北京时间 2026-11-26 17:29:05。P&R 于 17:27:15 启动，截取时在第 1 次全局布局。最终布线耗时、拥塞和布线后时序未取得。 |

截至快照，Compile、Synthesize、Device Map 和 P&R 日志均无 `E:` 行。[阶段日志](artifacts/round9/flow-excerpts.log)

### Device Map 资源

| 资源 | 第 8 轮用量 | 第 9 轮用量 | 容量 | 第 9 轮 PDS 占用 |
|---|---:|---:|---:|---:|
| LUT | 107,291 | 116,167 | 159,800 | 73% |
| FF | 185,127 | 174,211 | 319,600 | 55% |
| DRM（36K 等效） | 332 | 254 | 415 | 62% |
| APM | 217 | 243 | 740 | 33% |
| 分布式 RAM | 5,999 | 11,974 | 39,500 | 31% |
| I/O | 115 | 115 | 400 | 29% |
| GPLL | 7 | 7 | 10 | 70% |
| PPLL | 2 | 2 | 10 | 20% |

相较第 8 轮，DRM 少 **78** 块，FF 少 **10,916** 个，LUT 多 **8,876** 个，分布式 RAM 多 **5,975** 个，APM 多 **26** 个。综合层次报告显示，GPU 的 DRM 从 **269.5** 降到 **191.5**，其中 `u_perspective` 从 **25** 降到 **1**，`u_setup` 从 **33.5** 降到 **1**。[Device Map 资源原文](artifacts/round9/resource_summary.txt) · [GPU 各子模块及完整综合层次表](artifacts/round9/resource_hier.txt)

`ip_lutram_gpu_table` 生成结果为 0 错误、0 警告，实际 8 个端口与包装一致。确认 **64 × 72、组合读、输出不寄存、无初始化**。综合层次表记录 220 个该 IP 的实现实例，合计 7,467 个分布式 RAM LUT。[IP 生成记录、参数和端口](artifacts/round9/ip_lutram_gpu_table.txt)

### 综合预估时序

| 时钟域 | 估算 MHz | WNS（ns） | TNS（ns） | WHS（ns） | THS（ns） |
|---|---:|---:|---:|---:|---:|
| `clk_gpu` | 153.6182 | −0.954 | −1759.131 | 0.324 | 0.000 |
| `clk_sys` | 116.6444 | −0.573 | −83.752 | 0.324 | 0.000 |
| `clk_mem` | 109.2061 | −1.157 | −69.531 | −0.006 | −0.942 |
| `clk_aud` | 276.6247 | 77.765 | 0.000 | 0.619 | 0.000 |

`clk_gpu` 综合估算由第 8 轮的 **114.9311 MHz** 提升至 **153.6182 MHz**，全设计汇总 WNS **−1.157 ns** 对应 `clk_mem`。原 GUI 综合报告已包含 200 条 GPU setup 路径，核对为 200 个不同端点，slack 从 −0.954 ns 到 −0.557 ns。最差路径从 `u_soc/u_gpu/u_core/sample_quad_select_r/CLK` 到 `u_soc/u_gpu/u_core/u_texture/g_lod[0].amount_r[1]/D`，9 逻辑级。[所有时钟域时序](artifacts/round9/timing_summary.txt) · [GPU 最差 200 条 setup 路径](artifacts/round9/setup_top200_clk_gpu.txt) · [前 20 条逐级明细](artifacts/round9/setup_top20_detail.txt)

### 高扇出

综合报告记录 2,257 组控制集，`maximum fanout` 为 37,705，对应控制集表的单独时钟项 `CLK(clk_gpu_w)`。Device Map 的 GPU 全局时钟网 `ntclkbufg_0` 扇出为 150,511。Other 表中 GPU 的 `u_geometry/project_input_ready_w` 为 3,002，`u_setup/enable_w` 为 2,097。[Clock、Reset、CE、Other 原表](artifacts/round9/high_fanout.txt)

原始日志和报告快照存于 `G:/codex_project/edrv32-card107/build/card107-pds-check/logbackup/round9-20261126-172905`。

### 第 9 轮最终布局布线结果

P&R 于 2026-11-26 20:18:20（北京时间）以 `Route-0039` 和 `Route-0008` 结束。通用布线第 11 轮耗时 **2,016.117 秒**，超过单轮 2,000 秒上限，当轮报告 **161,152 条未布网**、`overused` **965,636**。工具另有 `Total net: 224179, route succeed net: 117774` 的结束统计，其口径与迭代计数分别保留。[逐轮拥塞摘要](artifacts/round9/route-congestion.txt) · [失败日志原文](artifacts/round9/final-route.log)

| 阶段 | PDS 用时 |
|---|---:|
| Compile | 2 分 33 秒 |
| Synthesize | 10 分 27 秒 |
| Device Map | 2 分 19 秒 |
| Place | 1,363.02 秒 |
| Route（失败） | 6,838.25 秒 |
| P&R 阶段墙钟合计 | 2 小时 51 分 06 秒 |

布局结束时，PDS 的全局 `Worst slack` 为 `-2358`、`TNS` 为 `-6274897`（路由日志原值）。布线后各时钟域 WNS/TNS/WHS/THS、clk_gpu 最差路径、比特流及上板结果未取得。可用的各时钟域数据是本轮综合估算。[综合时序](artifacts/round9/timing_summary.txt)

原始最终 P&R 日志、失败资源报告和未布网清单已备份到 `G:/codex_project/edrv32-card107/build/card107-pds-check/logbackup/before-round10/place_route`。

## 第 8 轮 Device Map 结果

| 项 | 内容 |
|---|---|
| 实测版本 | 本地 `18a9395f`，RTL 与任务卡 `38095a12` 一致 |
| 环境 | Windows PDS 2022.2-SP6.1 build 138931，ADS 综合，Logos2 PG2L200H-6 FBB676 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 阶段与用时 | Compile 通过（3 分 33 秒），Synthesize 通过（15 分 37 秒），Device Map 通过（2 分 16 秒） |
| 布线门槛 | `clk_gpu` 综合估算 **114.9311 MHz**，WNS **−3.145 ns**，低于第 8 轮要求的 150 MHz（WNS ≥ −1.11 ns） |
| 采集状态 | 北京时间 2026-11-26 15:05:17。日志显示 15:00:46 已启动 P&R，采集时处于布局，未取得本轮布线后报告。 |

[阶段日志](artifacts/round8/flow-excerpts.log)

### Device Map 资源

| 资源 | 第 7 轮用量 | 第 8 轮用量 | 容量 | 当前 PDS 占用 |
|---|---:|---:|---:|---:|
| LUT | 117,864 | 107,291 | 159,800 | 68% |
| FF | 148,974 | 185,127 | 319,600 | 58% |
| DRM（36K 等效） | 343 | 332 | 415 | 80% |
| APM | 227 | 217 | 740 | 30% |
| 分布式 RAM | 6,328 | 5,999 | 39,500 | 16% |
| I/O | 115 | 115 | 400 | 29% |
| GPLL | 7 | 7 | 10 | 70% |
| PPLL | 2 | 2 | 10 | 20% |

与第 7 轮相比，LUT 少 10,573、DRM 少 11、APM 少 10，FF 多 36,153。综合层次表显示 `u_geometry` 的 FF 从 19,135 增至 40,215，`u_setup` 从 6,317 增至 30,988；`u_perspective` 从 24,407 降至 13,479，DRM 从 41 降至 25，APM 从 16 降至 8。[Device Map 资源原文](artifacts/round8/resource_summary.txt) · [综合层次资源表](artifacts/round8/resource_hier.txt)

### 综合预估时序和高扇出

| 时钟域 | 估算 MHz | WNS（ns） | TNS（ns） |
|---|---:|---:|---:|
| `clk_gpu` | 114.9311 | −3.145 | −10849.357 |
| `clk_sys` | 115.7130 | −0.642 | −82.148 |
| `clk_mem` | 118.7790 | −0.419 | −15.351 |
| `clk_aud` | 276.6247 | 77.765 | 0.000 |

`clk_gpu` 综合估算从第 7 轮的 50.2539 MHz 提升至 114.9311 MHz。补跑时复用第 8 轮的 Compile ADF 和原 FDC，在独立 G 盘目录执行 ADS 综合，设置 `-max_path 200 -nworst 1 -clock_group_limit {clk_gpu}`。PDS 输出并核对了 200 条同域 setup 路径及 200 个不同端点，slack 从 −3.145 ns 到 −2.266 ns。最差路径仍为 `u_geometry/u_project/N788_m1/CLK` 到 `N788_m4/Z[19]`，11 逻辑级。时序和综合资源数字与原 GUI 综合报告一致。[全部时钟域估算](artifacts/round8/timing_summary.txt) · [GPU 最差 200 条 setup 路径](artifacts/round8/setup_top200_clk_gpu.txt) · [GPU 前 20 条逐级明细](artifacts/round8/setup_top20_detail.txt) · [补跑结果对照](artifacts/round8/setup_export_comparison.txt)

综合报告记录 2,110 组控制集，`maximum fanout` 为 35,549，对应控制集表中的 `CLK(clk_gpu_w)` 单独时钟项。Device Map 的全局 GPU 时钟网 `ntclkbufg_0` 扇出为 155,587。Other 表中 GPU 非时钟信号包括 `u_palette/g_current[0].u_ram/rd_en_r`（2,592）和 `u_geometry/polygon_accept_w`（2,129）。Reset、CE 和 Other 三张原表均已回传。[高扇出报告](artifacts/round8/high_fanout.txt)

原始日志和报告快照存于 `G:/codex_project/edrv32-card107/build/card107-pds-check/logbackup/round8-device-map-20261126-150517`。

## 第 7 轮进度快照

| 项 | 内容 |
|---|---|
| 截取时间 | 2026-11-25 21:00:47（北京时间） |
| 实测代码 | 本地 `574b1e39`，RTL 与任务卡 `1ff65121` 一致 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 工具与器件 | PDS 2022.2-SP6.1 build 138931，ADS 综合，Logos2 PG2L200H-6 FBB676 |
| 状态 | Compile、Synthesize、Device Map 和布局已完成。通用布线最新完成到第 12 轮，仍有 120,352 条网未布。 |

### 流程用时和布线进度

| 阶段 | 结果 | 用时 |
|---|---|---:|
| Compile | 完成 | 2 分 22 秒（阶段墙钟） |
| Synthesize | 完成 | 14 分 04 秒（阶段墙钟） |
| Device Map | 完成，第 5 轮的 FF 超限告警未再出现 | 2 分 57 秒（阶段墙钟） |
| Place | 完成 | 327.86 秒（PDS `Total placement takes`） |
| Route | 进行中，时钟网在第 4 轮全部布通 | 总用时未取得，`Pre route` 为 98.673 秒 |

P&R 于 19:44:56 开始。截取时最近一次日志写入为 20:58:56，PDS Shell 进程仍在。各阶段的现有日志均无 `E:` 行。布局日志记录了 `Place-2039`，涉及 `clk_i_ibuf/opit_1` 与 `u_pll_sys/u_gpll/gpll_inst` 的站点不兼容，工具随后完成布局并进入布线。[阶段用时与错误行](artifacts/round7/flow-excerpts.log) · [布局与布线原文](artifacts/round7/route-progress.log)

| 通用布线迭代 | 未布网 | `overused` | PDS `MT total route time`（秒） |
|---:|---:|---:|---:|
| 6 | 196,009 | 1,492,533 | 32.741 |
| 7 | 184,204 | 1,289,628 | 45.550 |
| 8 | 173,990 | 1,106,242 | 95.329 |
| 9 | 164,899 | 975,239 | 240.252 |
| 10 | 158,071 | 886,395 | 314.284 |
| 11 | 133,321 | 783,027 | 794.134 |
| 12 | 120,352 | 682,056 | 1311.289 |

未布网和超用计数均在下降，每轮报告的耗时持续上升。最终布线结果、拥塞图和 P&R 总用时未取得。[布线进度原文](artifacts/round7/route-progress.log)

### 资源和新 IP

| Device Map 资源 | 用量 | 容量 | PDS 占用 |
|---|---:|---:|---:|
| LUT | 117,864 | 159,800 | 74% |
| FF | 148,974 | 319,600 | 47% |
| DRM（36K 等效） | 343 | 415 | 83% |
| APM | 227 | 740 | 31% |
| Distributed RAM | 6,328 | 39,500 | 17% |
| I/O | 115 | 400 | 29% |
| GPLL | 7 | 10 | 70% |
| PPLL | 2 | 10 | 20% |

Device Map 的 FF 比第 5 轮 DRC 计数少 **171,866（53.57%）**。同口径的综合 FF 从 320,874 降到 149,008。GPU 层次从 286,085 降到 114,219 FF，其中 `u_perspective` 从 161,622 降到 24,407 FF，APM 从 48 降到 16；`u_raster` 从 51,448 降到 27,201 FF。综合报告的控制集从 1,544 增至 1,901，`maximum fanout` 从 156,088 降至 39,816。[Device Map 资源表](artifacts/round7/resource_summary.txt) · [综合层次资源表](artifacts/round7/resource_hier.txt)

`ip_ram_gpu_delay` 于 19:25 生成成功，0 错误、0 警告。实际 10 个端口与包装一致，数据 72 位、地址 9 位，读时钟使能开启、输出寄存器关闭、无初始化。综合层次共找到 51 个该 IP 的 DRM36K 实例，每个用 1 块。[IP 日志、参数、端口和综合实例计数](artifacts/round7/ip_ram_gpu_delay.txt)

### 当前时序

下表为 ADS 综合后、布局前的 Slow Corner 同域时序，单位 ns。

| 时钟域 | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|
| `clk_gpu` | −14.342 | −67269.698 | 0.324 | 0.000 |
| `clk_sys` | −0.526 | −59.608 | 0.324 | 0.000 |
| `clk_mem` | −0.402 | −18.440 | −0.006 | −0.942 |
| `clk_aud` | 77.765 | 0.000 | 0.619 | 0.000 |

综合报告列出 3 条 `clk_gpu` setup 路径，均为 −14.342 ns、41 逻辑级，从 `u_setup/g_attribute[1].value_r_1/CLKB` 到 `u_setup/u_plane/N156_m2/Y[9]`、`Y[10]`、`Y[11]`。布线后时序、`clk_gpu` 最差 200 条 setup 路径和最差 20 条明细待 P&R 完成。比特流和上板结果未取得。[综合时序汇总](artifacts/round7/timing_summary.txt) · [3 条 GPU setup 路径明细](artifacts/round7/synthesis-clk_gpu-setup.txt)

Windows 上保留了这次快照的原始日志和报告，目录为 `G:/codex_project/edrv32-card107/build/card107-pds-check/logbackup/round7-20261125-210047`。

## 第 5 轮及更早记录

| 项 | 内容 |
|---|---|
| 当前状态 | 第 5 轮 Compile 和 Synthesize 完成，Device Map 因 FF 超出容量报 `DRC-0018` |
| 实测代码 | 本地 HEAD `fd019a94`，RTL 与任务卡提交 `7bb2560e` 一致，包含 `ba1ab19f` 的 8 个 RTL 文件修复 |
| 测试时间 | 2026-11-24，Windows PDS 日志时间 22:09–22:35（北京时间） |
| PDS 版本 | Windows PDS 2022.2-SP6.1 build 138931，ADS 综合 |
| 器件 | Logos2 PG2L200H-6 FBB676 |
| 工程 | `G:/codex_project/EdRV32-FPGA/board_gpu/board_gpu.pds` |
| 输入 | 顶层 `edrv32_fpga_board_gpu_top`、宏 `FPGA_MODE`、GPU 专用 FDC、原工程 IP |

### 第 5 轮流程结果

| 阶段 | 结果 | 墙钟用时 | 进程 CPU 用时 | 峰值内存池 |
|---|---|---:|---:|---:|
| Compile | 完成，`rtl-infer` 通过，本轮无 `E:` 行 | 2 分 55 秒 | 16 秒 | 924 MB |
| Synthesize | 完成，报告寄存器超限警告 | 20 分 13 秒 | 6 分 30 秒 | 5,080 MB |
| Device Map | `DeviceMap-2003`、`DRC-0018`，容量检查失败 | 2 分 33 秒 | 55 秒 | 4,357 MB |
| Place、Route | 未开始 | 未取得 | 未取得 | 未取得 |

第 4 轮在 19 秒时因 `Sdm-4000` 中止。第 5 轮未复现该错误，也未见之前的内部崩溃或多驱动错误。Device Map 使用 320,840 个 FF，器件提供 319,600 个，**超出 1,240 个，约 0.39%**。[阶段日志及全部错误行](artifacts/round5/flow-excerpts.log)

### 资源

| 资源 | 综合用量 | 器件容量 | 占用 |
|---|---:|---:|---:|
| LUT | 141,214 | 159,800 | 88.37% |
| FF | 320,874 | 319,600 | 100.40% |
| LUT 作分布式 RAM（计入 LUT 总数） | 4,613 | 39,500 | 11.68% |
| DRM（36K 等效） | 296 | 415 | 71.33% |
| APM | 271 | 740 | 36.62% |
| I/O | 115 | 400 | 28.75% |
| PLL 基元 | 7 个 GPLL、2 个 PPLL | 未取得 | 未取得 |

综合超出 1,274 个 FF，Device Map 的容量检查使用另一个计数 320,840。最终 Device Map 资源汇总在 `multiseed_summary.csv` 里为 NA，表中其余数字均来自综合。[资源原文](artifacts/resource_summary.txt)

| 综合层次（包含子模块） | LUT | FF | 分布式 RAM LUT | APM | DRM |
|---|---:|---:|---:|---:|---:|
| `u_soc/u_gpu` | 101,007 | 286,085 | 3,372 | 260 | 233.5 |
| `u_soc/u_gpu/u_core/u_perspective` | 32,457 | 161,622 | 0 | 48 | 2 |
| `u_soc/u_gpu/u_core/u_raster` | 12,580 | 51,448 | 0 | 0 | 0 |
| `u_soc/u_gpu/u_core/u_geometry` | 13,724 | 21,346 | 262 | 68 | 1 |
| `u_soc/u_cpu` | 19,189 | 12,109 | 680 | 4 | 27 |

GPU 占全片综合 FF 的 89.16%，其中 `u_perspective` 单独占全片的 50.37%。综合报告有 1,544 组控制集，284,656 个 FF 带 CE 且没有同步或异步置位、复位。综合的 `u_palette` 层次共用 8 个 DRM，与 8 个 `palette_segment` 实例的配置相符。[完整层次资源表](artifacts/resource_hier.txt)

### 综合预估时序

以下为 ADS 综合后、布局前的 Slow Corner 估算。同域路径的 slack 单位为 ns。

| 时钟域 | 请求 MHz | 估算 MHz | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|---:|---:|
| `clk_gpu` | 180.0002 | 43.3514 | −17.510 | −163756.564 | 0.324 | 0.000 |
| `clk_sys` | 125.0001 | 115.0076 | −0.695 | −43.644 | 0.324 | 0.000 |
| `clk_mem` | 125.0000 | 119.2464 | −0.386 | −13.246 | −0.006 | −0.942 |
| `clk_aud` | 12.2880 | 276.6247 | 77.765 | 0.000 | 0.619 | 0.000 |

综合估算的 GPU 最差 setup 路径为 `u_soc/u_gpu/u_core/u_texture/log2_w_r[3]/CLK` 到 `u_soc/u_gpu/u_core/u_texture_ram/g_bank[3].read_addr_r[0]/D`，28 逻辑级，slack −17.510 ns。[时序汇总](artifacts/timing_summary.txt) · [已报告的路径索引](artifacts/round5/synthesis-path-index.txt) · [20 条最差 setup 明细](artifacts/round5/synthesis-setup-top20.txt) · [20 条最差 hold 明细](artifacts/round5/synthesis-hold-top20.txt)

布局布线时序、每时钟域布线后最差 200 条路径、拥塞、比特流和上板结果均未取得。原始报告为 `G:/codex_project/EdRV32-FPGA/board_gpu/synthesize/edrv32_fpga_board_gpu_top.snr`，阶段日志在同一工程的 `compile/run.log`、`synthesize/run.log`、`device_map/run.log` 和 `pds.log`。

### IP 与 PLL

13 个新 IP 均在 GUI 生成成功。逐项比对生成的 IDF 端口与当前 RTL 例化，13 项端口名称均一致。13 条原始成功记录见 [PDS GUI 日志节选](artifacts/compile/pds-gui-excerpts.log)。

| IP | 核对结果 |
|---|---|
| `ip_ram_gpu_texture_segment` | PDS 实际为 `a_*` / `b_*` 端口，共 16 个。每端地址 11 位、数据 16 位，字节写使能 2 位。|
| `ip_ram_gpu_palette_segment` | 同样为 `a_*` / `b_*`，共 14 个。每端地址 10 位、数据 20 位，整字写。生成 RTL 的地址和数据各展开一次，单实例为 1 个 `GTP_DRM36K_E1`。设计例化 8 个，整片 Device Map 占用待测。|
| `ip_rom_gpu_recip_q30`、`ip_rom_gpu_recip_p18` | 两个 IDF 都保存 `INIT_EN=true`、`INIT_FORMAT=HEX` 和所选 .dat 绝对路径。生成文件中每个 ROM 的 1024 个 18 位初值均与对应 .dat 逐字相等。|

| 时钟 | 目标 MHz | 生成配置 MHz | VCO / IDIV / MDIV / FDIV / ODIV0 | 误差 ppm |
|---|---:|---:|---|---:|
| clk_gpu | 180 | 180.00000000 | 1147.5 / 1 / 2 / 21.25 / 6.375 | 0.00 |
| clk_aud | 12.288 | 12.28798343 | 1112.0625 / 2 / 1 / 82.375 / 90.5 | −1.35 |

频率由生成的 IDF 分频参数计算。上板实测频率未取得。[PLL 参数](artifacts/pll.txt)

### 第 1 轮 Compile 诊断（历史记录）

| 范围 | 结果 | 用时（墙钟 / CPU） | 证据 |
|---|---|---|---|
| 整片 `board_gpu` | 源码分析 2.375 s、层次展开 1.581 s、编译准备 2.455 s，三步均通过。随后 `rtl-infer` 中 `pds_shell` 崩溃，报 `Flow-0189`。 | 10 分 51 秒 / 1 分 51 秒 | [整片 Compile 日志](artifacts/compile/board-compile-excerpts.log) |
| 独立 GPU 顶层 `edrv32_gpu` | 仅导入 `gpu.f` 的 RTL 和 GPU 存储 IP。层次展开通过，随后同样在 `InferWriteMode.cpp:2983` 崩溃。 | 6 分 45 秒 / 1 分 24 秒 | [GPU-only 日志](artifacts/compile/gpu-only-compile-excerpts.log) |
| 单独编译写 DMA、32×32 strobe RAM、简化纹理队列写入 | 三组均通过 | 5 秒、3 秒、3 秒 | [小工程日志](artifacts/compile/isolated-probes-excerpts.log) |

整片和 GPU-only 都在打印 `Found Ram strobe_r, depth=32, width=32` 后报内部错误。写 DMA 原模块和该数组单独编译均通过，导致崩溃的具体阵列或连接组合尚未定位。纹理队列含动态寻址、多处写入和按 lane 分段写入。PDS 对 `completed_r` 报反馈多路选择器警告，相关精简样例通过。对 `rtl/gpu` 的 36 个 Verilog 文件运行仓库风格检查，结果为 0 告警。此前的 `Verilog-4119` 是更新前的端口差异，已经过修复，当前运行通过层次展开。

[GPU-only 复现脚本](artifacts/compile/compile-gpu-only.tcl)使用两个环境变量。将 `EDRV32_REPO` 设为结果分支的源码根目录，将 `BOARD_GPU_IPCORE` 设为现有 board_gpu 工程的 ipcore 目录。另建空目录作为工作目录，以同版本 PDS 运行 `pds_shell.exe -file <脚本路径> -work_dir <工作目录> -project_name gpu_compile_probe`。

原始日志在 Windows 的 `G:/codex_project/EdRV32-FPGA/board_gpu/pds.log`、`compile/run.log` 和 `G:/codex_project/edrv32-card107/build/card107-pds-check/compile-crash/`。附件保留原始行号和崩溃调用栈。

卡 109 随后将 RAM 推断崩溃定位到 `edrv32_gpu_unpack` 的跨通道共享数组，并单独定位了 `edrv32_gpu_clip` 的多驱动问题。两处修复均已进入第 5 轮的代码基线。[卡 109 复现与日志](https://github.com/zc100116/EdRV32-Competition-2026/tree/win/20261124-109-gpu-compile-bisect/tasks/win/20261124-109-gpu-compile-bisect)
