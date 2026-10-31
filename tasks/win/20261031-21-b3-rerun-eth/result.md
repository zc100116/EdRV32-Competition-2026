# 任务 21 结果：B3R、B3N 与 B3VN 阶段快照

| 项目 | 结果 |
|---|---|
| 分支 | win/20261031-21-b3-rerun-eth |
| 代码基线 | 99f453b1ac59ed849739218b4713884261d524b3；本报告同时提交 Windows 包装端口适配和导入脚本修改 |
| 工具/器件 | PDS 2022.2-SP6.1，PG2L200H-6 FBB676 |
| R 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3R |
| RTL | 98 个，顶层 edrv32_fpga_board_render_top |
| 完成范围 | R 编译、综合、Device Map、布局布线、时序分析、bitstream、现有串口测试记录 |
| N / VN | N 已完成并补充；VN 已完成 Compile/综合/Device Map，布线进度快照见末尾 |

直接复用现有工程（用户要求），没有复制任务卡建议的新工程目录。

## 结论

- RND 自检：16/16 CRC PASS，ERR_CODE 全部为 0，出现 RND display ready。原始串口分块造成 CRC 跨行；仅在提取文本中合并 crc= 与下一行的十六进制值，再运行 expect.py，退出码 0。
- LVGL benchmark 自然结束：All scenes avg.,99%, 23, 77, 69, 8。该列顺序为 Avg. CPU、Avg. FPS、Avg. time、render time、flush time。
- RN-17 PASS：full_max_lsb=0，edge_max_lsb=17，over1=1024/921600，over1_ppm=1111。
- R 时序未全部达标：slow clk_eth setup WNS=-0.106 ns，TNS=-0.106 ns，1 个失败端点。路径 u_rgmii/g_rx[0].u_input/opit_1/DESCLK → u_rgmii/rx_data_r[4]/opit_0/D，逻辑级数 0。
- 危险裕量：slow clk_mem setup 0.202 ns，slow clk_sys setup 0.700 ns；fast clk_mem hold 0.081 ns。DDR PHY 最小脉宽裕量 0.035 ns。不能据功能运行判定整体时序通过。
- 当前串口记录无 NES ROM/fps 数据；工具 EDTM records=0，CSV 仅表头。ETH 实板连通和 NES 本版均记未取得，不将空 CSV 作为成功证据。
- 用户表示 R 测试完成；本版没有取得独立的 HDMI 照片及逐项画面观察。

## 实现耗时与内存

| 阶段 | 实际耗时 | CPU 时间 | Process CPU 时间 | 峰值内存池 |
|---|---|---|---|---|
| Compile | 1m58s | 8s | 8s | 559 MB |
| Synthesize | 6m03s | 1m08s | 1m12s | 3303 MB |
| Device Map | 53s | 9s | 9s | 1552 MB |
| Place and Route | 39m58s | 4m52s | 8m28s | 6376 MB |
| Report Timing | 1m30s | 10s | 13s | 5230 MB |
| Bitstream | 2m22s | 23s | 23s | 3526 MB |

各阶段 E: 日志行均为 0。警告行计数及分类见 artifacts/b3r/flow_summary.txt，警告原文见 logs/ 各阶段节选。Compile 含 ConstantProbeLoop 警告，综合包含大量资源/优化警告；保留原文供 Linux 端分析，没有将它们等同于运行失败。
RGMII RX、UART RX、外部复位存在未约束输入警告，完整原文已保留；时序达标范围应结合这些约束限制解释。

## 资源

PnR 层次总计：逻辑 LUT 65066，FF 50521，分布式 RAM 741，APM 102，DRM 113（36K 等效）。物理 IO 109（IOBD 56、IOBS 53），GPLL 5、PPLL 2。物理 CLMA/CLMS 的 LUT 数受打包影响，不与逻辑 LUT 总计混用。
资源原文和 cpu/cache/u_mem/u_xbar/u_rnd/u_eth 层次见 resource_summary.txt、resource_hier.txt。

## 各时钟关系时序

单位 ns。Setup 与 Hold 的 Slow/Fast 表均列出，Recovery/Removal/最小脉宽完整原文见 timing_summary.txt。

