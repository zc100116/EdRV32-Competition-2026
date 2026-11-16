# 卡 75 结果

布局布线成功，时序约束未全部满足。2026-11-16 06:29:42（北京时间）完成 PnR，06:31:48 完成布线后时序报告。16:13:19 完成整片比特流生成。上板取得 board_npu 全通过以及 Showcase 硬件后处理实时识别串口。

| 项 | 记录 |
|---|---|
| 代码 HEAD | `42b3fa1615af0330b1a4aabcdbe06a0dbfee3fa5` |
| 工程 | `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST/EdRV32-B3F-POST.pds` |
| 环境 | PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676 |
| PnR 配置 | 单工程，Slack Weight 40，Placement Decongestion 2，开启拥塞网格 |
| PnR 实际用时 | 36h 51m 01s；编译到时序报告共 37h 08m 47s |
| 布线归零 | 通用第 911 轮（PDS iteration 916）未布通、过用均为 0；后续修整至 PDS iteration 928 全部未布通网归零 |
| CLK_SYS_HZ / 上板 | BIOS 实测 125000000；board_npu 39/39；Showcase 实时识别中位数 27 fps |

[实际设置](artifacts/settings.txt) · [各阶段日志节选](artifacts/implementation_stages.txt) · [PDS 单种子汇总](artifacts/multiseed_summary.csv)

## 资源

| 指标 | 卡 68 R2 | 卡 73 A | 卡 75 |
|---|---:|---:|---:|
| Device Map LUT / FF | 91,208 / 107,042 | 88,296 / 108,806 | 89,032 / 109,052 |
| Device Map DRM / APM | 286 / 372 | 298 / 373 | 298 / 373 |
| ADS `u_npu` LUT / FF | 16,953 / 39,009 | 18,710 / 42,364 | 18,803 / 42,421 |
| ADS `u_rnd` LUT / FF | 16,785 / 11,129 | 13,452 / 11,251 | 13,665 / 11,511 |
| ADS `u_mem` LUT / FF | 9,168 / 9,096 | 9,351 / 9,095 | 9,751 / 9,150 |
| PnR CLMA / CLMS | 25,871 / 8,473 | 未取得 | 24,563 / 7,847 |

Device Map 另有 2,781 个分布式 RAM、137 个 IO、6 个 GPLL、2 个 PPLL。卡 68 R2 和卡 73 A 的层级数据取各自的 ADS 分层文件。[资源汇总](artifacts/resource_summary.txt) · [ADS 层级资源](artifacts/resource_hier.txt)

## 高扇出与副本

Device Map 的 Other High Fanout Signal 列了 1,000 条，末位扇出 64。RND 写 DMA 的 `cancel_region_w[6]` 由 677 降到 152；ADS 例化中 `stop_w[0]` 和 `stop_w[7]` 接出两根独立命名网，`[6:1]` 对应浮空连接，两根接出的网均未上榜。RND 13 位独热状态中 `[5]` 为 73（卡 73 A 为 582）、`[11]` 为 191、`[12]` 为 66，其余位未上榜。NPU 结果读地址的 10 个驱动位各为 128。

ADS 的 preserve DFF 清单确认了 RND 的 26 组四位状态副本、各 8 个 alpha bank/valid 和 blit bank、4 个 FILL 格式位，以及 MEM 的 9 组三位写端口选择和 28 个 skid valid 副本。各组原网、榜内副本网和 ADS 证据见核对表，榜外网的精确扇出未取得。[副本核对](artifacts/fanout_copies.txt) · [非 CPU 前 30](artifacts/high_fanout_top30_non_cpu.txt) · [完整高扇出表](artifacts/high_fanout.txt)

## 布线与拥塞

| 通用轮次 | 卡 68 R2 未布通 | 卡 73 A 未布通 | 卡 75 未布通 | 卡 75 过用 | 卡 75 单轮（s） |
|---:|---:|---:|---:|---:|---:|
| 1 | 147,564 | 147,815 | 150,022 | 1,096,422 | 24.808 |
| 7 | 71,679 | 74,336 | 76,571 | 386,017 | 321.929 |
| 9 | 55,897 | 58,510 | 61,746 | 274,972 | 582.131 |
| 20 | 24,186 | 未取得 | 31,728 | 89,905 | 1,043.452 |
| 34 | 11,159 | 未取得 | 20,033 | 47,617 | 545.986 |
| 60 | 未取得 | 未取得 | 11,598 | 23,993 | 462.274 |
| 100 | 未取得 | 未取得 | 6,461 | 11,744 | 342.927 |
| 911 | 第 172 轮已归零 | 未取得 | 0 | 0 | 0.589 |

