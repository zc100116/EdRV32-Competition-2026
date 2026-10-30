# 20261030-10-b3-timing-rerun 阶段报告

四个工程的编译、综合、device_map 均已完成。B3V 已完成布局布线、STA 和 bitstream；B3VN、B3R、B3F 仍在布线。本次按用户要求先回传已完成阶段及进行中快照，没有启动、停止或重跑任何 PDS 流程。

当前检出代码 commit：`05088f4b13d5d8399f63deef48dc2760ad0f5bec`（记录检出位置，不另行核验构建来源）。工程均复用 `G:/codex_project/EdRV32-FPGA/EdRV32-<工程名>`，实际目录为 B3V、B3VN、B3R、B3F。

## 阶段耗时与资源

耗时是日志 Action 的 Real time；完整 CPU time、Process CPU time、峰值内存及 W/C/E 行数在各工程 flow_summary.txt。资源表取 device_map 原生 DMR，DRM 沿用报告的块数口径；综合层级表另有 DRM36K 等效量。

| 工程 | compile | synthesize | device_map | PnR | LUT | FF | APM | DRM | 分布式 RAM | IO | GPLL/PPLL |
|---|---|---|---|---|---|---|---|---|---|---|---|
| B3V | 0h:1m:45s | 0h:4m:43s | 0h:1m:11s | 0h:24m:45s | 52760 (34%) | 49713 (16%) | 161 (22%) | 109 (27%) | 346 (1%) | 137 (35%) | 5 (50%)/2 (20%) |
| B3VN | 0h:2m:34s | 0h:8m:24s | 0h:2m:14s | 进行中 | 80508 (51%) | 85970 (27%) | 451 (61%) | 265 (64%) | 794 (3%) | 137 (35%) | 6 (60%)/2 (20%) |
| B3R | 0h:2m:5s | 0h:5m:14s | 0h:0m:55s | 进行中 | 51928 (33%) | 35062 (11%) | 138 (19%) | 110 (27%) | 233 (1%) | 94 (24%) | 4 (40%)/2 (20%) |
| B3F | 0h:3m:47s | 0h:16m:0s | 0h:2m:1s | 进行中 | 99201 (63%) | 94809 (30%) | 569 (77%) | 325 (79%) | 794 (3%) | 137 (35%) | 6 (60%)/2 (20%) |

## 布线慢的证据

B3R、B3F 存在显著的 RND 组合长路径，综合估算 clk_mem WNS 分别为 −18.535 ns（25 级）和 −18.700 ns（22 级），终点均为 u_draw/bank_sparse_r[0]。这是优先交给 RTL 侧分析的线索，不能直接当作布线后的结果。

布线日志中 B3R/B3F 的 before-route Worst slack 原始值为 −16185/−17717，TNS 为 −59151227/−108811314；B3VN 为 +377、TNS 0，B3V 为 +926、TNS 0。该日志行未注明单位，这里保留原值，不转换成 ns。B3VN 布局后没有负裕度仍然布线很慢，说明耗时不能只归因于负 slack。

| 工程 | 快照最后迭代 | 未布通 general nets | overused（原始计数） |
|---|---|---|---|
| B3V | 128 | 0 | 0 |
| B3VN | 14 | 58938 | 251169 |
| B3R | 36 | 8071 | 26324 |
| B3F | 13 | 91963 | 509292 |

三个进行中工程的未布通网络及 overused 随迭代总体下降，说明仍在收敛；大量 overused 是布线拥塞线索，不能保证最终成功。全部迭代见 route_progress.tsv。B3F 的 APM 77%、DRM 79% 增加了资源放置及布线压力；B3R 总 LUT 只有 33%，也不能排除局部拥塞。MT total route time 逐行保存，不累加成总墙钟时间。

系统快照时间：2026-10-30T14:41:46.5939407+08:00。物理内存 31.67 GiB，可用 4.09 GiB；系统提交量 67.25 GiB / 提交上限 76.19 GiB。