| Corner | Launch → Capture | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|
| Slow | clk_sys → clk_sys | 0.700 | 0.000 | 0.103 | 0.000 |
| Slow | clk_pix → clk_pix | 5.573 | 0.000 | 0.166 | 0.000 |
| Slow | clk_serial → clk_serial | 1.706 | 0.000 | 0.346 | 0.000 |
| Slow | rst_clk → rst_clk | 4.673 | 0.000 | 0.259 | 0.000 |
| Slow | clk_mem → clk_mem | 0.202 | 0.000 | 0.101 | 0.000 |
| Slow | phy_dq_sysclk_1 → clk_mem | 2.965 | 0.000 | 0.566 | 0.000 |
| Slow | phy_dq_sysclk_0 → clk_mem | 3.636 | 0.000 | 1.175 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_0 | 1.750 | 0.000 | 0.464 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_1 | 1.165 | 0.000 | 0.461 | 0.000 |
| Slow | clk_eth → clk_eth | -0.106 | -0.106 | 0.148 | 0.000 |
| Fast | clk_sys → clk_sys | 3.786 | 0.000 | 0.101 | 0.000 |
| Fast | clk_pix → clk_pix | 8.549 | 0.000 | 0.118 | 0.000 |
| Fast | clk_serial → clk_serial | 2.084 | 0.000 | 0.225 | 0.000 |
| Fast | rst_clk → rst_clk | 6.088 | 0.000 | 0.164 | 0.000 |
| Fast | clk_mem → clk_mem | 3.200 | 0.000 | 0.081 | 0.000 |
| Fast | phy_dq_sysclk_1 → clk_mem | 4.709 | 0.000 | 0.099 | 0.000 |
| Fast | phy_dq_sysclk_0 → clk_mem | 4.996 | 0.000 | 0.382 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_0 | 3.995 | 0.000 | 0.102 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_1 | 3.663 | 0.000 | 0.100 | 0.000 |
| Fast | clk_eth → clk_eth | 3.053 | 0.000 | 0.134 | 0.000 |

## 上板数据与产物

- uart/serial_console_session.log：工具现有会话原文；uart/rx_text.log：去掉显示时间戳后的 RX 文本。
- uart/rnd_board.log、uart/rnd_check.txt：RND 数据和 16/16 比对结果。
- uart/benchmark_summary.txt：所有场景汇总；lvgl_split.tsv：16 场景及 ALL 的 17 行完整 key=value 数据。
- uart/rn17.txt：RN-17 结果和类型计数。
- edtm.csv：空数据，仅保留本次导出状态；uart/telemetry_status.json records=0。
- timing_setup_top200.txt、timing_hold_top200.txt：从现有 routed DB 补导出的多路径列表（每组上限 200，PDS 跨时钟关系可能合并到同一路径组）；每组实际数量见 timing_path_counts.txt。
- timing_setup_top20_detail.txt、timing_hold_top20.txt：Slow/Fast 各自最差 20 条路径逐级明细。
- timing_near_setup.txt、timing_near_hold.txt：裕量 <1 ns 的已导出路径，包含负裕量。
- timing_other_checks.txt：已导出的异步与无约束组合路径列表；完整检查汇总在 timing_summary.txt。
- native_reports/：CMR、SNR、DMR、PRR；logs/：各阶段警告、错误及耗时节选。无实现数据库、生成 IP、bitstream、ROM 或完整原始 PDS 日志入库。

完整 PDS 报告和运行日志保留在上述 R 工程的 compile/、synthesize/、device_map/、place_route/、report_timing/、generate_bitstream/。
时序补导出数据库为 place_route/edrv32_fpga_board_render_top_pnr.adf，命令为 report_timing -delay_type min_max -max_path 200 -input_pins TRUE -nworst 1；在 build/win/20261031-21-b3-rerun-eth/exports/b3r_top200 独立运行，仅分析已有布线结果。
采集整理脚本 src/collect_b3r.py；CRC 校验命令 C:/Python314/python.exe sw/tests/rnd_board/expect.py tasks/win/20261031-21-b3-rerun-eth/artifacts/b3r/uart/rnd_board.log。

## Windows 适配记录

- mem_xbar 写缓冲两实例，以及 NPU quant/residual/result 的 FPGA 包装连接生成 IP 的 rd_clk=clk_i、rst=1'b0；没有修改生成 IP。
- N/VN 导入脚本采用工程相对 include 路径 ../../EdRV32-Competition-2026/rtl/include，PDS 格式末尾 TAB 分隔；FPGA_MODE 保持启用。
- VN 复制脚本从已检查的 N 工程逐文件覆盖 9 类 IP，更新项目引用。用户已移除旧 edrv32_mul_npu_int8_pair.v 残留引用，VN 为 145 RTL。


## B3N 结果补充

工程 G:/codex_project/EdRV32-FPGA/EdRV32-B3N；106 个 RTL、24 类 IP；顶层 edrv32_fpga_board_npu_top。编译、综合、Device Map、布局布线、时序和 bitstream 已完成，各阶段 E: 行均为 0。

### 上板

- 串口加载结果 PASS，加载 5184668 字节到 0x80000000，并从 0x80000000 运行。
- 最终结果：NPU board: PASS 39/39。
- NPU C-YOLO PASS PERF0=6250245 MAC=5347440 ms/frame=41.668 fps=23.999 CRC32=0738f96e。
- 完整本次加载与测试会话在 artifacts/b3n/uart/session.log，RX 文本在 npu_board.log。
- LED4/LED5 观察未取得；用户明确暂停网口测试，本版不宣称 ETH 连通通过。

