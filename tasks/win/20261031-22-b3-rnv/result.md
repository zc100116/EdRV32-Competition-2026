# 任务 22：R/N/V 阶段报告、V最终结果与旧VN失败补充

前半部分保留三个工程的 Compile、Synthesize、Device Map 报告。本版在后文补充 V 的最终实现/串口与网络问题，以及旧卡21 VN 的最终布线失败。各阶段数据直接取自现有工程；本次不启动、停止或重跑实现流程。

- 分支：win/20261031-22-b3-rnv；整理时已同步软件更新 8edfca2d。
- 工具：PDS 2022.2-SP6.1；器件 PG2L200H-6 FBB676。
- 工程目录：G:/codex_project/EdRV32-FPGA/EdRV32-B3R、EdRV32-B3N、EdRV32-B3V。
- 源码目标数：R=103、N=106、V=112；配置时的添加/移除清单在各 artifacts 子目录 sources.txt。
- 用户安排三个工程并行实现、配置逐个完成，覆盖任务卡的串行安排。

## 阶段耗时和告警

W/E 为日志行数，同一类告警可能重复出现，不代表独立根因数。峰值是工具报告的 memory pool，不等同于操作系统总工作集。

| 工程 | 阶段 | 实际耗时 | CPU 时间 | Process CPU 时间 | 峰值内存池 | W: | E: |
|---|---|---|---|---|---|---|---|
| b3r | compile | 0h:2m:22s | 0h:0m:3s | 0h:0m:3s | 609 MB | 3288 | 0 |
| b3r | synthesize | 0h:9m:21s | 0h:1m:23s | 0h:1m:30s | 3,390 MB | 10467 | 0 |
| b3r | device_map | 0h:1m:13s | 0h:0m:1s | 0h:0m:1s | 1,876 MB | 20 | 0 |
| b3n | compile | 0h:2m:30s | 0h:0m:4s | 0h:0m:4s | 658 MB | 3616 | 0 |
| b3n | synthesize | 0h:7m:41s | 0h:0m:8s | 0h:0m:10s | 3,491 MB | 13578 | 0 |
| b3n | device_map | 0h:1m:15s | 0h:0m:1s | 0h:0m:1s | 1,797 MB | 268 | 0 |
| b3v | compile | 0h:2m:16s | 0h:0m:2s | 0h:0m:2s | 540 MB | 3253 | 0 |
| b3v | synthesize | 0h:7m:9s | 0h:0m:9s | 0h:0m:10s | 2,870 MB | 9365 | 0 |
| b3v | device_map | 0h:1m:6s | 0h:0m:1s | 0h:0m:2s | 1,519 MB | 56 | 0 |

## Device Map 资源

全部为布局布线前的 Device Map 原文数值。DRM 采用厂商 36K 等效口径；原始 DRM18K/DRM36K 数量在 SNR Cell Usage。综合层次资源单独保存，不与 Device Map 数字混用。

| 工程 | LUT | FF | 分布式 RAM | APM | DRM | IO | GPLL | PPLL |
|---|---|---|---|---|---|---|---|---|
| b3r | 82411 | 61760 | 741 | 170 | 117.5 | 109 | 5 | 2 |
| b3n | 64136 | 64392 | 1774 | 303 | 173 | 101 | 5 | 2 |
| b3v | 62877 | 56372 | 922 | 47 | 97 | 137 | 5 | 2 |

## 布线前时序估计

以下仅统计 SNR 中现有的 sequential timing path，已保存的路径数量受原生报告选项限制。负裕量条数是已报告路径数，不是全设计失败端点总数。setup 为 max，hold 为 min，合并 SNR 中可用的 corners 统计最差值；具体角、时钟和起终点见逐路径列表。

| 工程 | 类型 | 已报告路径数 | 最差裕量 ns | 其中负裕量路径数 |
|---|---|---|---|---|
| b3r | setup | 28 | -0.104 | 3 |
| b3r | hold | 28 | -3.198 | 9 |
| b3n | setup | 25 | 0.209 | 0 |
| b3n | hold | 25 | -1.63 | 9 |
| b3v | setup | 34 | -0.792 | 3 |
| b3v | hold | 34 | -2.889 | 9 |

