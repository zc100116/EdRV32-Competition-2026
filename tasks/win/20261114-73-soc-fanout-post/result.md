# 卡 73 结果

| 项 | A（SW 40） | B（SW 20） |
|---|---|---|
| 代码 HEAD | `cc5df8890ed7f130c0dea9a52a70562028bee174` | 同 A |
| Device Map 完成时间（本地） | 2026-11-14 13:34:48 | 2026-11-14 13:34:52 |
| Device Map 用时 | 1 分 38 秒 | 1 分 38 秒 |
| 布线进度（2026-11-14 15:37:21 +08:00） | 已完成通用第 7 轮 | 已完成通用第 7 轮 |

## 资源（与卡 68、卡 72 对比）

| 项 | 卡 68 R2 | 卡 72 | 卡 73 A、B |
|---|---:|---:|---:|
| Device Map LUT / FF | 91,208 / 107,042 | 88,042 / 108,171 | 88,296 / 108,806 |
| Device Map DRM / APM | 286 / 372 | 298 / 373 | 298 / 373 |
| ADS `u_npu` LUT / FF | 16,945 / 39,249 | 18,511 / 41,772 | 18,710 / 42,364 |
| ADS `u_rnd` LUT / FF | 16,796 / 11,312 | 13,475 / 11,208 | 13,452 / 11,251 |

## 复制寄存器核对

A、B 的 ADS 网表逐行比对仅第 2 行生成时间不同，Device Map 的高扇出列表逐行相同。

| 卡 72 的网 | 卡 72 扇出 | 卡 73 原网扇出（A、B） | 卡 73 ADS 副本（A、B 每份工程） |
|---|---:|---|---|
| `u_npu/u_conv/u_datapath/quant_tag_w[28]` | 640 | 低于列表门限 | `wb1_res_en_r` 64 份 |
| `u_npu/post_active_r` | 357 | 99 | `post_active_slice_r` 8 份 |
| `u_npu/is_conv_r` | 373 | 120 | `is_conv_slice_r` 8 份 |
| `u_rnd/u_copy/align_offset_r[0..4]` | 256–496 | 低于列表门限 | `align_offset_r` 8 份 × 5 位 |
| `u_rnd/u_copy/read_index_w[9]` | 504 | 低于列表门限 | `read_overflow_r` 8 份 |

两份 ADS 网表都保留了上述 128 个带 `PAP_PRESERVE=TRUE` 的触发器。逐个核对 Device Map 的网名和驱动名，所有副本均低于列表门限。高扇出表只列出前 1,000 条，末位扇出为 64，表外网的精确扇出未取得。两份工程均未出现任务卡所述的合并回单个大扇出的情况，可以进入布局布线。

- A 的[逐副本核对](artifacts/A/fanout_copies.txt)、[高扇出原表](artifacts/A/high_fanout.txt)、[资源汇总](artifacts/A/resource_summary.txt)、[ADS 层次资源](artifacts/A/resource_hier.txt)、[设置](artifacts/A/settings.txt)。
- B 的[逐副本核对](artifacts/B/fanout_copies.txt)、[高扇出原表](artifacts/B/high_fanout.txt)、[资源汇总](artifacts/B/resource_summary.txt)、[ADS 层次资源](artifacts/B/resource_hier.txt)、[设置](artifacts/B/settings.txt)。

## 布线

按任务卡将首条 `Unrouted general nets` 记为通用第 1 轮，对应本轮 PDS iteration 7。A 的日志更新至 15:29:19，B 至 15:31:42。两边已进入通用第 8 轮，截至采样尚无该轮完成记录。

| 指标 | A（SW 40） | B（SW 20） |
|---|---:|---:|
| PnR 日志起始时间（本地） | 14:46:21 | 14:46:25 |
| 布局用时（秒） | 100.62 | 106.92 |
| 预布线用时（秒） | 75.357 | 71.925 |
| 通用第 6 轮耗时（秒） | 306.136 | 354.062 |
| 通用第 7 轮耗时（秒） | 605.229 | 708.174 |
| 通用第 7 轮未布通网 | 74,336 | 74,015 |
| 通用第 7 轮过用数 | 365,371 | 364,000 |

| 通用轮次 | 卡 68 R2 未布通 | 卡 72 未布通 | A 未布通 | B 未布通 |
|---|---:|---:|---:|---:|
| 1 | 147,564 | 146,548 | 147,815 | 147,815 |
| 7 | 71,679 | 77,183 | 74,336 | 74,015 |
| 20 | 24,186 | 35,933 | 未取得 | 未取得 |
| 34 | 11,159 | 24,329 | 未取得 | 未取得 |

卡 68 R2 通用第 7 轮用时 111.488 秒，卡 72 用时 663.820 秒。卡 73 两份工程从首轮到第 7 轮的未布通数和过用数持续下降，单轮用时逐轮增加。B 同轮未布通网略少，耗时更长。采样时可用物理内存 658 MiB，Windows 性能计数器的分页读入和写出均为 0 页/秒，单次采样无法确定布线变慢的原因。

两边均未记录 Route-0039 或 Route-0008，也还未到通用第 20 轮和第 34 轮的止损判定点。卡 73 的阈值分别为超过 30,000 和 15,000 条未布通网。

- A 的[布线日志节选](artifacts/A/routing_congestion.txt)、[逐轮 CSV](artifacts/A/routing_rounds.csv)和[实现阶段日志节选](artifacts/A/implementation_stages.txt)。
- B 的[布线日志节选](artifacts/B/routing_congestion.txt)、[逐轮 CSV](artifacts/B/routing_rounds.csv)和[实现阶段日志节选](artifacts/B/implementation_stages.txt)。
- 完整 PnR 日志位于本机 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST/place_route/run.log` 和 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST-B/place_route/run.log`。对应原始拥塞数据在各自的 `place_route/CongestionPlot` 和 `place_route/CongestionNetInfo`。

### 拥塞

首轮原始网格相同，峰值 67。通用第 7 轮两边峰值都降至 36，A 有 19,987 个正值格，B 有 19,962 个。该轮拥塞网列表首位分别是 A 的 `u_rnd/cancel_region_w[6]`（573）和 B 的 `u_rnd/state_r_reg[5]`（550）。首轮和当前最新轮的 255 × 123 网格已导出。通用第 20、34 轮和最终轮的网格未取得。

- [A 网格索引](artifacts/A/congestion_grids.txt)、[B 网格索引](artifacts/B/congestion_grids.txt)、[共用色标拥塞图](artifacts/routing_congestion.png)。
- [A 拥塞网节选](artifacts/A/congestion_top_nets.txt)、[B 拥塞网节选](artifacts/B/congestion_top_nets.txt)。

## 时序和上板

未取得。