| PnR 进程 | 已运行分钟 | CPU 秒 | 工作集 GiB | 私有提交量 GiB |
|---|---|---|---|---|
| B3R | 102.84 | 391.83 | 3.06 | 5.65 |
| B3VN | 98.13 | 649.52 | 1.61 | 8.04 |
| B3F | 78.98 | 237.98 | 1.85 | 9.15 |

当前单点 PagesInput/sec=0，PageReads/sec=0。此前排查中曾观测到全系统 8916/2274 的非零采样值，当前快照为零，表明不能把换页视为持续状态。私有提交量不是页面文件驻留量。并行运行及提交量说明内存压力，但现有采样不能量化换页对各工程耗时的贡献。待本轮结束，后续可按任务卡串行运行较大的工程进行比较；本次未改变运行方式。

## 综合估算最差路径

以下全部是综合估算，单位 ns；同时保留正裕度风险。详细路径、完整时钟域和层级资源见各工程 artifacts。

| 工程 | 时钟 | WNS | 逻辑级数 | 起点 → 终点 |
|---|---|---|---|---|
| B3V | clk_sys | -0.074 | 17 | `u_sys/u_plic/priority_r[2][1]/CLK (GTP_DFF_CE)` → `u_sys/u_plic/claimed_r[15]/D (GTP_DFF_C)` |
| B3V | clk_mem | +0.122 | 8 | `u_mem/u_xbar/u_rbuf/u_ram/u_ip/U_ipm2l_sdpram_ip_ram_mem_xbar_r/ADDR_LOOP[0].DATA_LOOP[3].U_GTP_DRM36K_E1/CLKB (GTP_DRM36K_E1)` → `u_mem/u_perf_mon/N106/CEY1 (GTP_APM_E2)` |
| B3V | clk_eth | +3.334 | 3 | `u_eth/u_tx_fifo/u_memory/u_ip/U_ipm2l_sdpram_ip_ram_eth_fifo/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/CLKB (GTP_DRM18K_E1)` → `u_eth/u_tx_front/crc_r[19]/D (GTP_DFF_SE)` |
| B3VN | clk_sys | -1.020 | 19 | `u_sys/u_plic/pending_r[1]/CLK (GTP_DFF_C)` → `u_sys/u_plic/claimed_r[15]/D (GTP_DFF_C)` |
| B3VN | clk_npu | +0.006 | 15 | `u_npu/u_conv/residual_pairs_r[0]/CLK (GTP_DFF_CE)` → `u_npu/u_conv/residual_addr_r[31]/D (GTP_DFF_E)` |
| B3VN | clk_mem | +0.206 | 12 | `u_mem/u_xbar/u_sched/funded_r[0]/CLK (GTP_DFF_CE)` → `u_mem/u_xbar/u_rbuf/port_addr_r[2][1]/D (GTP_DFF_E)` |
| B3VN | clk_eth | +3.307 | 3 | `u_eth/u_tx_fifo/u_memory/u_ip/U_ipm2l_sdpram_ip_ram_eth_fifo/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/CLKB (GTP_DRM18K_E1)` → `u_eth/u_tx_front/crc_r[19]/D (GTP_DFF_SE)` |
| B3R | clk_sys | -1.077 | 18 | `u_sys/u_plic/priority_r[1][2]/CLK (GTP_DFF_CE)` → `u_sys/u_plic/pending_r[15]/D (GTP_DFF_C)` |
| B3R | clk_mem | -18.535 | 25 | `u_rnd/command_r[176]/CLK (GTP_DFF_E)` → `u_rnd/u_draw/bank_sparse_r[0]/D (GTP_DFF_E)` |
| B3F | clk_sys | -1.785 | 20 | `u_soc/u_sys/u_plic/pending_r[1]/CLK (GTP_DFF_C)` → `u_soc/u_sys/u_plic/axi_rdata_o[35]/D (GTP_DFF_E)` |
| B3F | clk_npu | -0.770 | 15 | `u_soc/u_npu/u_apb_bridge/request_r[36]/CLK (GTP_DFF_E)` → `u_soc/u_npu/u_conv/residual_addr_r[31]/D (GTP_DFF_E)` |
| B3F | clk_mem | -18.700 | 22 | `u_soc/u_rnd/command_r[3]/CLK (GTP_DFF_E)` → `u_soc/u_rnd/u_draw/bank_sparse_r[0]/D (GTP_DFF_E)` |
| B3F | clk_eth | +3.460 | 3 | `u_soc/u_eth/u_tx_fifo/u_memory/u_ip/U_ipm2l_sdpram_ip_ram_eth_fifo/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/CLKB (GTP_DRM18K_E1)` → `u_soc/u_eth/u_tx_front/crc_r[31]/D (GTP_DFF_SE)` |