最终 WNS/TNS/WHS/THS、区域内实际站点、卡21违例路径的最终改善情况，需等待布局布线完成后分析，当前不作通过结论。

## 产物和说明

每个 artifacts/b3r、b3n、b3v 下：

- native_reports/：原生 CMR、SNR、DMR。
- logs/*_excerpt.txt：全部 W:/E: 行及阶段耗时/内存等关键信息。完整原始 run.log 留在各工程的 compile/、synthesize/、device_map/。
- flow_summary.txt：各阶段告警代码计数及时间/内存原文。
- resource_summary.txt、resource_hier.txt：Device Map 汇总、综合 primitive usage、完整综合层次表，包含 CPU/cache、u_mem/u_xbar，以及各工程实际包含的 RND/NPU/图像处理/ETH 模块。
- high_fanout.txt：Device Map 的高扇出、时钟、复位、CE 表。
- regions_pre_pnr.txt：DMR 的 PAP_REGION 属性记录；表示映射阶段记录了约束，不代表最终寄存器已经落入指定区域。
- timing_pre_pnr_paths.tsv：SNR 中全部可取得的路径；timing_pre_pnr_counts.txt：按角/组/类型的数量。
- timing_pre_pnr_setup_detail.txt、timing_pre_pnr_hold_detail.txt：最差可用路径明细；timing_pre_pnr_near.tsv：裕量 <1 ns 的现有路径，包含负裕量。

大量警告已按代码归类并保留原文，包括 ConstantProbeLoop、未驱动信号、综合资源优化及约束覆盖类信息。不通过修改 RTL 消警，不将布线前估计当作实际板级故障结论。

网口和软件上板测试尚未在本卡验收。卡22使用新的 BIOS 与应用协议，上板使用卡22 src 镜像。调试工具已更新，重新启动后才生效。

## 复现整理

C:/Python314/python.exe tasks/win/20261031-22-b3-rnv/src/collect_pre_pnr.py

此脚本只读取现有工程报告并写任务产物，不调用 PDS。

## 较大产物

- artifacts\b3r\native_reports\device_map\edrv32_fpga_board_render_top.dmr (2144939 bytes)：保留原厂警告或层次数据供分析，未复制完整原始运行日志。
- artifacts\b3n\native_reports\device_map\edrv32_fpga_board_npu_top.dmr (2067890 bytes)：保留原厂警告或层次数据供分析，未复制完整原始运行日志。
- artifacts\b3v\native_reports\device_map\edrv32_fpga_board_vision_top.dmr (2151406 bytes)：保留原厂警告或层次数据供分析，未复制完整原始运行日志。


## V 最终实现与网口问题补充

V 工程 G:/codex_project/EdRV32-FPGA/EdRV32-B3V 已完成布局布线、时序和 bitstream。本节覆盖之前仅收集到 Device Map 的状态。R/N 本卡的最终实现与上板结果未在本次请求中收集。

### V 耗时和资源

| 阶段 | 实际耗时 | CPU 时间 | Process CPU 时间 | 峰值内存池 | W: | E: |
|---|---|---|---|---|---|---|---|
| Place and Route | 37m58s | 1m05s | 1m48s | 5555 MB | 694 | 0 |
| Report Timing | 1m34s | 4s | 5s | 5176 MB | 166 | 0 |
| Bitstream | 1m52s | 3s | 3s | 3679 MB | 0 | 0 |

PnR 层次总计：逻辑 LUT 62631、FF 56428、分布式 RAM 922、APM 47、DRM 97（36K 等效）。PnR 资源汇总和层次见 artifacts/b3v/resource_summary.txt、resource_hier.txt；原先布线前的对应表保存在 resource_pre_pnr_summary.txt、resource_pre_pnr_hier.txt，避免阶段口径混用。

### V 最终时序

原厂汇总中的 setup、hold、recovery、removal、最小脉宽在两个角下均未列出负裕量。Setup 最差为 slow clk_mem 0.187 ns；Hold 最差为 fast clk_mem → phy_dq_sysclk_1 0.098 ns；DDR PHY 最小脉宽裕量仅 0.035 ns，均应继续关注。
工具仍有未约束输入/输出警告，时序结论限于当前约束覆盖范围，不能替代网络功能验收。

| Corner | Launch → Capture | WNS ns | TNS ns | WHS ns | THS ns |
|---|---|---|---|---|---|
| Slow | clk_cam0 → clk_cam0 | 5.079 | 0.000 | 0.167 | 0.000 |
| Slow | clk_cam1 → clk_cam1 | 5.893 | 0.000 | 0.196 | 0.000 |
| Slow | clk_sys → clk_sys | 0.467 | 0.000 | 0.148 | 0.000 |
| Slow | clk_pix → clk_pix | 6.900 | 0.000 | 0.101 | 0.000 |
| Slow | clk_serial → clk_serial | 1.706 | 0.000 | 0.346 | 0.000 |
| Slow | rst_clk → rst_clk | 4.891 | 0.000 | 0.146 | 0.000 |
| Slow | clk_mem → clk_mem | 0.187 | 0.000 | 0.101 | 0.000 |
| Slow | phy_dq_sysclk_1 → clk_mem | 2.978 | 0.000 | 0.533 | 0.000 |
| Slow | phy_dq_sysclk_0 → clk_mem | 3.891 | 0.000 | 0.734 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_0 | 1.838 | 0.000 | 0.462 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_1 | 1.977 | 0.000 | 0.465 | 0.000 |
| Slow | clk_eth → clk_eth | 2.517 | 0.000 | 0.272 | 0.000 |
| Fast | clk_cam0 → clk_cam0 | 7.116 | 0.000 | 0.117 | 0.000 |
| Fast | clk_cam1 → clk_cam1 | 7.628 | 0.000 | 0.131 | 0.000 |
| Fast | clk_sys → clk_sys | 3.776 | 0.000 | 0.101 | 0.000 |
| Fast | clk_pix → clk_pix | 9.548 | 0.000 | 0.103 | 0.000 |
| Fast | clk_serial → clk_serial | 2.084 | 0.000 | 0.225 | 0.000 |
| Fast | rst_clk → rst_clk | 6.199 | 0.000 | 0.100 | 0.000 |
| Fast | clk_mem → clk_mem | 3.335 | 0.000 | 0.100 | 0.000 |
| Fast | phy_dq_sysclk_1 → clk_mem | 4.781 | 0.000 | 0.099 | 0.000 |
| Fast | phy_dq_sysclk_0 → clk_mem | 5.359 | 0.000 | 0.250 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_0 | 4.032 | 0.000 | 0.102 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_1 | 4.188 | 0.000 | 0.098 | 0.000 |
| Fast | clk_eth → clk_eth | 4.686 | 0.000 | 0.178 | 0.000 |

完整时钟与所有检查汇总在 timing_summary.txt；从已完成的 routed DB 额外导出每组上限200条setup/hold，负裕量和 <1 ns 的危险路径全部保留在已导出集合内；最差20条逐级明细、异步/无约束路径另列。每组实际数量在 timing_path_counts.txt。本次只做报告分析，没有重新布局布线。

### 区域约束警告

PnR 有694条区域约束相关 W:：PhysicalConstraintEditor-4048 为344条、ConstraintEditor-4032 为192条、PhysicalConstraintEditor-4049 为158条。

- 4048：重复约束，def_inst_site 优先或实例已存在 def_inst_region，相关 region 命令被忽略。
- 4032：指定 region 不包含该硬资源类型（如 GPLL、DDR_PHY、TSERDES），相关命令被忽略。
- 4049：不建议对 IO 使用 region，该命令被忽略。

警告全文保存在 region_check.txt 和 logs/place_route_excerpt.txt；实际 Device Map PCF 在 native_reports/device_map/。没有宣称层次 region 会约束内部所有单元。最终路径中的物理 Location 原文作为抽样保留；未未经器件坐标转换就把 Location 的数字与 PAP_REGION 范围直接比较。

### 上板与网络

V 应用已通过 BIOS 加载运行，串口 status 可返回 Demo command: OK；摄像头和 CH0 帧计数增长，观测中的溢出计数为0。未取得任务卡要求的全部 PIX/GEO 模式逐项画面结论，不能将本轮完整功能验收记为通过。

网口未连通：PEER=0.0.0.0:0、ETH STATUS=0x00000002，工具视频/EDTM计数均为0，监控序列与 dropped records 同步增长。已发送连接请求不代表板端收到。完整过程、代理配置调整和未解决点在 network/observations.md，串口原文在 uart/，截图在 photos/。

电脑有线设为192.168.1.2/24、链路1Gbps，先前占用UDP6000的NI服务已按用户要求停止。Clash保持运行，已添加板子DIRECT规则与TUN路由排除，热加载HTTP204并回读确认；随后自动源地址仍选到Wi-Fi 192.168.5.31。板子MAC未解析成功，不能将问题全部归因于Clash，也未宣称已修复。
未上传Clash完整配置、订阅、代理节点或凭据。网络后续应继续检查源地址绑定、实际出口、ARP和板端RX链路。

烧录GUI地址问题一并修复：两个0x10000000原为placeholder，留空后int('',0)报错；现改为实际默认文本。回归测试 test_bin_program_uses_displayed_sram_addresses 已通过，验证默认地址正确传给烧录引擎。本次提交含该修复与测试，运行中的旧窗口需手填或重启后使用。

## 旧 VN 最终布线失败（卡21补充）

这是一直运行未停止的 EdRV32-B3VN，属于旧卡21；与本轮V分开记录于 artifacts/b3vn_card21_failure/。其Compile/综合/Device Map先前已完成，本次补齐最终失败结果，不把旧工程遗留的 report_timing 或 bitstream 当作本次成功产物。

报错原文：

```text
E: Route-0039: Design is too congested to be routed, iteration time exceed limit 2000 sec.
E: Route-0008: Design cannot be routed.
```

PnR 实际耗时3h26m11s，CPU17m41s，Process CPU19m27s，峰值内存池6618MB。第16轮MT total route time=2573.222 sec，Unrouted general nets=49263，overused=221725。这里的MT计时是原厂迭代日志字段，不与PnR总耗时混用。

结论：工具明确因拥塞与单轮运行时间超限结束，尚未获得完整可用布线；不是已完成布线后单纯存在负时序裕量。布局阶段的正slack不能替代最终布线通过。

- 保存CMR、SNR、DMR和失败PRR，以及各阶段警告/错误/耗时、完整布线迭代节选、高扇出与资源层次。
- fail_route_nets.txt 原文件136343442字节，保留本地。流式提取26615个网络块，列出的load合计334540、un-routed load合计182661；这是转储文件计数，不直接等同于迭代中的49263条网络。
- failed_nets_top200.tsv 按un-routed loads降序保留200个网络头/driver/负载数量；failed_nets_samples.txt保留首3个网络块（上限900行）供查看路由细节。
- 转储中GND/VCC网络分别有34330/22108个未布通load；其他较大项包括NPU r4_first_r、media_apb_paddr_w[2]、rst_mem_core_n_w、accum_valid_w，具体原文在top200表。不能据此单独认定某模块为根因；常量网和控制扇出的统计口径需结合工具解释。
- 失败现场的 *_fail_pnr.adf、partial_route.adf、完整运行日志及136MB转储都留在 G:/codex_project/EdRV32-FPGA/EdRV32-B3VN/place_route/，不入库。
- 此次没有停止进程、重启流程或改RTL/约束；失败后最终routed timing和可用bitstream未取得。

V 补导出成功退出（exit 0），总计 12036 条各类型/各角路径，其中已导出的负裕量路径为0。区域物理Location抽样 100 行；不据此宣称所有寄存器均受region限制。

旧VN的 logs/synthesize_excerpt.txt 约2.15MB，保留大量综合警告原文供Claude定位资源与优化问题；没有上传完整run.log。
