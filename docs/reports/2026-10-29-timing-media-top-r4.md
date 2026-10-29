# 媒体与网络模块合并测量第四轮：V-R8 余量提升后（V-W5）

| 项 | 内容 |
|---|---|
| commit | `90cf049`（V-R8 之后），结果提交 `e462643`（分支 `win/20261029-01-media-r4`） |
| 任务卡 | `tasks/win/20261029-01-media-r4/` |
| 工具 / 器件 | PDS 2022.2-SP6.1（build 138931），ADS；PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_media_top`；clk_mem（K21）、clk_ext（D18）均 8.000 ns，异步组；与第三轮相同 |
| 原始数据 | `tasks/win/20261029-01-media-r4/artifacts/`；完整报告在 Windows `G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/` |
| 上一轮 | `docs/reports/2026-10-28-timing-media-top-r3.md` |

## 时序

| 时钟 / 角 | WNS ns | TNS ns | WHS ns | setup 违例端点 | Fmax MHz（`1000 / (8 − WNS)`） | 上一轮 |
|---|---:|---:|---:|---:|---:|---|
| clk_mem / slow | **+0.592** | 0 | +0.143 | 0 | 135.0 | +0.388，131.4 MHz |
| clk_mem / fast | +3.497 | 0 | +0.100 | 0 | — | +3.243 |
| clk_ext / slow | +1.872 | 0 | +0.155 | 0 | — | +1.898 |
| clk_ext / fast | +4.439 | 0 | +0.105 | 0 | — | +4.444 |

V-R8 的目标 +1.0 ns 未达到。0 < slack < 1 ns 的端点 54 个（上一轮 144 个），分组：

| 起点 → 终点 | 端点 | 最差 ns | 级数 |
|---|---:|---:|---:|
| `u_pix/discard_r` → `u_pix/advance_kernel1x/2x_r`、`advance_filter1/2_r` | 42 | 0.592 | 3 |
| `stim_mem_r` → `u_geo/u_tiles/v_o` | 6 | 0.798 | 7 |
| `u_eth/u_rx/header_r` → `u_eth/u_rx/start_r` | 4 | 0.841 | 9 |
| `u_vin/u_fmt1/width_r` → `u_vin/u_msrc/u_buffer/head_data_r` | 2 | 0.952 | 8 |

最差路径是 PIX 的 `discard_r`（寄存的丢弃标志）经"清空或下一拍可推进"逻辑到 103 位推进寄存器的 D 端，3 级，延迟主要在到分散寄存器的布线。原来的 VIN abort → PIX `advance_w`（扇出 2358）路径已消失。

## 复制寄存器

103 位推进寄存器和 60 位 kernel 操作码寄存器在综合网表中均带 `PAP_PRESERVE = TRUE`（Compile 日志 12 条 "Convert attribute name from syn_preserve to PAP_PRESERVE"），布局布线后 163 位都是独立的物理 FF。PnR 后每位扇出最大 231（`advance_kernel21_r[0]`），原单一网络 2358。逐位扇出见 `artifacts/replication_fanout.tsv`。结论：RTL 中 `/* synthesis syn_preserve=1 */` 可用于防止 PDS 合并复制寄存器。

## 资源（PnR 后，按层次）

| 模块 | LUT | FF | 分布式 RAM | APM | DRM36K 当量 | 上一轮 LUT |
|---|---:|---:|---:|---:|---:|---:|
| u_vin | 3521 | 4862 | 37 | 0 | 12 | 3562 |
| u_pix | 4947 | 7860 | 0 | 132 | 11 | 4943 |
| u_disp | 1420 | 1828 | 0 | 0 | 4 | 1468 |
| VIN + PIX + DISP | **9888** | 14550 | 37 | 132 | 27 | 9973 |
| u_geo | 3054 | 3306 | 0 | 9 | 16 | 3184 |
| u_eth | 3899 | 4462 | 76 | 0 | 3 | 3858 |
| 整个测量顶层 | 18223 | 25227 | 113 | 141 | 46 | 18416 |

V-R8 增加约 2000 FF（寄存的事件、复制的使能），LUT 略降。本轮不含 VIN CH2（SoC 9.3 中计入 NPU 预算）。