第 9、20、34 轮分别超过卡定的 58,510、30,000、15,000 止损线，本轮实际继续运行至完成。第 9 轮比卡 73 A 少用约 538 秒，但多剩 3,236 条未布通网。最慢通用轮次是第 16 轮（1,161.629 s）。通用归零后的 PDS 第 919 轮修整重新留下 430 条，最后在第 928 轮清零。路由日志未见 Route-0039 或 Route-0008。

第 9 轮前三条拥塞网为 `u_cpu/u_core/u_csr/_N440737`（354）、`u_cpu/u_core/m_system_commit_w`（352）、`u_cpu/u_core/update_index_r[3]`（323）。最后通用轮的拥塞网文件为空，网格最大值为 0。按卡 73 共用色标绘图，超过色标上限 67 的首轮格饱和显示，原始网格保留数值（首轮峰值 72）。

[逐轮日志](artifacts/routing_rounds.csv) · [尾段修整轮次](artifacts/routing_finish_rounds.csv) · [第 9 轮和最后一轮拥塞网](artifacts/congestion_top_nets.txt) · [拥塞网格索引](artifacts/congestion_grids.txt) · [拥塞图](artifacts/routing_congestion.png)

## 布线后时序

下表按同域路径统计，单位 ns。快、慢两角的完整时钟对报告另附。

| 时钟 | 约束 | 慢角 WNS / TNS | 违例终点 | 慢角 WHS / THS | 快角 WNS / TNS | 快角 WHS / THS |
|---|---:|---:|---:|---:|---:|---:|
| `clk_sys` | 125 MHz | −0.546 / −73.191 | 479 | +0.153 / 0 | +2.618 / 0 | +0.099 / 0 |
| `clk_npu` | 180 MHz | −0.123 / −0.970 | 34 | +0.113 / 0 | +1.960 / 0 | +0.100 / 0 |
| `clk_mem` | 125 MHz | −0.218 / −4.297 | 52 | +0.101 / 0 | +2.881 / 0 | +0.099 / 0 |

慢角 setup 合计 565 个违例终点，TNS −78.458 ns。慢角还有 5 条 `clk_rgmii_ref → clk_eth` 的 RGMII RX hold 违例，WHS −0.361 ns、THS −1.698 ns。该时钟对快角 WHS +0.136 ns。最差 hold 从 `rgmii_rx_ctl_i` 到 `u_rgmii/g_rx[4].u_input/opit_1/DI`。

| 最差慢角 setup 路径 | 裕量（ns） | 逻辑 / 走线（ns） |
|---|---:|---:|
| `clk_sys`：CPU I-cache tag DRM → 前端 IB predecode | −0.546 | 3.046 / 4.873 |
| `clk_npu`：卷积 MAC 阵列 APM → `local_sum_r[17]` | −0.123 | 0.437 / 4.650 |
| `clk_mem`：DDR PHY `calib_done` → MEM xbar RBUF DRM | −0.218 | 0.413 / 7.295 |

补充导出中，第 6 节关注模块的最差 setup slack 为 `u_rnd/u_alpha` −0.051、`u_rnd/u_blit` −0.132、`u_rnd/u_write` −0.138、`u_mem/u_xbar` −0.218、`u_npu/u_conv/u_datapath/u_weight_store` −0.076、`u_npu/u_post` +0.180 ns。模块归类检索起点、终点和逐级资源，一条路径可以匹配多个模块。

[双角时序原文汇总](artifacts/timing_summary.txt) · [≤ +0.5 ns setup 路径](artifacts/timing_setup_le_0p5.csv) · [关注模块路径](artifacts/timing_selected_modules_le_0p5.csv) · [导出覆盖](artifacts/timing_path_coverage.csv) · [最差 20 条 setup 逐级明细](artifacts/timing_setup_top20_detail.txt) · [最差 20 条 hold 逐级明细](artifacts/timing_hold_top20_detail.txt)

从同一已布线数据库在独立目录补跑时序报告，使用 `-delay_type max -max_path 100000 -slack_less_than 0.500001`，保留报表中 ≤ +0.5 ns 的 setup 路径。三个主要时钟相关的路径共 10,887 条，其中慢角同域 clk_sys 3,400 条、clk_npu 3,564 条、clk_mem 3,894 条，其余为跨域。三域分别覆盖 479、34、52 个 setup 违例终点，与原始报告汇总一致。逐级明细取原始双角报告，补充导出的原文保存在 `G:/codex_project/EdRV32-FPGA/card75-report-export/report_timing/edrv32_fpga_board_full_top.rtr`。[补充导出命令](artifacts/timing_export_settings.txt)

