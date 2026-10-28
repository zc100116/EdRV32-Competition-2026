# 媒体与网络模块合并测量第三轮：ETH、GEO、VIN 时序修复后（V-W4）

| 项 | 内容 |
|---|---|
| commit | `b23c03c`（V-R7 ETH/GEO/VIN 修复之后），结果提交 `ec77019`、`eee2bcc`（分支 `win/20261028-07-media-r3-b1`） |
| 任务卡 | `tasks/win/20261028-07-media-r3-b1/` A 部分 |
| 工具 / 器件 | PDS 2022.2-SP6.1（build 138931），ADS；PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_media_top`；clk_mem（K21）、clk_ext（D18）均 8.000 ns，异步组；与第二轮相同 |
| 原始数据 | `tasks/win/20261028-07-media-r3-b1/artifacts/media/`；完整报告在 Windows `G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/` |
| 上一轮 | `docs/reports/2026-10-28-timing-media-top-r2.md` |

## 时序

| 时钟 / 角 | WNS ns | TNS ns | WHS ns | setup 违例端点 | Fmax MHz（`1000 / (8 − WNS)`） | 上一轮 |
|---|---:|---:|---:|---:|---:|---|
| clk_mem / slow | **+0.388** | 0 | +0.103 | 0 | 131.4 | −1.270，542，107.9 MHz |
| clk_mem / fast | +3.243 | 0 | +0.100 | 0 | — | +2.486 |
| clk_ext / slow | +1.898 | 0 | +0.169 | 0 | — | +1.475 |
| clk_ext / fast | +4.444 | 0 | +0.115 | 0 | — | +4.025 |

clk_mem 125 MHz 满足：全量违例端点导出为 0，与 PDS 汇总一致。

clk_mem slow 最差 200 条按终点模块：PIX 115 条（最差 +0.388）、VIN 58（+0.652）、ETH 18（+0.802）、DISP 5（+0.878）、GEO 3（+0.932）、观测寄存器 1。最差路径是测量顶层的激励寄存器 `stim_mem_r[10]` → `u_pix/u_stage2/u_kernel0` 乘法器（APM）的 CE，4 级；起点属于测量顶层的激励逻辑，在 SoC 中由 PIX 寄存器块驱动。VIN 的最差路径是 `stim_mem_r` → `u_vin/u_regs/perf_r` 计数器进位链（15 级）。上一轮的 ETH `header_r` → ARP 比较、GEO `desc_r` → `perf_r`、VIN `address_left_r` 三组路径均已不在违例中。

clk_ext 最差路径：`u_disp/u_timing/vertical_r` → DISP 扫描 FIFO RAM 的 CEB，4 级，+1.898。

## 资源（PnR 后，按层次）

| 模块 | LUT | FF | 分布式 RAM | APM | DRM36K 当量 | 上一轮 LUT |
|---|---:|---:|---:|---:|---:|---:|
| u_vin | 3562 | 4213 | 37 | 0 | 12 | 3532 |
| u_pix | 4943 | 7107 | 0 | 132 | 11 | 4935 |
| u_disp | 1468 | 1729 | 0 | 0 | 4 | 1452 |
| VIN + PIX + DISP | **9973** | 13049 | 37 | 132 | 27 | 9919 |
| u_geo | 3184 | 3002 | 0 | 9 | 16 | 3357 |
| u_eth | 3858 | 4234 | 76 | 0 | 3 | 3841 |
| 整个测量顶层 | 18416 | 23199 | 113 | 141 | 46 | 18506 |

VIN + PIX + DISP 在 SoC 9.3 的 10K 预算以内（余 27 LUT）。GEO −173 LUT、+361 FF，ETH +408 FF（修复中加入的流水寄存器）。
