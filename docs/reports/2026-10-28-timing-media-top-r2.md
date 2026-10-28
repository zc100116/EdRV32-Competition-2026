# 媒体与网络模块合并测量第二轮：PIX 流水化后（V-W3）

| 项 | 内容 |
|---|---|
| commit | `8b3d5df`（PIX 流水化 `d9d5258` 之后），结果提交 `7bd88a7`（协调者分支 `d5be65a`） |
| 任务卡 | `tasks/win/20261028-05-media-r2/` |
| 工具 / 器件 | PDS 2022.2-SP6.1（build 138931），ADS；PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_media_top`；clk_mem（K21）、clk_ext（D18）均 8.000 ns，异步组 |
| 原始数据 | `tasks/win/20261028-05-media-r2/artifacts/`；完整报告在 Windows `G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/` |
| 上一轮 | `docs/reports/2026-10-28-timing-media-top.md` |

## 时序

| 时钟 / 角 | WNS ns | TNS ns | WHS ns | setup 违例端点 | Fmax MHz（`1000 / (8 − WNS)`） | 上一轮 |
|---|---:|---:|---:|---:|---:|---|
| clk_mem / slow | **−1.270** | −250.561 | +0.136 | 542 | 107.9 | −7.667，6356，63.8 MHz |
| clk_mem / fast | +2.486 | 0 | +0.100 | 0 | — | −1.862，314 |
| clk_ext / slow | +1.475 | 0 | +0.153 | 0 | — | +2.064 |
| clk_ext / fast | +4.025 | 0 | +0.101 | 0 | — | +4.623 |

clk_mem slow 全部 542 个违例端点已导出（`endpoints_violating.tsv`，与 PDS 汇总一致）。按终点模块：

| 模块 | 违例端点 | 最差 ns | 主要分组（起点 → 终点，端点数，最差 ns，级数） |
|---|---:|---:|---|
| PIX | 0 | — | — |
| DISP | 0 | — | — |
| ETH | 196 | −1.270 | `u_rx/header_r` → `arp_ip_r`/`arp_mac_r`/`u_rx_write/metadata_r`/`u_rx/start_r`/`u_rx_packets`（32/48/55/19/…，−1.270 至 −0.81，20–22 级） |
| GEO | 174 | −0.995 | `desc_r` → `u_regs/perf_r`（62，−0.995，22 级）；`u_source` 源缓冲 RAM → `u_bilinear` 乘法输入（约 100，−0.478 至 −0.06，4–5 级）；`desc_r` → `u_bilinear`（−0.193，13 级） |
| VIN | 172 | −0.348 | `g_channel[0].u_write/address_left_r` → 两个通道的 `write_data_r`、`count_r`、`write_fifo/fetch_bin_r`（93/63/5/5，−0.348 至 −0.227，10–11 级） |

最差路径（ETH）：`u_rx/header_r[144]` → 4 段首尾相接的进位链（`N1453`、`N1462`、`pseudo_w_2`、`N1437`、`N53`）→ 选择 → `arp_ip_r` 的 CE，20 级。

GEO 最差路径：`desc_r` → `u_range` 两次减法（`span_y`）→ 写字节使能 → 求和 → `u_regs/perf_r` 计数器进位链，22 级。

## 资源（PnR 后，按层次）

| 模块 | LUT | FF | 分布式 RAM | APM | DRM36K 当量 | 上一轮 LUT / APM |
|---|---:|---:|---:|---:|---:|---|
| u_vin | 3532 | 4205 | 37 | 0 | 12 | 3482 / 0 |
| u_pix | 4935 | 7107 | 0 | 132 | 11 | 5593 / 96 |
| u_disp | 1452 | 1729 | 0 | 0 | 4 | 1448 / 0 |
| VIN + PIX + DISP | **9919** | 13041 | 37 | 132 | 27 | 10523（超 10K） |
| u_geo | 3357 | 2641 | 0 | 9 | 16 | 3238 / 9 |
| u_eth | 3841 | 3826 | 76 | 0 | 3 | 3863 / 0 |
| 整个测量顶层 | 18506 | 22422 | 113 | 141 | 46 | 19009 / 105 |

PIX 流水化后 LUT −658（÷9 改为常数乘），FF +5941，APM +36；VIN + PIX + DISP 回到 SoC 9.3 的 10K 预算以内。器件容量 APM 740、DRM 415。