## B3V 布线后 STA

原生报告结论 All Constraints Met。slow 角 clk_mem +0.305 ns、clk_sys +0.762 ns、clk_eth +0.189 ns；正裕度仍偏紧，特别是 eth 和 mem。相比卡 07：mem −0.554 → +0.305、sys +0.182 → +0.762、eth +0.798 → +0.189 ns。当前通过不代表以后集成更多模块后仍有足够裕度。

| 分析 | 角 | launch → capture | WNS/WHS ns | TNS/THS ns | 违例端点 | 总端点 |
|---|---|---|---|---|---|---|
| Setup | Slow | clk_cam0 → clk_cam0 | 5.536 | 0.000 | 0 | 298 |
| Setup | Slow | clk_cam1 → clk_cam1 | 5.430 | 0.000 | 0 | 298 |
| Setup | Slow | clk_sys → clk_sys | 0.762 | 0.000 | 0 | 44213 |
| Setup | Slow | clk_pix → clk_pix | 6.874 | 0.000 | 0 | 5709 |
| Setup | Slow | clk_serial → clk_serial | 1.706 | 0.000 | 0 | 8 |
| Setup | Slow | rst_clk → rst_clk | 4.633 | 0.000 | 0 | 419 |
| Setup | Slow | clk_mem → clk_mem | 0.305 | 0.000 | 0 | 125188 |
| Setup | Slow | phy_dq_sysclk_1 → clk_mem | 2.915 | 0.000 | 0 | 260 |
| Setup | Slow | phy_dq_sysclk_0 → clk_mem | 3.896 | 0.000 | 0 | 1 |
| Setup | Slow | clk_mem → phy_dq_sysclk_0 | 1.817 | 0.000 | 0 | 196 |
| Setup | Slow | clk_mem → phy_dq_sysclk_1 | 1.630 | 0.000 | 0 | 420 |
| Setup | Slow | clk_eth → clk_eth | 0.189 | 0.000 | 0 | 712 |
| Hold | Slow | clk_cam0 → clk_cam0 | 0.142 | 0.000 | 0 | 298 |
| Hold | Slow | clk_cam1 → clk_cam1 | 0.170 | 0.000 | 0 | 298 |
| Hold | Slow | clk_sys → clk_sys | 0.143 | 0.000 | 0 | 44213 |
| Hold | Slow | clk_pix → clk_pix | 0.112 | 0.000 | 0 | 5709 |
| Hold | Slow | clk_serial → clk_serial | 0.346 | 0.000 | 0 | 8 |
| Hold | Slow | rst_clk → rst_clk | 0.192 | 0.000 | 0 | 419 |
| Hold | Slow | clk_mem → clk_mem | 0.105 | 0.000 | 0 | 125188 |
| Hold | Slow | phy_dq_sysclk_1 → clk_mem | 0.546 | 0.000 | 0 | 260 |
| Hold | Slow | phy_dq_sysclk_0 → clk_mem | 1.053 | 0.000 | 0 | 1 |
| Hold | Slow | clk_mem → phy_dq_sysclk_0 | 0.502 | 0.000 | 0 | 196 |
| Hold | Slow | clk_mem → phy_dq_sysclk_1 | 0.479 | 0.000 | 0 | 420 |
| Hold | Slow | clk_eth → clk_eth | 0.265 | 0.000 | 0 | 712 |
| Recovery | Slow | clk_cam0 → clk_cam0 | 8.651 | 0.000 | 0 | 24 |
| Recovery | Slow | clk_cam1 → clk_cam1 | 8.108 | 0.000 | 0 | 24 |
| Recovery | Slow | clk_sys → clk_sys | 4.929 | 0.000 | 0 | 3147 |
| Recovery | Slow | clk_pix → clk_pix | 8.790 | 0.000 | 0 | 360 |
| Recovery | Slow | rst_clk → rst_clk | 5.052 | 0.000 | 0 | 97 |
| Recovery | Slow | clk_mem → clk_mem | 2.252 | 0.000 | 0 | 11214 |
| Recovery | Slow | clk_eth → clk_eth | 4.517 | 0.000 | 0 | 59 |
| Removal | Slow | clk_cam0 → clk_cam0 | 0.298 | 0.000 | 0 | 24 |
| Removal | Slow | clk_cam1 → clk_cam1 | 0.425 | 0.000 | 0 | 24 |
| Removal | Slow | clk_sys → clk_sys | 0.598 | 0.000 | 0 | 3147 |
| Removal | Slow | clk_pix → clk_pix | 1.076 | 0.000 | 0 | 360 |
| Removal | Slow | rst_clk → rst_clk | 0.464 | 0.000 | 0 | 97 |
| Removal | Slow | clk_mem → clk_mem | 0.326 | 0.000 | 0 | 11214 |
| Removal | Slow | clk_eth → clk_eth | 0.753 | 0.000 | 0 | 59 |
| Setup | Fast | clk_cam0 → clk_cam0 | 7.502 | 0.000 | 0 | 298 |
| Setup | Fast | clk_cam1 → clk_cam1 | 7.451 | 0.000 | 0 | 298 |
| Setup | Fast | clk_sys → clk_sys | 4.009 | 0.000 | 0 | 44213 |
| Setup | Fast | clk_pix → clk_pix | 9.411 | 0.000 | 0 | 5709 |
| Setup | Fast | clk_serial → clk_serial | 2.084 | 0.000 | 0 | 8 |
| Setup | Fast | rst_clk → rst_clk | 5.919 | 0.000 | 0 | 419 |
| Setup | Fast | clk_mem → clk_mem | 3.315 | 0.000 | 0 | 125188 |
| Setup | Fast | phy_dq_sysclk_1 → clk_mem | 4.671 | 0.000 | 0 | 260 |
| Setup | Fast | phy_dq_sysclk_0 → clk_mem | 5.232 | 0.000 | 0 | 1 |
| Setup | Fast | clk_mem → phy_dq_sysclk_0 | 4.015 | 0.000 | 0 | 196 |
| Setup | Fast | clk_mem → phy_dq_sysclk_1 | 3.867 | 0.000 | 0 | 420 |
| Setup | Fast | clk_eth → clk_eth | 3.341 | 0.000 | 0 | 712 |
| Hold | Fast | clk_cam0 → clk_cam0 | 0.100 | 0.000 | 0 | 298 |
| Hold | Fast | clk_cam1 → clk_cam1 | 0.113 | 0.000 | 0 | 298 |
| Hold | Fast | clk_sys → clk_sys | 0.100 | 0.000 | 0 | 44213 |
| Hold | Fast | clk_pix → clk_pix | 0.112 | 0.000 | 0 | 5709 |
| Hold | Fast | clk_serial → clk_serial | 0.225 | 0.000 | 0 | 8 |
| Hold | Fast | rst_clk → rst_clk | 0.158 | 0.000 | 0 | 419 |
| Hold | Fast | clk_mem → clk_mem | 0.100 | 0.000 | 0 | 125188 |
| Hold | Fast | phy_dq_sysclk_1 → clk_mem | 0.100 | 0.000 | 0 | 260 |
| Hold | Fast | phy_dq_sysclk_0 → clk_mem | 0.241 | 0.000 | 0 | 1 |
| Hold | Fast | clk_mem → phy_dq_sysclk_0 | 0.103 | 0.000 | 0 | 196 |
| Hold | Fast | clk_mem → phy_dq_sysclk_1 | 0.099 | 0.000 | 0 | 420 |
| Hold | Fast | clk_eth → clk_eth | 0.167 | 0.000 | 0 | 712 |
| Recovery | Fast | clk_cam0 → clk_cam0 | 9.239 | 0.000 | 0 | 24 |
| Recovery | Fast | clk_cam1 → clk_cam1 | 8.844 | 0.000 | 0 | 24 |
| Recovery | Fast | clk_sys → clk_sys | 6.885 | 0.000 | 0 | 3147 |
| Recovery | Fast | clk_pix → clk_pix | 10.580 | 0.000 | 0 | 360 |
| Recovery | Fast | rst_clk → rst_clk | 6.260 | 0.000 | 0 | 97 |
| Recovery | Fast | clk_mem → clk_mem | 4.366 | 0.000 | 0 | 11214 |
| Recovery | Fast | clk_eth → clk_eth | 5.859 | 0.000 | 0 | 59 |
| Removal | Fast | clk_cam0 → clk_cam0 | 0.202 | 0.000 | 0 | 24 |
| Removal | Fast | clk_cam1 → clk_cam1 | 0.289 | 0.000 | 0 | 24 |
| Removal | Fast | clk_sys → clk_sys | 0.402 | 0.000 | 0 | 3147 |
| Removal | Fast | clk_pix → clk_pix | 0.714 | 0.000 | 0 | 360 |
| Removal | Fast | rst_clk → rst_clk | 0.317 | 0.000 | 0 | 97 |
| Removal | Fast | clk_mem → clk_mem | 0.217 | 0.000 | 0 | 11214 |
| Removal | Fast | clk_eth → clk_eth | 0.506 | 0.000 | 0 | 59 |