## 上板

### 比特流与程序

PDS 记录整片编程文件生成成功，用时 2 分 24 秒，文件 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST/generate_bitstream/edrv32_fpga_board_full_top.sbit`，9,188,552 字节。串口为 COM7 / 115200，BIOS 报 `CLK_SYS_HZ: 125000000`、`MEM_READY: 1`，ROM commit `92b38fd2`。[编程文件生成日志](artifacts/bitstream_generation.txt)

串口缓冲含三次成功加载，按 ELF 的非空可加载段字节数和入口分段。原始完整缓冲留在 `G:/codex_project/edrv32-card75/board/uart-current-buffer.log`。

| 时间（北京时间） | ELF | BIOS 记录的加载字节 / 段数 | 入口 |
|---|---|---:|---|
| 16:15:15.082 | `board_npu.elf` | 5,190,724 / 1 | `0x80000000` |
| 16:15:48.833 | `showcase-post.elf` | 12,768,880 / 5 | `0x90000000` |
| 16:19:29.862 | 卡 85 `showcase-grab-cpu.elf` | 29,417,992 / 5 | `0x90000000` |

### NPU 回归

**39/39 PASS**。D-01 至 D-20 全通过，CRC32 均为 `0738f96e`，与 C-YOLO 一致。C-YOLO 的 `PERF0=6187347` cycles，34.374 ms/帧，**29.091 FPS**。D 组 PERF0 为 6,182,208–6,193,231 cycles。[board_npu 串口](artifacts/uart/board_npu.log)

### Showcase 硬件后处理

`showcase-post.elf` 启动并进入实时识别。16:16:11.535–16:18:46.458 取得 **154 行连续** `vision fps=`，覆盖约 **2 分 35 秒**。16:18:47.560 出现下一次 Boot ROM 输出，随后重新加载另一份 ELF。任务卡要求的完整 5 分钟未取得。用户反馈程序能运行，检测框位置和类别的专项确认未取得。

| 字段 | 最小 / 中位数 / 最大 |
|---|---:|
| fps | 24 / **27** / 28 |
| npu（ms） | 34.9 / 34.9 / 35.1 |
| wait（ms） | 0.0 / 0.0 / 1.2 |
| decode（ms） | 0.0 / **0.0** / 0.0 |
| post_span（ms） | 0.0 / **0.1** / 0.4 |
| gui（ms） | 0.0 / 25.0 / 34.8 |
| e2e（ms） | 0.0 / 78.1 / 100.0 |
| period（ms） | 34.9 / 35.0 / 36.7 |

`gui` 与 `e2e` 各有 16 行原文为 0。其余 138 行的中位数分别为 25.35 ms 和 78.9 ms。[Showcase 串口分段](artifacts/uart/showcase_post.log) · [154 行实时识别原文](artifacts/uart/showcase_vision.log) · [逐项统计](artifacts/showcase_vision_stats.csv)

### 其他检查

| 项目 | 卡 75 `showcase-post.elf` 的记录 |
|---|---|
| 图片识别 / PC 收到候选 | 未取得 |
| 图像处理（高斯、Sobel，1 分钟） | 界面帧率和图像证据未取得 |
| RND 拷贝 / 半透明叠加 | 专项现场观察和照片未取得 |
| CoreMark | 串口成绩和截图未取得 |
| LVGL Benchmark | 指定 ELF 的成绩未取得 |
| 死机、复位 | 实时识别段后有一次 BIOS 启动和换 ELF；复位原因未取得 |

后续卡 85 ELF 的串口里有一轮完整 LVGL Benchmark，平均 **23 FPS**，ALL 为 **1,290 帧、43.270 ms 平均渲染**。该记录保留供参考，单独标明 ELF 归属。[跑分证据](artifacts/benchmark.txt) · [切换 ELF 的串口](artifacts/uart/elf_switch.log)

本机完整原始文件在工程目录下的 `place_route/run.log`、`place_route/edrv32_fpga_board_full_top.prr`、`place_route/CongestionNetInfo/`、`place_route/CongestionPlot/`、`device_map/edrv32_fpga_board_full_top.dmr`、`synthesize/edrv32_fpga_board_full_top.snr` 和 `report_timing/edrv32_fpga_board_full_top.rtr`。
