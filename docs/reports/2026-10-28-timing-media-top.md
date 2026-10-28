# 媒体与网络模块合并测量：资源和时序（V-W2）

| 项 | 内容 |
|---|---|
| commit | 任务卡 `f757c4f`（RTL 同 `91368b8` 之后的 main），结果提交 `756ebfc` |
| 任务卡 | `tasks/win/20261028-04-media-cpu-probes/`（A 部分） |
| 工具 | PDS 2022.2-SP6.1（build 138931），ADS 综合 |
| 器件 | PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_media_top`，`edrv32_fpga_media_top.fdc`：clk_mem（K21）、clk_ext（D18）均 8.000 ns（125 MHz），两域异步 |
| 原始数据 | `tasks/win/20261028-04-media-cpu-probes/artifacts/media/`；完整报告在 Windows `G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/` |

导入脚本 `fpga/scripts/import_media_top.tcl` 在本次改为 include 列表加 `-force_to_run`（Windows 端修正，随结果提交）。

## IP

六个 IP 的模块名和端口与 `rtl/tech/` 包装一致（`artifacts/media/ip/`）。`ip_ram_geo_src` 的不同读写位宽配置可以生成并通过 PnR。

| IP | 每实例 | 实例数 | DRM36K 当量 |
|---|---|---:|---:|
| ip_ram_vin_wfifo | 4 × DRM36K | 3 | 12 |
| ip_ram_disp_scan | 4 × DRM36K | 1 | 4 |
| ip_ram_pix_line | 2 × DRM36K | 4 | 8 |
| ip_ram_geo_src | 2 × DRM36K | 8 | 16 |
| ip_ram_eth_buf | 1 × DRM36K | 2 | 2 |
| ip_ram_eth_fifo | 1 × DRM18K | 2 | 1 |

## 资源（PnR 后，按层次）

| 模块 | LUT | FF | 分布式 RAM | APM | DRM36K 当量 | SoC 9.3 / 模块规格 |
|---|---:|---:|---:|---:|---:|---|
| u_vin | 3482 | 4205 | 37 | 0 | 12 | VIN ≤ 4K（vin-spec 7） |
| u_pix | 5593 | 1166 | 0 | 96 | 11 | 规格估算 6 DRM36K |
| u_disp | 1448 | 1729 | 0 | 0 | 4 | — |
| VIN + PIX + DISP | **10523** | 7100 | 37 | 96 | 27 | **≤ 10K LUT，超 5.2%** |
| u_geo | 3238 | 2641 | 0 | 9 | 16 | ≤ 8K LUT；规格估算 6 DRM36K |
| u_eth | 3863 | 3826 | 76 | 0 | 3 | ≤ 5K LUT；规格估算约 6 DRM18K |
| 测量顶层自身（激励/观测） | 1385 | 2909 | 0 | 0 | 0 | 不计入模块 |
| 合计 | 19009 | 16480 | 113 | 105 | 46 | — |

器件容量：APM 740、DRM 415、LUT 159800（CLMA + CLMS）。

Linux Yosys 参考（RAM 黑盒）：PIX 32535、GEO 9043、ETH 8279 LUT6，比 PDS 大 2–6 倍（PDS 把 PIX、GEO 的乘法映射到 APM），不能作为资源判断依据。

## 时序

| 时钟 / 角 | WNS ns | TNS ns | WHS ns | setup 违例端点 | Fmax MHz（`1000 / (8 − WNS)`） |
|---|---:|---:|---:|---:|---:|
| clk_mem / slow | **−7.667** | −13627.003 | +0.146 | 6356 | 63.8 |
| clk_mem / fast | −1.862 | −217.617 | +0.101 | 314 | — |
| clk_ext / slow | +2.064 | 0 | +0.155 | 0 | — |
| clk_ext / fast | +4.623 | 0 | +0.105 | 0 | — |

clk_mem 导出的最差 200 条全部在 PIX：

| 起点 → 终点 | 条数（top200 内） | 最差 ns | 级数 |
|---|---:|---:|---:|
| `u_pix/u_stage2` 行 RAM → `u_pix/u_point2` 乘法 APM | 48 | −7.667 | 14 |
| `u_pix/u_stage1` → `u_pix/u_stage1` | 92 | −6.758 | — |
| `u_pix/u_stage2` → `u_pix/u_stage2` | 60 | −6.570 | — |

最差路径：行 RAM 读出（tco 1.644）→ 窗口选择 → 灰度乘法 APM → APM 级联加 → 进位链 → 比较/饱和 → `u_point2` 乘法 APM 输入，全部在一拍内（`edrv32_pix_kernel.v` 整体是组合逻辑，`edrv32_pix_point2` 的乘法也接在其后）。

导出范围只有每域最差 200 条和 0 < slack < 1 ns 的 200 条；PIX 以外的模块是否有违例**未取得**。0 < slack < 1 ns 的路径主要从测量顶层的 `stim_mem_r` 出发（VIN 内存源、ETH 寄存器），以及 `u_disp/u_perf0 → u_regs`、`u_geo/u_source → u_bilinear`。

clk_ext（DISP 扫描侧）在 125 MHz 约束下最差 +2.064 ns，满足 74.25 MHz 目标。