当前原生默认 report_timing 含 232 条路径记录（跨时钟、角和路径类型），已全部保存索引及明细，并额外汇总 0–1 ns 的正裕度路径。每个角的 setup/hold 最差路径也已整理。setup_top200_<时钟>.txt 文件头明确标注覆盖不足：本次未另行导出每时钟 200 条，以避免在三个 PnR 进程运行时启动额外 STA。后续最终报告需补足该项。B3VN/B3R/B3F 的布线后时序尚未取得，不以综合结果代填。

## 警告与产物范围

各工程保存 CMR/SNR/DMR、include 关系、综合控制集、APM/DRM/LUTRAM、carry-chain、约束检查报告、层级资源及高扇出表。B3V 另有 PRR/RTR 和时钟资源报告。logs/warnings_detail.txt 保存各阶段全部 W/C/E 原文，flow_summary.txt 统计行数；C 行按原始严重级别保留，不擅自当成致命错误。原生报告内的 loop、截位、未驱动、扇出等警告均可由 Claude 直接复核。

未上传完整 run.log、数据库、工程/IP 目录或 bitstream。执行摘要保留阶段耗时和路由收敛行。完整本地日志位于上述各工程的 <stage>/run.log；PDS 报告在对应 compile/synthesize/device_map/place_route/report_timing 子目录。上板启动信息和 BIOS 验收本次未取得。

这是按用户要求提交的阶段回传；其余三个工程结束后仍需追加最终 PnR/STA/bitstream 结果。

大文件清单（超过 3 MiB；保留原生报告或完整警告供诊断）：

- `artifacts/B3F/logs/execution_excerpt.txt`：3.04 MiB
- `artifacts/B3F/logs/warnings_detail.txt`：3.04 MiB
