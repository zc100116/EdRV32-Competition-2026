# 任务 21 首版结果：B3R

| 项目 | 结果 |
|---|---|
| 分支 | win/20261031-21-b3-rerun-eth |
| 代码基线 | 99f453b1ac59ed849739218b4713884261d524b3；本报告同时提交 Windows 包装端口适配和导入脚本修改 |
| 工具/器件 | PDS 2022.2-SP6.1，PG2L200H-6 FBB676 |
| R 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3R |
| RTL | 98 个，顶层 edrv32_fpga_board_render_top |
| 完成范围 | R 编译、综合、Device Map、布局布线、时序分析、bitstream、现有串口测试记录 |
| N / VN | 后续流程结果待收集，本版不作结论 |

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