### 时序

**未达到全部时序通过判据**：Slow Corner 的 clk_mem → phy_dq_sysclk_1 setup WNS=-0.103 ns、TNS=-0.142 ns，2 个失败端点。最小 Hold 裕量为 0.100 ns。CPU 与 NPU 域 setup 也接近临界：clk_sys=0.290 ns，clk_npu=0.279 ns，clk_mem 同域=0.312 ns。板级功能测试通过不消除这些时序风险。

| Corner | Launch → Capture | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|
| Slow | clk_sys → clk_sys | 0.290 | 0.000 | 0.145 | 0.000 |
| Slow | clk_npu → clk_npu | 0.279 | 0.000 | 0.138 | 0.000 |
| Slow | rst_clk → rst_clk | 4.828 | 0.000 | 0.162 | 0.000 |
| Slow | clk_mem → clk_mem | 0.312 | 0.000 | 0.107 | 0.000 |
| Slow | phy_dq_sysclk_1 → clk_mem | 3.047 | 0.000 | 0.527 | 0.000 |
| Slow | phy_dq_sysclk_0 → clk_mem | 3.696 | 0.000 | 1.053 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_0 | 1.914 | 0.000 | 0.469 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_1 | -0.103 | -0.142 | 0.504 | 0.000 |
| Slow | clk_eth → clk_eth | 1.683 | 0.000 | 0.261 | 0.000 |
| Fast | clk_sys → clk_sys | 3.825 | 0.000 | 0.102 | 0.000 |
| Fast | clk_npu → clk_npu | 2.633 | 0.000 | 0.100 | 0.000 |
| Fast | rst_clk → rst_clk | 6.178 | 0.000 | 0.110 | 0.000 |
| Fast | clk_mem → clk_mem | 3.343 | 0.000 | 0.100 | 0.000 |
| Fast | phy_dq_sysclk_1 → clk_mem | 4.800 | 0.000 | 0.100 | 0.000 |
| Fast | phy_dq_sysclk_0 → clk_mem | 5.122 | 0.000 | 0.326 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_0 | 4.107 | 0.000 | 0.100 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_1 | 2.725 | 0.000 | 0.104 | 0.000 |
| Fast | clk_eth → clk_eth | 4.080 | 0.000 | 0.168 | 0.000 |

完整 Recovery、Removal、Minimum Pulse Width、时钟信息原文在 artifacts/b3n/timing_summary.txt。从现有 routed DB 补导出每组上限 200 条 setup/hold 路径，列表、各角最差 20 条逐级明细、裕量 <1 ns 路径及异步/无约束路径，文件名与 R 一致。未重跑综合或布局布线。

### 实现耗时

| 阶段 | 实际耗时 | CPU 时间 | Process CPU 时间 | 峰值内存池 |
|---|---|---|---|---|
| Compile | 2m26s | 11s | 11s | 663 MB |
| Synthesize | 7m36s | 52s | 58s | 3106 MB |
| Device Map | 1m05s | 7s | 8s | 1789 MB |
| Place and Route | 37m01s | 5m28s | 10m07s | 5919 MB |
| Report Timing | 1m30s | 11s | 13s | 5557 MB |
| Bitstream | 1m48s | 8s | 8s | 3747 MB |

### 资源和警告

PnR 层次总计：逻辑 LUT 64351、FF 64508、分布式 RAM 1774、APM 303、DRM 173（36K 等效）。物理 IO 101，GPLL 5、PPLL 2；完整原厂表见 resource_summary.txt；cpu、cache、u_mem/u_xbar、u_npu、u_eth 等层次见 resource_hier.txt。

Compile 3616 条 W:，综合 13566 条，Device Map 267 条，PnR 0 条，时序分析 130 条，bitstream 0 条；这是日志 W: 行计数，并非唯一根因数。按告警代码统计在 flow_summary.txt，各阶段告警原文在 logs/。
Compile 的 ConstantProbeLoop、未驱动信号以及综合的资源优化警告保留供 Linux 端审查；没有自行更改 RTL 来消除告警。时序有未约束输入/输出告警，判断时序覆盖范围应结合约束原文。

本次为配置/端口适配后的真实生成 IP；配置检查记录见 ip_check.txt。完整原始 PDS 日志、报告和布线数据库继续保留在 N 工程目录，入库仅包含 CMR/SNR/DMR/PRR、时序提取、日志节选与串口数据。

## 网口测试暂停说明

用户决定本轮暂不测试网口，R/N 的 ETH 均未验收。电脑有线网卡已设 192.168.1.2/24；先前 UDP 6000 被 NI Citadel 4 Service 占用，按用户要求临时停止该服务，启动类型保持 Automatic。之后工具监听成功但未收到板端 PEER/EDTM；排查中观察到工具本机地址被选为 Mihomo 的 198.18.0.1，尝试临时板子主机路由无效且已撤销。未完成进一步网口诊断，不将原因定为已解决。


## B3VN 部分流程报告（布线中）

工程 G:/codex_project/EdRV32-FPGA/EdRV32-B3VN，顶层 edrv32_fpga_board_vnpu_top。复用现有工程，用户已经移除旧 int8_pair 源码残留引用。
本次只收集已运行阶段，不停止、不重启、不修改 VN 流程；不等待其布线结束才回传。布局布线最终报告、时序签核、bitstream、上板结果本版均未取得，不引用旧工程残留的最终报告。

### 已完成阶段

| 阶段 | 实际耗时 | CPU 时间 | Process CPU 时间 | 峰值内存池 | W: 行 | E: 行 |
|---|---|---|---|---|---|---|
| Compile | 2m48s | 14s | 14s | 729 MB | 4514 | 0 |
| Synthesize | 9m21s | 1m06s | 1m12s | 3718 MB | 16347 | 0 |
| Device Map | 1m32s | 8s | 8s | 2208 MB | 312 | 0 |
| Place and Route | 尚未完成 | 未取得最终值 | 未取得最终值 | 未取得最终值 | 快照 0 | 快照 0 |

CMR/SNR/DMR 保存在 artifacts/b3vn/native_reports/，各阶段警告原文节选和代码统计在 logs/、flow_summary.txt。包含 ConstantProbeLoop、未驱动信号、资源优化、时钟资源和未约束 IO 告警，保留原文，不自行修改硬件消警。

### 当前布线进度

- 日志记录布局完成，Total placement takes 81.98 sec，随后进入 timing-driven routing，Route thread size: 5。
- Total nets for routing: 139500；Total loads for routing: 651424；Total route nets size: 139456。
- 时钟网络在第 4 轮未布线数降为 0。
- 普通网络迭代原文如下，MT total route time 是工具报告的该计时值，不当作整个 PnR 阶段最终耗时：

| Iteration | MT total route time (sec) | Unrouted general nets | overused |
|---|---|---|---|
| 6 | 18.386 | 123845 | 943565 |
| 7 | 23.151 | 112293 | 776574 |
| 8 | 66.974 | 102173 | 625871 |
| 9 | 215.185 | 93395 | 516558 |
| 10 | 533.242 | 86214 | 445617 |
| 11 | 864.425 | 74177 | 419031 |

未布线数量和资源冲突量在这些迭代中下降，但仍很大，反映路由资源冲突尚未消解。仅凭当前日志无法确定是否最终收敛，也不能将较长运行时间直接归因于某一条时序路径。
日志中 Worst slack is 451, TNS after placement is 0，TNS before route is 0；这些为布线器原始整数单位，未推断换算成 ns，不能代替最终 routed timing。
完整进度节选在 routing_progress.txt，当前末尾 100 行在 routing_tail.txt；没有使用大小为 0 的当前 PRR 作为最终资源/时序依据。

### 布线前资源与时序参考

Device Map 报告：LUT 84428/159800（53%），FF 89819/319600（29%），分布式 RAM 2099/39500（6%），APM 337/740（46%），DRM 225/415（55%，36K 等效），IO 137/400（35%），GPLL 6、PPLL 2。
综合层次总计为 LUT 84432、FF 90122、分布式 RAM 2099、APM 337、DRM 225；与 Device Map 为不同阶段，分别保留，不混用。

- resource_summary.txt：Device Map 资源原文与综合 Cell Usage。
- resource_hier.txt：综合阶段全层次资源，包含 cpu/cache、u_mem/u_xbar、u_npu、vin/pix/geo/disp、ETH 等。
- high_fanout.txt：Device Map 高扇出、时钟、复位、CE 原文表，供布局布线困难分析。
- timing_synthesis_paths.txt：综合阶段现有 128 条路径索引；timing_synthesis_detail.txt：可用路径最差明细；完整路径在原生 SNR。
- 这些是布局布线前估计，未将它们作为最终违例或裕量结论。待完成后仍需收集 routed top200、最差 setup/hold 明细和各角汇总。

VN synthesize_excerpt.txt 约 2.15 MB，保留 16347 条警告原文以便定位资源/优化问题，仅为节选，不含完整综合日志。

N 补导出时序成功退出（exit 0），取得 9544 条各类型/各角路径；控制台额外出现 W: open run.log failed，报告本身已生成，警告及动作原文在 artifacts/b3n/logs/timing_export_excerpt.txt。
